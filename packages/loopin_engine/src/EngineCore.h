// Loopin — núcleo del motor, independiente de Oboe (se puede probar en el PC)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <atomic>
#include <cstdint>
#include <vector>

#include "Backing.h"
#include "Clip.h"
#include "Drums.h"
#include "LatencyMeter.h"
#include "Looper.h"
#include "Metronome.h"
#include "SpscQueue.h"
#include "TapCalibrator.h"
#include "Tone.h"
#include "Transport.h"
#include "Tuner.h"

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
    // Etapa 4a: batería
    kSetDrumsEnabled,
    kSetDrumStyle,     // value = estilo, arg = 1 si el tiempo es la corchea
    kSetDrumVolume,
    // Etapa 4b: audio importado
    kSetBackingEnabled,
    kSetBackingVolume,
    kPreviewPlay,      // value = muestra desde la que suena
    kPreviewStop,
    kSetPreviewClick,
    kSetPreviewMark,   // value = muestra del 1 (con decimales), arg = acentos
    kSetPreviewBeat,   // value = muestras por tiempo (con decimales), arg = tiempos
    // Etapa 5: directo y práctica
    kSetTrackReverse,  // arg = pista, value = 1/0
    kSetTrackHalf,     // arg = pista, value = 1/0
    kSetQuantize,      // silencio y efectos de pista en el siguiente 1
    kStop,             // parar según el modo (value = 1: al momento, siempre)
    kSetStopMode,      // StopMode
    kSetFadeSeconds,
    kSetTrainer,       // value = BPM que sube, arg = cada cuántos compases (0 = apagado)
    kSetTrainerTop,    // value = hasta qué tempo
    kSetTone,          // nota de referencia: value = Hz (0 = callar)
    // Etapa 6: sesiones
    kRestore,          // las pistas ya escritas suenan (ver loadSession)
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
  kUntilRecording = 3,  // con el metrónomo solo y en la cuenta; se calla al grabar
};

// Cómo para el botón de parar (y el doble toque)
enum class StopMode : int32_t {
  kNow = 0,   // al momento
  kBar = 1,   // en el siguiente 1
  kFade = 2,  // bajando poco a poco (fadeSeconds) y luego para
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
  // Batería
  int32_t drumsEnabled;
  int32_t drumStyle;
  int32_t drumsPlaying;     // está sonando (ya ha entrado en un 1)
  float drumVolume;
  // Audio importado: la canción que suena con el transporte
  int32_t backingEnabled;
  int32_t backingPlaying;
  int32_t backingId;        // id del clip cargado (0 = ninguno)
  int32_t backingSpb;       // tempo y compás a los que está estirado
  int32_t backingBpb;
  int64_t backingPosition;
  int64_t backingLength;
  float backingVolume;
  // y la vista previa
  int32_t previewId;
  int32_t previewPlaying;
  int32_t previewClick;
  int64_t previewPosition;
  int64_t previewLength;
  // Etapa 5
  int32_t trackReverse[Looper::kTracks];
  int32_t trackHalf[Looper::kTracks];
  int32_t trackPending[Looper::kTracks];  // bits: 1 silencio, 2 reverse, 4 media velocidad
  int32_t quantize;
  int32_t stopMode;
  int32_t stopping;         // 0 no, 1 esperando al 1, 2 bajando
  int32_t trainerBars;      // 0 = entrenador apagado
  double trainerStep;
  double trainerTop;
  double toneHz;            // nota de referencia que suena (0 = ninguna)
  // Etapa 6: sesiones
  int32_t loopSettled;      // las pistas se pueden leer (ver Looper::settled)
  int64_t loopRevision;     // cambia con cada orden que puede tocar las pistas
  int64_t trackOffset[Looper::kTracks];
};

// Una sesión guardada: lo que hace falta para que sus pistas vuelvan a sonar.
// Los datos pueden ser de otra frecuencia: se pasan a la del motor.
struct SessionSpec {
  double bpm = 100.0;
  int32_t beatsPerBar = 4;
  uint32_t accentMask = 0;
  int32_t sampleRate = 48000;  // a la que se grabaron los datos
  int64_t barFrames = 0;       // a esa frecuencia
  int64_t baseLen = 0;
  int64_t len[Looper::kTracks] = {};
  int64_t offset[Looper::kTracks] = {};
  int32_t layers[Looper::kTracks] = {};
  int32_t selected = 0;
};

