// Loopin — looper: grabar una pista y overdub
// SPDX-License-Identifier: GPL-3.0-or-later
#include "Looper.h"

#include <algorithm>
#include <cmath>

namespace loopin {

// ---------------------------------------------------------------- grabar

void Looper::arm(int64_t now) {
  active_ = selected_;
  Track& t = tr(active_);
  if (t.clearing) finishClear(t);  // se acaba de borrar: se termina ya
  userClosed_ = false;
  stopAfterRec_ = false;
  newLen_ = 0;
  waiting_ = false;
  if (baseLen_ == 0 && (startOnSound_ || mode_ == Mode::kFree)) {
    // Sin cuenta de entrada y en silencio: o se espera a que suene la
    // guitarra o (en libre) se empieza ya
    transport_->stop();
    barFrames_ = 0;
    t.layers = 0;
    state_ = State::kArmed;
    if (startOnSound_) {
      waiting_ = true;
      scanPos_ = -1;
      warmup_ = sampleRate_ * 15 / 100;  // 150 ms para medir el ruido
      noisePeak_ = 0.0f;
      recStart_ = recEnd_ = kNever;
      nextEvent_ = kNever;
      t.winOpen = false;
    } else {
      recStart_ = now;
      recEnd_ = now + capacity_;
      t.winOpen = true;
      t.winStart = recStart_;
      t.winEnd = recEnd_;
      nextEvent_ = recStart_;
    }
    return;
  }
  if (baseLen_ == 0) {
    // Primer loop, siempre con cuenta de entrada: el metrónomo vuelve a
    // empezar en el tiempo 1 justo al pulsar (aunque ya estuviera sonando),
    // cuenta 1 compás y se graba.
    transport_->stop();
    transport_->play();
    barFrames_ = transport_->samplesPerBar();
    recStart_ = now + barFrames_;
    const int64_t bars =
        mode_ == Mode::kSync ? std::min<int64_t>(syncBars_, maxBars()) : maxBars();
    recEnd_ = recStart_ + bars * barFrames_;
  } else {
    // Otra pista, sobre lo que suena: empieza en el primer tiempo del
    // siguiente compás y dura como mucho 4 veces la base.
    const int64_t inBar = wrap(now - origin_, barFrames_);
    recStart_ = inBar == 0 ? now : now + (barFrames_ - inBar);
    int64_t span = maxMultiple() * baseLen_;
    if (mode_ == Mode::kSync) span = std::min(span, int64_t(syncBars_) * barFrames_);
    recEnd_ = recStart_ + span;
  }
  t.winOpen = true;
  t.winStart = recStart_;
  t.winEnd = recEnd_;
  t.layers = 0;
  state_ = State::kArmed;
  nextEvent_ = recStart_;
}

// Empieza la primera pista en la muestra de salida `start` (que puede estar
// en el pasado: el ataque se detecta cuando ya ha llegado a la entrada).
void Looper::startFirstAt(int64_t start, int64_t now) {
  Track& t = tr(active_);
  start = std::min(start, now);
  waiting_ = false;
  recStart_ = start;
  if (mode_ == Mode::kFree) {
    recEnd_ = start + capacity_;
  } else {
    // El compás 1 empieza donde ha empezado a tocar
    transport_->stop();
    transport_->playFrom(now - start);
    barFrames_ = transport_->samplesPerBar();
    const int64_t bars =
        mode_ == Mode::kSync ? std::min<int64_t>(syncBars_, maxBars()) : maxBars();
    recEnd_ = start + bars * barFrames_;
  }
  t.winOpen = true;
  t.winStart = recStart_;
  t.winEnd = recEnd_;
  // Lo que ya ha entrado desde el ataque también se graba
  capN_ = std::min(capN_, recStart_);
  state_ = State::kRecording;
  nextEvent_ = recEnd_;
}

// Libre: el primer loop dura lo que se haya tocado y de ahí sale el tempo. Se
// busca el número de compases que da un tempo entre 70 y 140 BPM y se ajusta
// la duración a un número entero de muestras por tiempo (se quitan como mucho
// unas decenas de muestras, menos de 1 ms). Devuelve false si es demasiado
// corto (menos de un compás a 240 BPM): entonces se anula.
bool Looper::closeFree(int64_t now) {
  Track& t = tr(active_);
  const int64_t len = std::min(now - recStart_, capacity_);
  const int64_t beats = transport_->beatsPerBar();
  const int64_t minLen = int64_t(Transport::computeSamplesPerBeat(sampleRate_, Transport::kMaxBpm)) * beats;
  if (len < minLen) return false;
  // Con más compases, cada uno es más corto y el tempo más rápido: el menor
  // número de compases (1, 2, 4…) que llegue a 70 BPM. Doblar desde menos de
  // 70 deja por debajo de 140. Si con 1 compás ya pasa de 140, se queda así.
  int64_t bars = 1;
  while (bars < 64 && 60.0 * sampleRate_ * double(bars * beats) / double(len) < 70.0) bars *= 2;
  const int64_t spb = len / (bars * beats);
  transport_->setBpm(60.0 * sampleRate_ / double(spb));
  barFrames_ = spb * beats;
  recEnd_ = recStart_ + bars * barFrames_;
  t.winEnd = recEnd_;
  // El tempo arranca con el loop (salvo si se está parando todo)
  if (!stopAfterRec_) transport_->playFrom(now - recStart_);
  finishRecording(now);
  return true;
}

void Looper::closeRecording(int64_t now) {
  if (userClosed_) return;
  userClosed_ = true;
  if (baseLen_ == 0 && mode_ == Mode::kFree) {
    if (!closeFree(now)) cancelRecording();
    return;
  }
  Track& t = tr(active_);
  const int64_t elapsed = now - recStart_;
  int64_t bars = static_cast<int64_t>(std::llround(double(elapsed) / double(barFrames_)));
  bars = std::clamp<int64_t>(bars, 1, maxBars());
  if (baseLen_ == 0) {
    // Primer loop, al compás más cercano: si se pulsa tarde se recorta y si se
    // pulsa pronto se sigue grabando hasta el final del compás.
    recEnd_ = recStart_ + bars * barFrames_;
    t.winEnd = recEnd_;
    if (recEnd_ <= now) {
      finishRecording(now);
    } else {
      nextEvent_ = recEnd_;
    }
  } else {
    // Otra pista: se deja de grabar justo al pulsar y lo que falte hasta
    // completar 1, 2 o 4 veces la base queda en silencio. La longitud sale de
    // los compases tocados (al más cercano), para que pulsar un pelín tarde
    // no la doble.
    newLen_ = lengthFor(bars * barFrames_);
    recEnd_ = std::min(now, recStart_ + newLen_);
    t.winEnd = recEnd_;
    finishRecording(now);
  }
}

void Looper::finishRecording(int64_t now) {
  Track& t = tr(active_);
  if (baseLen_ == 0) {
    t.len = recEnd_ - recStart_;
    baseLen_ = t.len;
    origin_ = recStart_;
  } else {
    // Si se ha cerrado sola (modo sincronizado o pista llena), la longitud
    // sale de lo grabado
    if (!userClosed_) newLen_ = lengthFor(recEnd_ - recStart_);
    t.len = newLen_;
  }
  // Si se cerró tarde, lo grabado más allá del final se borra (es poco: menos
  // de medio compás)
  const int64_t written = std::min(now - recStart_, capacity_);
  if (written > t.len) {
    std::fill(t.data.begin() + static_cast<std::ptrdiff_t>(t.len),
              t.data.begin() + static_cast<std::ptrdiff_t>(written), 0.0f);
  }
  t.origin = recStart_;
  resetTrackFx(t);
  t.q = gridQ(t, now);
  rescheduleTrackChanges();
  t.layers = 1;
  t.gain = t.muted ? 0.0f : t.volume;
  nextEvent_ = kNever;
  // La ventana de grabación sigue abierta hasta que llegue la entrada que
  // falta (la latencia); capture() la cierra.
  consolidateLive();
  last_ = Last::kTrack;
  lastTrack_ = active_;
  if (stopAfterRec_) {
    stopAfterRec_ = false;
    state_ = State::kStopped;
  } else {
    state_ = State::kPlaying;
  }
  if (autoAdvance_) advanceSelection(active_);
}

void Looper::cancelRecording() {
  Track& t = tr(active_);
  waiting_ = false;
  t.winOpen = false;
  // Lo que ya se había escrito se borra en segundo plano
  const int64_t written = std::clamp<int64_t>(capN_ - t.winStart, 0, capacity_);
  if (written > 0) startClear(t, written);
  t.len = 0;
  t.layers = 0;
  nextEvent_ = kNever;
  stopAfterRec_ = false;
  userClosed_ = false;
  if (anyContent()) {
    state_ = transport_ != nullptr && transport_->playing() ? State::kPlaying : State::kStopped;
  } else {
    state_ = State::kEmpty;
    baseLen_ = 0;
    last_ = Last::kNone;
  }
}

// ---------------------------------------------------------------- overdub

// La capa que aún se podía deshacer deja de poderse: se suma a su pista en
// segundo plano
void Looper::consolidateLive() {
  for (Layer& l : layers_) {
    if (l.st == Layer::St::kLive) {
      l.st = Layer::St::kMerging;
      l.cursor = 0;
    }
  }
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
  active_ = selected_;
  const Track& t = tr(active_);
  fresh->st = Layer::St::kRecording;
  fresh->track = active_;
  fresh->extent = t.len;
  fresh->cursor = 0;
  fresh->winOpen = true;
  // Empieza en el primer tiempo del siguiente compás, para dar tiempo a
  // volver a poner la mano en la guitarra tras pulsar.
  const int64_t inBar = wrap(now - origin_, barFrames_);
  fresh->winStart = inBar == 0 ? now : now + (barFrames_ - inBar);
  fresh->winEnd = kNever;
  // Se escribe donde se oye la pista (con reverse o media velocidad, también)
  readAt(t, now, fresh->winStart, &fresh->q0, &fresh->dq);
  state_ = State::kOverdubbing;
}

void Looper::endOverdub(int64_t now) {
  Layer* rec = findLayer(Layer::St::kRecording);
  if (rec != nullptr && now <= rec->winStart) {
    // Aún estaba esperando al compás: no se ha grabado nada, se anula
    rec->st = Layer::St::kEmpty;
    rec->winOpen = false;
    rec->extent = 0;
    state_ = State::kPlaying;
    return;
  }
  // Lo anterior ya no se podrá deshacer
  consolidateLive();
  if (rec != nullptr) {
    rec->st = Layer::St::kLive;
    rec->winEnd = now;  // sigue capturando hasta que llegue la latencia
    ++tr(rec->track).layers;
    last_ = Last::kLayer;
  }
  state_ = State::kPlaying;
}

void Looper::discard(Layer& l) {
  l.st = Layer::St::kClearing;
  l.cursor = 0;
  l.winOpen = false;
}

}  // namespace loopin
