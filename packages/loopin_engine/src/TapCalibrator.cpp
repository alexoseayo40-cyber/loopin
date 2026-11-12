// Loopin — calibración de la latencia tocando al clic
// SPDX-License-Identifier: GPL-3.0-or-later
#include "TapCalibrator.h"

#include <algorithm>
#include <cmath>

namespace loopin {

void TapCalibrator::prepare(int32_t sampleRate) {
  sampleRate_ = sampleRate > 0 ? sampleRate : 48000;
  clicks_.prepare(sampleRate_);
  onset_.prepare(sampleRate_);
  period_ = std::llround(60.0 * sampleRate_ / kBpm);
  state_ = State::kIdle;
}

void TapCalibrator::start() {
  state_ = State::kRunning;
  justStarted_ = true;
  clicksPlayed_ = 0;
  hits_ = 0;
  hit_.fill(false);
  offsets_.fill(0);
  resultFrames_ = 0;
  spreadFrames_ = 0;
  // Un golpe cada 750 ms como mucho: se ignora lo que suene en los 250 ms
  // siguientes a un golpe (el resto de un rasgueo, un rebote...)
  onset_.reset(0.01f, sampleRate_ / 4);
}

void TapCalibrator::cancel() {
  if (state_ == State::kRunning) state_ = State::kIdle;
}

void TapCalibrator::process(const float* inMono, int32_t inFrames, int64_t inStart,
                            float* outMono, int32_t outFrames, int64_t outStart) {
  if (state_ != State::kRunning) return;
  if (justStarted_) {
    justStarted_ = false;
    firstClick_ = outStart + sampleRate_ / 2;  // medio segundo para prepararse
  }

  // Clics: el primero de cada 4, más fuerte
  for (int32_t i = 0; i < outFrames; ++i) {
    const int64_t n = outStart + i;
    if (clicksPlayed_ < kTotal && n == clickAt(clicksPlayed_)) {
      clicks_.trigger(clicksPlayed_ % 4 == 0 ? Metronome::Accent::kStrong
                                             : Metronome::Accent::kWeak);
      ++clicksPlayed_;
    }
    outMono[i] += clicks_.next() * 0.9f;
  }

  // Golpes: cada uno se asigna al clic del que esté entre 150 ms antes y
  // 600 ms después. Cuenta el primero de cada clic.
  const int64_t early = int64_t(sampleRate_) * 15 / 100;
  for (int32_t i = 0; i < inFrames; ++i) {
    if (!onset_.push(inMono[i])) continue;
    const int64_t j = inStart + i;
    const int64_t k = (j - firstClick_ + early) / period_;
    if (j - firstClick_ + early < 0 || k < kCountIn || k >= kTotal) continue;
    const int32_t idx = static_cast<int32_t>(k - kCountIn);
    if (hit_[static_cast<size_t>(idx)]) continue;
    hit_[static_cast<size_t>(idx)] = true;
    offsets_[static_cast<size_t>(idx)] = static_cast<int32_t>(j - clickAt(static_cast<int32_t>(k)));
    ++hits_;
  }

  // Se acaba cuando ya no puede llegar ningún golpe del último clic
  const int64_t lastWindowEnd = clickAt(kTotal - 1) + (period_ - early);
  if (inStart + inFrames >= lastWindowEnd) finish();
}

void TapCalibrator::finish() {
  std::array<int32_t, kCounted> v{};
  int32_t n = 0;
  for (int32_t i = 0; i < kCounted; ++i)
    if (hit_[static_cast<size_t>(i)]) v[static_cast<size_t>(n++)] = offsets_[static_cast<size_t>(i)];
  if (n < kMinHits) {
    state_ = State::kFailed;
    return;
  }
  auto median = [](int32_t* first, int32_t count) {
    std::sort(first, first + count);
    return count % 2 == 1 ? first[count / 2]
                          : static_cast<int32_t>((int64_t(first[count / 2 - 1]) + first[count / 2]) / 2);
  };
  const int32_t med = median(v.data(), n);
  std::array<int32_t, kCounted> dev{};
  for (int32_t i = 0; i < n; ++i) dev[static_cast<size_t>(i)] = std::abs(v[static_cast<size_t>(i)] - med);
  spreadFrames_ = median(dev.data(), n);
  // La compensación no puede ser negativa ni pasar de medio segundo
  resultFrames_ = std::clamp(med, 0, sampleRate_ / 2);
  state_ = State::kDone;
}

}  // namespace loopin
