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

void post(Command::Type type, double value = 0.0, int32_t arg = 0) {
  Command c;
  c.type = type;
  c.value = value;
  c.arg = arg;
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
void loopin_set_meter(int32_t beats, int32_t accent_mask) {
  post(Command::Type::kSetMeter, beats, accent_mask);
}
void loopin_set_click_mode(int32_t mode) { post(Command::Type::kSetClickMode, mode); }
void loopin_start_tap_calibration(void) { post(Command::Type::kStartTapCalibration); }
void loopin_cancel_tap_calibration(void) { post(Command::Type::kCancelTapCalibration); }
void loopin_nudge_latency(int32_t frames) { post(Command::Type::kNudgeLatency, frames); }
void loopin_set_start_on_sound(int32_t enabled) {
  post(Command::Type::kSetStartOnSound, enabled ? 1.0 : 0.0);
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

void loopin_loop_press(void) { post(Command::Type::kLoopPress); }
void loopin_loop_hold(void) { post(Command::Type::kLoopHold); }
void loopin_loop_double_tap(void) { post(Command::Type::kLoopDoubleTap); }
void loopin_loop_undo(void) { post(Command::Type::kLoopUndo); }
void loopin_loop_clear(void) { post(Command::Type::kLoopClear); }
void loopin_select_track(int32_t track) { post(Command::Type::kSelectTrack, 0.0, track); }
void loopin_select_next_track(void) { post(Command::Type::kSelectNextTrack); }
void loopin_set_track_volume(int32_t track, float volume) {
  post(Command::Type::kSetTrackVolume, volume, track);
}
void loopin_set_track_muted(int32_t track, int32_t muted) {
  post(Command::Type::kSetTrackMuted, muted ? 1.0 : 0.0, track);
}
void loopin_clear_track(int32_t track) { post(Command::Type::kClearTrack, 0.0, track); }
void loopin_set_auto_advance(int32_t enabled) {
  post(Command::Type::kSetAutoAdvance, enabled ? 1.0 : 0.0);
}
void loopin_set_loop_mode(int32_t mode) { post(Command::Type::kSetLoopMode, mode); }
void loopin_set_sync_bars(int32_t bars) { post(Command::Type::kSetSyncBars, bars); }
void loopin_set_loop_volume(float volume) { post(Command::Type::kSetLoopVolume, volume); }
void loopin_set_latency_compensation(int32_t frames) {
  post(Command::Type::kSetLatencyFrames, frames);
}

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
    out->input_frames_per_burst = input->getFramesPerBurst();
    out->input_buffer_frames = input->getBufferSizeInFrames();
    out->input_exclusive = input->getSharingMode() == oboe::SharingMode::Exclusive ? 1 : 0;
    out->input_low_latency =
        input->getPerformanceMode() == oboe::PerformanceMode::LowLatency ? 1 : 0;
    out->input_max_read = e.inputMaxRead();
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

  out->loop_state = c.loopState;
  out->loop_mode = c.loopMode;
  out->loop_sync_bars = c.loopSyncBars;
  out->loop_layers = c.loopLayers;
  out->loop_can_undo = c.loopCanUndo;
  out->loop_latency_frames = c.loopLatencyFrames;
  out->loop_length = c.loopLength;
  out->loop_position = c.loopPosition;
  out->loop_recorded = c.loopRecorded;
  out->loop_target = c.loopTarget;
  out->loop_bar_frames = c.loopBarFrames;

  out->loop_selected = c.loopSelected;
  out->loop_active = c.loopActive;
  out->loop_auto_advance = c.loopAutoAdvance;
  out->loop_base_length = c.loopBaseLength;
  out->loop_base_position = c.loopBasePosition;
  for (int i = 0; i < LOOPIN_TRACKS; ++i) {
    out->track_state[i] = c.trackState[i];
    out->track_layers[i] = c.trackLayers[i];
    out->track_muted[i] = c.trackMuted[i];
    out->track_volume[i] = c.trackVolume[i];
    out->track_length[i] = c.trackLength[i];
    out->track_position[i] = c.trackPosition[i];
  }
  out->beat_frames = c.beatFrames;
  out->accent_mask = c.accentMask;
  out->click_mode = c.clickMode;
  out->start_on_sound = c.startOnSound;
  out->loop_waiting = c.loopWaiting;
  out->tap_state = c.tapState;
  out->tap_clicks = c.tapClicks;
  out->tap_hits = c.tapHits;
  out->tap_frames = c.tapFrames;
  out->tap_spread = c.tapSpread;
}

}  // extern "C"
