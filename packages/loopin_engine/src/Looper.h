// Loopin — looper de 4 pistas: grabar, reproducir, overdub, deshacer y borrar
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <algorithm>
#include <array>
#include <cstdint>
#include <limits>
#include <vector>

#include "InputRing.h"
#include "OnsetDetector.h"
#include "Transport.h"

namespace loopin {

// Cuatro pistas sincronizadas con el transporte.
//
// Cómo se cuenta el tiempo: n es el índice absoluto de una muestra de salida y
// j el de una de entrada. Todo (inicio y fin de la grabación, overdub, origen
// del loop) se decide en índices de salida, que es lo que oye el músico. La
// muestra de entrada j se grabó mientras sonaba la salida n = j − latencia, así
// que se escribe en la posición del loop que corresponde a n. Por eso la
// escritura va con retraso: capture() avanza un cursor de salida capN_ a medida
// que llega la entrada.
//
// Pistas: la primera que se graba marca la duración base (con cuenta de
// entrada). Las siguientes se graban sobre lo que suena, empiezan en el primer
// tiempo del siguiente compás y duran 1, 2 o 4 veces la base. Cada pista tiene
// su propio origen (la muestra de salida de su posición 0), así no hay que
// girar ningún buffer: suena en wrap(n − origen, longitud).
//
// Solo se graba en una pista a la vez (la «activa»). La pista «seleccionada»
// es la que usará el siguiente toque del botón principal.
//
// Capas: cada overdub va a una capa aparte (hay dos, compartidas entre las
// cuatro pistas) para poder deshacerlo. Al acabar el siguiente overdub o la
// siguiente pista, la capa anterior se suma a su pista poco a poco en segundo
// plano: como lo que suena es pista + capas, sumar una muestra de la capa a la
// pista y poner la capa a 0 no cambia nada de lo que se oye.
//
// Invariante: el buffer de una pista vacía es todo ceros (salvo mientras se
// está borrando en segundo plano). Así, si se deja de grabar antes de llenar la
// pista, el resto es silencio sin tener que escribirlo.
//
// Reverse y media velocidad (Etapa 5): cada pista lee su buffer en una
// posición q contada en medias muestras, que avanza dq por muestra de salida:
// +2 normal, +1 a media velocidad (entre dos muestras se toma la media), −2 al
// revés y −1 las dos cosas. Sin efectos, q sale de la rejilla (2 × posición en
// el loop). Al poner un efecto se sigue desde donde suena; al quitarlos todos
// la pista vuelve a su sitio en la rejilla. Cada cambio lleva un fundido
// cruzado de 5 ms. Un overdub sobre una pista con efecto se escribe donde se
// está oyendo (al revés o, a media velocidad, dos muestras de entrada por cada
// una del buffer).
//
// Cambios al compás: con quantize, silenciar, reverse y media velocidad se
// aplican en el siguiente primer tiempo (el silencio, justo en el 1; quitarlo,
// 5 ms antes para que la rampa de volumen acabe en el 1).
class Looper {
 public:
  static constexpr int32_t kTracks = 4;

  // Estado general y también el de cada pista (trackState).
  enum class State : int32_t {
    kEmpty = 0,     // sin loop
    kArmed = 1,     // esperando para grabar (cuenta de entrada o siguiente compás)
    kRecording = 2, // grabando una pista vacía
    kPlaying = 3,
    kOverdubbing = 4,
    kStopped = 5,   // hay loop pero el transporte está parado
  };
  enum class Mode : int32_t {
    kSync = 0,    // graba N compases y se cierra solo
    kManual = 1,  // se cierra al pulsar
    kFree = 2,    // sin metrónomo: el primer loop marca el tempo
  };

  static constexpr int32_t kMaxSeconds = 60;
  static constexpr int64_t kNever = std::numeric_limits<int64_t>::max();

  // Fuera del hilo de audio. Reserva memoria. Si ya estaba preparado con la
  // misma frecuencia, conserva los loops (quedan parados); si cambia, los borra.
  void prepare(int32_t sampleRate, Transport* transport, int32_t maxSeconds = kMaxSeconds);