class EngineCore {
 public:
  static constexpr int32_t kMaxBlockFrames = 8192;
  // Trabajo de fondo del looper por bloque (sumar/borrar capas): a 48 kHz y
  // bloques de 256 muestras es ~60 veces el tiempo real y cuesta microsegundos.
  static constexpr int32_t kBackgroundBudget = 16384;

  ~EngineCore() { collectClips(); }

  // Fuera del hilo de audio (antes de arrancar el stream). Reserva memoria
  // (loopSeconds por pista: menos en un núcleo que solo exporta).
  void prepare(int32_t sampleRate, int32_t loopSeconds = Looper::kMaxSeconds);

  // --- Sesiones (Etapa 6), desde el hilo de la interfaz ---
  static constexpr int32_t kSessionOk = 0;
  static constexpr int32_t kSessionNotReady = -1;  // grabando, borrando… o con loops
  static constexpr int32_t kSessionBad = -2;       // los datos no cuadran
  static constexpr int32_t kSessionTooLong = -3;   // no cabe en las pistas
  // Ya se han aplicado todas las órdenes enviadas y las pistas están quietas
  // (Looper::settled): se pueden leer sin que el audio las toque.
  bool sessionReady() const {
    return queue_.drained() && aSettled_.load(std::memory_order_acquire);
  }
  // Copia lo que suena de una pista (ver Looper::readTrack). −1 si no está
  // quieta (sessionReady).
  int64_t readTrack(int32_t track, float* out, int64_t max, uint64_t* hash) const {
    if (!sessionReady()) return -1;
    return looper_.readTrack(track, out, max, hash);
  }
  // Carga unas pistas (sin loops y con sessionReady): escribe los datos en
  // los buffers (pasándolos a la frecuencia del motor) y pide que suenen. Se
  // quedan paradas, con el tempo y el compás de la sesión. data[i] tiene
  // s.len[i] muestras (nullptr si la pista está vacía).
  int32_t loadSession(const SessionSpec& s, const float* const* data);

  // Para un núcleo que exporta (sin audio): la salida sin recortar a ±1, y
  // el kit de la batería de otro núcleo.
  void setClampOutput(bool on) { clampOutput_ = on; }
  void copyDrumKit(const EngineCore& from) { drums_.copySamples(from.drums_); }
  // Corta lo que aún suena (colas de la batería, la canción) con todo parado
  void silenceTails() {
    drums_.silence();
    backing_.halt();
  }
  // El tiempo de la batería es la corchea (para exportarla igual). Solo
  // cambia con una orden: se lee desde el hilo de la interfaz sin cola.
  bool drumsBeatIsEighth() const { return drumsEighth_.load(std::memory_order_relaxed); }

  // Fuera del hilo de audio y con el audio cerrado: muestra de un sonido de la
  // batería. Se aplica en el siguiente prepare().
  void setDrumSample(DrumSound sound, const float* data, int32_t frames, int32_t rate) {
    drums_.setSample(sound, data, frames, rate);
  }

  // Hilo de la interfaz: encola una orden. Devuelve false si la cola está llena.
  bool post(const Command& cmd) { return queue_.push(cmd); }

  // Afinador: lo último que ha entrado (el hilo de la interfaz lo analiza)
  TunerTap& tunerTap() { return tunerTap_; }
  const TunerTap& tunerTap() const { return tunerTap_; }

  // Audio importado: los trabajos de fondo dejan aquí los clips (ver SongJobs)
  Backing& backing() { return backing_; }
  ClipBin& clipBin() { return bin_; }
  // Hilo de la interfaz: borra los clips que ya no suenan.
  void collectClips() { bin_.collect(&retired_); }

  // Hilo de audio. in: entrada entrelazada (inChannels canales); out: salida
  // entrelazada (outChannels canales). Sin reservas, sin bloqueos, sin E/S.
  void process(const float* in, int32_t inFrames, int32_t inChannels, float* out,
               int32_t outFrames, int32_t outChannels);

  CoreStatus status() const;
  int32_t sampleRate() const { return sampleRate_; }
  // Solo para tests (mismo hilo que process)
  const Looper& looper() const { return looper_; }
  const Drums& drums() const { return drums_; }
  Drums& drumsForTest() { return drums_; }
  int64_t outputPosition() const { return outPos_; }

 private:
  void apply(const Command& cmd);
  void publish();
  // Parar: según el modo (al momento, en el 1, bajando) o al momento
  void requestStop(int64_t now, bool force);
  void stopNow(int64_t n);
  bool stopping() const { return stopAt_ != Looper::kNever || fade_ == Fade::kFading; }
  // La orden puede cambiar lo que hay en las pistas
  static bool touchesTracks(Command::Type t);
  // Entrenador: al empezar el último tiempo de cada N compases, sube el tempo
  // (se aplica en el 1 siguiente)
  void trainerBeat();

