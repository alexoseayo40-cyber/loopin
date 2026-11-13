// Loopin — looper: escribir la entrada, borrar y trabajo de fondo
// SPDX-License-Identifier: GPL-3.0-or-later
#include "Looper.h"

#include <algorithm>
#include <cmath>

namespace loopin {

// ---------------------------------------------------------------- capas

void Looper::finishBackground(Layer& l) {
  const size_t end = static_cast<size_t>(std::min(l.extent, capacity_));
  if (l.st == Layer::St::kMerging) {
    std::vector<float>& dst = tr(l.track).data;
    for (size_t i = static_cast<size_t>(l.cursor); i < end; ++i) {
      dst[i] += l.data[i];
      l.data[i] = 0.0f;
    }
  } else if (l.st == Layer::St::kClearing) {
    std::fill(l.data.begin() + static_cast<std::ptrdiff_t>(l.cursor),
              l.data.begin() + static_cast<std::ptrdiff_t>(std::max(end, size_t(l.cursor))), 0.0f);
  }
  l.st = Layer::St::kEmpty;
  l.winOpen = false;
  l.cursor = 0;
  l.extent = 0;
}

// ---------------------------------------------------------------- borrar

void Looper::startClear(Track& t, int64_t extent) {
  extent = std::clamp<int64_t>(extent, 0, capacity_);
  if (t.clearing) extent = std::max(extent, t.clearExtent);
  t.clearing = true;
  t.clearCursor = 0;
  t.clearExtent = extent;
}

void Looper::finishClear(Track& t) {
  if (t.clearing) {
    std::fill(t.data.begin() + static_cast<std::ptrdiff_t>(t.clearCursor),
              t.data.begin() + static_cast<std::ptrdiff_t>(std::max(t.clearExtent, t.clearCursor)),
              0.0f);
  }
  t.clearing = false;
  t.clearCursor = 0;
  t.clearExtent = 0;
}

// Quita una pista con contenido y sus capas (no toca el estado general)
void Looper::dropTrack(int32_t track) {
  for (Layer& l : layers_) {
    if (l.track != track || l.st == Layer::St::kEmpty || l.st == Layer::St::kClearing) continue;
    if (l.st == Layer::St::kLive) last_ = Last::kNone;
    discard(l);
  }
  Track& t = tr(track);
  if (t.len > 0) startClear(t, t.len);
  t.len = 0;
  t.layers = 0;
  t.winOpen = false;
  resetTrackFx(t);
  rescheduleTrackChanges();
  if (last_ == Last::kTrack && lastTrack_ == track) last_ = Last::kNone;
}

void Looper::clearTrack(int32_t track, int64_t /*now*/) {
  if (track < 0 || track >= kTracks) return;
  if (recordingTrack()) {
    // Se cancela la grabación si es en esta pista o si, sin esta pista, ya no
    // quedaría ningún loop sobre el que grabar
    bool others = false;
    for (int32_t i = 0; i < kTracks; ++i) others = others || (i != track && tr(i).len > 0);
    if (track == active_ || !others) cancelRecording();
  } else if (state_ == State::kOverdubbing && track == active_) {
    state_ = State::kPlaying;
  }
  dropTrack(track);
  refreshEmpty();
  clearPre();
}

void Looper::clearAll(int64_t /*now*/) {
  if (recordingTrack()) cancelRecording();
  if (state_ == State::kOverdubbing) state_ = State::kPlaying;
  for (int32_t i = 0; i < kTracks; ++i) dropTrack(i);
  refreshEmpty();
  clearPre();
}

// ---------------------------------------------------------------- captura

void Looper::capture(const InputRing& in, int64_t now) {
  if (waiting_) {
    // Primero se mide el ruido de fondo (150 ms) y luego se busca el primer
    // ataque por encima de él
    if (scanPos_ < 0) scanPos_ = in.end();
    scanPos_ = std::max(scanPos_, in.begin());
    for (; scanPos_ < in.end(); ++scanPos_) {
      const float x = in.at(scanPos_);
      if (warmup_ > 0) {
        noisePeak_ = std::max(noisePeak_, std::fabs(x));
        if (--warmup_ == 0) onset_.reset(std::clamp(3.0f * noisePeak_, 0.02f, 0.5f), 0);
        continue;
      }
      if (onset_.push(x)) {
        // El ataque se nota un poco después de empezar: 2 ms antes
        const int64_t start = scanPos_ - latency_ - sampleRate_ / 500;
        startFirstAt(start, now);
        break;
      }
    }
  }
  const int64_t end = in.end() - latency_;  // se pueden capturar los n < end
  bool open = false;
  for (const Track& t : tracks_) open = open || t.winOpen;
  for (const Layer& l : layers_) open = open || l.winOpen;
  if (!open) {
    capN_ = std::max(capN_, end);
    return;
  }
  int64_t n = std::max(capN_, in.begin() - latency_);
  for (; n < end; ++n) {
    const float x = in.at(n + latency_);
    for (Track& t : tracks_) {
      if (t.winOpen && n >= t.winStart && n < t.winEnd) {
        const int64_t idx = n - t.winStart;
        if (idx < capacity_) t.data[static_cast<size_t>(idx)] = x;
      }
    }
    for (Layer& l : layers_) {
      if (l.winOpen && n >= l.winStart && n < l.winEnd) {
        // Donde se oía la pista en n (al revés o a media velocidad, también)
        const int64_t q = wrap(l.q0 + int64_t(l.dq) * (n - l.winStart), 2 * l.extent);
        l.data[static_cast<size_t>(q >> 1)] += (l.dq == 2 || l.dq == -2) ? x : 0.5f * x;
      }
    }
  }
  capN_ = std::max(capN_, n);
  for (int32_t i = 0; i < kTracks; ++i) {
    Track& t = tr(i);
    // La pista que se está grabando no se cierra hasta que acabe
    if (t.winOpen && !(recordingTrack() && i == active_) && capN_ >= t.winEnd) t.winOpen = false;
  }
  for (Layer& l : layers_)
    if (l.winOpen && capN_ >= l.winEnd) l.winOpen = false;
}

// ---------------------------------------------------------------- fondo

void Looper::background(int32_t budget) {
  for (Layer& l : layers_) {
    if (budget <= 0) return;
    const bool merging = l.st == Layer::St::kMerging && !l.winOpen;
    const bool clearing = l.st == Layer::St::kClearing;
    if (!merging && !clearing) continue;
    std::vector<float>& dst = tr(l.track).data;
    const int64_t end = std::min(std::min(l.extent, capacity_), l.cursor + budget);
    for (int64_t i = l.cursor; i < end; ++i) {
      const size_t k = static_cast<size_t>(i);
      if (merging) dst[k] += l.data[k];
      l.data[k] = 0.0f;
    }
    budget -= static_cast<int32_t>(end - l.cursor);
    l.cursor = end;
    if (l.cursor >= std::min(l.extent, capacity_)) {
      l.st = Layer::St::kEmpty;
      l.cursor = 0;
      l.extent = 0;
    }
  }
  for (Track& t : tracks_) {
    if (budget <= 0) return;
    if (!t.clearing) continue;
    const int64_t end = std::min(t.clearExtent, t.clearCursor + budget);
    if (end > t.clearCursor) {
      std::fill(t.data.begin() + static_cast<std::ptrdiff_t>(t.clearCursor),
                t.data.begin() + static_cast<std::ptrdiff_t>(end), 0.0f);
      budget -= static_cast<int32_t>(end - t.clearCursor);
      t.clearCursor = end;
    }
    if (t.clearCursor >= t.clearExtent) {
      t.clearing = false;
      t.clearCursor = 0;
      t.clearExtent = 0;
    }
  }
}

}  // namespace loopin
