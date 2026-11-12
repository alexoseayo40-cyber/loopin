// Loopin — metrónomo
// SPDX-License-Identifier: GPL-3.0-or-later
#include "Metronome.h"

#include <cmath>

namespace loopin {

namespace {

constexpr double kPi = 3.14159265358979323846;

// Seno con caída exponencial y un ataque de 1 ms para que no chasque.
std::vector<float> makeClick(int32_t sampleRate, double freq, double gain) {
  const double durationS = 0.045;
  const size_t length = static_cast<size_t>(sampleRate * durationS);
  const double attack = sampleRate * 0.001;
  const double decay = sampleRate * 0.010;  // constante de tiempo
  std::vector<float> out(length);
  for (size_t i = 0; i < length; ++i) {
    const double t = double(i);
    const double env = (t < attack ? t / attack : 1.0) * std::exp(-t / decay);
    out[i] = static_cast<float>(gain * env * std::sin(2.0 * kPi * freq * t / sampleRate));
  }
  return out;
}

}  // namespace

void Metronome::prepare(int32_t sampleRate) {
  current_ = nullptr;
  index_ = 0;
  clicks_[static_cast<int>(Accent::kStrong)] = makeClick(sampleRate, 1760.0, 0.9);
  clicks_[static_cast<int>(Accent::kMedium)] = makeClick(sampleRate, 1320.0, 0.7);
  clicks_[static_cast<int>(Accent::kWeak)] = makeClick(sampleRate, 1320.0, 0.5);
}

Metronome::Accent Metronome::accentFor(int32_t beat, uint32_t accentMask) {
  if (beat == 0) return Accent::kStrong;
  if (beat < 32 && (accentMask >> beat) & 1u) return Accent::kMedium;
  return Accent::kWeak;
}

}  // namespace loopin
