// Loopin — batería
// SPDX-License-Identifier: GPL-3.0-or-later
#include "Drums.h"

#include <algorithm>
#include <cmath>

namespace loopin {

namespace {

constexpr float kGainSmoothing = 0.004f;

}  // namespace

// ---------------------------------------------------------------- patrones
//
// Cada patrón se escribe como una caja de ritmos: una fila por sonido y un
// carácter por paso (stepsPerBeat pasos por tiempo). Los espacios y las
// barras solo separan para leerlo mejor.
//   X = fuerte · x = normal · o = flojo (caja y charles: su muestra suave) · . = nada
// Filas: K bombo · S caja · C aro · H charles · O charles abierto · R ride · Y crash

Drums::Pattern Drums::parse(int32_t beats, uint32_t accents, int32_t stepsPerBeat,
                            std::initializer_list<const char*> rows) {
  Pattern p;
  p.beats = beats;
  p.accents = accents;
  p.stepsPerBeat = stepsPerBeat;
  int32_t steps = 0;
  for (const char* row : rows) {
    const char kind = row[0];
    int32_t step = 0;
    for (const char* c = row + 2; *c != '\0'; ++c) {
      if (*c == ' ' || *c == '|') continue;
      if (*c != '.') {
        const bool soft = *c == 'o';
        const float gain = *c == 'X' ? 1.0f : (*c == 'x' ? 0.75f : 0.5f);
        DrumSound s = DrumSound::kKick;
        float g = gain;
        switch (kind) {
          case 'K': s = DrumSound::kKick; break;
          case 'S':
            // La caja floja ya está grabada floja: suena a su volumen
            s = soft ? DrumSound::kSnareSoft : DrumSound::kSnare;
            if (soft) g = 1.0f;
            break;
          case 'C': s = DrumSound::kCrossStick; break;
          case 'H':
            s = soft ? DrumSound::kHatSoft : DrumSound::kHat;
            if (soft) g = 0.8f;
            break;
          case 'O': s = DrumSound::kHatOpen; break;
          case 'R': s = DrumSound::kRide; break;
          case 'Y': s = DrumSound::kCrash; break;
          default: break;
        }
        p.hits.push_back({step, s, g});
      }
      ++step;
    }
    steps = std::max(steps, step);
  }
  const int32_t perBar = beats * stepsPerBeat;
  p.bars = perBar > 0 ? std::max(1, steps / perBar) : 1;
  std::stable_sort(p.hits.begin(), p.hits.end(),
                   [](const Hit& a, const Hit& b) { return a.step < b.step; });
  return p;
}

void Drums::buildPatterns() {
  auto& P = patterns_;
  auto at = [&](DrumStyle s) -> Pattern& { return P[static_cast<size_t>(s)]; };
  // 4/4 en semicorcheas (4 pasos por tiempo)
  at(DrumStyle::kRock) = parse(4, 0, 4, {
      "K:X.......X.x.....|X.......X.x...x.",
      "S:....X.......X...|....X.......X...",
      "H:X.x.X.x.X.x.X.x.|X.x.X.x.X.x.X.x.",
  });
  at(DrumStyle::kPop) = parse(4, 0, 4, {
      "K:X.....x.X.......|X.....x.X.x.....",
      "S:....X.......X...|....X.......X...",
      "H:x.o.x.o.x.o.x.o.|x.o.x.o.x.o.x...",
      "O:................|..............x.",
  });
  at(DrumStyle::kFunk) = parse(4, 0, 4, {
      "K:X.x.......x..x..",
      "S:....X..o.o..X..o",
      "H:xoxoxoxoxoxoxo..",
      "O:..............x.",
  });
  at(DrumStyle::kBallad) = parse(4, 0, 4, {
      "K:X.........x.....",
      "C:....x.......x...",
      "H:x.o.x.o.x.o.x.o.",
  });
  // One drop: bombo y aro en el 3, charles a contratiempo
  at(DrumStyle::kReggae) = parse(4, 0, 4, {
      "K:........X.......",
      "C:........X.......",
      "H:o.x.o.x.o.x.o.x.",
  });
  // Shuffle: tresillos (3 pasos por tiempo), el charles en el 1 y el 3
  at(DrumStyle::kShuffle) = parse(4, 0, 3, {
      "K:X.....X.....",
      "S:...X.....X..",
      "H:x.ox.ox.ox.o",
  });
  // 3/4 en corcheas
  at(DrumStyle::kWaltz) = parse(3, 0, 2, {
      "K:X.....",
      "S:..x.x.",
      "H:x.x.x.",
  });
  // 6/8 (3+3) y 12/8 (3+3+3+3): el tiempo es la corchea
  at(DrumStyle::kSixEight) = parse(6, 1u << 3, 1, {
      "K:X.....|X..x..",
      "S:...X..|...X..",
      "H:xooxoo|xooxoo",
  });
  at(DrumStyle::kSlowBlues) = parse(12, (1u << 3) | (1u << 6) | (1u << 9), 1, {
      "K:X....xX.....",
      "S:...X.....X..",
      "R:xooxooxooxoo",
  });
}

int32_t Drums::styleBeats(DrumStyle style) {
  switch (style) {
    case DrumStyle::kBasic: return 0;
    case DrumStyle::kWaltz: return 3;
    case DrumStyle::kSixEight: return 6;
    case DrumStyle::kSlowBlues: return 12;
    default: return 4;
  }
}

uint32_t Drums::styleAccents(DrumStyle style) {
  switch (style) {
    case DrumStyle::kSixEight: return 1u << 3;
    case DrumStyle::kSlowBlues: return (1u << 3) | (1u << 6) | (1u << 9);
    default: return 0;
  }
}

// ---------------------------------------------------------------- muestras

void Drums::setSample(DrumSound sound, const float* data, int32_t frames, int32_t srcRate) {
  const size_t i = idx(sound);
  if (i >= raw_.size()) return;
  if (data == nullptr || frames <= 0 || srcRate <= 0) {
    raw_[i].clear();
    rawRate_[i] = 0;
    return;
  }
  raw_[i].assign(data, data + frames);
  rawRate_[i] = srcRate;
}

void Drums::prepare(int32_t sampleRate) {
  sampleRate_ = sampleRate > 0 ? sampleRate : 48000;
  // Interpolación lineal: de 48 a 44,1 kHz (o al revés) basta para golpes
  for (size_t i = 0; i < raw_.size(); ++i) {
    const std::vector<float>& src = raw_[i];
    std::vector<float>& dst = kit_[i];
    if (src.empty() || rawRate_[i] <= 0) {
      dst.clear();
      continue;
    }
    if (rawRate_[i] == sampleRate_) {
      dst = src;
      continue;
    }
    const double ratio = double(rawRate_[i]) / double(sampleRate_);
    const size_t n = static_cast<size_t>(std::floor(double(src.size() - 1) / ratio)) + 1;
    dst.assign(n, 0.0f);
    for (size_t k = 0; k < n; ++k) {
      const double x = double(k) * ratio;
      const size_t a = static_cast<size_t>(x);
      const double f = x - double(a);
      const float s0 = src[a];
      const float s1 = a + 1 < src.size() ? src[a + 1] : 0.0f;
      dst[k] = static_cast<float>(s0 + (s1 - s0) * f);
    }
  }
  if (patterns_[static_cast<size_t>(DrumStyle::kRock)].hits.empty()) buildPatterns();
  chokeFrames_ = std::max(1, sampleRate_ / 200);
  for (Voice& v : voices_) v = Voice{};
  eventCount_ = eventIdx_ = posInBeat_ = 0;
  started_ = false;
  frame_ = 0;
  style_ = pendingStyle_;
  gain_ = volume_;
}

// ---------------------------------------------------------------- órdenes

void Drums::setEnabled(bool on) {
  if (on == enabled_) return;
  enabled_ = on;
  // Al apagarla lo que ya suena acaba solo (los platos no se cortan); al
  // encenderla entra en el siguiente 1
  started_ = false;
  eventCount_ = eventIdx_ = 0;
}

void Drums::setStyle(DrumStyle style, bool beatIsEighth) {
  const int32_t s = std::clamp(static_cast<int32_t>(style), 0,
                               static_cast<int32_t>(DrumStyle::kCount) - 1);
  pendingStyle_ = static_cast<DrumStyle>(s);
  eighths_ = beatIsEighth;
  // Sonando, el cambio espera al siguiente compás; parada, se aplica ya
  if (!started_) style_ = pendingStyle_;
}

void Drums::setVolume(float v) {
  volume_ = std::clamp(v, 0.0f, 1.5f);
  // Sin nada sonando no hace falta ir poco a poco
  bool sounding = false;
  for (const Voice& voice : voices_) sounding = sounding || voice.sample != nullptr;
  if (!sounding) gain_ = volume_;
}

void Drums::halt() {
  started_ = false;
  eventCount_ = eventIdx_ = 0;
}

void Drums::silence() {
  halt();
  for (Voice& v : voices_) v = Voice{};
}

DrumStyle Drums::resolve(int32_t beatsPerBar, uint32_t accentMask) const {
  if (style_ == DrumStyle::kBasic) return style_;
  const Pattern& p = patterns_[static_cast<size_t>(style_)];
  if (p.beats == beatsPerBar && (p.accents & ~1u) == (accentMask & ~1u)) return style_;
  return DrumStyle::kBasic;
}

// ---------------------------------------------------------------- secuenciador

void Drums::add(int32_t offset, DrumSound sound, float gain) {
  if (eventCount_ >= kMaxEvents) return;
  events_[static_cast<size_t>(eventCount_++)] = {offset, sound, gain};
}

// Básico, sacado de los acentos del compás: el compás se parte en grupos (los
// del compás o, si no tiene, uno por tiempo; el 3/4 va como un vals). Bombo en
// los grupos pares, caja en los impares y charles en cada tiempo (y en la
// corchea de en medio si el tiempo es una negra).
void Drums::basicBeat(int32_t beat, int32_t beatsPerBar, uint32_t accentMask, int32_t spb) {
  const uint32_t mask = accentMask & ~1u;
  bool groupStart = beat == 0;
  int32_t group = 0;  // grupo al que pertenece este tiempo
  if (mask == 0) {
    groupStart = true;
    group = beatsPerBar == 3 ? (beat == 0 ? 0 : 1) : beat;
  } else {
    for (int32_t b = 1; b <= beat && b < 32; ++b)
      if ((mask >> b) & 1u) ++group;
    if (beat > 0 && beat < 32 && ((mask >> beat) & 1u)) groupStart = true;
  }
  if (groupStart) {
    if (group % 2 == 0) {
      add(0, DrumSound::kKick, beat == 0 ? 1.0f : 0.8f);
    } else {
      add(0, DrumSound::kSnare, 0.85f);
    }
  }
  add(0, DrumSound::kHat, beat == 0 ? 1.0f : (groupStart ? 0.75f : 0.6f));
  if (!eighths_) add(spb / 2, DrumSound::kHatSoft, 0.8f);
}

bool Drums::beat(int32_t bar, int32_t beat, int32_t beatsPerBar, uint32_t accentMask,
                 int32_t samplesPerBeat, bool countIn, bool sticks, bool freshStart,
                 int32_t late) {
  eventCount_ = eventIdx_ = 0;
  posInBeat_ = std::max(0, late);
  if (!enabled_) return false;
  if (countIn) {
    // Cuenta de entrada con baquetas: más fuerte en el 1 y en cada grupo
    started_ = false;
    if (sticks) {
      const bool group = beat > 0 && beat < 32 && ((accentMask >> beat) & 1u);
      add(0, DrumSound::kSticks, beat == 0 ? 1.0f : (group ? 0.8f : 0.65f));
    }
    return true;
  }
  bool entrance = false;
  if (beat == 0) {
    // Los cambios de estilo esperan al compás
    if (style_ != pendingStyle_) style_ = pendingStyle_;
    effective_ = resolve(beatsPerBar, accentMask);
    if (!started_ || freshStart) entrance = true;
    started_ = true;
  }
  if (!started_) return false;  // ha arrancado a mitad de compás: espera al 1

  if (entrance) add(0, DrumSound::kCrash, 0.9f);
  if (effective_ == DrumStyle::kBasic) {
    basicBeat(beat, beatsPerBar, accentMask, samplesPerBeat);
    return true;
  }
  const Pattern& p = patterns_[static_cast<size_t>(effective_)];
  const int32_t perBar = p.beats * p.stepsPerBeat;
  const int32_t first = (bar % p.bars) * perBar + beat * p.stepsPerBeat;
  const int32_t last = first + p.stepsPerBeat;
  for (const Hit& h : p.hits) {
    if (h.step < first) continue;
    if (h.step >= last) break;
    // El desfase de cada paso dentro del tiempo se redondea a la muestra
    const int32_t sub = h.step - first;
    const int32_t offset = static_cast<int32_t>(
        (int64_t(sub) * samplesPerBeat + p.stepsPerBeat / 2) / p.stepsPerBeat);
    add(offset, h.sound, h.gain);
  }
  return true;
}

void Drums::trigger(DrumSound sound, float gain) {
  if (log_ != nullptr) log_->push_back({frame_, sound, gain});
  const std::vector<float>& sample = kit_[idx(sound)];
  if (sample.empty()) return;
  // El charles cerrado corta el abierto (como el pie en el pedal)
  if (sound == DrumSound::kHat || sound == DrumSound::kHatSoft) {
    for (Voice& v : voices_)
      if (v.sample != nullptr && v.sound == DrumSound::kHatOpen && v.fade == 0)
        v.fade = chokeFrames_;
  }
  Voice* slot = nullptr;
  for (Voice& v : voices_) {
    if (v.sample == nullptr) {
      slot = &v;
      break;
    }
  }
  if (slot == nullptr) {
    // Todas ocupadas: se usa la que lleva más rato sonando
    slot = &voices_[0];
    for (Voice& v : voices_)
      if (v.pos > slot->pos) slot = &v;
  }
  slot->sample = &sample;
  slot->sound = sound;
  slot->pos = 0;
  slot->gain = gain;
  slot->fade = 0;
}

float Drums::next() {
  while (eventIdx_ < eventCount_ && events_[static_cast<size_t>(eventIdx_)].offset <= posInBeat_) {
    const Event& e = events_[static_cast<size_t>(eventIdx_++)];
    trigger(e.sound, e.gain);
  }
  ++posInBeat_;
  ++frame_;
  float out = 0.0f;
  for (Voice& v : voices_) {
    if (v.sample == nullptr) continue;
    float g = v.gain;
    if (v.fade > 0) {
      g *= float(v.fade) / float(chokeFrames_);
      if (--v.fade == 0) {
        v.sample = nullptr;
        continue;
      }
    }
    out += (*v.sample)[v.pos] * g;
    if (++v.pos >= v.sample->size()) v.sample = nullptr;
  }
  if (gain_ != volume_) {
    gain_ += (volume_ - gain_) * kGainSmoothing;
    if (std::fabs(gain_ - volume_) < 1e-4f) gain_ = volume_;
  }
  return out * gain_;
}

}  // namespace loopin
