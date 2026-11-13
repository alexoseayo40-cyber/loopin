// Loopin — cola sin bloqueos de un productor y un consumidor
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <array>
#include <atomic>
#include <cstddef>

namespace loopin {

// Capacity debe ser potencia de 2. push() desde un solo hilo (la interfaz) y
// pop() desde otro (el audio). Ni reserva memoria ni bloquea.
template <typename T, size_t Capacity>
class SpscQueue {
  static_assert((Capacity & (Capacity - 1)) == 0, "Capacity debe ser potencia de 2");

 public:
  bool push(const T& item) {
    const size_t head = head_.load(std::memory_order_relaxed);
    const size_t tail = tail_.load(std::memory_order_acquire);
    if (head - tail >= Capacity) return false;  // llena
    items_[head & (Capacity - 1)] = item;
    head_.store(head + 1, std::memory_order_release);
    return true;
  }

  bool pop(T& out) {
    const size_t tail = tail_.load(std::memory_order_relaxed);
    const size_t head = head_.load(std::memory_order_acquire);
    if (tail == head) return false;  // vacía
    out = items_[tail & (Capacity - 1)];
    tail_.store(tail + 1, std::memory_order_release);
    return true;
  }

  // Productor: el consumidor ya ha sacado todo lo que se ha metido (lo que
  // hizo antes de sacarlo es visible desde aquí).
  bool drained() const {
    return tail_.load(std::memory_order_acquire) == head_.load(std::memory_order_relaxed);
  }
  // Consumidor: queda algo por sacar.
  bool pending() const {
    return head_.load(std::memory_order_acquire) != tail_.load(std::memory_order_relaxed);
  }

 private:
  std::array<T, Capacity> items_{};
  alignas(64) std::atomic<size_t> head_{0};
  alignas(64) std::atomic<size_t> tail_{0};
};

}  // namespace loopin
