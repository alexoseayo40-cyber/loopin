// Loopin — streams de audio con Oboe
// SPDX-License-Identifier: GPL-3.0-or-later
#include "AudioEngine.h"

#include <android/log.h>

#include <algorithm>

#define LOG_TAG "loopin"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace loopin {

oboe::Result AudioEngine::openAudio() {
  closeAudio();
  disconnected_.store(false, std::memory_order_release);

  // 1) Salida primero: elegimos la frecuencia nativa del dispositivo, que es la
  //    que da la ruta de menor latencia (casi siempre 48 kHz).
  oboe::AudioStreamBuilder out;
  out.setDirection(oboe::Direction::Output)
      ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
      ->setSharingMode(oboe::SharingMode::Exclusive)
      ->setFormat(oboe::AudioFormat::Float)
      ->setFormatConversionAllowed(true)
      ->setChannelCount(oboe::ChannelCount::Stereo)
      ->setUsage(oboe::Usage::Game)
      ->setContentType(oboe::ContentType::Music)
      ->setDataCallback(this)
      ->setErrorCallback(this);
  oboe::Result result = out.openStream(output_);
  if (result != oboe::Result::OK) {
    LOGE("No se pudo abrir la salida: %s", oboe::convertToText(result));
    return result;
  }

  // 2) Entrada con la misma frecuencia, mono. Por defecto en modo «sin
  //    procesar» (sin control automático de ganancia, supresión de ruido ni
  //    filtros), que es lo que mejor recoge una guitarra por el micrófono. Si
  //    el móvil no lo admite, se vuelve a VoiceRecognition, que es el que
  //    Oboe recomienda para baja latencia.
  auto openInput = [&](oboe::InputPreset preset, int32_t deviceId) {
    oboe::AudioStreamBuilder in;
    in.setDirection(oboe::Direction::Input)
        ->setDeviceId(deviceId > 0 ? deviceId : oboe::kUnspecified)
        ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
        ->setSharingMode(oboe::SharingMode::Exclusive)
        ->setFormat(oboe::AudioFormat::Float)
        ->setFormatConversionAllowed(true)
        ->setChannelCount(oboe::ChannelCount::Mono)
        ->setChannelConversionAllowed(true)
        ->setSampleRate(output_->getSampleRate())
        ->setSampleRateConversionQuality(oboe::SampleRateConversionQuality::Medium)
        ->setInputPreset(preset);
    return in.openStream(input_);
  };
  presetFallback_ = false;
  const auto wanted = static_cast<oboe::InputPreset>(requestedPreset_);
  result = openInput(wanted, requestedInputDevice_);
  if (result != oboe::Result::OK && requestedInputDevice_ > 0) {
    LOGE("Entrada %d no disponible (%s); uso la de Android", requestedInputDevice_,
         oboe::convertToText(result));
    result = openInput(wanted, 0);
  }
  if (result != oboe::Result::OK && wanted != oboe::InputPreset::VoiceRecognition) {
    LOGE("Modo de micrófono %d no disponible (%s); uso VoiceRecognition", requestedPreset_,
         oboe::convertToText(result));
    presetFallback_ = true;
    result = openInput(oboe::InputPreset::VoiceRecognition, 0);
  }
  if (result != oboe::Result::OK) {
    LOGE("No se pudo abrir la entrada: %s", oboe::convertToText(result));
    closeStreams();
    return result;
  }

  // Buffer de salida: empieza en 2 bloques y, si hay cortes, el LatencyTuner
  // de Oboe lo sube de bloque en bloque (hasta 6) y se queda donde no corta.
  const int32_t burst = output_->getFramesPerBurst();
  const int32_t maxBuffer = std::min(output_->getBufferCapacityInFrames(), burst * 6);
  tuner_ = std::make_unique<oboe::LatencyTuner>(*output_, maxBuffer);
  output_->setBufferSizeInFrames(burst * 2);
  // Pide a Android que suba la CPU si el callback va justo (ADPF, si existe).
  output_->setPerformanceHintEnabled(true);

  core_.prepare(output_->getSampleRate());
  setSharedInputStream(input_);
  setSharedOutputStream(output_);

  result = oboe::FullDuplexStream::start();
  if (result != oboe::Result::OK) {
    LOGE("No se pudo arrancar: %s", oboe::convertToText(result));
    closeStreams();
    return result;
  }
  running_.store(true, std::memory_order_release);
  LOGI("Audio en marcha: %d Hz, burst %d, API %s, %s", output_->getSampleRate(),
       output_->getFramesPerBurst(),
       output_->getAudioApi() == oboe::AudioApi::AAudio ? "AAudio" : "OpenSL ES",
       output_->getSharingMode() == oboe::SharingMode::Exclusive ? "exclusivo" : "compartido");
  return oboe::Result::OK;
}

void AudioEngine::closeAudio() {
  if (output_ || input_) {
    oboe::FullDuplexStream::stop();
  }
  closeStreams();
  running_.store(false, std::memory_order_release);
}

void AudioEngine::closeStreams() {
  tuner_.reset();  // guarda una referencia a la salida: se va antes que ella
  if (output_) {
    output_->close();
    output_.reset();
  }
  if (input_) {
    input_->close();
    input_.reset();
  }
}

oboe::DataCallbackResult AudioEngine::onAudioReady(oboe::AudioStream* stream, void* audioData,
                                                   int32_t numFrames) {
  if (tuner_) tuner_->tune();
  const oboe::DataCallbackResult r =
      oboe::FullDuplexStream::onAudioReady(stream, audioData, numFrames);
  if (r == oboe::DataCallbackResult::Stop) {
    // La entrada ha fallado (p. ej. se ha desconectado). La interfaz lo verá y
    // reiniciará el audio.
    running_.store(false, std::memory_order_release);
    disconnected_.store(true, std::memory_order_release);
  }
  return r;
}

oboe::DataCallbackResult AudioEngine::onBothStreamsReady(const void* inputData,
                                                         int numInputFrames, void* outputData,
                                                         int numOutputFrames) {
  core_.process(static_cast<const float*>(inputData), numInputFrames,
                getInputStream()->getChannelCount(), static_cast<float*>(outputData),
                numOutputFrames, getOutputStream()->getChannelCount());
  return oboe::DataCallbackResult::Continue;
}

void AudioEngine::onErrorAfterClose(oboe::AudioStream* /*stream*/, oboe::Result error) {
  LOGE("Stream cerrado por error: %s", oboe::convertToText(error));
  running_.store(false, std::memory_order_release);
  disconnected_.store(true, std::memory_order_release);
}

}  // namespace loopin
