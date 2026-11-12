// Loopin — detector de ataques (el golpe de una nota o un rasgueo)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <cmath>
#include <cstdint>

namespace loopin {

// Compara dos envolventes de la señal: una rápida (sube al instante y cae en
// unos milisegundos) y una lenta (el nivel medio de los últimos ~80 ms). Hay
// ataque cuando la rápida supera a la lenta varias veces y además pasa de un
// mínimo (para no saltar con el ruido). Tras un ataque espera un tiempo antes
// de aceptar otro. Sin reservas de memoria: se puede usar en el hilo de audio.
class OnsetDetector {
 public:
  void prepare(int32_t sampleRate) {
    sampleRate_ = sampleRate > 0 ? sampleRate : 48000;
    fastRelease_ = std::exp(-1.0f / (0.003f * float(sampleRate_)));
    slowCoef_ = 1.0f - std::exp(-1.0f / (0.080f * float(sampleRate_)));
    reset(floor_, refractory_);
  }

  // floor: nivel mínimo para que cuente; refractory: muestras que hay que
  // esperar tras un ataque antes de aceptar otro.
  void reset(float floor, int32_t refractory) {
    floor_ = floor;
    refractory_ = refractory;
    fast_ = 0.0f;
    slow_ = 0.0f;
    since_ = refractory;
  }

  // Una muestra. Devuelve true si en ella empieza un ataque.
  inline bool push(float x) {
    const float a = std::fabs(x);
    fast_ = a > fast_ ? a : fast_ * fastRelease_;
    const bool hit = since_ >= refractory_ && fast_ > floor_ && fast_ > kRatio * slow_;
    slow_ += (a - slow_) * slowCoef_;
    if (hit) {
      since_ = 0;
    } else if (since_ < refractory_) {
      ++since_;
    }
    return hit;
  }

  float floor() const { return floor_; }

 private:
  static constexpr float kRatio = 3.0f;
  int32_t sampleRate_ = 48000;
  float fastRelease_ = 0.99f;
  float slowCoef_ = 0.0003f;
  float floor_ = 0.02f;
  int32_t refractory_ = 4800;
  float fast_ = 0.0f;
  float slow_ = 0.0f;
  int32_t since_ = 0;
};

}  // namespace loopin