  // --- Órdenes (hilo de audio, al principio de un bloque) ---
  // now = índice absoluto de la próxima muestra de salida.
  void press(int64_t now);      // toque del botón principal
  void hold(int64_t now);       // mantener pulsado tras un toque
  void doubleTap(int64_t now);  // segundo toque rápido tras un toque
  void undo(int64_t now);       // deshace lo último (una capa o una pista)
  void clearAll(int64_t now);
  void clearTrack(int32_t track, int64_t now);
  void startAll(int64_t now);   // arranca transporte (y loops si los hay)
  void stopAll(int64_t now);    // para transporte y loops
  void select(int32_t track);   // no hace nada mientras se graba
  void selectNext();
  void setAutoAdvance(bool on) { autoAdvance_ = on; }
  // La primera pista no cuenta: espera a que suene la guitarra y empieza
  // justo en ese ataque (que pasa a ser el primer tiempo del compás 1).
  void setStartOnSound(bool on) { startOnSound_ = on; }
  // Mueve todo lo grabado frames muestras antes (o después, si es negativo).
  // Para corregir la latencia a oído: si la compensación se queda corta en d,
  // todo lo grabado suena d tarde. No hace nada mientras se graba.
  bool shiftAudio(int64_t frames, int64_t now);
  void setMode(Mode mode) { mode_ = mode; }
  void setSyncBars(int32_t bars);
  void setLatency(int32_t frames);
  void setVolume(float volume);  // volumen general de los loops
  void setTrackVolume(int32_t track, float volume);
  // Silenciar, reverse y media velocidad: al momento o, con quantize, en el
  // siguiente 1. Reverse y media velocidad solo en pistas con loop que no se
  // estén grabando (ni con un overdub en marcha).
  void setTrackMuted(int32_t track, bool muted, int64_t now);
  void setTrackReverse(int32_t track, bool on, int64_t now);
  void setTrackHalf(int32_t track, bool on, int64_t now);
  void setQuantize(bool on) { quantize_ = on; }
  bool quantize() const { return quantize_; }
  // Termina el overdub en marcha (para parar con fundido o en el 1)
  void finishOverdub(int64_t now) {
    if (state_ == State::kOverdubbing) endOverdub(now);
  }
  // El doble toque pide parar: EngineCore decide cómo (al momento, en el 1 o
  // con fundido). Devuelve true una vez por petición.
  bool takeStopRequest() {
    const bool r = stopRequest_;
    stopRequest_ = false;
    return r;
  }
  // Volumen de lo que ya suena mientras se graba (1 = normal, 0 = silencio).
  // Con el altavoz y el micrófono del móvil, lo que suena vuelve a entrar por
  // el micrófono y se grabaría otra vez encima.
  void setRecordDuck(float gain) { recordDuck_ = std::clamp(gain, 0.0f, 1.0f); }
  float recordDuck() const { return recordDuck_; }

  // --- Por muestra / por bloque (hilo de audio) ---
  // Una muestra de salida. Llamar después de transport.tick() de esa muestra.
  inline float render(int64_t n) {
    if (n >= nextEvent_) fireEvent(n);
    if (n >= nextTrackChange_) applyTrackChanges(n);
    if (state_ == State::kStopped || baseLen_ == 0) return 0.0f;
    float out = 0.0f;
    for (int32_t i = 0; i < kTracks; ++i) {
      Track& t = tracks_[static_cast<size_t>(i)];
      if (t.len == 0) continue;
      float s = read(i, t.q);
      if (t.xfade > 0) {
        // Fundido cruzado con la lectura de antes del cambio
        const float w = float(t.xfade) / float(xfadeLen_);
        s = s * (1.0f - w) + read(i, t.oq) * w;
        t.oq = step(t.oq, t.odq, t.len);
        --t.xfade;
      }
      t.q = step(t.q, t.dq, t.len);
      // El volumen cambia en una rampa de 5 ms para que no haga «clic»
      const float target = t.muted ? 0.0f : t.volume;
      if (t.gain != target) {
        if (t.gain < target) t.gain = std::min(target, t.gain + gainStep_);
        else t.gain = std::max(target, t.gain - gainStep_);
      }
      out += s * t.gain;
    }
    // Mientras se graba, lo que suena baja (o se calla). Empieza a bajar un
    // poco antes del inicio para que ya esté abajo cuando empiece a grabar;
    // vuelve justo al acabar. Como el micrófono oye la salida con la latencia
    // de retraso, lo que sonó antes del inicio o después del final cae fuera
    // de la grabación.
    if (recordDuck_ < 1.0f || duck_ != 1.0f) {
      const float target =
          writingAt(n) || writingAt(n + duckLead_) ? recordDuck_ : 1.0f;
      // Rampa recta de 12,5 ms: ya está abajo del todo cuando empieza a grabar
      if (duck_ < target) duck_ = std::min(target, duck_ + duckStep_);
      else if (duck_ > target) duck_ = std::max(target, duck_ - duckStep_);
      out *= duck_;
    }
    return out * volume_;
  }
  // Escribe en las pistas la entrada que ya ha llegado, compensada. now =
  // índice de la próxima muestra de salida. También busca el primer ataque
  // si se está esperando a que suene la guitarra.
  void capture(const InputRing& in, int64_t now);
  // Trabajo de fondo acotado: sumar o borrar capas y pistas (budget muestras).
  void background(int32_t budget);

