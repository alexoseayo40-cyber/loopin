// Loopin — audio importado: reproducción
// SPDX-License-Identifier: GPL-3.0-or-later
#include "Backing.h"

#include <algorithm>
#include <cmath>

namespace loopin {

namespace {

int64_t wrap(int64_t a, int64_t m) {
  const int64_t r = a % m;
  return r < 0 ? r + m : r;
}

// La vista previa suena un poco más baja que a tope: se suma al clic
constexpr float kPreviewGain = 0.8f;

}  // namespace

void Backing::prepare(int32_t sampleRate, ClipBin& bin) {
  sampleRate_ = sampleRate > 0 ? sampleRate : 48000;
  song_.dropUnless(sampleRate_, bin);
  preview_.dropUnless(sampleRate_, bin);
  bin.add(fading_);
  fading_ = nullptr;
  started_ = playing_ = previewPlaying_ = false;
  env_ = fadingEnv_ = 0.0f;
  pos_ = previewPos_ = 0;
  envUp_ = 1.0f / std::max(1, sampleRate_ / 1000);
  envDown_ = 1.0f / std::max(1, sampleRate_ / 200);
  gain_ = volume_;
}

void Backing::retire(Clip* c, RetiredClips& retired) {
  if (c != nullptr) retired.push(c);  // si la cola estuviera llena, se pierde (no pasa)
}

void Backing::takeClips(RetiredClips& retired) {
  bool changed = false;
  Clip* old = song_.take(&changed);
  if (changed) {
    const Clip* now = song_.current();
    if (old != nullptr && env_ > 0.0f) {
      // Sonaba: se apaga poco a poco en vez de cortarse de golpe
      retire(fading_, retired);
      fading_ = old;
      fadingPos_ = pos_;
      fadingEnv_ = env_;
    } else {
      retire(old, retired);
    }
    // La misma canción a otro tempo sigue por donde iba; otra canción
    // empieza desde el principio en el siguiente 1
    if (now == nullptr || old == nullptr || now->id != old->id) started_ = false;
    playing_ = false;
    env_ = 0.0f;
  }
  old = preview_.take(&changed);
  if (changed) {
    retire(old, retired);
    previewPlaying_ = false;
    previewPos_ = 0;
  }
}

void Backing::setEnabled(bool on) {
  if (on == enabled_) return;
  enabled_ = on;
  // Al encenderla entra en el siguiente 1, desde el principio
  started_ = false;
  playing_ = false;
}

void Backing::setVolume(float v) {
  volume_ = std::clamp(v, 0.0f, 1.5f);
  if (env_ == 0.0f && fading_ == nullptr) gain_ = volume_;
}

void Backing::beat(int32_t bar, int32_t beat, int32_t samplesPerBeat, int32_t beatsPerBar,
                   bool countIn, int32_t late) {
  const Clip* c = song_.current();
  if (countIn) {
    // Entra con la grabación, después de la cuenta
    started_ = false;
    stop();
    return;
  }
  const bool fits = enabled_ && c != nullptr && c->bars > 0 &&
                    c->samplesPerBeat == samplesPerBeat && c->beatsPerBar == beatsPerBar;
  if (!fits) {
    // Otro tempo (o apagada, o sin canción): se calla. Si es el tempo, la
    // canción estirada al tempo nuevo volverá a entrar por donde iría.
    stop();
    return;
  }
  if (beat != 0) return;  // entra y se recoloca solo en los 1
  if (!started_) {
    started_ = true;
    anchor_ = bar;
  }
  // En cada 1 se pone donde toca (ya debería estar ahí: así nunca se desvía)
  pos_ = wrap(int64_t(bar) - anchor_, c->bars) * c->barFrames + std::max(0, late);
  if (pos_ >= c->frames()) pos_ = wrap(pos_, c->frames());
  playing_ = true;
}

void Backing::halt() {
  started_ = false;
  stop();
}

void Backing::previewPlay(int64_t from) {
  const Clip* p = preview_.current();
  if (p == nullptr || p->frames() == 0) {
    previewPlaying_ = false;
    return;
  }
  previewPos_ = std::clamp<int64_t>(from, 0, p->frames() - 1);
  previewPlaying_ = true;
  if (beatLen_ > 0.0) {
    clickIndex_ = static_cast<int64_t>(std::ceil((double(previewPos_) - mark_) / beatLen_));
    scheduleClick();
  }
}

void Backing::setPreviewMark(double mark, uint32_t accentMask) {
  mark_ = mark;
  gridAccents_ = accentMask & ~1u;
  if (previewPlaying_ && beatLen_ > 0.0) previewPlay(previewPos_);
}

void Backing::setPreviewBeat(double beat, int32_t beatsPerBar) {
  beatLen_ = beat > 1.0 ? beat : 0.0;
  gridBeats_ = std::clamp(beatsPerBar, 1, 16);
  if (previewPlaying_ && beatLen_ > 0.0) previewPlay(previewPos_);
}

void Backing::scheduleClick() {
  clickAt_ = beatLen_ > 0.0 ? std::llround(mark_ + double(clickIndex_) * beatLen_) : -1;
}

int32_t Backing::previewClickNow() {
  if (!previewPlaying_ || !previewClick_ || clickAt_ < 0 || previewPos_ < clickAt_) return 0;
  const int64_t b = wrap(clickIndex_, gridBeats_);
  ++clickIndex_;
  scheduleClick();
  if (b == 0) return 1;
  return b < 32 && ((gridAccents_ >> b) & 1u) ? 2 : 3;
}

float Backing::next(RetiredClips& retired) {
  float out = 0.0f;
  const Clip* c = song_.current();
  const float target = playing_ && c != nullptr ? 1.0f : 0.0f;
  if (env_ < target) env_ = std::min(target, env_ + envUp_);
  else if (env_ > target) env_ = std::max(target, env_ - envDown_);
  if (c != nullptr && env_ > 0.0f) {
    out += c->at(pos_) * env_;
    if (++pos_ >= c->frames()) pos_ = 0;  // al acabar, vuelve a empezar (en un 1)
  }
  if (fading_ != nullptr) {
    fadingEnv_ -= envDown_;
    if (fadingEnv_ <= 0.0f || fadingPos_ >= fading_->frames()) {
      retire(fading_, retired);
      fading_ = nullptr;
    } else {
      out += fading_->at(fadingPos_++) * fadingEnv_;
    }
  }
  if (gain_ != volume_) {
    gain_ += (volume_ - gain_) * kGainSmoothing;
    if (std::fabs(gain_ - volume_) < 1e-4f) gain_ = volume_;
  }
  out *= gain_;

  const Clip* p = preview_.current();
  if (previewPlaying_ && p != nullptr) {
    out += p->at(previewPos_) * kPreviewGain;
    if (++previewPos_ >= p->frames()) previewPlaying_ = false;
  }
  return out;
}

}  // namespace loopin
