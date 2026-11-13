// Loopin — looper de 4 pistas: estado, selección y órdenes del pulsador
// SPDX-License-Identifier: GPL-3.0-or-later
//
// El looper está repartido en tres archivos:
//   Looper.cpp         preparar, estado, selección, órdenes (toque, mantener,
//                      doble toque, deshacer, arrancar y parar)
//   LooperRecord.cpp   grabar una pista (cuenta, libre, empezar al tocar) y
//                      overdub
//   LooperBuffers.cpp  escribir la entrada (capture), borrar y el trabajo de
//                      fondo (sumar capas)
#include "Looper.h"

#include <algorithm>
#include <cmath>

namespace loopin {

// ---------------------------------------------------------------- Looper

void Looper::prepare(int32_t sampleRate, Transport* transport, int32_t maxSeconds) {
  transport_ = transport;
  onset_.prepare(sampleRate);
  const int64_t capacity = int64_t(sampleRate) * maxSeconds;
  const bool keep = sampleRate == sampleRate_ && capacity == capacity_ && anyContent();
  sampleRate_ = sampleRate;
  duckLead_ = sampleRate / 40;
  duckStep_ = 2.0f / float(duckLead_);
  duck_ = 1.0f;
  xfadeLen_ = std::max(1, sampleRate / 200);
  gainStep_ = 1.0f / float(xfadeLen_);

  if (!keep) {
    capacity_ = capacity;
    for (Track& t : tracks_) {
      t.data.assign(static_cast<size_t>(capacity_), 0.0f);
      t.len = 0;
      t.origin = 0;
      t.layers = 0;
      t.winOpen = false;
      t.clearing = false;
      resetTrackFx(t);
      t.muted = t.wantMuted;
      t.muteAt = kNever;
      t.gain = t.muted ? 0.0f : t.volume;
    }
    for (Layer& l : layers_) {
      l.data.assign(static_cast<size_t>(capacity_), 0.0f);
      l.st = Layer::St::kEmpty;
      l.track = 0;
      l.extent = 0;
      l.cursor = 0;
      l.winOpen = false;
    }
    state_ = State::kEmpty;
    baseLen_ = 0;
    selected_ = 0;
    active_ = 0;
    last_ = Last::kNone;
  } else {
    // El audio se ha reabierto (otro dispositivo, otro modo de micro...). Los
    // loops se conservan y quedan parados. Aquí no hay hilo de audio: se
    // termina todo el trabajo pendiente de golpe.
    // Un overdub a medias se da por terminado (la capa anterior se consolida)
    if (Layer* rec = findLayer(Layer::St::kRecording)) {
      for (Layer& l : layers_)
        if (&l != rec && l.st == Layer::St::kLive) l.st = Layer::St::kMerging;
      rec->st = Layer::St::kLive;
      ++tr(rec->track).layers;
      last_ = Last::kLayer;
    }
    // Una pista a medio grabar se pierde
    if (recordingTrack()) cancelRecording();
    for (Layer& l : layers_) {
      l.winOpen = false;
      if (l.st == Layer::St::kMerging || l.st == Layer::St::kClearing) l.cursor = 0;
    }
    for (Layer& l : layers_)
      if (l.st == Layer::St::kMerging || l.st == Layer::St::kClearing) finishBackground(l);
    for (Track& t : tracks_) {
      t.winOpen = false;
      if (t.clearing) finishClear(t);
      // Lo pendiente se aplica ya (está todo parado)
      t.muted = t.wantMuted;
      t.muteAt = kNever;
      t.reverse = t.wantReverse;
      t.half = t.wantHalf;
      t.dq = stepFor(t.reverse, t.half);
      t.fxAt = kNever;
      t.xfade = 0;
      t.gain = t.muted ? 0.0f : t.volume;
    }
    state_ = anyContent() ? State::kStopped : State::kEmpty;
    if (state_ == State::kEmpty) baseLen_ = 0;
  }
  nextEvent_ = kNever;
  nextTrackChange_ = kNever;
  stopRequest_ = false;
  stopAfterRec_ = false;
  userClosed_ = false;
  capN_ = -latency_;
  clearPre();
}

void Looper::setSyncBars(int32_t bars) { syncBars_ = std::clamp(bars, 1, 64); }

void Looper::setLatency(int32_t frames) {
  // Como mucho medio segundo: más no tiene sentido y debe ser menor que un
  // compás para que el final de un loop se escriba antes de sonar.
  latency_ = std::clamp(frames, 0, sampleRate_ / 2);
}

void Looper::setVolume(float volume) { volume_ = std::clamp(volume, 0.0f, 2.0f); }

void Looper::setTrackVolume(int32_t track, float volume) {
  if (track < 0 || track >= kTracks) return;
  tr(track).volume = std::clamp(volume, 0.0f, 2.0f);
}

// ---------------------------------------------------------------- silencio y efectos

int64_t Looper::changeAt(int64_t now) const {
  if (!quantize_ || transport_ == nullptr || !transport_->playing() || state_ == State::kStopped)
    return now;
  return now + transport_->framesToNextBar();
}

void Looper::setTrackMuted(int32_t track, bool muted, int64_t now) {
  if (track < 0 || track >= kTracks) return;
  Track& t = tr(track);
  t.wantMuted = muted;
  if (muted == t.muted) {
    t.muteAt = kNever;  // lo pedido ya está (se anula lo pendiente)
  } else {
    int64_t at = changeAt(now);
    // Al quitar el silencio, la rampa empieza antes para acabar justo en el 1
    if (!muted && at > now) {
      const int64_t ramp = int64_t(std::ceil(std::max(1.0f, t.volume) / gainStep_));
      at = std::max(now, at - ramp);
    }
    if (at <= now) {
      t.muted = muted;
      t.muteAt = kNever;
    } else {
      t.muteAt = at;
    }
  }
  rescheduleTrackChanges();
}

void Looper::setTrackReverse(int32_t track, bool on, int64_t now) {
  if (track < 0 || track >= kTracks) return;
  Track& t = tr(track);
  if (t.len == 0 || (busy() && active_ == track)) return;
  t.wantReverse = on;
  if (t.wantReverse == t.reverse && t.wantHalf == t.half) {
    t.fxAt = kNever;
  } else if (const int64_t at = changeAt(now); at <= now) {
    applyFx(t, now);
  } else {
    t.fxAt = at;
  }
  rescheduleTrackChanges();
}

void Looper::setTrackHalf(int32_t track, bool on, int64_t now) {
  if (track < 0 || track >= kTracks) return;
  Track& t = tr(track);
  if (t.len == 0 || (busy() && active_ == track)) return;
  t.wantHalf = on;
  if (t.wantReverse == t.reverse && t.wantHalf == t.half) {
    t.fxAt = kNever;
  } else if (const int64_t at = changeAt(now); at <= now) {
    applyFx(t, now);
  } else {
    t.fxAt = at;
  }
  rescheduleTrackChanges();
}

int32_t Looper::trackPending(int32_t track) const {
  const Track& t = tr(track);
  int32_t bits = 0;
  if (t.muteAt != kNever) bits |= 1;
  if (t.fxAt != kNever && t.wantReverse != t.reverse) bits |= 2;
  if (t.fxAt != kNever && t.wantHalf != t.half) bits |= 4;
  return bits;
}

// Con efecto, se sigue desde donde suena; sin ninguno, la pista vuelve a su
// sitio en la rejilla. La lectura de antes se apaga en un fundido cruzado.
void Looper::applyFx(Track& t, int64_t n) {
  t.fxAt = kNever;
  if (t.wantReverse == t.reverse && t.wantHalf == t.half) return;
  t.oq = t.q;
  t.odq = t.dq;
  t.xfade = xfadeLen_;
  t.reverse = t.wantReverse;
  t.half = t.wantHalf;
  t.dq = stepFor(t.reverse, t.half);
  if (!t.reverse && !t.half) {
    t.q = gridQ(t, n);
  } else if (!t.half) {
    t.q &= ~int64_t(1);  // a velocidad normal, siempre en una muestra entera
  }
}

void Looper::applyTrackChanges(int64_t n) {
  for (Track& t : tracks_) {
    if (t.muteAt <= n) {
      t.muted = t.wantMuted;
      t.muteAt = kNever;
    }
    if (t.fxAt <= n) applyFx(t, n);
  }
  rescheduleTrackChanges();
}

void Looper::rescheduleTrackChanges() {
  nextTrackChange_ = kNever;
  for (const Track& t : tracks_) nextTrackChange_ = std::min({nextTrackChange_, t.muteAt, t.fxAt});
}

void Looper::readAt(const Track& t, int64_t now, int64_t n, int64_t* q, int32_t* dq) const {
  int64_t pos = t.q;
  int32_t d = t.dq;
  int64_t from = now;
  if (t.fxAt <= n) {
    pos = wrap(pos + int64_t(d) * (t.fxAt - from), 2 * t.len);
    d = stepFor(t.wantReverse, t.wantHalf);
    if (!t.wantReverse && !t.wantHalf) {
      pos = gridQ(t, t.fxAt);
    } else if (!t.wantHalf) {
      pos &= ~int64_t(1);
    }
    from = t.fxAt;
  }
  *q = wrap(pos + int64_t(d) * (n - from), 2 * t.len);
  *dq = d;
}

void Looper::resetTrackFx(Track& t) {
  t.q = 0;
  t.dq = 2;
  t.oq = 0;
  t.odq = 2;
  t.xfade = 0;
  t.reverse = t.half = false;
  t.wantReverse = t.wantHalf = false;
  t.fxAt = kNever;
}

bool Looper::anyContent() const {
  for (const Track& t : tracks_)
    if (t.len > 0) return true;
  return false;
}

int64_t Looper::maxBars() const {
  return barFrames_ > 0 ? std::max<int64_t>(1, capacity_ / barFrames_) : 1;
}

// Cuántas veces la base puede durar una pista (1, 2 o 4) sin pasarse del buffer
int64_t Looper::maxMultiple() const {
  if (baseLen_ <= 0) return 1;
  if (capacity_ >= 4 * baseLen_) return 4;
  if (capacity_ >= 2 * baseLen_) return 2;
  return 1;
}

// La longitud de pista más corta (1, 2 o 4 veces la base) en la que caben
// frames muestras. Si no cabe en ninguna, la más larga.
int64_t Looper::lengthFor(int64_t frames) const {
  const int64_t maxM = maxMultiple();
  for (int64_t m = 1; m <= maxM; m *= 2)
    if (m * baseLen_ >= frames) return m * baseLen_;
  return maxM * baseLen_;
}

int64_t Looper::basePosition(int64_t now) const {
  if (baseLen_ <= 0 || state_ == State::kStopped) return 0;
  return wrap(now - origin_, baseLen_);
}

bool Looper::canUndo() const {
  switch (state_) {
    case State::kArmed:
    case State::kRecording:
    case State::kOverdubbing:
      return true;
    case State::kPlaying:
    case State::kStopped:
      return last_ != Last::kNone;
    case State::kEmpty:
      return false;
  }
  return false;
}

int64_t Looper::recordedFrames(int64_t now) const {
  if (waiting_) return 0;
  if (recordingTrack()) return now - recStart_;
  if (state_ == State::kOverdubbing) {
    // Overdub esperando al compás: negativo, lo que falta para empezar
    for (const Layer& l : layers_)
      if (l.st == Layer::St::kRecording && now < l.winStart) return now - l.winStart;
  }
  return 0;
}

int64_t Looper::targetFrames() const {
  if (!recordingTrack()) return 0;
  if (mode_ == Mode::kSync || userClosed_) return recEnd_ - recStart_;
  return 0;
}

Looper::State Looper::trackState(int32_t track) const {
  if (track < 0 || track >= kTracks) return State::kEmpty;
  if (busy() && track == active_) return state_;
  if (tr(track).len > 0) return state_ == State::kStopped ? State::kStopped : State::kPlaying;
  return State::kEmpty;
}

Looper::Layer* Looper::findLayer(Layer::St st) {
  for (Layer& l : layers_)
    if (l.st == st) return &l;
  return nullptr;
}

// Si ya no queda ningún loop, todo vuelve al principio (y el tempo se libera)
void Looper::refreshEmpty() {
  if (anyContent()) return;
  baseLen_ = 0;
  last_ = Last::kNone;
  if (!recordingTrack()) state_ = State::kEmpty;
}

// ---------------------------------------------------------------- selección

void Looper::select(int32_t track) {
  if (track < 0 || track >= kTracks || busy()) return;
  selected_ = track;
  clearPre();
}

void Looper::selectNext() { select((selected_ + 1) % kTracks); }

// Tras grabar una pista, la selección pasa a la siguiente vacía (si la hay)
void Looper::advanceSelection(int32_t from) {
  for (int32_t k = 1; k < kTracks; ++k) {
    const int32_t j = (from + k) % kTracks;
    if (tr(j).len == 0) {
      selected_ = j;
      return;
    }
  }
}

// ---------------------------------------------------------------- eventos

void Looper::fireEvent(int64_t n) {
  nextEvent_ = kNever;
  if (state_ == State::kArmed) {
    state_ = State::kRecording;
    nextEvent_ = recEnd_;
  } else if (state_ == State::kRecording) {
    // En libre, si no se ha cerrado (60 s), hay que calcular el tempo
    if (baseLen_ == 0 && mode_ == Mode::kFree && !userClosed_) {
      closeRecording(n);
    } else {
      finishRecording(n);
    }
  }
}

// ---------------------------------------------------------------- órdenes

void Looper::press(int64_t now) {
  preState_ = state_;
  hasPre_ = true;
  switch (state_) {
    case State::kEmpty:
      arm(now);
      break;
    case State::kArmed:
      cancelRecording();
      break;
    case State::kRecording:
      closeRecording(now);
      break;
    case State::kPlaying:
      // Pista seleccionada vacía → se graba; con loop → overdub
      if (tr(selected_).len > 0) {
        startOverdub(now);
      } else {
        arm(now);
      }
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
      if (last_ == Last::kLayer) {
        if (Layer* live = findLayer(Layer::St::kLive)) {
          Track& t = tr(live->track);
          t.layers = std::max(1, t.layers - 1);
          discard(*live);
        }
        last_ = Last::kNone;
      } else if (last_ == Last::kTrack) {
        // Lo último fue grabar una pista: se quita y vuelve a quedar elegida
        const int32_t track = lastTrack_;
        dropTrack(track);
        selected_ = track;
        refreshEmpty();
      }
      break;
    case State::kEmpty:
      break;
  }
  clearPre();
}

void Looper::startAll(int64_t now) {
  if (transport_->playing()) stopAll(now);
  if (recordingTrack()) cancelRecording();
  transport_->play();
  if (state_ == State::kStopped) {
    // El ciclo base vuelve a empezar con el compás 1; cada pista conserva su
    // posición respecto a las demás
    const int64_t shift = now - origin_;
    origin_ = now;
    for (Track& t : tracks_) {
      if (t.len == 0) continue;
      t.origin += shift;
      // Con efecto, también desde su sitio en la rejilla (y en su sentido)
      t.q = gridQ(t, now);
      t.xfade = 0;
    }
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
      // Se cierra como al pulsar y luego se queda parado. Si el cierre cae en
      // el futuro (primer loop), la grabación sigue hasta ahí.
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
      if (recordingTrack()) cancelRecording();
      break;
    case State::kArmed:      // el toque canceló: nada más
      break;
    case State::kRecording:  // el toque cerró la pista → se quita
      undo(now);
      break;
    case State::kPlaying:    // el toque empezó a grabar → fuera, y lo anterior
      if (busy()) undo(now);
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
      if (recordingTrack()) cancelRecording();
      stopAll(now);
      break;
    case State::kArmed:
      stopAll(now);
      break;
    case State::kRecording:  // el toque cerró la pista → además parar
      stopAll(now);
      break;
    case State::kPlaying:    // el toque empezó a grabar → fuera y parar
      if (busy()) undo(now);
      stopRequest_ = true;   // EngineCore para (al momento, en el 1 o con fundido)
      break;
    case State::kOverdubbing:  // el toque acabó el overdub → parar
      stopRequest_ = true;
      break;
    case State::kStopped:    // el toque ya arrancó todo
      break;
  }
}

// ---------------------------------------------------------------- latencia

bool Looper::shiftAudio(int64_t frames, int64_t now) {
  if (busy() || frames == 0) return false;
  // Lo que está en la posición p del buffer tenía que estar en p − frames:
  // basta con que cada pista empiece a sonar frames muestras antes
  for (Track& t : tracks_) {
    if (t.len == 0) continue;
    t.origin -= frames;
    // Sin efecto, de la rejilla; con efecto, lo que sonaría frames después
    t.q = !t.reverse && !t.half ? gridQ(t, now) : wrap(t.q + int64_t(t.dq) * frames, 2 * t.len);
  }
  return true;
}

}  // namespace loopin
