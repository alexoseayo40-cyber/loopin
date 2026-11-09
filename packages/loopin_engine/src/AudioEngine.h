// Loopin — streams de audio con Oboe (solo Android)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <oboe/Oboe.h>

#include <atomic>
#include <memory>

#include "EngineCore.h"

namespace loopin {

// Stream full-duplex: la salida lleva el callback y lee la entrada en el
// mismo callback (oboe::FullDuplexStream), así entrada y salida van a la par.
class AudioEngine : public oboe::FullDuplexStream, public oboe::AudioStreamErrorCallback {
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
  oboe::DataCallbackResult onBothStreamsReady(const void* inputData, int numInputFrames,
                                              void* outputData,
                                              int numOutputFrames) override;

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
};

}  // namespace loopin
