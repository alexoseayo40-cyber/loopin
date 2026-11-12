// Loopin — calibración de la latencia tocando al clic
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <array>
#include <cstdint>

#include "Metronome.h"
#include "OnsetDetector.h"

namespace loopin {

// Para cuando el clic no puede volver solo al micrófono (cascos): el músico
// toca al ritmo de unos clics (rasgueo con las cuerdas apagadas o un golpe en
// la guitarra) y se mide cuánto tarda cada golpe en llegar respecto a su clic.
//
// Usa los mismos índices absolutos que el looper: el clic k sale en la muestra
// de salida c_k y el golpe entra en la muestra de entrada j; j − c_k es la
// latencia de ida y vuelta más lo que el músico se adelante o se retrase. Eso
// es justo lo que hay que compensar para que lo que grabe caiga en el tiempo.
//
// Va a 80 BPM (750 ms entre clics) para que no haya duda de a qué clic
// corresponde cada golpe: se aceptan golpes de 150 ms antes a 600 ms después.
// 4 clics para entrar y 12 que cuentan; se queda con la mediana.
class TapCalibrator {
 public:
  enum class State { kIdle, kRunning, kDone, kFailed };
  static constexpr int32_t kCountIn = 4;
  static constexpr int32_t kCounted = 12;
  static constexpr int32_t kTotal = kCountIn + kCounted;
  static constexpr int32_t kMinHits = 6;
  static constexpr double kBpm = 80.0;

  void prepare(int32_t sampleRate);
  void start();
  void cancel();
  bool active() const { return state_ == State::kRunning; }

  // Una vez por bloque: la entrada (mono) y la salida (mono, se le suman los
  // clics), con el índice absoluto de su primera muestra.
  void process(const float* inMono, int32_t inFrames, int64_t inStart, float* outMono,
               int32_t outFrames, int64_t outStart);

  State state() const { return state_; }
  int32_t clicks() const { return clicksPlayed_; }  // clics que ya han sonado
  int32_t hits() const { return hits_; }            // golpes que cuentan
  int32_t resultFrames() const { return resultFrames_; }
  // Dispersión de los golpes (mediana de las desviaciones): cuanto menor,
  // más fiable la medida.
  int32_t spreadFrames() const { return spreadFrames_; }

 private:
  void finish();
  int64_t clickAt(int32_t k) const { return firstClick_ + int64_t(k) * period_; }

  int32_t sampleRate_ = 48000;
  State state_ = State::kIdle;
  Metronome clicks_;
  OnsetDetector onset_;
  bool justStarted_ = false;
  int64_t firstClick_ = 0;
  int64_t period_ = 36000;
  int32_t clicksPlayed_ = 0;
  int32_t hits_ = 0;
  std::array<int32_t, kCounted> offsets_{};
  std::array<bool, kCounted> hit_{};
  int32_t resultFrames_ = 0;
  int32_t spreadFrames_ = 0;
};

}  // namespace loopin
