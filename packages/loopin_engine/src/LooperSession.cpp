// Loopin — looper: leer las pistas y cargarlas (sesiones, Etapa 6)
// SPDX-License-Identifier: GPL-3.0-or-later
#include <cstring>

#include "Looper.h"

namespace loopin {

bool Looper::settled() const {
  if (busy() || waiting_) return false;
  for (const Track& t : tracks_)
    if (t.winOpen || t.clearing) return false;
  for (const Layer& l : layers_) {
    if (l.winOpen) return false;
    if (l.st == Layer::St::kRecording || l.st == Layer::St::kMerging ||
        l.st == Layer::St::kClearing)
      return false;
  }
  return true;
}

int64_t Looper::trackOffset(int32_t track) const {
  const Track& t = tr(track);
  return t.len > 0 ? wrap(t.origin - origin_, t.len) : 0;
}

int64_t Looper::readTrack(int32_t track, float* out, int64_t max, uint64_t* hash) const {
  if (track < 0 || track >= kTracks) return 0;
  const Track& t = tr(track);
  const int64_t len = std::min(t.len, capacity_);
  // Capas de esta pista que suenan (las que se pueden deshacer)
  const Layer* live[2] = {nullptr, nullptr};
  int32_t nLive = 0;
  for (const Layer& l : layers_)
    if (l.track == track && l.audible() && nLive < 2) live[nLive++] = &l;
  // FNV-1a de 64 bits sobre los bits de cada muestra
  uint64_t h = 1469598103934665603ull;
  const bool copy = out != nullptr && len <= max;
  for (int64_t i = 0; i < len; ++i) {
    const size_t k = static_cast<size_t>(i);
    float s = t.data[k];
    for (int32_t j = 0; j < nLive; ++j) s += live[j]->data[k];
    if (copy) out[i] = s;
    if (hash != nullptr) {
      uint32_t bits;
      std::memcpy(&bits, &s, sizeof bits);
      h = (h ^ bits) * 1099511628211ull;
    }
  }
  if (hash != nullptr) *hash = len > 0 ? (h ^ uint64_t(len)) : 0;
  return len;
}

bool Looper::restore(const Restore& r, int64_t now) {
  if (state_ != State::kEmpty || !settled()) return false;
  if (r.barFrames <= 0 || r.baseLen <= 0 || r.baseLen % r.barFrames != 0) return false;
  bool any = false;
  for (int32_t i = 0; i < kTracks; ++i) {
    const int64_t len = r.len[i];
    if (len == 0) continue;
    const int64_t m = len / r.baseLen;
    if (len < 0 || len > capacity_ || len % r.baseLen != 0 || (m != 1 && m != 2 && m != 4))
      return false;
    any = true;
  }
  if (!any) return false;

  barFrames_ = r.barFrames;
  baseLen_ = r.baseLen;
  origin_ = now;
  for (int32_t i = 0; i < kTracks; ++i) {
    Track& t = tr(i);
    resetTrackFx(t);
    t.len = r.len[i];
    t.layers = t.len > 0 ? std::max(1, r.layers[i]) : 0;
    t.origin = now + (t.len > 0 ? wrap(r.offset[i], t.len) : 0);
    t.q = t.len > 0 ? gridQ(t, now) : 0;
    t.winOpen = false;
    t.muted = t.wantMuted;
    t.muteAt = kNever;
    t.gain = t.muted ? 0.0f : t.volume;
  }
  state_ = State::kStopped;
  last_ = Last::kNone;
  selected_ = std::clamp(r.selected, 0, kTracks - 1);
  nextEvent_ = kNever;
  stopAfterRec_ = false;
  userClosed_ = false;
  rescheduleTrackChanges();
  clearPre();
  return true;
}

}  // namespace loopin
