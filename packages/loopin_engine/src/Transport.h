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
  // Compás con sus acentos: el bit k de accentMask marca el tiempo k como
  // acento medio (el tiempo 0 siempre es fuerte). Ej.: 6/8 → 6 tiempos y el
  // bit 3; 7/8 (2+2+3) → 7 tiempos y los bits 2 y 4.
  void setMeter(int32_t beatsPerBar, uint32_t accentMask);

  void play();   // arranca desde el compás 0, tiempo 0
  // Arranca como si hubiera empezado hace `elapsed` muestras: el compás 0,
  // tiempo 0 cayó en la muestra «ahora − elapsed». Para empezar a contar el
  // tempo justo donde el músico empezó a tocar.
  void playFrom(int64_t elapsed);
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
    ++posInBar_;
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
  uint32_t accentMask() const { return accentMask_; }
  // Muestras ya sonadas del tiempo actual
  int32_t framesSinceBeat() const { return playing_ ? posInBeat_ : 0; }
  int32_t samplesPerBeat() const { return samplesPerBeat_; }
  int64_t samplesPerBar() const { return int64_t(samplesPerBeat_) * beatsPerBar_; }
  double bpm() const { return bpm_; }
  int64_t framePosition() const { return framePosition_; }

  // --- Para el looper (se consultan antes de tick() de la muestra «ahora») ---

  // Muestras ya sonadas del compás actual. 0 = la próxima muestra es un
  // primer tiempo (o el transporte está parado).
  int64_t framesSinceBar() const { return playing_ ? posInBar_ : 0; }
  // Muestras hasta el próximo primer tiempo (0 si la próxima muestra lo es).
  // Tiene en cuenta un cambio de tempo pendiente.
  int64_t framesToNextBar() const;
  // Duración de un compás con el tempo y el compás que van a regir a partir
  // del siguiente primer tiempo.
  int64_t nextSamplesPerBar() const {
    return int64_t(computeSamplesPerBeat(sampleRate_, pendingBpm_)) * pendingBeatsPerBar_;
  }
  // true si hay un cambio de tempo o de compás aún sin aplicar.
  bool hasPendingChange() const {
    return pendingBpm_ != bpm_ || pendingBeatsPerBar_ != beatsPerBar_ ||
           pendingAccentMask_ != accentMask_;
  }

  static int32_t computeSamplesPerBeat(int32_t sampleRate, double bpm);

 private:
  void advanceBeat();

  int32_t sampleRate_ = 48000;
  double bpm_ = 100.0;
  int32_t samplesPerBeat_ = 28800;
  int32_t beatsPerBar_ = 4;
  uint32_t accentMask_ = 0;

  double pendingBpm_ = 100.0;
  int32_t pendingBeatsPerBar_ = 4;
  uint32_t pendingAccentMask_ = 0;

  bool playing_ = false;
  int32_t posInBeat_ = 0;   // muestras dentro del tiempo actual
  int64_t posInBar_ = 0;    // muestras dentro del compás actual
  int32_t currentBeat_ = 0; // tiempo dentro del compás
  int32_t currentBar_ = 0;
  int64_t framePosition_ = 0;
};

}  // namespace loopin
