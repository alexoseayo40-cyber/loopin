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
  // Con qué se preparó (archivo, tempo, 1, rejilla, frecuencia): para volver
  // a usarlo sin prepararlo otra vez. 0 en la vista previa.
  uint64_t key = 0;
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
//
// Las canciones ya preparadas (con key) no se borran enseguida: se guardan
// las kKeep últimas, por si se vuelve a ese tempo (volver al tempo de la
// canción después de practicar más despacio es instantáneo).
class ClipBin {
 public:
  static constexpr size_t kKeep = 2;

  ~ClipBin() {
    collect(nullptr);
    for (Clip* c : kept_) delete c;
  }
  void add(Clip* c) {
    if (c == nullptr) return;
    std::lock_guard<std::mutex> lock(mutex_);
    clips_.push_back(c);
  }
  // Borra lo pendiente y lo que haya devuelto el hilo de audio (guardando
  // las últimas canciones preparadas). Desde un solo hilo (el de la interfaz).
  void collect(RetiredClips* retired) {
    std::vector<Clip*> v;
    Clip* c = nullptr;
    if (retired != nullptr)
      while (retired->pop(c)) v.push_back(c);
    std::lock_guard<std::mutex> lock(mutex_);
    v.insert(v.end(), clips_.begin(), clips_.end());
    clips_.clear();
    for (Clip* x : v) {
      if (x->key == 0) {
        delete x;
        continue;
      }
      kept_.push_back(x);
      if (kept_.size() > kKeep) {
        delete kept_.front();
        kept_.erase(kept_.begin());
      }
    }
  }
  // Una canción ya preparada con esa key (y deja de estar guardada), o nullptr.
  Clip* takeKept(uint64_t key) {
    std::lock_guard<std::mutex> lock(mutex_);
    for (size_t i = 0; i < kept_.size(); ++i) {
      if (kept_[i]->key == key) {
        Clip* c = kept_[i];
        kept_.erase(kept_.begin() + long(i));
        return c;
      }
    }
    return nullptr;
  }
  size_t keptCount() {
    std::lock_guard<std::mutex> lock(mutex_);
    return kept_.size();
  }

 private:
  std::mutex mutex_;
  std::vector<Clip*> clips_;
  std::vector<Clip*> kept_;
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
