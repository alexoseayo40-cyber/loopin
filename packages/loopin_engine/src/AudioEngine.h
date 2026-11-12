// Loopin — streams de audio con Oboe (solo Android)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <oboe/Oboe.h>

#include <atomic>
#include <memory>
#include <vector>

#include "EngineCore.h"
#include "LoadMeter.h"

namespace loopin {

// Full-duplex: la salida lleva el callback y en él se lee TODA la entrada que
// haya llegado (sin esperar). No usamos oboe::FullDuplexStream porque lee como
// mucho un bloque por callback: si la entrada se adelanta, lo que sobra se
// queda acumulado para siempre y suma latencia. El núcleo cuenta entrada y
// salida por separado, así que no necesita bloques iguales.
class AudioEngine : public oboe::AudioStreamDataCallback, public oboe::AudioStreamErrorCallback {
 public:
  // Hilo de la interfaz
  oboe::Result openAudio();
  void closeAudio();
  EngineCore& core() { return core_; }
  void setInputPreset(int32_t preset) { requestedPreset_ = preset; }
  void setInputDevice(int32_t deviceId) { requestedInputDevice_ = deviceId; }
  bool presetFallback() const { return presetFallback_; }

  bool running() const { return running_.load(std::memory_order_acquire); }
  bool disconnected() const { return disconnected_.load(std::memory_order_acquire); }
  std::shared_ptr<oboe::AudioStream> output() const { return output_; }
  std::shared_ptr<oboe::AudioStream> input() const { return input_; }

  // Hilo de audio
  oboe::DataCallbackResult onAudioReady(oboe::AudioStream* stream, void* audioData,
                                        int32_t numFrames) override;

  // Diagnóstico: máximo de muestras de entrada leídas en un callback durante
  // los últimos ~2 s (si es mucho mayor que el bloque, la entrada llega a
  // trompicones).
  int32_t inputMaxRead() const { return inputMaxReadPublished_.load(std::memory_order_relaxed); }

  // Carga del callback (media y pico del último segundo, mayor pico desde que
  // se abrió el audio), en fracciones del tiempo disponible.
  const LoadMeter& load() const { return load_; }

  // Hilo de errores de Oboe (p. ej. se desenchufan los auriculares)
  void onErrorAfterClose(oboe::AudioStream* stream, oboe::Result error) override;

 private:
  void closeStreams();

  EngineCore core_;
  std::shared_ptr<oboe::AudioStream> output_;
  std::shared_ptr<oboe::AudioStream> input_;
  // Sube el buffer de salida de bloque en bloque si hay cortes (y no lo baja).
  std::unique_ptr<oboe::LatencyTuner> tuner_;
  int32_t requestedPreset_ = static_cast<int32_t>(oboe::InputPreset::Unprocessed);
  bool presetFallback_ = false;
  int32_t requestedInputDevice_ = 0;  // 0 = el que elija Android
  std::atomic<bool> running_{false};
  std::atomic<bool> disconnected_{false};

  // Callbacks del arranque en los que se tira la entrada (ver onAudioReady)
  static constexpr int32_t kWarmupCallbacks = 20;
  int32_t warmupLeft_ = 0;
  std::vector<float> inBuf_;
  int32_t inBufFrames_ = 0;
  int32_t inputMaxRead_ = 0;
  int32_t diagCallbacks_ = 0;
  std::atomic<int32_t> inputMaxReadPublished_{0};
  LoadMeter load_;
};

}  // namespace loopin
