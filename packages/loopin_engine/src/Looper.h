// Loopin — looper: grabar, reproducir, overdub, deshacer y borrar
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <array>
#include <cstdint>
#include <limits>
#include <vector>

#include "Transport.h"

namespace loopin {

// Últimas muestras de entrada (mono, ya con ganancia), indexadas por su índice
// absoluto de entrada. El looper lee de aquí con retraso (la latencia) y el
// monitor lee lo más reciente.
class InputRing {
 public:
  // Fuera del hilo de audio. Tamaño: la potencia de 2 que cubra minFrames.
  void prepare(int32_t minFrames);
  void reset();

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

// Un loop sincronizado con el transporte (Etapa 2: una pista).
//
// Cómo se cuenta el tiempo: n es el índice absoluto de una muestra de salida y
// j el de una de entrada. Todo (inicio y fin de la grabación, overdub, origen
// del loop) se decide en índices de salida, que es lo que oye el músico. La
// muestra de entrada j se grabó mientras sonaba la salida n = j − latencia, así
// que se escribe en la posición del loop que corresponde a n. Por eso la
// escritura va con retraso: capture() avanza un cursor de salida capN_ a medida
// que llega la entrada.
//
// Capas: base_ es el loop ya consolidado. Cada overdub va a una capa aparte
// (hay dos) para poder deshacerlo. Al acabar un overdub, la capa anterior se
// suma a base_ poco a poco en segundo plano: como lo que suena es
// base_ + capas, sumar una muestra de la capa a base_ y poner la capa a 0 no
// cambia nada de lo que se oye.
class Looper {
 public:
  enum class State : int32_t {
    kEmpty = 0,     // sin loop
    kArmed = 1,     // esperando al primer tiempo para grabar (cuenta de entrada)
    kRecording = 2, // grabando el primer loop
    kPlaying = 3,
    kOverdubbing = 4,
    kStopped = 5,   // hay loop pero el transporte está parado
  };
  enum class Mode : int32_t {
    kSync = 0,    // graba N compases y se cierra solo
    kManual = 1,  // se cierra al pulsar, en el compás más cercano
  };

  static constexpr int32_t kMaxSeconds = 60;
  static constexpr int64_t kNever = std::numeric_limits<int64_t>::max();

  // Fuera del hilo de audio. Reserva memoria. Si ya estaba preparado con la
  // misma frecuencia, conserva el loop (queda parado); si cambia, lo borra.
  void prepare(int32_t sampleRate, Transport* transport, int32_t maxSeconds = kMaxSeconds);

  // --- Órdenes (hilo de audio, al principio de un bloque) ---
  // now = índice absoluto de la próxima muestra de salida.
  void press(int64_t now, const InputRing& in);  // toque del botón principal
  void hold(int64_t now);       // mantener pulsado tras un toque
  void doubleTap(int64_t now);  // segundo toque rápido tras un toque
  void undo(int64_t now);
  void clear(int64_t now);
  void startAll(int64_t now);   // arranca transporte (y loop si lo hay)
  void stopAll(int64_t now);    // para transporte y loop
  void setMode(Mode mode) { mode_ = mode; }
  void setSyncBars(int32_t bars);
  void setLatency(int32_t frames);
  void setVolume(float volume);

  // --- Por muestra / por bloque (hilo de audio) ---
  // Una muestra de salida. Llamar después de transport.tick() de esa muestra.
  inline float render(int64_t n) {
    if (n >= nextEvent_) fireEvent(n);
    if (state_ != State::kPlaying && state_ != State::kOverdubbing) return 0.0f;
    const size_t p = static_cast<size_t>(playPos_);
    float s = base_[p];
    for (const Layer& l : layers_)
      if (l.audible()) s += l.data[p];
    if (++playPos_ >= length_) playPos_ = 0;
    return s * volume_;
  }
  // Escribe en el loop la entrada que ya ha llegado, compensada.
  void capture(const InputRing& in);
  // Trabajo de fondo acotado: sumar o borrar capas (budget muestras).
  void background(int32_t budget);

  // --- Estado ---
  State state() const { return state_; }
  Mode mode() const { return mode_; }
  int32_t syncBars() const { return syncBars_; }
  bool locksTempo() const { return state_ != State::kEmpty; }
  // Durante la cuenta de entrada el clic suena aunque esté apagado.
  bool forcesClick() const { return state_ == State::kArmed; }
  int64_t length() const { return length_; }
  int64_t position() const { return playPos_; }
  int64_t barFrames() const { return barFrames_; }
  int32_t latency() const { return latency_; }
  int32_t layerCount() const { return layerCount_; }
  bool canUndo() const;
  // Armado: negativo, muestras que faltan para empezar. Grabando: grabadas.
  int64_t recordedFrames(int64_t now) const;
  // Duración a la que se cerrará la grabación en curso (0 si aún no se sabe).
  int64_t targetFrames() const;
  int64_t capacityFrames() const { return capacity_; }

 private:
  struct Layer {
    enum class St { kEmpty, kRecording, kLive, kMerging, kClearing };
    std::vector<float> data;
    St st = St::kEmpty;
    int64_t extent = 0;  // posiciones [0, extent) que pueden no ser 0
    int64_t cursor = 0;  // avance del trabajo de fondo
    // Ventana de grabación (índices de salida) y origen del loop en ella
    bool winOpen = false;
    int64_t winStart = 0, winEnd = 0, winOrigin = 0;
    bool audible() const {
      return st == St::kRecording || st == St::kLive || st == St::kMerging;
    }
  };

  void fireEvent(int64_t n);
  void arm(int64_t now, const InputRing& in);
  void closeRecording(int64_t now);
  void finishRecording(int64_t now);
  void cancelRecording();
  void startOverdub(int64_t now);
  void endOverdub(int64_t now);
  void discard(Layer& l);
  void finishBackground(Layer& l);
  Layer* findLayer(Layer::St st);
  int64_t maxBars() const;
  void clearPre() { hasPre_ = false; }

  int32_t sampleRate_ = 0;
  Transport* transport_ = nullptr;
  int64_t capacity_ = 0;
  std::vector<float> base_;
  std::array<Layer, 2> layers_;

  State state_ = State::kEmpty;
  Mode mode_ = Mode::kSync;
  int32_t syncBars_ = 4;
  float volume_ = 1.0f;
  int32_t latency_ = 0;

  int64_t barFrames_ = 0;  // muestras por compás del loop
  int64_t length_ = 0;     // longitud del loop (0 = vacío)
  int64_t origin_ = 0;     // índice de salida de la posición 0 del loop
  int64_t playPos_ = 0;
  int64_t nextEvent_ = kNever;
  int32_t layerCount_ = 0;  // capas que suenan (el loop base cuenta como 1)

  // Grabación del primer loop: ventana [recStart_, recEnd_)
  int64_t recStart_ = 0;
  int64_t recEnd_ = 0;
  bool recWinOpen_ = false;
  bool userClosed_ = false;    // ya se pulsó para cerrar
  bool stopAfterRec_ = false;  // al acabar de grabar, quedarse parado

  int64_t capN_ = 0;  // siguiente índice de salida a capturar

  // Estado antes del último toque, para interpretar «mantener» y «doble toque»
  bool hasPre_ = false;
  State preState_ = State::kEmpty;
};

}  // namespace loopin
