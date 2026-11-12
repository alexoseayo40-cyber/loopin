// Loopin — looper de 4 pistas
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
  onset_.prepare(sampleRate);
  const int64_t capacity = int64_t(sampleRate) * maxSeconds;
  const bool keep = sampleRate == sampleRate_ && capacity == capacity_ && anyContent();
  sampleRate_ = sampleRate;

  if (!keep) {
    capacity_ = capacity;
    for (Track& t : tracks_) {
      t.data.assign(static_cast<size_t>(capacity_), 0.0f);
      t.len = 0;
      t.origin = 0;
      t.playPos = 0;
      t.layers = 0;
      t.winOpen = false;
      t.clearing = false;
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
      t.gain = t.muted ? 0.0f : t.volume;
    }
    state_ = anyContent() ? State::kStopped : State::kEmpty;
    if (state_ == State::kEmpty) baseLen_ = 0;
  }
  nextEvent_ = kNever;
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

void Looper::setTrackMuted(int32_t track, bool muted) {
  if (track < 0 || track >= kTracks) return;
  tr(track).muted = muted;
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
  t.playPos = wrap(now - t.origin, t.len);
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

void Looper::finishBackground(Layer& l) {
  const size_t end = static_cast<size_t>(std::min(l.extent, capacity_));
  if (l.st == Layer::St::kMerging) {
    std::vector<float>& dst = tr(l.track).data;
    for (size_t i = static_cast<size_t>(l.cursor); i < end; ++i) {
      dst[i] += l.data[i];
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
  fresh->winOrigin = t.origin;
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

// ---------------------------------------------------------------- borrar

void Looper::startClear(Track& t, int64_t extent) {
  extent = std::clamp<int64_t>(extent, 0, capacity_);
  if (t.clearing) extent = std::max(extent, t.clearExtent);
  t.clearing = true;
  t.clearCursor = 0;
  t.clearExtent = extent;
}

void Looper::finishClear(Track& t) {
  if (t.clearing) {
    std::fill(t.data.begin() + static_cast<std::ptrdiff_t>(t.clearCursor),
              t.data.begin() + static_cast<std::ptrdiff_t>(std::max(t.clearExtent, t.clearCursor)),
              0.0f);
  }
  t.clearing = false;
  t.clearCursor = 0;
  t.clearExtent = 0;
}

// Quita una pista con contenido y sus capas (no toca el estado general)
void Looper::dropTrack(int32_t track) {
  for (Layer& l : layers_) {
    if (l.track != track || l.st == Layer::St::kEmpty || l.st == Layer::St::kClearing) continue;
    if (l.st == Layer::St::kLive) last_ = Last::kNone;
    discard(l);
  }
  Track& t = tr(track);
  if (t.len > 0) startClear(t, t.len);
  t.len = 0;
  t.layers = 0;
  t.playPos = 0;
  t.winOpen = false;
  if (last_ == Last::kTrack && lastTrack_ == track) last_ = Last::kNone;
}

void Looper::clearTrack(int32_t track, int64_t /*now*/) {
  if (track < 0 || track >= kTracks) return;
  if (recordingTrack()) {
    // Se cancela la grabación si es en esta pista o si, sin esta pista, ya no
    // quedaría ningún loop sobre el que grabar
    bool others = false;
    for (int32_t i = 0; i < kTracks; ++i) others = others || (i != track && tr(i).len > 0);
    if (track == active_ || !others) cancelRecording();
  } else if (state_ == State::kOverdubbing && track == active_) {
    state_ = State::kPlaying;
  }
  dropTrack(track);
  refreshEmpty();
  clearPre();
}

void Looper::clearAll(int64_t /*now*/) {
  if (recordingTrack()) cancelRecording();
  if (state_ == State::kOverdubbing) state_ = State::kPlaying;
  for (int32_t i = 0; i < kTracks; ++i) dropTrack(i);
  refreshEmpty();
  clearPre();
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
      t.playPos = wrap(now - t.origin, t.len);
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
      stopAll(now);
      break;
    case State::kOverdubbing:
      stopAll(now);
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
    t.playPos = wrap(now - t.origin, t.len);
  }
  return true;
}

// ---------------------------------------------------------------- captura

void Looper::capture(const InputRing& in, int64_t now) {
  if (waiting_) {
    // Primero se mide el ruido de fondo (150 ms) y luego se busca el primer
    // ataque por encima de él
    if (scanPos_ < 0) scanPos_ = in.end();
    scanPos_ = std::max(scanPos_, in.begin());
    for (; scanPos_ < in.end(); ++scanPos_) {
      const float x = in.at(scanPos_);
      if (warmup_ > 0) {
        noisePeak_ = std::max(noisePeak_, std::fabs(x));
        if (--warmup_ == 0) onset_.reset(std::clamp(3.0f * noisePeak_, 0.02f, 0.5f), 0);
        continue;
      }
      if (onset_.push(x)) {
        // El ataque se nota un poco después de empezar: 2 ms antes
        const int64_t start = scanPos_ - latency_ - sampleRate_ / 500;
        startFirstAt(start, now);
        break;
      }
    }
  }
  const int64_t end = in.end() - latency_;  // se pueden capturar los n < end
  bool open = false;
  for (const Track& t : tracks_) open = open || t.winOpen;
  for (const Layer& l : layers_) open = open || l.winOpen;
  if (!open) {
    capN_ = std::max(capN_, end);
    return;
  }
  int64_t n = std::max(capN_, in.begin() - latency_);
  for (; n < end; ++n) {
    const float x = in.at(n + latency_);
    for (Track& t : tracks_) {
      if (t.winOpen && n >= t.winStart && n < t.winEnd) {
        const int64_t idx = n - t.winStart;
        if (idx < capacity_) t.data[static_cast<size_t>(idx)] = x;
      }
    }
    for (Layer& l : layers_) {
      if (l.winOpen && n >= l.winStart && n < l.winEnd) {
        l.data[static_cast<size_t>(wrap(n - l.winOrigin, l.extent))] += x;
      }
    }
  }
  capN_ = std::max(capN_, n);
  for (int32_t i = 0; i < kTracks; ++i) {
    Track& t = tr(i);
    // La pista que se está grabando no se cierra hasta que acabe
    if (t.winOpen && !(recordingTrack() && i == active_) && capN_ >= t.winEnd) t.winOpen = false;
  }
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
    std::vector<float>& dst = tr(l.track).data;
    const int64_t end = std::min(std::min(l.extent, capacity_), l.cursor + budget);
    for (int64_t i = l.cursor; i < end; ++i) {
      const size_t k = static_cast<size_t>(i);
      if (merging) dst[k] += l.data[k];
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
  for (Track& t : tracks_) {
    if (budget <= 0) return;
    if (!t.clearing) continue;
    const int64_t end = std::min(t.clearExtent, t.clearCursor + budget);
    if (end > t.clearCursor) {
      std::fill(t.data.begin() + static_cast<std::ptrdiff_t>(t.clearCursor),
                t.data.begin() + static_cast<std::ptrdiff_t>(end), 0.0f);
      budget -= static_cast<int32_t>(end - t.clearCursor);
      t.clearCursor = end;
    }
    if (t.clearCursor >= t.clearExtent) {
      t.clearing = false;
      t.clearCursor = 0;
      t.clearExtent = 0;
    }
  }
}

}  // namespace loopin
