// Loopin — anillo con las últimas muestras de entrada
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <algorithm>
#include <cstdint>
#include <vector>

namespace loopin {

// Últimas muestras de entrada (mono, ya con ganancia), indexadas por su índice
// absoluto de entrada. El looper lee de aquí con retraso (la latencia) y el
// monitor lee lo más reciente.
class InputRing {
 public:
  // Fuera del hilo de audio. Tamaño: la potencia de 2 que cubra minFrames.
  void prepare(int32_t minFrames) {
    size_t size = 1;
    while (size < static_cast<size_t>(std::max(minFrames, 1))) size <<= 1;
    if (data_.size() != size) data_.assign(size, 0.0f);
    mask_ = size - 1;
    reset();
  }
  void reset() {
    std::fill(data_.begin(), data_.end(), 0.0f);
    end_ = 0;
  }

  inline void push(float s) {
    data_[static_cast<size_t>(end_) & mask_] = s;
    ++end_;
  }
  inline float at(int64_t idx) const { return data_[static_cast<size_t>(idx) & mask_]; }
  int64_t end() const { return end_; }  // índice de la próxima muestra que llegue
  int64_t begin() const {               // la más antigua que aún se conserva
    const int64_t size = static_cast<int64_t>(data_.size());
    return end_ > size ? end_ - size : 0;
  }

 private:
  std::vector<float> data_;
  size_t mask_ = 0;
  int64_t end_ = 0;
};

}  // namespace loopin
