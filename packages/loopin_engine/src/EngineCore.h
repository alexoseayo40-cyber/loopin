// Loopin — núcleo del motor, independiente de Oboe (se puede probar en el PC)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <atomic>
#include <cstdint>
#include <vector>

#include "LatencyMeter.h"
#include "Metronome.h"
#include "SpscQueue.h"
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
    kMeasureLatency,
  };
  Type type = Type::kPlay;
  double value = 0.0;
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
};

class EngineCore {
 public:
  static constexpr int32_t kMaxBlockFrames = 8192;

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

 private:
  void apply(const Command& cmd);
  void publish();

  int32_t sampleRate_ = 48000;
  SpscQueue<Command, 128> queue_;
  Transport transport_;
  Metronome metronome_;
  LatencyMeter latency_;

  bool clickEnabled_ = true;
  float clickVolume_ = 0.8f;
  bool monitorEnabled_ = false;
  float monitorVolume_ = 1.0f;
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
};

}  // namespace loopin
