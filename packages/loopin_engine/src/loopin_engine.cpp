// Loopin — implementación de la API en C
// SPDX-License-Identifier: GPL-3.0-or-later
#include "loopin_engine.h"

#include <memory>

#include "AudioEngine.h"

using loopin::AudioEngine;
using loopin::Command;

namespace {

AudioEngine& engine() {
  static AudioEngine* instance = new AudioEngine();  // vive toda la app
  return *instance;
}

void post(Command::Type type, double value = 0.0) {
  Command c;
  c.type = type;
  c.value = value;
  engine().core().post(c);
}

}  // namespace

extern "C" {

int32_t loopin_start(void) { return static_cast<int32_t>(engine().openAudio()); }

void loopin_stop(void) { engine().closeAudio(); }

void loopin_play(void) { post(Command::Type::kPlay); }
void loopin_pause(void) { post(Command::Type::kPause); }
void loopin_set_bpm(double bpm) { post(Command::Type::kSetBpm, bpm); }
void loopin_set_beats_per_bar(int32_t beats) { post(Command::Type::kSetBeatsPerBar, beats); }
void loopin_set_click_enabled(int32_t enabled) {
  post(Command::Type::kSetClickEnabled, enabled ? 1.0 : 0.0);
}
void loopin_set_click_volume(float volume) { post(Command::Type::kSetClickVolume, volume); }
void loopin_set_monitor_enabled(int32_t enabled) {
  post(Command::Type::kSetMonitorEnabled, enabled ? 1.0 : 0.0);
}
void loopin_set_monitor_volume(float volume) { post(Command::Type::kSetMonitorVolume, volume); }
void loopin_set_input_preset(int32_t preset) { engine().setInputPreset(preset); }
void loopin_set_input_device(int32_t device_id) { engine().setInputDevice(device_id); }
void loopin_set_input_gain(float gain) { post(Command::Type::kSetInputGain, gain); }
void loopin_measure_latency(void) { post(Command::Type::kMeasureLatency); }

void loopin_get_status(LoopinStatus* out) {
  if (out == nullptr) return;
  *out = LoopinStatus{};
  AudioEngine& e = engine();
  const loopin::CoreStatus c = e.core().status();

  out->running = e.running() ? 1 : 0;
  out->disconnected = e.disconnected() ? 1 : 0;
  out->sample_rate = e.core().sampleRate();
  out->xrun_count = -1;
  out->output_latency_ms = -1.0;
  out->input_latency_ms = -1.0;

  auto output = e.output();
  auto input = e.input();
  if (output && out->running) {
    out->frames_per_burst = output->getFramesPerBurst();
    out->buffer_size_frames = output->getBufferSizeInFrames();
    out->audio_api = output->getAudioApi() == oboe::AudioApi::AAudio ? LOOPIN_API_AAUDIO
                                                                     : LOOPIN_API_OPENSLES;
    out->exclusive = output->getSharingMode() == oboe::SharingMode::Exclusive ? 1 : 0;
    out->low_latency =
        output->getPerformanceMode() == oboe::PerformanceMode::LowLatency ? 1 : 0;
    out->output_channels = output->getChannelCount();
    out->output_device_id = output->getDeviceId();
    auto xruns = output->getXRunCount();
    if (xruns) out->xrun_count = xruns.value();
    auto lat = output->calculateLatencyMillis();
    if (lat) out->output_latency_ms = lat.value();
  }
  if (input && out->running) {
    out->input_channels = input->getChannelCount();
    out->input_preset = static_cast<int32_t>(input->getInputPreset());
    out->input_device_id = input->getDeviceId();
    out->preset_fallback = e.presetFallback() ? 1 : 0;
    auto lat = input->calculateLatencyMillis();
    if (lat) out->input_latency_ms = lat.value();
  }

  out->playing = c.playing ? 1 : 0;
  out->bar = c.bar;
  out->beat = c.beat;
  out->beats_per_bar = c.beatsPerBar;
  out->samples_per_beat = c.samplesPerBeat;
  out->bpm = c.bpm;
  out->frame_position = c.framePosition;
  out->input_peak = c.inputPeak;
  out->latency_state = c.latencyState;
  out->latency_progress = c.latencyProgress;
  out->latency_frames = c.latencyFrames;
  out->latency_ms = out->sample_rate > 0 ? 1000.0 * c.latencyFrames / out->sample_rate : 0.0;
}

}  // extern "C"
