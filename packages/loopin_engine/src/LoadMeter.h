// Loopin — carga del callback de audio
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <algorithm>
#include <atomic>
#include <cstdint>

namespace loopin {

// Cuánto del tiempo disponible se va en el callback de audio. Si un callback
// tiene que dar 256 muestras a 48 kHz, dispone de 5,33 ms; si tarda 0,53 ms,
// la carga es del 10 %. Por encima del 100 % el audio se corta.
//
// Se escribe desde el hilo de audio (add) y se lee desde la interfaz: sin
// bloqueos ni reservas. Publica la media y el pico de cada segundo, y el
// mayor pico desde que se abrió el audio.
class LoadMeter {
 public:
  // Fuera del hilo de audio
  void prepare(int32_t sampleRate) {
    sampleRate_ = sampleRate > 0 ? sampleRate : 48000;
    busyNs_ = 0.0;
    availNs_ = 0.0;
    windowPeak_ = 0.0f;
    windowFrames_ = 0;
    maxPeak_ = 0.0f;
    aAverage_.store(0.0f, std::memory_order_relaxed);
    aPeak_.store(0.0f, std::memory_order_relaxed);
    aMaxPeak_.store(0.0f, std::memory_order_relaxed);
  }

  // Hilo de audio: el callback ha tardado busyNs nanosegundos en dar frames
  // muestras de salida.
  void add(int64_t busyNs, int32_t frames) {
    if (frames <= 0 || busyNs < 0) return;
    const double avail = 1e9 * double(frames) / double(sampleRate_);
    busyNs_ += double(busyNs);
    availNs_ += avail;
    windowPeak_ = std::max(windowPeak_, float(double(busyNs) / avail));
    windowFrames_ += frames;
    if (windowFrames_ < sampleRate_) return;
    // Un segundo: se publica y se empieza otro
    maxPeak_ = std::max(maxPeak_, windowPeak_);
    aAverage_.store(float(busyNs_ / availNs_), std::memory_order_relaxed);
    aPeak_.store(windowPeak_, std::memory_order_relaxed);
    aMaxPeak_.store(maxPeak_, std::memory_order_relaxed);
    busyNs_ = 0.0;
    availNs_ = 0.0;
    windowPeak_ = 0.0f;
    windowFrames_ = 0;
  }

  // Cualquier hilo. Fracciones del tiempo disponible (1.0 = 100 %).
  float average() const { return aAverage_.load(std::memory_order_relaxed); }
  float peak() const { return aPeak_.load(std::memory_order_relaxed); }
  float maxPeak() const { return aMaxPeak_.load(std::memory_order_relaxed); }

 private:
  int32_t sampleRate_ = 48000;
  double busyNs_ = 0.0;
  double availNs_ = 0.0;
  float windowPeak_ = 0.0f;
  int32_t windowFrames_ = 0;
  float maxPeak_ = 0.0f;
  std::atomic<float> aAverage_{0.0f};
  std::atomic<float> aPeak_{0.0f};
  std::atomic<float> aMaxPeak_{0.0f};
};

}  // namespace loopin
