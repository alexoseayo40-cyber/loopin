// Loopin — trabajos con el audio importado, en segundo plano
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <string>
#include <thread>

#include "Backing.h"
#include "Clip.h"

namespace loopin {

// Un hilo para un trabajo largo. Empezar uno nuevo cancela (y espera) el
// anterior. El estado se publica con atómicos para la interfaz.
class Worker {
 public:
  enum State : int32_t { kIdle = 0, kRunning = 1, kDone = 2, kFailed = 3 };

  ~Worker() { stop(); }
  // fn devuelve 0 si ha ido bien o un código de error
  void run(int32_t id, std::function<int32_t(Worker&)> fn);
  // Cancela el que esté en marcha y espera a que acabe (unos milisegundos).
  void stop();

  bool cancelled() const { return cancel_.load(std::memory_order_relaxed); }
  void setProgress(double fraction);
  // Hecho sin trabajar (lo pedido ya estaba): cancela el que haya.
  void finishNow(int32_t id);

  int32_t id() const { return id_.load(std::memory_order_relaxed); }
  int32_t state() const { return state_.load(std::memory_order_acquire); }
  int32_t progress() const { return progress_.load(std::memory_order_relaxed); }  // 0–1000
  int32_t error() const { return error_.load(std::memory_order_relaxed); }

 private:
  std::thread thread_;
  std::atomic<bool> cancel_{false};
  std::atomic<int32_t> id_{0};
  std::atomic<int32_t> state_{kIdle};
  std::atomic<int32_t> progress_{0};
  std::atomic<int32_t> error_{0};
};

// Lo que hace falta para estirar una canción al tempo del transporte.
struct PrepareParams {
  std::string path;
  double songBpm = 0.0;      // tempo de la canción (el de verdad, con decimales)
  double markSeconds = 0.0;  // dónde cae un 1 en el archivo
  int32_t samplesPerBeat = 0;  // los del transporte (a rate)
  int32_t beatsPerBar = 0;
  int32_t rate = 0;            // frecuencia del motor
  int32_t id = 0;
};

// Lo que se sabe de la canción abierta para prepararla.
struct PreviewInfo {
  int64_t frames = 0;          // a la frecuencia del motor
  double bpmGuess = 0.0;       // tempo sugerido (0 = ni idea)
  int64_t firstAttack = -1;    // primer golpe claro (muestra)
};

// Dos trabajos, cada uno en su hilo (así preparar la canción para sonar no
// interrumpe abrir otra para prepararla):
// - Abrir: decodifica y pasa a la frecuencia del motor, sin estirar. Es la
//   vista previa (forma de onda, escucharla, marcar el 1).
// - Preparar: decodifica y estira al tempo del transporte con SoundTouch
//   (LGPL), con el 1 en un inicio de compás. Es lo que suena con los loops.
// Se hace una vez, al pedirlo; el hilo de audio solo lee el resultado.
class SongJobs {
 public:
  // Duración máxima de lo que se guarda en memoria (10 min mono en 16 bits a
  // 48 kHz son unos 58 MB)
  static constexpr int32_t kMaxSeconds = 600;
  // Cuánto se puede estirar o encoger
  static constexpr double kMinTempo = 0.5;
  static constexpr double kMaxTempo = 2.0;
  // Por debajo de esta diferencia de tempo (0,3 %, unos 5 cents) no se
  // estira: se cambia la velocidad (el tono cambia tan poco que no se oye y
  // así no hay ningún artefacto del estirado)
  static constexpr double kRateOnly = 0.003;

  enum Error : int32_t {
    kOk = 0,
    kErrOpen = 1,     // no se puede abrir o no es WAV, MP3 ni FLAC
    kErrTooLong = 2,  // más de kMaxSeconds (a ese tempo)
    kErrMemory = 3,
    kErrEmpty = 4,    // no tiene sonido
    kErrTempo = 5,    // demasiado lejos del tempo de la canción
  };

  SongJobs(Backing& backing, ClipBin& bin) : backing_(backing), bin_(bin) {}
  ~SongJobs();

  // --- Hilo de la interfaz ---
  void open(const std::string& path, int32_t rate, int32_t id);
  void closeOpen();
  // Si ya se preparó hace poco igual (ver ClipBin), suena enseguida.
  void prepare(const PrepareParams& p);
  // Cancela la preparación en marcha (la que suena sigue).
  void cancelPrepare() { preparer_.stop(); }
  // Quita la canción que suena con el transporte
  void unload();

  const Worker& opener() const { return opener_; }
  const Worker& preparer() const { return preparer_; }
  PreviewInfo previewInfo() const;
  // Picos (de 0 a 1) de la canción abierta entre start y end, en bins trozos.
  // Devuelve cuántos ha escrito.
  int32_t peaks(int64_t start, int64_t end, int32_t bins, float* out) const;
  // El ataque más claro cerca de center (± radius muestras); -1 si no hay
  // canción abierta.
  int64_t findAttack(int64_t center, int64_t radius) const;

  // --- Lo que hace cada trabajo (se puede llamar directamente: tests) ---
  static int32_t buildPreview(const std::string& path, int32_t rate, int32_t id, Clip** out,
                              PreviewInfo* info, Worker* w);
  static int32_t buildBacking(const PrepareParams& p, Clip** out, Worker* w);
  static uint64_t keyOf(const PrepareParams& p);
  static int32_t peaksOf(const Clip& c, int64_t start, int64_t end, int32_t bins, float* out);
  static int64_t attackNear(const Clip& c, int64_t center, int64_t radius);

 private:
  Backing& backing_;
  ClipBin& bin_;
  Worker opener_;
  Worker preparer_;
  // La canción abierta (es la de la vista previa). Solo se borra desde el
  // hilo de la interfaz, que es el único que la consulta.
  std::atomic<const Clip*> open_{nullptr};
  std::atomic<int64_t> openFrames_{0};
  std::atomic<double> bpmGuess_{0.0};
  std::atomic<int64_t> firstAttack_{-1};
};

}  // namespace loopin