  // --- Estado ---
  State state() const { return state_; }
  Mode mode() const { return mode_; }
  int32_t syncBars() const { return syncBars_; }
  bool autoAdvance() const { return autoAdvance_; }
  bool startOnSound() const { return startOnSound_; }
  // Esperando a que suene la guitarra para empezar la primera pista
  bool waiting() const { return waiting_; }
  bool locksTempo() const { return state_ != State::kEmpty; }
  // Durante la cuenta de entrada el clic suena aunque esté apagado.
  bool forcesClick() const {
    return state_ == State::kArmed && baseLen_ == 0 && !waiting_ && mode_ != Mode::kFree;
  }
  int32_t selected() const { return selected_; }
  // Pista en la que se está grabando (o a punto), −1 si ninguna.
  int32_t active() const { return busy() ? active_ : -1; }
  int64_t baseLength() const { return baseLen_; }
  int64_t basePosition(int64_t now) const;
  int64_t barFrames() const { return barFrames_; }
  int32_t latency() const { return latency_; }
  bool canUndo() const;
  // Armado: negativo, muestras que faltan para empezar. Grabando: grabadas.
  int64_t recordedFrames(int64_t now) const;
  // Duración a la que se cerrará la grabación en curso (0 si aún no se sabe).
  int64_t targetFrames() const;
  int64_t capacityFrames() const { return capacity_; }

  State trackState(int32_t track) const;
  int64_t trackLength(int32_t track) const { return tr(track).len; }
  // Posición del buffer que suena (al revés, va hacia atrás)
  int64_t trackPosition(int32_t track) const { return tr(track).q >> 1; }
  int32_t trackLayers(int32_t track) const { return tr(track).layers; }
  float trackVolume(int32_t track) const { return tr(track).volume; }
  // Lo pedido (puede estar esperando al siguiente 1: ver trackPending)
  bool trackMuted(int32_t track) const { return tr(track).wantMuted; }
  bool trackReverse(int32_t track) const { return tr(track).wantReverse; }
  bool trackHalf(int32_t track) const { return tr(track).wantHalf; }
  // Cambios que esperan al siguiente 1: bit 0 silencio, bit 1 reverse, bit 2
  // media velocidad
  int32_t trackPending(int32_t track) const;
  // Paso de lectura aplicado (+2, +1, −2 o −1 medias muestras por muestra)
  int32_t trackStep(int32_t track) const { return tr(track).dq; }

  // --- Sesiones (Etapa 6) ---
  // Nada se escribe en las pistas ni se va a escribir sin una orden nueva: no
  // se graba ni se espera para grabar, no queda entrada por capturar y no hay
  // trabajo de fondo (sumar capas, borrar). Entonces otro hilo puede leerlas.
  bool settled() const;
  // Dónde empieza la pista respecto al ciclo base: su origen menos el del
  // ciclo, en [0, longitud). Se conserva al parar y arrancar.
  int64_t trackOffset(int32_t track) const;
  // Lo que suena de la pista (con sus capas) en out[0, longitud), si out no
  // es nullptr y cabe en max. Devuelve la longitud (0 = vacía). hash: una
  // huella del contenido, para saber si ha cambiado (puede ser nullptr).
  // Solo con settled() (desde otro hilo) o en el hilo de audio.
  int64_t readTrack(int32_t track, float* out, int64_t max, uint64_t* hash) const;
  // Para cargar una sesión desde otro hilo: el buffer de una pista vacía
  // (con settled() y sin loops: nadie lo toca). Caben capacityFrames().
  float* trackBuffer(int32_t track) { return tr(track).data.data(); }
  // Lo que hace falta para que suenen unas pistas ya escritas en sus buffers
  struct Restore {
    int64_t barFrames = 0;
    int64_t baseLen = 0;
    int64_t len[kTracks] = {};     // 0 = vacía; si no, 1, 2 o 4 veces la base
    int64_t offset[kTracks] = {};  // ver trackOffset()
    int32_t layers[kTracks] = {};  // capas que se ven (sin deshacer)
    int32_t selected = 0;
  };
  // Hilo de audio, sin loops y con settled(): las pistas quedan con esas
  // longitudes, paradas, sin efectos y sin nada que deshacer. Devuelve false
  // (y no cambia nada) si no se puede.
  bool restore(const Restore& r, int64_t now);

