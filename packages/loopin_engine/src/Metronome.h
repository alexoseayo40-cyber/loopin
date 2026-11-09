// Loopin — metrónomo: clic sintetizado
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <cstdint>
#include <vector>

namespace loopin {

// Tres clics precalculados (acento, medio y normal). prepare() reserva la
// memoria y se llama fuera del hilo de audio; trigger() y next() no reservan.
class Metronome {
 public:
  enum class Accent { kStrong, kMedium, kWeak };

  void prepare(int32_t sampleRate);

  // Acento según el compás: el 1 siempre fuerte; en 6/8 el 4 es medio.
  static Accent accentFor(int32_t beat, int32_t beatsPerBar);

  void trigger(Accent accent) {
    current_ = &clicks_[static_cast<int>(accent)];
    index_ = 0;
  }

  // Siguiente muestra del clic (0 si no suena nada).
  inline float next() {
    if (current_ == nullptr) return 0.0f;
    if (index_ >= current_->size()) {
      current_ = nullptr;
      return 0.0f;
    }
    return (*current_)[index_++];
  }

  size_t clickLength() const { return clicks_[0].size(); }

 private:
  std::vector<float> clicks_[3];
  const std::vector<float>* current_ = nullptr;
  size_t index_ = 0;
};

}  // namespace loopin
