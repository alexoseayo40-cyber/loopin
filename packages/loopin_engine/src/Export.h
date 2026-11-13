// Loopin — exportar la sesión a WAV (la mezcla y cada pista por separado)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <array>
#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "Clip.h"
#include "Drums.h"
#include "EngineCore.h"

namespace loopin {

// Lo que hay que exportar: las pistas tal como suenan (volumen, silencio,
// reverse y media velocidad), la batería y la canción, durante unas vueltas
// del ciclo entero (la pista más larga).
struct ExportSpec {
  SessionSpec session;  // tempo, compás y pistas (a session.sampleRate)
  std::array<std::vector<float>, Looper::kTracks> data;
  float volume[Looper::kTracks] = {1, 1, 1, 1};
  bool muted[Looper::kTracks] = {};
  bool reverse[Looper::kTracks] = {};
  bool half[Looper::kTracks] = {};
  bool drums = false;
  DrumStyle drumStyle = DrumStyle::kBasic;
  bool beatIsEighth = false;
  float drumVolume = 0.7f;
  std::unique_ptr<Clip> song;  // ya estirada al tempo (nullptr = sin canción)
  float songVolume = 0.7f;
  int32_t loops = 1;
  // Archivos (vacío = ese no). La mezcla lleva lo que suena; cada pista va
  // sola (aunque esté en silencio), con su volumen y sus efectos.
  std::string mixPath;
  std::string trackPath[Looper::kTracks];
  std::string drumsPath;
  std::string songPath;
};

// Exporta en un hilo aparte (con menos prioridad) con un núcleo propio, sin
// audio: el mismo motor que suena, así lo exportado es lo que se oye. Se
// hace dos veces: la primera solo mide el pico (si la mezcla pasa de 0 dB,
// todo se baja lo mismo) y la segunda escribe WAV mono de 16 bits.
class Exporter {
 public:
  enum State : int32_t { kIdle = 0, kRunning = 1, kDone = 2, kFailed = 3 };
  static constexpr int32_t kErrWrite = 1;    // no se ha podido escribir
  static constexpr int32_t kErrMemory = 2;
  static constexpr int32_t kErrNothing = 3;  // nada que exportar
  static constexpr int32_t kErrLoad = 4;     // las pistas no cuadran

  ~Exporter();

  // Hilo de la interfaz. kitFrom: el núcleo que suena (su kit de batería).
  // false si ya hay una exportación en marcha.
  bool start(ExportSpec spec, const EngineCore& kitFrom);
  void cancel();

  int32_t state() const { return state_.load(std::memory_order_acquire); }
  int32_t progress() const { return progress_.load(std::memory_order_relaxed); }  // 0..1000
  int32_t error() const { return error_.load(std::memory_order_relaxed); }
  // Duración de lo exportado (muestras, a la frecuencia de la sesión)
  int64_t frames() const { return frames_.load(std::memory_order_relaxed); }

  // Todo en el hilo que llama (los tests). core: un núcleo sin preparar, con
  // el kit ya copiado. Devuelve 0 o un kErr*.
  static int32_t run(EngineCore& core, ExportSpec& spec, const std::atomic<bool>* cancel,
                     std::atomic<int32_t>* progress, int64_t* frames);

  // WAV mono de 16 bits (también lo usan los tests)
  static bool writeWav(const std::string& path, const std::vector<int16_t>& pcm, int32_t rate);

 private:
  void join();
  std::thread thread_;
  std::atomic<bool> cancel_{false};
  std::atomic<int32_t> state_{kIdle};
  std::atomic<int32_t> progress_{0};
  std::atomic<int32_t> error_{0};
  std::atomic<int64_t> frames_{0};
};

}  // namespace loopin
