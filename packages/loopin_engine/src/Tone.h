// Loopin — nota de referencia del afinador (para afinar de oído)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace loopin {

// Una nota sostenida con 6 armónicos (de 1/k): así se oye su altura también
// por el altavoz del móvil, que casi no da graves (el Mi grave, 82 Hz, suena
// sobre todo por sus armónicos). Sale de una tabla de una vuelta; entra y
// sale en 10 ms. Cambiar de nota mantiene la fase (sin chasquido).
class Tone {
 public:
  static constexpr int32_t kTable = 2048;
  static constexpr float kLevel = 0.25f;

  // Fuera del hilo de audio
  void prepare(int32_t sampleRate) {
    sampleRate_ = sampleRate > 0 ? sampleRate : 48000;
    table_.assign(kTable + 1, 0.0f);
    double peak = 0.0;
    for (int32_t i = 0; i <= kTable; ++i) {
      double s = 0.0;
      for (int k = 1; k <= 6; ++k) s += std::sin(2.0 * 3.14159265358979323846 * k * i / kTable) / k;
      table_[static_cast<size_t>(i)] = static_cast<float>(s);
      peak = std::max(peak, std::fabs(s));
    }
    for (float& v : table_) v = static_cast<float>(v / peak);
    step_ = 1.0f / (0.010f * float(sampleRate_));
    gain_ = 0.0f;
    phase_ = 0.0;
    hz_ = 0.0;
  }

  // 0 = callar (baja en 10 ms)
  void setFrequency(double hz) { hz_ = hz > 0.0 ? std::fmin(hz, 4000.0) : 0.0; }
  double frequency() const { return hz_; }
  bool sounding() const { return gain_ > 0.0f; }

  inline float next() {
    const float target = hz_ > 0.0 ? kLevel : 0.0f;
    if (gain_ != target) gain_ = gain_ < target ? std::fmin(target, gain_ + step_ * kLevel)
                                                : std::fmax(target, gain_ - step_ * kLevel);
    if (gain_ <= 0.0f) return 0.0f;
    if (hz_ > 0.0) inc_ = hz_ / sampleRate_;  // al callar, sigue con la de antes
    const double x = phase_ * kTable;
    const int32_t i = static_cast<int32_t>(x);
    const float f = static_cast<float>(x - i);
    const float s = table_[static_cast<size_t>(i)] +
                    (table_[static_cast<size_t>(i + 1)] - table_[static_cast<size_t>(i)]) * f;
    phase_ += inc_;
    if (phase_ >= 1.0) phase_ -= 1.0;
    return s * gain_;
  }

 private:
  int32_t sampleRate_ = 48000;
  std::vector<float> table_;
  double phase_ = 0.0, inc_ = 0.0, hz_ = 0.0;
  float gain_ = 0.0f, step_ = 0.0f;
};

}  // namespace loopin
