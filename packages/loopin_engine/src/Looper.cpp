// Loopin — looper
// SPDX-License-Identifier: GPL-3.0-or-later
#include "Looper.h"

#include <algorithm>
#include <cmath>

namespace loopin {

namespace {
// Módulo siempre positivo
inline int64_t wrap(int64_t a, int64_t m) {
  const int64_t r = a % m;
  return r < 0 ? r + m : r;
}
}  // namespace

// ---------------------------------------------------------------- InputRing

void InputRing::prepare(int32_t minFrames) {
  size_t size = 1;
  while (size < static_cast<size_t>(std::max(minFrames, 1))) size <<= 1;
  if (data_.size() != size) data_.assign(size, 0.0f);
  mask_ = size - 1;
  reset();
}

void InputRing::reset() {
  std::fill(data_.begin(), data_.end(), 0.0f);
  end_ = 0;
}

// ---------------------------------------------------------------- Looper

void Looper::prepare(int32_t sampleRate, Transport* transport, int32_t maxSeconds) {
  transport_ = transport;
  const int64_t capacity = int64_t(sampleRate) * maxSeconds;
  const bool keep = sampleRate == sampleRate_ && capacity == capacity_ && length_ > 0;
  sampleRate_ = sampleRate;

  if (!keep) {
    capacity_ = capacity;
    base_.assign(static_cast<size_t>(capacity_), 0.0f);
    for (Layer& l : layers_) {
      l.data.assign(static_cast<size_t>(capacity_), 0.0f);
      l = Layer{std::move(l.data)};
    }
    state_ = State::kEmpty;
    length_ = 0;
    layerCount_ = 0;
  } else {
    // El audio se ha reabierto (otro dispositivo, otro modo de micro...). El
    // loop se conserva y queda parado. Aquí no hay hilo de audio: se termina
    // todo el trabajo pendiente de golpe.
    // Un overdub a medias se da por terminado (la capa anterior se consolida)
    if (Layer* rec = findLayer(Layer::St::kRecording)) {
      for (Layer& l : layers_)
        if (&l != rec && l.st == Layer::St::kLive) l.st = Layer::St::kMerging;
      rec->st = Layer::St::kLive;
      ++layerCount_;
    }
    for (Layer& l : layers_) {
      l.winOpen = false;
      if (l.st == Layer::St::kMerging || l.st == Layer::St::kClearing) l.cursor = 0;
    }
    for (Layer& l : layers_)
      if (l.st == Layer::St::kMerging || l.st == Layer::St::kClearing) finishBackground(l);
    if (state_ == State::kArmed || state_ == State::kRecording) {
      cancelRecording();
    } else if (state_ != State::kEmpty) {
      state_ = State::kStopped;
    }
  }
  recWinOpen_ = false;
  nextEvent_ = kNever;
  stopAfterRec_ = false;
  capN_ = -latency_;
  clearPre();
}

void Looper::setSyncBars(int32_t bars) { syncBars_ = std::clamp(bars, 1, 64); }

void Looper::setLatency(int32_t frames) {
  // Como mucho medio segundo: más no tiene sentido y debe ser menor que un
  // compás para que el final del primer loop se escriba antes de sonar.
  latency_ = std::clamp(frames, 0, sampleRate_ / 2);
}

void Looper::setVolume(float volume) { volume_ = std::clamp(volume, 0.0f, 2.0f); }

int64_t Looper::maxBars() const {
  return barFrames_ > 0 ? std::max<int64_t>(1, capacity_ / barFrames_) : 1;
}

bool Looper::canUndo() const {
  switch (state_) {
    case State::kArmed:
    case State::kRecording:
    case State::kOverdubbing:
      return true;
    case State::kPlaying:
    case State::kStopped:
      for (const Layer& l : layers_)
        if (l.st == Layer::St::kLive) return true;
      return false;
    case State::kEmpty:
      return false;
  }
  return false;
}

int64_t Looper::recordedFrames(int64_t now) const {
  if (state_ == State::kArmed || state_ == State::kRecording) return now - recStart_;
  return 0;
}

int64_t Looper::targetFrames() const {
  if (state_ != State::kArmed && state_ != State::kRecording) return 0;
  if (mode_ == Mode::kSync || userClosed_) return recEnd_ - recStart_;
  return 0;
}

Looper::Layer* Looper::findLayer(Layer::St st) {
  for (Layer& l : layers_)
    if (l.st == st) return &l;
  return nullptr;
}

// ---------------------------------------------------------------- eventos

void Looper::fireEvent(int64_t n) {
  nextEvent_ = kNever;
  if (state_ == State::kArmed) {
    state_ = State::kRecording;
    nextEvent_ = recEnd_;
  } else if (state_ == State::kRecording) {
    finishRecording(n);
  }
}

// ---------------------------------------------------------------- grabar

void Looper::arm(int64_t now, const InputRing& in) {
  userClosed_ = false;
  stopAfterRec_ = false;
  if (!transport_->playing()) {
    // Parado: arranca el metrónomo y graba tras 1 compás de cuenta de entrada
    transport_->play();
    barFrames_ = transport_->samplesPerBar();
    recStart_ = now + barFrames_;
  } else {
    barFrames_ = transport_->nextSamplesPerBar();
    const int64_t since = transport_->framesSinceBar();
    // En modo manual, si se pulsa un poco tarde (hasta 1/4 de compás y como
    // mucho 1 s) se empieza en el primer tiempo que acaba de pasar.
    const int64_t grace = std::min<int64_t>(barFrames_ / 4, sampleRate_);
    if (mode_ == Mode::kManual && since > 0 && since <= grace &&
        !transport_->hasPendingChange()) {
      recStart_ = now - since;
    } else {
      recStart_ = now + transport_->framesToNextBar();
    }
  }
  const int64_t bars = mode_ == Mode::kSync ? std::min<int64_t>(syncBars_, maxBars()) : maxBars();
  recEnd_ = recStart_ + bars * barFrames_;
  recWinOpen_ = true;
  layerCount_ = 0;

  if (recStart_ <= now) {
    state_ = State::kRecording;
    nextEvent_ = recEnd_;
    // Lo que ya se ha capturado de la ventana (empezó en el pasado) se copia
    // ahora del anillo de entrada.
    for (int64_t n = recStart_; n < capN_; ++n) {
      const int64_t j = n + latency_;
      if (j >= in.begin() && j < in.end()) base_[static_cast<size_t>(n - recStart_)] = in.at(j);
    }
  } else {
    state_ = State::kArmed;
    nextEvent_ = recStart_;
  }
}

void Looper::closeRecording(int64_t now) {
  if (userClosed_) return;
  userClosed_ = true;
  // Al compás más cercano: si se pulsa tarde se recorta y si se pulsa pronto
  // se sigue grabando hasta el final del compás.
  const int64_t elapsed = now - recStart_;
  int64_t bars = static_cast<int64_t>(std::llround(double(elapsed) / double(barFrames_)));
  bars = std::clamp<int64_t>(bars, 1, maxBars());
  recEnd_ = recStart_ + bars * barFrames_;
  if (recEnd_ <= now) {
    finishRecording(now);
  } else {
    nextEvent_ = recEnd_;
  }
}

void Looper::finishRecording(int64_t now) {
  length_ = recEnd_ - recStart_;
  origin_ = recStart_;
  playPos_ = wrap(now - origin_, length_);
  nextEvent_ = kNever;
  layerCount_ = 1;
  // La ventana de grabación sigue abierta hasta que llegue la entrada que
  // falta (la latencia); capture() la cierra.
  if (stopAfterRec_) {
    stopAfterRec_ = false;
    state_ = State::kStopped;
  } else {
    state_ = State::kPlaying;
  }
}

void Looper::cancelRecording() {
  state_ = State::kEmpty;
  recWinOpen_ = false;
  nextEvent_ = kNever;
  length_ = 0;
  layerCount_ = 0;
  stopAfterRec_ = false;
}

// ---------------------------------------------------------------- overdub

void Looper::finishBackground(Layer& l) {
  const size_t end = static_cast<size_t>(std::min(l.extent, capacity_));
  if (l.st == Layer::St::kMerging) {
    for (size_t i = static_cast<size_t>(l.cursor); i < end; ++i) {
      base_[i] += l.data[i];
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

void Looper::startOverdub(int64_t now) {
  Layer* fresh = findLayer(Layer::St::kEmpty);
  if (fresh == nullptr) {
    // La otra capa aún se está sumando o borrando (dos overdubs muy
    // seguidos): se termina ya. Cuesta como mucho la longitud del loop.
    for (Layer& l : layers_) {
      if (l.st == Layer::St::kMerging || l.st == Layer::St::kClearing) {
        finishBackground(l);
        fresh = &l;
        break;
      }
    }
  }
  if (fresh == nullptr) return;  // no debería pasar
  fresh->st = Layer::St::kRecording;
  fresh->extent = length_;
  fresh->cursor = 0;
  fresh->winOpen = true;
  fresh->winStart = now;
  fresh->winEnd = kNever;
  fresh->winOrigin = origin_;
  state_ = State::kOverdubbing;
}

void Looper::endOverdub(int64_t now) {
  Layer* rec = findLayer(Layer::St::kRecording);
  // La capa anterior ya no se podrá deshacer: se consolida en segundo plano
  for (Layer& l : layers_) {
    if (&l != rec && l.st == Layer::St::kLive) {
      l.st = Layer::St::kMerging;
      l.cursor = 0;
    }
  }
  if (rec != nullptr) {
    rec->st = Layer::St::kLive;
    rec->winEnd = now;  // sigue capturando hasta que llegue la latencia
    ++layerCount_;
  }
  state_ = State::kPlaying;
}

void Looper::discard(Layer& l) {
  l.st = Layer::St::kClearing;
  l.cursor = 0;
  l.winOpen = false;
}

// ---------------------------------------------------------------- órdenes

void Looper::press(int64_t now, const InputRing& in) {
  preState_ = state_;
  hasPre_ = true;
  switch (state_) {
    case State::kEmpty:
      arm(now, in);
      break;
    case State::kArmed:
      cancelRecording();
      break;
    case State::kRecording:
      closeRecording(now);
      break;
    case State::kPlaying:
      startOverdub(now);
      break;
    case State::kOverdubbing:
      endOverdub(now);
      break;
    case State::kStopped:
      startAll(now);
      hasPre_ = true;  // startAll lo borra
      break;
  }
}

void Looper::undo(int64_t /*now*/) {
  switch (state_) {
    case State::kArmed:
    case State::kRecording:
      cancelRecording();
      break;
    case State::kOverdubbing:
      if (Layer* rec = findLayer(Layer::St::kRecording)) discard(*rec);
      state_ = State::kPlaying;
      break;
    case State::kPlaying:
    case State::kStopped:
      if (Layer* live = findLayer(Layer::St::kLive)) {
        discard(*live);
        layerCount_ = std::max(1, layerCount_ - 1);
      }
      break;
    case State::kEmpty:
      break;
  }
  clearPre();
}

void Looper::clear(int64_t /*now*/) {
  cancelRecording();
  for (Layer& l : layers_)
    if (l.st != Layer::St::kEmpty) discard(l);
  clearPre();
}

void Looper::startAll(int64_t now) {
  if (transport_->playing()) stopAll(now);
  if (state_ == State::kArmed || state_ == State::kRecording) cancelRecording();
  transport_->play();
  if (state_ == State::kStopped) {
    origin_ = now;  // el loop vuelve a empezar con el compás 1
    playPos_ = 0;
    state_ = State::kPlaying;
  }
  clearPre();
}

void Looper::stopAll(int64_t now) {
  transport_->stop();
  switch (state_) {
    case State::kArmed:
      cancelRecording();
      break;
    case State::kRecording:
      // Se cierra como al pulsar (compás más cercano) y luego se queda parado.
      // Si el cierre cae en el futuro, la grabación sigue hasta ahí.
      stopAfterRec_ = true;
      if (!userClosed_) closeRecording(now);
      break;
    case State::kOverdubbing:
      endOverdub(now);
      state_ = State::kStopped;
      break;
    case State::kPlaying:
      state_ = State::kStopped;
      break;
    case State::kEmpty:
    case State::kStopped:
      break;
  }
  clearPre();
}

// Mantener pulsado: el toque ya hizo su efecto; aquí se deshace lo que tenga
// sentido según el estado de antes del toque.
void Looper::hold(int64_t now) {
  if (!hasPre_) return;
  const State pre = preState_;
  clearPre();
  switch (pre) {
    case State::kEmpty:      // el toque armó o empezó a grabar → cancelar
      if (state_ == State::kArmed || state_ == State::kRecording) cancelRecording();
      break;
    case State::kArmed:      // el toque canceló: nada más
      break;
    case State::kRecording:  // el toque cerró el loop → se borra
      clear(now);
      break;
    case State::kPlaying:    // el toque empezó un overdub → fuera, y la capa anterior
      if (state_ == State::kOverdubbing) undo(now);
      undo(now);
      break;
    case State::kOverdubbing:  // el toque acabó el overdub → se deshace esa capa
      undo(now);
      break;
    case State::kStopped:    // el toque arrancó → deshacer y seguir parado
      undo(now);
      stopAll(now);
      break;
  }
}

// Doble toque = parar / arrancar todo. El primer toque ya hizo su efecto.
void Looper::doubleTap(int64_t now) {
  if (!hasPre_) return;
  const State pre = preState_;
  clearPre();
  switch (pre) {
    case State::kEmpty:      // el toque armó → cancelar y parar
      if (state_ == State::kArmed || state_ == State::kRecording) cancelRecording();
      stopAll(now);
      break;
    case State::kArmed:
      stopAll(now);
      break;
    case State::kRecording:  // el toque cerró el loop → además parar
      stopAll(now);
      break;
    case State::kPlaying:    // el toque empezó un overdub → fuera y parar
      if (state_ == State::kOverdubbing) undo(now);
      stopAll(now);
      break;
    case State::kOverdubbing:
      stopAll(now);
      break;
    case State::kStopped:    // el toque ya arrancó todo
      break;
  }
}

// ---------------------------------------------------------------- captura

void Looper::capture(const InputRing& in) {
  const int64_t end = in.end() - latency_;  // se pueden capturar los n < end
  bool open = recWinOpen_;
  for (const Layer& l : layers_) open = open || l.winOpen;
  if (!open) {
    capN_ = std::max(capN_, end);
    return;
  }
  int64_t n = std::max(capN_, in.begin() - latency_);
  for (; n < end; ++n) {
    const float x = in.at(n + latency_);
    if (recWinOpen_ && n >= recStart_ && n < recEnd_) {
      const int64_t idx = n - recStart_;
      if (idx < capacity_) base_[static_cast<size_t>(idx)] = x;
    }
    for (Layer& l : layers_) {
      if (l.winOpen && n >= l.winStart && n < l.winEnd) {
        l.data[static_cast<size_t>(wrap(n - l.winOrigin, l.extent))] += x;
      }
    }
  }
  capN_ = std::max(capN_, n);
  if (recWinOpen_ && state_ != State::kArmed && capN_ >= recEnd_) recWinOpen_ = false;
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
    const int64_t end = std::min(std::min(l.extent, capacity_), l.cursor + budget);
    for (int64_t i = l.cursor; i < end; ++i) {
      const size_t k = static_cast<size_t>(i);
      if (merging) base_[k] += l.data[k];
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
}

}  // namespace loopin