  enum class Fade { kNone, kFading, kTail };

  int32_t sampleRate_ = 48000;
  bool clampOutput_ = true;
  SpscQueue<Command, 128> queue_;
  // Sesión que se está cargando (la escribe la interfaz antes de kRestore)
  SessionSpec restore_;
  Looper::Restore restoreLoops_;
  int64_t revision_ = 0;
  Transport transport_;
  Metronome metronome_;
  LatencyMeter latency_;
  TapCalibrator tap_;
  Looper looper_;
  Drums drums_;
  Backing backing_;
  TunerTap tunerTap_;
  Tone tone_;
  ClipBin bin_;
  RetiredClips retired_;
  InputRing ring_;
  int64_t outPos_ = 0;    // índice absoluto de la próxima muestra de salida
  int64_t monRead_ = 0;   // próxima muestra de entrada que sonará en el monitor
  int32_t monChunk_ = 0;  // mayor bloque (de entrada o salida) del último segundo
  int32_t monChunkAge_ = 0;

  ClickMode clickMode_ = ClickMode::kAlways;
  bool clickGate_ = false;  // el clic que está sonando se oye
  bool wasPlaying_ = false; // el transporte corría en la muestra anterior
  float clickVolume_ = 0.8f;
  bool monitorEnabled_ = false;
  float monitorVolume_ = 1.0f;
  float inputGain_ = 1.0f;
  float peak_ = 0.0f;

  // Parar
  StopMode stopMode_ = StopMode::kNow;
  int64_t stopAt_ = Looper::kNever;  // parar en esta muestra (el siguiente 1)
  Fade fade_ = Fade::kNone;
  float fadeSeconds_ = 4.0f;
  float fadeGain_ = 1.0f;   // volumen de todo menos el monitor
  float fadeMul_ = 1.0f;    // por muestra: −60 dB en fadeSeconds_
  int32_t fadeHold_ = 0;    // tras el fundido, muestras en silencio
  // Entrenador de tempo
  int32_t trainerBars_ = 0;
  double trainerStep_ = 5.0;
  double trainerTop_ = 240.0;
  double userBpm_ = 100.0;     // el tempo que pidió el usuario
  bool trainerRaised_ = false; // el entrenador lo ha subido

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
  std::atomic<int32_t> aDrumsEnabled_{0};
  std::atomic<int32_t> aDrumStyle_{0};
  std::atomic<int32_t> aDrumsPlaying_{0};
  std::atomic<float> aDrumVolume_{0.7f};
  std::atomic<int32_t> aBackingEnabled_{0};
  std::atomic<int32_t> aBackingPlaying_{0};
  std::atomic<int32_t> aBackingId_{0};
  std::atomic<int32_t> aBackingSpb_{0};
  std::atomic<int32_t> aBackingBpb_{0};
  std::atomic<int64_t> aBackingPosition_{0};
  std::atomic<int64_t> aBackingLength_{0};
  std::atomic<float> aBackingVolume_{0.7f};
  std::atomic<int32_t> aPreviewId_{0};
  std::atomic<int32_t> aPreviewPlaying_{0};
  std::atomic<int32_t> aPreviewClick_{0};
  std::atomic<int64_t> aPreviewPosition_{0};
  std::atomic<int64_t> aPreviewLength_{0};
  std::atomic<int32_t> aTrackReverse_[Looper::kTracks] = {};
  std::atomic<int32_t> aTrackHalf_[Looper::kTracks] = {};
  std::atomic<int32_t> aTrackPending_[Looper::kTracks] = {};
  std::atomic<int32_t> aQuantize_{0};
  std::atomic<int32_t> aStopMode_{0};
  std::atomic<int32_t> aStopping_{0};
  std::atomic<int32_t> aTrainerBars_{0};
  std::atomic<double> aTrainerStep_{5.0};
  std::atomic<double> aTrainerTop_{240.0};
  std::atomic<double> aToneHz_{0.0};
  std::atomic<int64_t> aRevision_{0};
  std::atomic<bool> drumsEighth_{false};
  std::atomic<int64_t> aTrackOffset_[Looper::kTracks] = {};
  // Va el último (release): quien lo lea como «quieto» ve ya todo lo demás
  std::atomic<bool> aSettled_{true};
};

}  // namespace loopin
