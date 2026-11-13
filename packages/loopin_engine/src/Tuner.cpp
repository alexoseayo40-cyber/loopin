// Loopin — afinador (YIN)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "Tuner.h"

#include <algorithm>
#include <cmath>

namespace loopin {

void Tuner::prepare(int32_t sampleRate) {
  sampleRate_ = sampleRate > 0 ? sampleRate : 48000;
  // A ~24 kHz sobra para una guitarra (la fundamental no pasa de 1,4 kHz) y
  // cuesta 4 veces menos que a 48 kHz
  decim_ = sampleRate_ >= 64000 ? 4 : (sampleRate_ >= 32000 ? 2 : 1);
  rate_ = float(sampleRate_) / float(decim_);
  tauMin_ = std::max(2, static_cast<int32_t>(std::floor(rate_ / kMaxHz)));
  tauMax_ = static_cast<int32_t>(std::ceil(rate_ / kMinHz));
  y_.assign(static_cast<size_t>(kWindow + tauMax_ + 4), 0.0f);
  d_.assign(static_cast<size_t>(tauMax_ + 2), 0.0f);
}

// En la entrada original: suma de diferencias al cuadrado con un retardo lag
static double difference(const float* x, int32_t window, int32_t lag, float mean) {
  double sum = 0.0;
  for (int32_t i = 0; i < window; ++i) {
    const double e = double(x[i] - mean) - double(x[i + lag] - mean);
    sum += e * e;
  }
  return sum;
}

// Vértice de la parábola que pasa por (−1, a), (0, b), (1, c)
static double vertex(double a, double b, double c) {
  const double den = a - 2.0 * b + c;
  if (den <= 0.0) return 0.0;
  return std::clamp(0.5 * (a - c) / den, -1.0, 1.0);
}

TunerResult Tuner::analyze(const float* x) {
  TunerResult r;
  if (sampleRate_ <= 0 || x == nullptr) return r;
  const int32_t m = kWindow + tauMax_ + 4;
  const int32_t D = decim_;

  // Se reduce la frecuencia (media de D muestras) y se quita la continua
  double mean = 0.0;
  for (int32_t k = 0; k < m; ++k) {
    float s = 0.0f;
    for (int32_t j = 0; j < D; ++j) s += x[k * D + j];
    y_[static_cast<size_t>(k)] = s / float(D);
    mean += y_[static_cast<size_t>(k)];
  }
  mean /= m;
  double energy = 0.0;
  for (int32_t k = 0; k < m; ++k) {
    float& v = y_[static_cast<size_t>(k)];
    v -= float(mean);
    energy += double(v) * v;
  }
  const double rms = std::sqrt(energy / m);
  r.levelDb = rms > 1e-9 ? float(20.0 * std::log10(rms)) : -120.0f;
  if (r.levelDb < kMinLevelDb) return r;

  // Función diferencia y su versión normalizada (CMNDF)
  const float* y = y_.data();
  std::vector<float>& d = d_;
  d[0] = 1.0f;
  double running = 0.0;
  for (int32_t tau = 1; tau <= tauMax_; ++tau) {
    double sum = 0.0;
    for (int32_t i = 0; i < kWindow; ++i) {
      const float e = y[i] - y[i + tau];
      sum += double(e) * e;
    }
    running += sum;
    d[static_cast<size_t>(tau)] = running > 0.0 ? float(sum * tau / running) : 1.0f;
  }

  // El primer mínimo por debajo del umbral (así no se salta a la octava de
  // abajo); si no hay ninguno, el más bajo si es lo bastante claro
  constexpr float kThreshold = 0.15f;
  int32_t tau = -1;
  for (int32_t t = tauMin_; t < tauMax_; ++t) {
    if (d[static_cast<size_t>(t)] < kThreshold) {
      while (t + 1 < tauMax_ && d[static_cast<size_t>(t + 1)] < d[static_cast<size_t>(t)]) ++t;
      tau = t;
      break;
    }
  }
  if (tau < 0) {
    tau = tauMin_;
    for (int32_t t = tauMin_; t < tauMax_; ++t)
      if (d[static_cast<size_t>(t)] < d[static_cast<size_t>(tau)]) tau = t;
    if (d[static_cast<size_t>(tau)] > 0.35f) {
      r.clarity = std::max(0.0f, 1.0f - d[static_cast<size_t>(tau)]);
      return r;
    }
  }
  r.clarity = std::clamp(1.0f - d[static_cast<size_t>(tau)], 0.0f, 1.0f);
  double period = tau + vertex(d[static_cast<size_t>(tau - 1)], d[static_cast<size_t>(tau)],
                               d[static_cast<size_t>(tau + 1)]);

  // Afinar el periodo en la entrada original, alrededor de lo encontrado
  if (D > 1) {
    float xm = 0.0f;
    const int32_t window = kWindow * D;
    for (int32_t i = 0; i < m * D; ++i) xm += x[i];
    xm /= float(m * D);
    const int32_t center = static_cast<int32_t>(std::lround(period * D));
    double best = 0.0;
    int32_t bestLag = -1;
    double vals[7];
    for (int32_t k = 0; k < 7; ++k) {
      const int32_t lag = center - 3 + k;
      vals[k] = lag >= 1 && window + lag <= m * D ? difference(x, window, lag, xm) : -1.0;
      if (vals[k] >= 0.0 && (bestLag < 0 || vals[k] < best)) {
        best = vals[k];
        bestLag = k;
      }
    }
    if (bestLag >= 1 && bestLag <= 5 && vals[bestLag - 1] >= 0.0 && vals[bestLag + 1] >= 0.0) {
      period = (center - 3 + bestLag + vertex(vals[bestLag - 1], vals[bestLag], vals[bestLag + 1])) /
               double(D);
    }
  }
  r.frequency = float(rate_ / period);
  if (r.frequency < kMinHz * 0.97f || r.frequency > kMaxHz * 1.03f) r.frequency = 0.0f;
  return r;
}

}  // namespace loopin
