// Loopin — núcleo del motor
// SPDX-License-Identifier: GPL-3.0-or-later
#include "EngineCore.h"

#include <algorithm>
#include <cmath>

namespace loopin {

void EngineCore::prepare(int32_t sampleRate) {
  sampleRate_ = sampleRate > 0 ? sampleRate : 48000;
  transport_.setSampleRate(sampleRate_);
  metronome_.prepare(sampleRate_);
  latency_.prepare(sampleRate_);
  inMono_.assign(kMaxBlockFrames, 0.0f);
  outMono_.assign(kMaxBlockFrames, 0.0f);
  publish();
}

void EngineCore::apply(const Command& cmd) {
  switch (cmd.type) {
    case Command::Type::kPlay:
      transport_.play();
      break;
    case Command::Type::kPause:
      transport_.stop();
      break;
    case Command::Type::kSetBpm:
      transport_.setBpm(cmd.value);
      break;
    case Command::Type::kSetBeatsPerBar:
      transport_.setBeatsPerBar(static_cast<int32_t>(cmd.value));
      break;
    case Command::Type::kSetClickEnabled:
      clickEnabled_ = cmd.value != 0.0;
      break;
    case Command::Type::kSetClickVolume:
      clickVolume_ = std::clamp(static_cast<float>(cmd.value), 0.0f, 1.0f);
      break;
    case Command::Type::kSetMonitorEnabled:
      monitorEnabled_ = cmd.value != 0.0;
      break;
    case Command::Type::kSetMonitorVolume:
      monitorVolume_ = std::clamp(static_cast<float>(cmd.value), 0.0f, 2.0f);
      break;
    case Command::Type::kSetInputGain:
      inputGain_ = std::clamp(static_cast<float>(cmd.value), 0.0f, 32.0f);
      break;
    case Command::Type::kMeasureLatency:
      latency_.start();
      break;
  }
}

void EngineCore::process(const float* in, int32_t inFrames, int32_t inChannels, float* out,
                         int32_t outFrames, int32_t outChannels) {
  Command cmd;
  while (queue_.pop(cmd)) apply(cmd);

  inFrames = std::clamp(inFrames, 0, kMaxBlockFrames);
  const int32_t n = std::clamp(outFrames, 0, kMaxBlockFrames);

  // Entrada a mono (canal 0) con su ganancia, y nivel de pico. El medidor de
  // latencia usa la señal sin ganancia para que el umbral no dependa de ella.
  float blockPeak = 0.0f;
  const float gain = latency_.active() ? 1.0f : inputGain_;
  for (int32_t i = 0; i < inFrames; ++i) {
    const float s = in != nullptr ? in[i * inChannels] * gain : 0.0f;
    inMono_[i] = s;
    blockPeak = std::max(blockPeak, std::fabs(s));
  }
  // Caída del medidor: unos 20 dB por segundo
  const float decay = std::pow(0.1f, float(n) / float(sampleRate_));
  peak_ = std::max(peak_ * decay, blockPeak);

  const bool measuring = latency_.active();

  for (int32_t i = 0; i < n; ++i) {
    float s = 0.0f;
    if (transport_.tick()) {
      metronome_.trigger(
          Metronome::accentFor(transport_.beat(), transport_.beatsPerBar()));
    }
    const float click = metronome_.next();
    if (!measuring) {
      if (clickEnabled_) s += click * clickVolume_;
      if (monitorEnabled_ && i < inFrames) s += inMono_[i] * monitorVolume_;
    }
    outMono_[i] = s;
  }

  // El medidor añade su pulso a outMono_ (con todo lo demás en silencio)
  latency_.process(inMono_.data(), inFrames, outMono_.data(), n);

  for (int32_t i = 0; i < n; ++i) {
    const float s = std::clamp(outMono_[i], -1.0f, 1.0f);
    for (int32_t c = 0; c < outChannels; ++c) out[i * outChannels + c] = s;
  }
  // Por si el dispositivo pide más de lo que procesamos (no debería pasar)
  for (int32_t i = n * outChannels; i < outFrames * outChannels; ++i) out[i] = 0.0f;

  publish();
}

void EngineCore::publish() {
  aPlaying_.store(transport_.playing(), std::memory_order_relaxed);
  aBar_.store(transport_.bar(), std::memory_order_relaxed);
  aBeat_.store(transport_.beat(), std::memory_order_relaxed);
  aBeatsPerBar_.store(transport_.beatsPerBar(), std::memory_order_relaxed);
  aSamplesPerBeat_.store(transport_.samplesPerBeat(), std::memory_order_relaxed);
  aBpm_.store(transport_.bpm(), std::memory_order_relaxed);
  aFramePosition_.store(transport_.framePosition(), std::memory_order_relaxed);
  aPeak_.store(peak_, std::memory_order_relaxed);
  aLatencyProgress_.store(latency_.detectedRounds(), std::memory_order_relaxed);
  aLatencyFrames_.store(latency_.resultFrames(), std::memory_order_relaxed);
  // El estado va el último: quien lo lea como «hecho» ve ya el resultado.
  aLatencyState_.store(static_cast<int32_t>(latency_.state()), std::memory_order_release);
}

CoreStatus EngineCore::status() const {
  CoreStatus s{};
  s.latencyState = aLatencyState_.load(std::memory_order_acquire);
  s.latencyFrames = aLatencyFrames_.load(std::memory_order_relaxed);
  s.playing = aPlaying_.load(std::memory_order_relaxed);
  s.bar = aBar_.load(std::memory_order_relaxed);
  s.beat = aBeat_.load(std::memory_order_relaxed);
  s.beatsPerBar = aBeatsPerBar_.load(std::memory_order_relaxed);
  s.samplesPerBeat = aSamplesPerBeat_.load(std::memory_order_relaxed);
  s.bpm = aBpm_.load(std::memory_order_relaxed);
  s.framePosition = aFramePosition_.load(std::memory_order_relaxed);
  s.inputPeak = aPeak_.load(std::memory_order_relaxed);
  s.latencyProgress = aLatencyProgress_.load(std::memory_order_relaxed);
  return s;
}

}  // namespace loopin
