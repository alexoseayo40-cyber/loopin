// Loopin — núcleo del motor, independiente de Oboe (se puede probar en el PC)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <atomic>
#include <cstdint>
#include <vector>

#include "LatencyMeter.h"
#include "Looper.h"
#include "Metronome.h"
#include "SpscQueue.h"
#include "TapCalibrator.h"
#include "Transport.h"

namespace loopin {

struct Command {
  enum class Type : int32_t {
    kPlay,
    kPause,
    kSetBpm,
    kSetBeatsPerBar,
    kSetClickEnabled,
    kSetClickVolume,
    kSetMonitorEnabled,
    kSetMonitorVolume,
    kSetInputGain,
    kMeasureLatency,
    // Looper
    kLoopPress,      // toque del botón principal
    kLoopHold,       // se mantiene pulsado tras el toque
    kLoopDoubleTap,  // segundo toque rápido
    kLoopUndo,
    kLoopClear,      // borra todas las pistas
    kSetLoopMode,    // Looper::Mode
    kSetSyncBars,
    kSetLatencyFrames,  // compensación de la grabación (muestras)
    kSetLoopVolume,
    kSetRecordDuck,     // volumen de lo que suena mientras se graba (0–1)
    // Pistas (arg = pista, de 0 a 3)
    kSelectTrack,
    kSelectNextTrack,
    kSetTrackVolume,
    kSetTrackMuted,
    kClearTrack,
    kSetAutoAdvance,
    // Etapa 3, parte 2
    kSetMeter,         // value = tiempos, arg = acentos medios (bits)
    kSetClickMode,     // ClickMode
    kStartTapCalibration,
    kCancelTapCalibration,
    kNudgeLatency,     // nueva compensación; mueve lo grabado lo que cambie
    kSetStartOnSound,
  };
  Type type = Type::kPlay;
  double value = 0.0;
  int32_t arg = 0;
};

// Cuándo suena el clic del metrónomo
enum class ClickMode : int32_t {
  kSilent = 0,   // nunca (metrónomo solo visual)
  kCountIn = 1,  // solo en la cuenta de entrada
  kAlways = 2,
};

// Lo que el núcleo publica para la interfaz (atómicos, sin bloqueos).
struct CoreStatus {
  bool playing;
  int32_t bar;
  int32_t beat;
  int32_t beatsPerBar;
  int32_t samplesPerBeat;
  double bpm;
  int64_t framePosition;
  float inputPeak;
  int32_t latencyState;
  int32_t latencyProgress;
  int32_t latencyFrames;
  // Looper
  int32_t loopState;
  int32_t loopMode;
  int32_t loopSyncBars;
  int32_t loopLayers;
  int32_t loopCanUndo;
  int32_t loopLatencyFrames;
  int64_t loopLength;
  int64_t loopPosition;
  int64_t loopRecorded;
  int64_t loopTarget;
  int64_t loopBarFrames;
  // Pistas
  int32_t loopSelected;
  int32_t loopActive;
  int32_t loopAutoAdvance;
  int64_t loopBaseLength;
  int64_t loopBasePosition;
  int32_t trackState[Looper::kTracks];
  int32_t trackLayers[Looper::kTracks];
  int32_t trackMuted[Looper::kTracks];
  float trackVolume[Looper::kTracks];
  int64_t trackLength[Looper::kTracks];
  int64_t trackPosition[Looper::kTracks];
  // Etapa 3, parte 2
  int32_t beatFrames;       // muestras ya sonadas del tiempo actual
  int32_t accentMask;
  int32_t clickMode;
  int32_t loopWaiting;      // esperando a que suene la guitarra
  int32_t startOnSound;
  int32_t tapState;         // TapCalibrator::State
  int32_t tapClicks;
  int32_t tapHits;
  int32_t tapFrames;
  int32_t tapSpread;
};

class EngineCore {
 public:
  static constexpr int32_t kMaxBlockFrames = 8192;
  // Trabajo de fondo del looper por bloque (sumar/borrar capas): a 48 kHz y
  // bloques de 256 muestras es ~60 veces el tiempo real y cuesta microsegundos.
  static constexpr int32_t kBackgroundBudget = 16384;

  // Fuera del hilo de audio (antes de arrancar el stream). Reserva memoria.
  void prepare(int32_t sampleRate);

  // Hilo de la interfaz: encola una orden. Devuelve false si la cola está llena.
  bool post(const Command& cmd) { return queue_.push(cmd); }

