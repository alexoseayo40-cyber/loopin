// Loopin — núcleo del motor
// SPDX-License-Identifier: GPL-3.0-or-later
#include "EngineCore.h"

#include <algorithm>
#include <cmath>

namespace loopin {

void EngineCore::prepare(int32_t sampleRate) {
  sampleRate_ = sampleRate > 0 ? sampleRate : 48000;
  transport_.stop();
  transport_.setSampleRate(sampleRate_);
  metronome_.prepare(sampleRate_);
  latency_.prepare(sampleRate_);
  // 6 s de entrada: cubre la latencia (≤ 0,5 s), el margen para empezar a
  // grabar un poco tarde (≤ 1 s) y bloques grandes.
  ring_.prepare(sampleRate_ * 6);
  looper_.prepare(sampleRate_, &transport_);
  outPos_ = 0;
  monRead_ = 0;
  monChunk_ = 0;
  monChunkAge_ = 0;
  inMono_.assign(kMaxBlockFrames, 0.0f);
  outMono_.assign(kMaxBlockFrames, 0.0f);
  publish();
}

void EngineCore::apply(const Command& cmd) {
  const int64_t now = outPos_;
  switch (cmd.type) {
    case Command::Type::kPlay:
      looper_.startAll(now);
      break;
    case Command::Type::kPause:
      looper_.stopAll(now);
      break;
    case Command::Type::kSetBpm:
      // Con un loop grabado (o grabándose) el tempo no se puede cambiar
      if (!looper_.locksTempo()) transport_.setBpm(cmd.value);
      break;
    case Command::Type::kSetBeatsPerBar:
      if (!looper_.locksTempo()) transport_.setBeatsPerBar(static_cast<int32_t>(cmd.value));
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
    case Command::Type::kLoopPress:
      looper_.press(now);
      break;
    case Command::Type::kLoopHold:
      looper_.hold(now);
      break;
    case Command::Type::kLoopDoubleTap:
      looper_.doubleTap(now);
      break;
    case Command::Type::kLoopUndo:
      looper_.undo(now);
      break;
    case Command::Type::kLoopClear:
      looper_.clearAll(now);
      break;
    case Command::Type::kSetLoopMode:
      looper_.setMode(cmd.value != 0.0 ? Looper::Mode::kManual : Looper::Mode::kSync);
      break;
    case Command::Type::kSetSyncBars:
      looper_.setSyncBars(static_cast<int32_t>(cmd.value));
      break;
    case Command::Type::kSetLatencyFrames:
      looper_.setLatency(static_cast<int32_t>(cmd.value));
      break;
    case Command::Type::kSetLoopVolume:
      looper_.setVolume(static_cast<float>(cmd.value));
      break;
    case Command::Type::kSelectTrack:
      looper_.select(cmd.arg);
      break;
    case Command::Type::kSelectNextTrack:
      looper_.selectNext();
      break;
    case Command::Type::kSetTrackVolume:
      looper_.setTrackVolume(cmd.arg, static_cast<float>(cmd.value));
      break;
    case Command::Type::kSetTrackMuted:
      looper_.setTrackMuted(cmd.arg, cmd.value != 0.0);
      break;
    case Command::Type::kClearTrack:
      looper_.clearTrack(cmd.arg, now);
      break;
    case Command::Type::kSetAutoAdvance:
      looper_.setAutoAdvance(cmd.value != 0.0);
      break;
  }
}

void EngineCore::process(const float* in, int32_t inFrames, int32_t inChannels, float* out,
                         int32_t outFrames, int32_t outChannels) {
  Command cmd;
  while (queue_.pop(cmd)) apply(cmd);

  inFrames = std::clamp(inFrames, 0, kMaxBlockFrames);
  const int32_t n = std::clamp(outFrames, 0, kMaxBlockFrames);

  // Entrada a mono (canal 0) con su ganancia, al anillo, y nivel de pico. El
  // medidor de latencia usa la señal sin ganancia para que el umbral no
  // dependa de ella.
  float blockPeak = 0.0f;
  const float gain = latency_.active() ? 1.0f : inputGain_;
  for (int32_t i = 0; i < inFrames; ++i) {
    const float s = in != nullptr ? in[i * inChannels] * gain : 0.0f;
    inMono_[i] = s;
    ring_.push(s);
    blockPeak = std::max(blockPeak, std::fabs(s));
  }
  const int64_t inStart = ring_.end() - inFrames;
  // Caída del medidor: unos 20 dB por segundo
  const float decay = std::pow(0.1f, float(n) / float(sampleRate_));
  peak_ = std::max(peak_ * decay, blockPeak);

  // Monitor: lee la entrada más reciente. Si se acumula más de lo que la
  // entrada suele traer de golpe (más un bloque), salta para no ir con
  // retraso. El margen sigue al mayor bloque de entrada del último segundo.
  monChunk_ = std::max({monChunk_, inFrames, n});
  monChunkAge_ += n;
  if (monChunkAge_ > sampleRate_) {
    monChunk_ = std::max(inFrames, n);
    monChunkAge_ = 0;
  }
  if (ring_.end() - monRead_ > int64_t(monChunk_) + n) monRead_ = ring_.end() - n;
  monRead_ = std::max(monRead_, ring_.begin());

  const bool measuring = latency_.active();

  for (int32_t i = 0; i < n; ++i) {
    if (transport_.tick()) {
      metronome_.trigger(
          Metronome::accentFor(transport_.beat(), transport_.beatsPerBar()));
    }
    const float click = metronome_.next();
    const float loop = looper_.render(outPos_ + i);
    float mon = 0.0f;
    if (monRead_ < ring_.end()) mon = ring_.at(monRead_++);
    float s = 0.0f;
    if (!measuring) {
      if (clickEnabled_ || looper_.forcesClick()) s += click * clickVolume_;
      if (monitorEnabled_) s += mon * monitorVolume_;
      s += loop;
    }
    outMono_[i] = s;
  }

  // El medidor añade su pulso a outMono_ (con todo lo demás en silencio)
  latency_.process(inMono_.data(), inFrames, inStart, outMono_.data(), n, outPos_);
  outPos_ += n;

  // Lo que ha entrado se graba en el loop (con la latencia compensada)
  looper_.capture(ring_);
  looper_.background(kBackgroundBudget);

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

  aLoopState_.store(static_cast<int32_t>(looper_.state()), std::memory_order_relaxed);
  aLoopMode_.store(static_cast<int32_t>(looper_.mode()), std::memory_order_relaxed);
  aLoopSyncBars_.store(looper_.syncBars(), std::memory_order_relaxed);
  aLoopLayers_.store(looper_.layerCount(), std::memory_order_relaxed);
  aLoopCanUndo_.store(looper_.canUndo() ? 1 : 0, std::memory_order_relaxed);
  aLoopLatency_.store(looper_.latency(), std::memory_order_relaxed);
  aLoopLength_.store(looper_.length(), std::memory_order_relaxed);
  aLoopPosition_.store(looper_.position(), std::memory_order_relaxed);
  aLoopRecorded_.store(looper_.recordedFrames(outPos_), std::memory_order_relaxed);
  aLoopTarget_.store(looper_.targetFrames(), std::memory_order_relaxed);
  aLoopBarFrames_.store(looper_.barFrames(), std::memory_order_relaxed);
  aLoopSelected_.store(looper_.selected(), std::memory_order_relaxed);
  aLoopActive_.store(looper_.active(), std::memory_order_relaxed);
  aLoopAutoAdvance_.store(looper_.autoAdvance() ? 1 : 0, std::memory_order_relaxed);
  aLoopBaseLength_.store(looper_.baseLength(), std::memory_order_relaxed);
  aLoopBasePosition_.store(looper_.basePosition(outPos_), std::memory_order_relaxed);
  for (int32_t i = 0; i < Looper::kTracks; ++i) {
    aTrackState_[i].store(static_cast<int32_t>(looper_.trackState(i)), std::memory_order_relaxed);
    aTrackLayers_[i].store(looper_.trackLayers(i), std::memory_order_relaxed);
    aTrackMuted_[i].store(looper_.trackMuted(i) ? 1 : 0, std::memory_order_relaxed);
    aTrackVolume_[i].store(looper_.trackVolume(i), std::memory_order_relaxed);
    aTrackLength_[i].store(looper_.trackLength(i), std::memory_order_relaxed);
    aTrackPosition_[i].store(looper_.trackPosition(i), std::memory_order_relaxed);
  }

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
  s.loopState = aLoopState_.load(std::memory_order_relaxed);
  s.loopMode = aLoopMode_.load(std::memory_order_relaxed);
  s.loopSyncBars = aLoopSyncBars_.load(std::memory_order_relaxed);
  s.loopLayers = aLoopLayers_.load(std::memory_order_relaxed);
  s.loopCanUndo = aLoopCanUndo_.load(std::memory_order_relaxed);
  s.loopLatencyFrames = aLoopLatency_.load(std::memory_order_relaxed);
  s.loopLength = aLoopLength_.load(std::memory_order_relaxed);
  s.loopPosition = aLoopPosition_.load(std::memory_order_relaxed);
  s.loopRecorded = aLoopRecorded_.load(std::memory_order_relaxed);
  s.loopTarget = aLoopTarget_.load(std::memory_order_relaxed);
  s.loopBarFrames = aLoopBarFrames_.load(std::memory_order_relaxed);
  s.loopSelected = aLoopSelected_.load(std::memory_order_relaxed);
  s.loopActive = aLoopActive_.load(std::memory_order_relaxed);
  s.loopAutoAdvance = aLoopAutoAdvance_.load(std::memory_order_relaxed);
  s.loopBaseLength = aLoopBaseLength_.load(std::memory_order_relaxed);
  s.loopBasePosition = aLoopBasePosition_.load(std::memory_order_relaxed);
  for (int32_t i = 0; i < Looper::kTracks; ++i) {
    s.trackState[i] = aTrackState_[i].load(std::memory_order_relaxed);
    s.trackLayers[i] = aTrackLayers_[i].load(std::memory_order_relaxed);
    s.trackMuted[i] = aTrackMuted_[i].load(std::memory_order_relaxed);
    s.trackVolume[i] = aTrackVolume_[i].load(std::memory_order_relaxed);
    s.trackLength[i] = aTrackLength_[i].load(std::memory_order_relaxed);
    s.trackPosition[i] = aTrackPosition_[i].load(std::memory_order_relaxed);
  }
  return s;
}

}  // namespace loopin
