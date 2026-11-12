// Loopin — transporte
// SPDX-License-Identifier: GPL-3.0-or-later
#include "Transport.h"

#include <algorithm>
#include <cmath>

namespace loopin {

int32_t Transport::computeSamplesPerBeat(int32_t sampleRate, double bpm) {
  bpm = std::clamp(bpm, kMinBpm, kMaxBpm);
  return static_cast<int32_t>(std::llround(double(sampleRate) * 60.0 / bpm));
}

void Transport::setSampleRate(int32_t sampleRate) {
  sampleRate_ = sampleRate > 0 ? sampleRate : 48000;
  samplesPerBeat_ = computeSamplesPerBeat(sampleRate_, bpm_);
}

void Transport::setBpm(double bpm) {
  pendingBpm_ = std::clamp(bpm, kMinBpm, kMaxBpm);
  if (!playing_) {
    bpm_ = pendingBpm_;
    samplesPerBeat_ = computeSamplesPerBeat(sampleRate_, bpm_);
  }
}

void Transport::setBeatsPerBar(int32_t beatsPerBar) {
  setMeter(beatsPerBar, 0);
}

void Transport::setMeter(int32_t beatsPerBar, uint32_t accentMask) {
  pendingBeatsPerBar_ = std::clamp(beatsPerBar, 1, 16);
  pendingAccentMask_ = accentMask & ~1u;
  if (!playing_) {
    beatsPerBar_ = pendingBeatsPerBar_;
    accentMask_ = pendingAccentMask_;
  }
}

void Transport::playFrom(int64_t elapsed) {
  play();
  if (elapsed <= 0) return;
  const int64_t beats = elapsed / samplesPerBeat_;
  posInBeat_ = static_cast<int32_t>(elapsed % samplesPerBeat_);
  currentBeat_ = static_cast<int32_t>(beats % beatsPerBar_);
  currentBar_ = static_cast<int32_t>(beats / beatsPerBar_);
  posInBar_ = int64_t(currentBeat_) * samplesPerBeat_ + posInBeat_;
  framePosition_ = elapsed;
}

void Transport::play() {
  bpm_ = pendingBpm_;
  samplesPerBeat_ = computeSamplesPerBeat(sampleRate_, bpm_);
  beatsPerBar_ = pendingBeatsPerBar_;
  accentMask_ = pendingAccentMask_;
  posInBeat_ = 0;
  posInBar_ = 0;
  currentBeat_ = 0;
  currentBar_ = 0;
  framePosition_ = 0;
  playing_ = true;
}

void Transport::stop() { playing_ = false; }

int64_t Transport::framesToNextBar() const {
  if (!playing_ || posInBar_ == 0) return 0;
  // Lo que queda del tiempo actual (ya con su tempo) y los tiempos que faltan
  // del compás, que irán con el tempo pendiente.
  const int64_t nextSpb = computeSamplesPerBeat(sampleRate_, pendingBpm_);
  return int64_t(samplesPerBeat_ - posInBeat_) + int64_t(beatsPerBar_ - 1 - currentBeat_) * nextSpb;
}

void Transport::advanceBeat() {
  posInBeat_ = 0;
  ++currentBeat_;
  if (currentBeat_ >= beatsPerBar_) {
    currentBeat_ = 0;
    posInBar_ = 0;
    ++currentBar_;
    beatsPerBar_ = pendingBeatsPerBar_;
    accentMask_ = pendingAccentMask_;
  }
  if (pendingBpm_ != bpm_) {
    bpm_ = pendingBpm_;
    samplesPerBeat_ = computeSamplesPerBeat(sampleRate_, bpm_);
  }
}

}  // namespace loopin
