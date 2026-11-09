// Loopin — medidor de latencia de ida y vuelta
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <array>
#include <cstdint>

namespace loopin {

// Emite un pulso por la salida y busca cuándo llega a la entrada. Cuenta en
// muestras de salida y de entrada por separado, que es justo lo que el looper
// necesitará para compensar: «la muestra de salida N vuelve como la muestra de
// entrada N + latencia». Hace kRounds rondas y se queda con la mediana.
class LatencyMeter {
 public:
  enum class State { kIdle, kRunning, kDone, kFailed };
  static constexpr int kRounds = 5;

  void prepare(int32_t sampleRate) { sampleRate_ = sampleRate; state_ = State::kIdle; }
  void start();
  bool active() const { return state_ == State::kRunning; }

  // Llamar una vez por bloque, con la entrada (mono) y la salida (mono) del
  // bloque. Escribe el pulso en outMono (se suma).
  void process(const float* inMono, int32_t inFrames, float* outMono, int32_t outFrames);

  State state() const { return state_; }
  int32_t detectedRounds() const { return successes_; }
  int32_t resultFrames() const { return resultFrames_; }

 private:
  enum class Phase { kListen, kEmit, kDetect, kCooldown };
  void nextRound();
  void finish();

  int32_t sampleRate_ = 48000;
  State state_ = State::kIdle;
  Phase phase_ = Phase::kListen;

  int64_t outFrames_ = 0;  // muestras de salida desde start()
  int64_t inFrames_ = 0;   // muestras de entrada desde start()
  int64_t phaseEndOut_ = 0;
  int64_t emitAt_ = 0;     // índice de salida del pulso
  int32_t pulseIndex_ = -1;
  float noisePeak_ = 0.0f;
  float threshold_ = 0.0f;

  int32_t round_ = 0;
  int32_t successes_ = 0;
  int32_t failures_ = 0;
  std::array<int32_t, kRounds> results_{};
  int32_t resultFrames_ = 0;
};

}  // namespace loopin
