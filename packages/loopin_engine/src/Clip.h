// Loopin — audio importado ya preparado y su paso al hilo de audio
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <vector>

#include "SpscQueue.h"

namespace loopin {

// Un audio ya decodificado (y, si es para tocar encima, estirado al tempo).
// Mono, en 16 bits (la mitad de memoria que en float) y a la frecuencia del
// motor. Una vez entregado al hilo de audio ya no cambia.
struct Clip {
  std::vector<int16_t> pcm;
  int32_t rate = 0;
  int32_t id = 0;  // el que puso la app (para saber qué canción es)
  // Rejilla, solo en los que suenan con el transporte (0 en la vista previa).
  // pcm.size() == bars * barFrames y el 1 de la canción cae en un inicio de
  // compás.
  int32_t samplesPerBeat = 0;
  int32_t beatsPerBar = 0;
  int64_t barFrames = 0;
  int64_t bars = 0;

  float at(int64_t i) const { return float(pcm[static_cast<size_t>(i)]) * (1.0f / 32768.0f); }
  int64_t frames() const { return int64_t(pcm.size()); }

#ifdef LOOPIN_CLIP_COUNT
  // Los tests cuentan los clips vivos (para ver que no se pierde ninguno)
  Clip() { count().fetch_add(1); }
  ~Clip() { count().fetch_sub(1); }
  Clip(const Clip&) = delete;
  Clip& operator=(const Clip&) = delete;
  static std::atomic<int>& count() {
    static std::atomic<int> c{0};
    return c;
  }
#endif
};

// Los clips que el hilo de audio ya no usa vuelven por aquí para borrarlos
// fuera de él.
using RetiredClips = SpscQueue<Clip*, 64>;

// Clips que hay que borrar y que no vienen del hilo de audio (los que nunca
// llegó a coger). Solo se usa fuera del hilo de audio: puede bloquear.
class ClipBin {
 public:
  ~ClipBin() { collect(nullptr); }
  void add(Clip* c) {
    if (c == nullptr) return;
    std::lock_guard<std::mutex> lock(mutex_);
    clips_.push_back(c);
  }
  // Borra lo pendiente y lo que haya devuelto el hilo de audio. Desde un solo
  // hilo (el de la interfaz).
  void collect(RetiredClips* retired) {
    Clip* c = nullptr;
    if (retired != nullptr)
      while (retired->pop(c)) delete c;
    std::vector<Clip*> v;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      v.swap(clips_);
    }
    for (Clip* x : v) delete x;
  }

 private:
  std::mutex mutex_;
  std::vector<Clip*> clips_;
};

// Un hueco para un clip que suena. Cualquier hilo que no sea el de audio
// ofrece uno (o pide quitarlo); el hilo de audio lo coge al principio de un
// bloque y devuelve el anterior por la cola de retirados. Sin bloqueos.
class ClipSlot {
 public:
  // Fuera del hilo de audio. nullptr = quitar el que suena.
  void offer(Clip* c, ClipBin& bin) {
    Clip* old = incoming_.exchange(c != nullptr ? c : removed(), std::memory_order_acq_rel);
    if (old != nullptr && old != removed()) bin.add(old);  // nunca llegó a sonar
  }

  // Hilo de audio. Devuelve el clip que deja de sonar (nullptr si no cambia
  // nada o no había ninguno) y en *changed si ha habido cambio. Quien llama
  // decide cuándo retirarlo (puede que quiera apagarlo poco a poco).
  Clip* take(bool* changed) {
    *changed = false;
    Clip* in = incoming_.exchange(nullptr, std::memory_order_acq_rel);
    if (in == nullptr) return nullptr;
    *changed = true;
    Clip* old = current_;
    current_ = in == removed() ? nullptr : in;
    return old;
  }

  // Hilo de audio
  const Clip* current() const { return current_; }

  // Con el audio parado (ningún callback en marcha): lo que haya, al cubo.
  // keepRate: se conserva el que suena si es de esa frecuencia.
  void dropUnless(int32_t keepRate, ClipBin& bin) {
    Clip* in = incoming_.exchange(nullptr, std::memory_order_acq_rel);
    if (in != nullptr && in != removed()) {
      if (in->rate == keepRate) {
        bin.add(current_);
        current_ = in;
      } else {
        bin.add(in);
      }
    } else if (in == removed()) {
      bin.add(current_);
      current_ = nullptr;
    }
    if (current_ != nullptr && current_->rate != keepRate) {
      bin.add(current_);
      current_ = nullptr;
    }
  }

  ~ClipSlot() {
    Clip* in = incoming_.load();
    if (in != removed()) delete in;
    delete current_;
  }

 private:
  static Clip* removed() {
    static Clip marker;
    return &marker;
  }
  std::atomic<Clip*> incoming_{nullptr};
  Clip* current_ = nullptr;
};

}  // namespace loopin