  // De la pista seleccionada (lo que mira el botón principal)
  int64_t length() const { return trackLength(selected_); }
  int64_t position() const { return trackPosition(selected_); }
  int32_t layerCount() const { return trackLayers(selected_); }

 private:
  // Módulo siempre positivo
  static int64_t wrap(int64_t a, int64_t m) {
    const int64_t r = a % m;
    return r < 0 ? r + m : r;
  }

  struct Track {
    std::vector<float> data;
    int64_t len = 0;      // 0 = vacía
    int64_t origin = 0;   // índice de salida de su posición 0
    // Lectura: posición en medias muestras [0, 2·len) y paso por muestra
    int64_t q = 0;
    int32_t dq = 2;
    // Fundido cruzado tras un cambio de lectura: la de antes sigue sonando
    // xfade muestras más, cada vez más baja
    int64_t oq = 0;
    int32_t odq = 2;
    int32_t xfade = 0;
    int32_t layers = 0;   // capas que suenan (la primera grabación cuenta 1)
    float volume = 1.0f;
    bool muted = false;   // aplicado
    float gain = 1.0f;    // volumen aplicado (sigue a volume / muted)
    bool reverse = false, half = false;  // aplicados
    // Lo pedido y cuándo se aplica (kNever = ya aplicado)
    bool wantMuted = false, wantReverse = false, wantHalf = false;
    int64_t muteAt = kNever, fxAt = kNever;
    // Ventana de la primera grabación de la pista (índices de salida)
    bool winOpen = false;
    int64_t winStart = 0, winEnd = 0;
    // Borrado en segundo plano de [0, clearExtent)
    bool clearing = false;
    int64_t clearCursor = 0, clearExtent = 0;
  };

  struct Layer {
    enum class St { kEmpty, kRecording, kLive, kMerging, kClearing };
    std::vector<float> data;
    St st = St::kEmpty;
    int32_t track = 0;   // pista a la que pertenece
    int64_t extent = 0;  // posiciones [0, extent) que pueden no ser 0
    int64_t cursor = 0;  // avance del trabajo de fondo
    // Ventana de grabación (índices de salida). La muestra de salida n se
    // escribe donde la pista se oye en n: q = q0 + dq · (n − winStart)
    bool winOpen = false;
    int64_t winStart = 0, winEnd = 0;
    int64_t q0 = 0;
    int32_t dq = 2;
    bool audible() const {
      return st == St::kRecording || st == St::kLive || st == St::kMerging;
    }
  };

  // Lo último que se hizo y se puede deshacer
  enum class Last { kNone, kLayer, kTrack };

  const Track& tr(int32_t track) const {
    return tracks_[static_cast<size_t>(track < 0 ? 0 : (track >= kTracks ? kTracks - 1 : track))];
  }
  Track& tr(int32_t track) {
    return tracks_[static_cast<size_t>(track < 0 ? 0 : (track >= kTracks ? kTracks - 1 : track))];
  }
  bool busy() const {
    return state_ == State::kArmed || state_ == State::kRecording ||
           state_ == State::kOverdubbing;
  }
  bool recordingTrack() const {
    return state_ == State::kArmed || state_ == State::kRecording;
  }
  bool anyContent() const;
  // En la muestra de salida n se está grabando (una pista o un overdub)
  bool writingAt(int64_t n) const {
    if (recordingTrack() && n >= recStart_ && n < recEnd_) return true;
    for (const Layer& l : layers_)
      if (l.st == Layer::St::kRecording && l.winOpen && n >= l.winStart && n < l.winEnd)
        return true;
    return false;
  }

