// Loopin — afinador: la entrada se copia sin bloqueos y se analiza fuera del
// hilo de audio (YIN)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <vector>

namespace loopin {

// Los últimos kSize valores de la entrada (mono, con su ganancia), para el
// afinador. El hilo de audio escribe (solo si está encendido); el de la
// interfaz copia lo último sin bloquear a nadie. La memoria se reserva una
// vez, al crearlo.
class TunerTap {
 public:
  static constexpr int32_t kSize = 16384;  // potencia de 2: 0,34 s a 48 kHz

  TunerTap() : buf_(new std::atomic<float>[kSize]) {
    for (int32_t i = 0; i < kSize; ++i) buf_[i].store(0.0f, std::memory_order_relaxed);
  }

  void setEnabled(bool on) { enabled_.store(on, std::memory_order_relaxed); }
  bool enabled() const { return enabled_.load(std::memory_order_relaxed); }

  // Hilo de audio
  void push(const float* x, int32_t n) {
    if (!enabled()) return;
    const int64_t e = end_.load(std::memory_order_relaxed);
    for (int32_t i = 0; i < n; ++i)
      buf_[(e + i) & (kSize - 1)].store(x[i], std::memory_order_relaxed);
    end_.store(e + n, std::memory_order_release);
  }

  // Otro hilo: copia las últimas n muestras (n ≤ kSize / 2). false si aún no
  // hay tantas o si el audio las ha pisado mientras se copiaban.
  bool latest(float* out, int32_t n) const {
    if (n <= 0 || n > kSize / 2) return false;
    const int64_t e1 = end_.load(std::memory_order_acquire);
    if (e1 < n) return false;
    for (int32_t i = 0; i < n; ++i)
      out[i] = buf_[(e1 - n + i) & (kSize - 1)].load(std::memory_order_relaxed);
    const int64_t e2 = end_.load(std::memory_order_acquire);
    return e2 - e1 <= kSize - n;
  }

  // Muestras escritas desde que se creó (para saber si llega audio nuevo)
  int64_t written() const { return end_.load(std::memory_order_acquire); }

 private:
  std::unique_ptr<std::atomic<float>[]> buf_;
  std::atomic<int64_t> end_{0};
  std::atomic<bool> enabled_{false};
};

struct TunerResult {
  float frequency = 0.0f;  // Hz (0 = no hay una nota clara)
  float clarity = 0.0f;    // 0..1: lo periódica que es la señal
  float levelDb = -120.0f; // nivel (RMS) de lo analizado, en dBFS
};

// Detector de la frecuencia fundamental (YIN, de Cheveigné y Kawahara 2002)
// para guitarra: de 38 a 1400 Hz. Analiza a ~24 kHz (la entrada se reduce a
// la mitad o a la cuarta parte) con una ventana de 1024 muestras.
class Tuner {
 public:
  static constexpr float kMinHz = 38.0f;
  static constexpr float kMaxHz = 1400.0f;
  static constexpr int32_t kWindow = 1024;
  // Por debajo de este nivel no se intenta (silencio o ruido de fondo)
  static constexpr float kMinLevelDb = -60.0f;

  // Fuera del hilo de audio: reserva memoria.
  void prepare(int32_t sampleRate);
  int32_t sampleRate() const { return sampleRate_; }
  // Muestras de entrada (a sampleRate) que necesita analyze()
  int32_t frames() const { return (kWindow + tauMax_ + 4) * decim_; }
  // x: las últimas frames() muestras de la entrada
  TunerResult analyze(const float* x);

 private:
  int32_t sampleRate_ = 0;
  int32_t decim_ = 1;
  float rate_ = 0.0f;   // frecuencia tras reducir
  int32_t tauMin_ = 0, tauMax_ = 0;
  std::vector<float> y_;    // la señal reducida
  std::vector<float> d_;    // diferencia normalizada (CMNDF)
};

}  // namespace loopin