  // Hilo de audio. in: entrada entrelazada (inChannels canales); out: salida
  // entrelazada (outChannels canales). Sin reservas, sin bloqueos, sin E/S.
  void process(const float* in, int32_t inFrames, int32_t inChannels, float* out,
               int32_t outFrames, int32_t outChannels);

  CoreStatus status() const;
  int32_t sampleRate() const { return sampleRate_; }
  // Solo para tests (mismo hilo que process)
  const Looper& looper() const { return looper_; }
  int64_t outputPosition() const { return outPos_; }

 private:
  void apply(const Command& cmd);
  void publish();

  int32_t sampleRate_ = 48000;
  SpscQueue<Command, 128> queue_;
  Transport transport_;
  Metronome metronome_;
  LatencyMeter latency_;
  TapCalibrator tap_;
  Looper looper_;
  InputRing ring_;
  int64_t outPos_ = 0;    // índice absoluto de la próxima muestra de salida
  int64_t monRead_ = 0;   // próxima muestra de entrada que sonará en el monitor
  int32_t monChunk_ = 0;  // mayor bloque (de entrada o salida) del último segundo
  int32_t monChunkAge_ = 0;

  ClickMode clickMode_ = ClickMode::kAlways;
  bool clickGate_ = false;  // el clic que está sonando se oye
  float clickVolume_ = 0.8f;
  bool monitorEnabled_ = false;
  float monitorVolume_ = 1.0f;
  float inputGain_ = 1.0f;
  float peak_ = 0.0f;

  std::vector<float> inMono_;
  std::vector<float> outMono_;

  // Estado publicado
  std::atomic<bool> aPlaying_{false};
  std::atomic<int32_t> aBar_{0};
  std::atomic<int32_t> aBeat_{0};
  std::atomic<int32_t> aBeatsPerBar_{4};
  std::atomic<int32_t> aSamplesPerBeat_{0};
  std::atomic<double> aBpm_{100.0};
  std::atomic<int64_t> aFramePosition_{0};
  std::atomic<float> aPeak_{0.0f};
  std::atomic<int32_t> aLatencyState_{0};
  std::atomic<int32_t> aLatencyProgress_{0};
  std::atomic<int32_t> aLatencyFrames_{0};
  std::atomic<int32_t> aLoopState_{0};
  std::atomic<int32_t> aLoopMode_{0};
  std::atomic<int32_t> aLoopSyncBars_{4};
  std::atomic<int32_t> aLoopLayers_{0};
  std::atomic<int32_t> aLoopCanUndo_{0};
  std::atomic<int32_t> aLoopLatency_{0};
  std::atomic<int64_t> aLoopLength_{0};
  std::atomic<int64_t> aLoopPosition_{0};
  std::atomic<int64_t> aLoopRecorded_{0};
  std::atomic<int64_t> aLoopTarget_{0};
  std::atomic<int64_t> aLoopBarFrames_{0};
  std::atomic<int32_t> aLoopSelected_{0};
  std::atomic<int32_t> aLoopActive_{-1};
  std::atomic<int32_t> aLoopAutoAdvance_{0};
  std::atomic<int64_t> aLoopBaseLength_{0};
  std::atomic<int64_t> aLoopBasePosition_{0};
  std::atomic<int32_t> aTrackState_[Looper::kTracks] = {};
  std::atomic<int32_t> aTrackLayers_[Looper::kTracks] = {};
  std::atomic<int32_t> aTrackMuted_[Looper::kTracks] = {};
  std::atomic<float> aTrackVolume_[Looper::kTracks] = {};
  std::atomic<int64_t> aTrackLength_[Looper::kTracks] = {};
  std::atomic<int64_t> aTrackPosition_[Looper::kTracks] = {};
  std::atomic<int32_t> aBeatFrames_{0};
  std::atomic<int32_t> aAccentMask_{0};
  std::atomic<int32_t> aClickMode_{2};
  std::atomic<int32_t> aLoopWaiting_{0};
  std::atomic<int32_t> aStartOnSound_{0};
  std::atomic<int32_t> aTapState_{0};
  std::atomic<int32_t> aTapClicks_{0};
  std::atomic<int32_t> aTapHits_{0};
  std::atomic<int32_t> aTapFrames_{0};
  std::atomic<int32_t> aTapSpread_{0};
};

}  // namespace loopin