  void fireEvent(int64_t n);
  // Lectura de la pista i en la posición q (medias muestras): pista + capas
  inline float read(int32_t i, int64_t q) const {
    const Track& t = tracks_[static_cast<size_t>(i)];
    const size_t p = static_cast<size_t>(q >> 1);
    float s = t.data[p];
    for (const Layer& l : layers_)
      if (l.track == i && l.audible()) s += l.data[p];
    if ((q & 1) == 0) return s;
    // Entre dos muestras (media velocidad): la media
    const size_t p2 = p + 1 >= static_cast<size_t>(t.len) ? 0 : p + 1;
    float s2 = t.data[p2];
    for (const Layer& l : layers_)
      if (l.track == i && l.audible()) s2 += l.data[p2];
    return 0.5f * (s + s2);
  }
  static inline int64_t step(int64_t q, int32_t dq, int64_t len) {
    q += dq;
    if (q >= 2 * len) q -= 2 * len;
    else if (q < 0) q += 2 * len;
    return q;
  }
  static int32_t stepFor(bool reverse, bool half) {
    return (half ? 1 : 2) * (reverse ? -1 : 1);
  }
  // Posición en la rejilla (sin efectos) de la pista en la muestra n
  int64_t gridQ(const Track& t, int64_t n) const { return 2 * wrap(n - t.origin, t.len); }
  // Dónde leerá la pista en la muestra n ≥ ahora (con el cambio pendiente)
  void readAt(const Track& t, int64_t now, int64_t n, int64_t* q, int32_t* dq) const;
  // Aplica en la muestra n lo que toque (silencio y efectos pendientes)
  void applyTrackChanges(int64_t n);
  void applyFx(Track& t, int64_t n);
  void rescheduleTrackChanges();
  // Muestra en la que se aplica un cambio pedido ahora (el siguiente 1)
  int64_t changeAt(int64_t now) const;
  void resetTrackFx(Track& t);
  void arm(int64_t now);
  void startFirstAt(int64_t start, int64_t now);
  bool closeFree(int64_t now);
  void closeRecording(int64_t now);
  void finishRecording(int64_t now);
  void cancelRecording();
  void startOverdub(int64_t now);
  void endOverdub(int64_t now);
  void discard(Layer& l);
  void finishBackground(Layer& l);
  void startClear(Track& t, int64_t extent);
  void finishClear(Track& t);
  void dropTrack(int32_t track);
  void consolidateLive();
  void advanceSelection(int32_t from);
  void refreshEmpty();
  Layer* findLayer(Layer::St st);
  int64_t maxBars() const;
  int64_t maxMultiple() const;
  int64_t lengthFor(int64_t frames) const;
  void clearPre() { hasPre_ = false; }

  int32_t sampleRate_ = 0;
  Transport* transport_ = nullptr;
  int64_t capacity_ = 0;
  std::array<Track, kTracks> tracks_;
  std::array<Layer, 2> layers_;

  State state_ = State::kEmpty;
  Mode mode_ = Mode::kSync;
  int32_t syncBars_ = 4;
  float volume_ = 1.0f;
  float recordDuck_ = 1.0f;  // volumen de lo que suena mientras se graba
  float duck_ = 1.0f;        // el aplicado (sigue a recordDuck_ poco a poco)
  int64_t duckLead_ = 1200;  // empieza a bajar 25 ms antes de grabar
  float duckStep_ = 1.0f / 600;  // por muestra: de arriba abajo en la mitad
  float gainStep_ = 1.0f / 240;  // volumen de una pista: rampa de 5 ms
  int32_t xfadeLen_ = 240;       // fundido cruzado al cambiar de efecto: 5 ms
  bool quantize_ = false;        // silencio y efectos en el siguiente 1
  int64_t nextTrackChange_ = kNever;
  bool stopRequest_ = false;
  int32_t latency_ = 0;
  bool autoAdvance_ = false;
  bool startOnSound_ = false;

  // Esperando el primer ataque
  bool waiting_ = false;
  int64_t scanPos_ = -1;    // próxima muestra de entrada por mirar (−1 = desde ya)
  int32_t warmup_ = 0;      // muestras para medir el ruido antes de escuchar
  float noisePeak_ = 0.0f;
  OnsetDetector onset_;

  int32_t selected_ = 0;  // pista que usará el siguiente toque
  int32_t active_ = 0;    // pista en la que se graba

  int64_t barFrames_ = 0;  // muestras por compás de los loops
  int64_t baseLen_ = 0;    // duración base (0 = no hay ningún loop)
  int64_t origin_ = 0;     // índice de salida de un inicio del ciclo base
  int64_t nextEvent_ = kNever;

  // Grabación en curso de la pista activa: ventana [recStart_, recEnd_)
  int64_t recStart_ = 0;
  int64_t recEnd_ = 0;
  int64_t newLen_ = 0;         // longitud elegida al cerrar (pistas 2 a 4)
  bool userClosed_ = false;    // ya se pulsó para cerrar
  bool stopAfterRec_ = false;  // al acabar de grabar, quedarse parado

  int64_t capN_ = 0;  // siguiente índice de salida a capturar

  Last last_ = Last::kNone;
  int32_t lastTrack_ = 0;

  // Estado antes del último toque, para interpretar «mantener» y «doble toque»
  bool hasPre_ = false;
  State preState_ = State::kEmpty;
};

}  // namespace loopin
