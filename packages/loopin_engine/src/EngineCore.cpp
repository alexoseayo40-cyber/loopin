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
  tap_.prepare(sampleRate_);
  // 6 s de entrada: cubre la latencia (≤ 0,5 s), el margen para empezar a
  // grabar un poco tarde (≤ 1 s) y bloques grandes.
  ring_.prepare(sampleRate_ * 6);
  looper_.prepare(sampleRate_, &transport_);
  drums_.prepare(sampleRate_);
  backing_.prepare(sampleRate_, bin_);
  outPos_ = 0;
  monRead_ = 0;
  wasPlaying_ = false;
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
      // Antiguo: encendido = siempre; apagado = solo en la cuenta
      clickMode_ = cmd.value != 0.0 ? ClickMode::kAlways : ClickMode::kCountIn;
      break;
    case Command::Type::kSetClickMode:
      clickMode_ = static_cast<ClickMode>(std::clamp(static_cast<int32_t>(cmd.value), 0, 2));
      break;
    case Command::Type::kSetMeter:
      if (!looper_.locksTempo())
        transport_.setMeter(static_cast<int32_t>(cmd.value), static_cast<uint32_t>(cmd.arg));
      break;
    case Command::Type::kStartTapCalibration:
      // No mientras se graba: los clics acabarían dentro del loop
      if (!latency_.active() && !tap_.active() && looper_.active() < 0) tap_.start();
      break;
    case Command::Type::kCancelTapCalibration:
      tap_.cancel();
      break;
    case Command::Type::kNudgeLatency: {
      const int32_t old = looper_.latency();
      looper_.setLatency(static_cast<int32_t>(cmd.value));
      looper_.shiftAudio(looper_.latency() - old, now);
      break;
    }
    case Command::Type::kSetStartOnSound:
      looper_.setStartOnSound(cmd.value != 0.0);
      break;
    case Command::Type::kSetDrumsEnabled:
      drums_.setEnabled(cmd.value != 0.0);
      break;
    case Command::Type::kSetDrumStyle:
      drums_.setStyle(static_cast<DrumStyle>(static_cast<int32_t>(cmd.value)), cmd.arg != 0);
      break;
    case Command::Type::kSetDrumVolume:
      drums_.setVolume(static_cast<float>(cmd.value));
      break;
    case Command::Type::kSetBackingEnabled:
      backing_.setEnabled(cmd.value != 0.0);
      break;
    case Command::Type::kSetBackingVolume:
      backing_.setVolume(static_cast<float>(cmd.value));
      break;
    case Command::Type::kPreviewPlay:
      backing_.previewPlay(static_cast<int64_t>(cmd.value));
      break;
    case Command::Type::kPreviewStop:
      backing_.previewStop();
      break;
    case Command::Type::kSetPreviewClick:
      backing_.setPreviewClick(cmd.value != 0.0);
      break;
    case Command::Type::kSetPreviewMark:
      backing_.setPreviewMark(cmd.value, static_cast<uint32_t>(cmd.arg));
      break;
    case Command::Type::kSetPreviewBeat:
      backing_.setPreviewBeat(cmd.value, cmd.arg);
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
      looper_.setMode(static_cast<Looper::Mode>(std::clamp(static_cast<int32_t>(cmd.value), 0, 2)));
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
    case Command::Type::kSetRecordDuck:
      looper_.setRecordDuck(static_cast<float>(cmd.value));
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
  // Los clips nuevos del audio importado van antes que las órdenes (una orden
  // de la vista previa puede ser para el clip que acaba de llegar)
  backing_.takeClips(retired_);
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

  // Mientras se mide la latencia (con el altavoz o tocando) solo suena lo
  // del medidor
  const bool measuring = latency_.active() || tap_.active();
  for (int32_t i = 0; i < n; ++i) {
    // El looper va primero: si en esta muestra empieza a grabar, el clic de
    // este tiempo ya no es de la cuenta de entrada
    const float loop = looper_.render(outPos_ + i);
    if (transport_.tick()) {
      metronome_.trigger(Metronome::accentFor(transport_.beat(), transport_.accentMask()));
      // Se decide al empezar cada clic (un clic nunca se corta a medias). En
      // libre no hay metrónomo; en la cuenta de entrada suena salvo en «nunca»
      const bool countIn = looper_.forcesClick();
      clickGate_ = looper_.mode() != Looper::Mode::kFree &&
                   (clickMode_ == ClickMode::kAlways ||
                    (clickMode_ == ClickMode::kCountIn && countIn));
      // La batería toca este tiempo (o, en la cuenta, las baquetas en lugar
      // del clic): entonces el clic se calla, la batería ya marca el tempo
      const bool sticks = clickMode_ != ClickMode::kSilent;
      if (drums_.beat(transport_.bar(), transport_.beat(), transport_.beatsPerBar(),
                      transport_.accentMask(), transport_.samplesPerBeat(), countIn, sticks,
                      transport_.framePosition() == 1)) {
        clickGate_ = false;
      }
      backing_.beat(transport_.bar(), transport_.beat(), transport_.samplesPerBeat(),
                    transport_.beatsPerBar(), countIn);
    } else if (!transport_.playing()) {
      drums_.halt();
      backing_.halt();
    } else if (!wasPlaying_ && transport_.beat() == 0 &&
               (drums_.enabled() || backing_.enabled()) && transport_.framesSinceBeat() >= 1 &&
               transport_.framesSinceBeat() <= sampleRate_ / 50) {
      // El transporte acaba de arrancar «desde atrás», un pelín pasado un 1
      // (al cerrar el primer loop en libre se recorta a muestras enteras por
      // tiempo): la batería y la canción entran ya en vez de esperar un compás
      const int32_t late = transport_.framesSinceBeat() - 1;
      drums_.beat(transport_.bar(), 0, transport_.beatsPerBar(), transport_.accentMask(),
                  transport_.samplesPerBeat(), false, false, false, late);
      backing_.beat(transport_.bar(), 0, transport_.samplesPerBeat(), transport_.beatsPerBar(),
                    false, late);
    }
    wasPlaying_ = transport_.playing();
    // La vista previa del audio importado lleva su propio clic (el transporte
    // está parado mientras se prepara una canción)
    if (const int32_t pc = backing_.previewClickNow()) {
      metronome_.trigger(static_cast<Metronome::Accent>(pc - 1));
      clickGate_ = true;
    }
    const float click = metronome_.next();
    const float drums = drums_.next();
    const float song = backing_.next(retired_);
    float mon = 0.0f;
    if (monRead_ < ring_.end()) mon = ring_.at(monRead_++);
    float s = 0.0f;
    if (!measuring) {
      if (clickGate_) s += click * clickVolume_;
      if (monitorEnabled_) s += mon * monitorVolume_;
      s += loop + drums + song;
    }
    outMono_[i] = s;
  }

  // El medidor añade su pulso a outMono_ (con todo lo demás en silencio)
  latency_.process(inMono_.data(), inFrames, inStart, outMono_.data(), n, outPos_);
  tap_.process(inMono_.data(), inFrames, inStart, outMono_.data(), n, outPos_);
  outPos_ += n;

  // Lo que ha entrado se graba en el loop (con la latencia compensada)
  looper_.capture(ring_, outPos_);
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
  aBeatFrames_.store(transport_.framesSinceBeat(), std::memory_order_relaxed);
  aAccentMask_.store(static_cast<int32_t>(transport_.accentMask()), std::memory_order_relaxed);
  aClickMode_.store(static_cast<int32_t>(clickMode_), std::memory_order_relaxed);
  aLoopWaiting_.store(looper_.waiting() ? 1 : 0, std::memory_order_relaxed);
  aStartOnSound_.store(looper_.startOnSound() ? 1 : 0, std::memory_order_relaxed);
  aTapClicks_.store(tap_.clicks(), std::memory_order_relaxed);
  aTapHits_.store(tap_.hits(), std::memory_order_relaxed);
  aTapFrames_.store(tap_.resultFrames(), std::memory_order_relaxed);
  aTapSpread_.store(tap_.spreadFrames(), std::memory_order_relaxed);
  aDrumsEnabled_.store(drums_.enabled() ? 1 : 0, std::memory_order_relaxed);
  aDrumStyle_.store(static_cast<int32_t>(drums_.style()), std::memory_order_relaxed);
  aDrumsPlaying_.store(drums_.playing() ? 1 : 0, std::memory_order_relaxed);
  aDrumVolume_.store(drums_.volume(), std::memory_order_relaxed);
  const Clip* song = backing_.song();
  const Clip* preview = backing_.preview();
  aBackingEnabled_.store(backing_.enabled() ? 1 : 0, std::memory_order_relaxed);
  aBackingPlaying_.store(backing_.enabled() && backing_.playing() ? 1 : 0,
                         std::memory_order_relaxed);
  aBackingId_.store(song != nullptr ? song->id : 0, std::memory_order_relaxed);
  aBackingSpb_.store(song != nullptr ? song->samplesPerBeat : 0, std::memory_order_relaxed);
  aBackingBpb_.store(song != nullptr ? song->beatsPerBar : 0, std::memory_order_relaxed);
  aBackingPosition_.store(backing_.position(), std::memory_order_relaxed);
  aBackingLength_.store(song != nullptr ? song->frames() : 0, std::memory_order_relaxed);
  aBackingVolume_.store(backing_.volume(), std::memory_order_relaxed);
  aPreviewId_.store(preview != nullptr ? preview->id : 0, std::memory_order_relaxed);
  aPreviewPlaying_.store(backing_.previewPlaying() ? 1 : 0, std::memory_order_relaxed);
  aPreviewClick_.store(backing_.previewClick() ? 1 : 0, std::memory_order_relaxed);
  aPreviewPosition_.store(backing_.previewPosition(), std::memory_order_relaxed);
  aPreviewLength_.store(preview != nullptr ? preview->frames() : 0, std::memory_order_relaxed);
  aTapState_.store(static_cast<int32_t>(tap_.state()), std::memory_order_release);

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
  s.tapState = aTapState_.load(std::memory_order_acquire);
  s.tapClicks = aTapClicks_.load(std::memory_order_relaxed);
  s.tapHits = aTapHits_.load(std::memory_order_relaxed);
  s.tapFrames = aTapFrames_.load(std::memory_order_relaxed);
  s.tapSpread = aTapSpread_.load(std::memory_order_relaxed);
  s.beatFrames = aBeatFrames_.load(std::memory_order_relaxed);
  s.accentMask = aAccentMask_.load(std::memory_order_relaxed);
  s.clickMode = aClickMode_.load(std::memory_order_relaxed);
  s.loopWaiting = aLoopWaiting_.load(std::memory_order_relaxed);
  s.startOnSound = aStartOnSound_.load(std::memory_order_relaxed);
  s.drumsEnabled = aDrumsEnabled_.load(std::memory_order_relaxed);
  s.drumStyle = aDrumStyle_.load(std::memory_order_relaxed);
  s.drumsPlaying = aDrumsPlaying_.load(std::memory_order_relaxed);
  s.drumVolume = aDrumVolume_.load(std::memory_order_relaxed);
  s.backingEnabled = aBackingEnabled_.load(std::memory_order_relaxed);
  s.backingPlaying = aBackingPlaying_.load(std::memory_order_relaxed);
  s.backingId = aBackingId_.load(std::memory_order_relaxed);
  s.backingSpb = aBackingSpb_.load(std::memory_order_relaxed);
  s.backingBpb = aBackingBpb_.load(std::memory_order_relaxed);
  s.backingPosition = aBackingPosition_.load(std::memory_order_relaxed);
  s.backingLength = aBackingLength_.load(std::memory_order_relaxed);
  s.backingVolume = aBackingVolume_.load(std::memory_order_relaxed);
  s.previewId = aPreviewId_.load(std::memory_order_relaxed);
  s.previewPlaying = aPreviewPlaying_.load(std::memory_order_relaxed);
  s.previewClick = aPreviewClick_.load(std::memory_order_relaxed);
  s.previewPosition = aPreviewPosition_.load(std::memory_order_relaxed);
  s.previewLength = aPreviewLength_.load(std::memory_order_relaxed);
  return s;
}

}  // namespace loopin
