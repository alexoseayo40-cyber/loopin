// Loopin — transporte: cuenta muestras, tiempos y compases
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <cstdint>

namespace loopin {

// Todo se cuenta en muestras enteras. Un tiempo dura exactamente
// samplesPerBeat muestras (redondeado), así un compás y un loop son siempre
// múltiplos exactos y nada puede desfasarse con el tiempo. El precio es que el
// tempo real puede diferir del pedido en menos de 0,5 muestras por tiempo
// (< 20 ppm a 48 kHz), algo inaudible.
class Transport {
 public:
  static constexpr double kMinBpm = 40.0;
  static constexpr double kMaxBpm = 240.0;

  void setSampleRate(int32_t sampleRate);

  // Los cambios de tempo se aplican al empezar el siguiente tiempo y los de
  // compás al empezar el siguiente compás, para no romper el pulso.
  void setBpm(double bpm);
  void setBeatsPerBar(int32_t beatsPerBar);

  void play();   // arranca desde el compás 0, tiempo 0
  void stop();

  // Avanza una muestra. Devuelve true si esta muestra es el inicio de un
  // tiempo (y entonces beat() y bar() describen ese tiempo).
  inline bool tick() {
    if (!playing_) return false;
    bool isBeatStart = false;
    if (posInBeat_ == 0) {
      isBeatStart = true;
    }
    ++posInBeat_;
    ++framePosition_;
    if (posInBeat_ >= samplesPerBeat_) {
      advanceBeat();
    }
    return isBeatStart;
  }

  bool playing() const { return playing_; }
  int32_t bar() const { return currentBar_; }
  int32_t beat() const { return currentBeat_; }
  int32_t beatsPerBar() const { return beatsPerBar_; }
  int32_t samplesPerBeat() const { return samplesPerBeat_; }
  int64_t samplesPerBar() const { return int64_t(samplesPerBeat_) * beatsPerBar_; }
  double bpm() const { return bpm_; }
  int64_t framePosition() const { return framePosition_; }

  static int32_t computeSamplesPerBeat(int32_t sampleRate, double bpm);

 private:
  void advanceBeat();

  int32_t sampleRate_ = 48000;
  double bpm_ = 100.0;
  int32_t samplesPerBeat_ = 28800;
  int32_t beatsPerBar_ = 4;

  double pendingBpm_ = 100.0;
  int32_t pendingBeatsPerBar_ = 4;

  bool playing_ = false;
  int32_t posInBeat_ = 0;   // muestras dentro del tiempo actual
  int32_t currentBeat_ = 0; // tiempo dentro del compás
  int32_t currentBar_ = 0;
  int64_t framePosition_ = 0;
};

}  // namespace loopin
