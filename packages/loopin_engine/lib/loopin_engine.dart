// Loopin — puente Dart ↔ motor C++
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'loopin_engine_bindings_generated.dart';

/// API de audio que ha elegido Oboe.
enum AudioApi { unknown, openSles, aaudio }

/// Modo del micrófono (InputPreset de Android).
enum InputPreset {
  unprocessed(9, 'Sin procesar'),
  voicePerformance(10, 'Actuación en directo'),
  voiceRecognition(6, 'Reconocimiento de voz'),
  camcorder(5, 'Vídeo'),
  generic(1, 'Normal');

  const InputPreset(this.code, this.label);
  final int code;
  final String label;

  static InputPreset? fromCode(int code) {
    for (final p in values) {
      if (p.code == code) return p;
    }
    return null;
  }
}

/// Estado del test de latencia.
enum LatencyState { idle, running, done, failed }

/// Copia inmutable del estado del motor en un instante.
class EngineStatus {
  const EngineStatus({
    this.running = false,
    this.disconnected = false,
    this.sampleRate = 0,
    this.framesPerBurst = 0,
    this.bufferSizeFrames = 0,
    this.audioApi = AudioApi.unknown,
    this.exclusive = false,
    this.lowLatency = false,
    this.inputChannels = 0,
    this.outputChannels = 0,
    this.inputPreset,
    this.presetFallback = false,
    this.xrunCount = -1,
    this.outputLatencyMs = -1,
    this.inputLatencyMs = -1,
    this.playing = false,
    this.bar = 0,
    this.beat = 0,
    this.beatsPerBar = 4,
    this.samplesPerBeat = 0,
    this.bpm = 100,
    this.framePosition = 0,
    this.inputPeak = 0,
    this.latencyState = LatencyState.idle,
    this.latencyProgress = 0,
    this.latencyFrames = 0,
    this.latencyMs = 0,
  });

  final bool running;
  final bool disconnected;
  final int sampleRate;
  final int framesPerBurst;
  final int bufferSizeFrames;
  final AudioApi audioApi;
  final bool exclusive;
  final bool lowLatency;
  final int inputChannels;
  final int outputChannels;

  /// Modo del micrófono que está usando la entrada (null si no se sabe).
  final InputPreset? inputPreset;

  /// true si el modo pedido no funcionó y se usó «Reconocimiento de voz».
  final bool presetFallback;

  /// Cortes de la salida desde que arrancó el stream (-1 si no se sabe).
  final int xrunCount;

  /// Estimaciones de Oboe en ms (-1 si no se saben).
  final double outputLatencyMs;
  final double inputLatencyMs;

  final bool playing;
  final int bar;
  final int beat;
  final int beatsPerBar;
  final int samplesPerBeat;
  final double bpm;
  final int framePosition;
  final double inputPeak;

  final LatencyState latencyState;
  final int latencyProgress;
  final int latencyFrames;
  final double latencyMs;

  /// Segundos que lleva sonando el metrónomo.
  double get playSeconds => sampleRate > 0 ? framePosition / sampleRate : 0;

  /// Latencia de buffer del bloque de salida en ms.
  double get bufferMs => sampleRate > 0 ? 1000 * bufferSizeFrames / sampleRate : 0;
}

/// Motor de audio. Todas las llamadas son rápidas y no bloquean: se pueden
/// hacer desde el isolate principal.
class LoopinEngine {
  LoopinEngine._();
  static final LoopinEngine instance = LoopinEngine._();

  final LoopinEngineBindings _b = LoopinEngineBindings(_openLibrary());
  final Pointer<LoopinStatus> _status = calloc<LoopinStatus>();

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libloopin_engine.so');
    }
    throw UnsupportedError('Loopin solo funciona en Android de momento');
  }

  /// Abre el audio. Devuelve 0 si va bien o un código de error de Oboe.
  int start() => _b.loopin_start();
  void stop() => _b.loopin_stop();

  void play() => _b.loopin_play();
  void pause() => _b.loopin_pause();
  void setBpm(double bpm) => _b.loopin_set_bpm(bpm);
  void setBeatsPerBar(int beats) => _b.loopin_set_beats_per_bar(beats);
  void setClickEnabled(bool on) => _b.loopin_set_click_enabled(on ? 1 : 0);
  void setClickVolume(double v) => _b.loopin_set_click_volume(v);
  /// Se aplica la próxima vez que se abra el audio ([start]).
  void setInputPreset(InputPreset preset) => _b.loopin_set_input_preset(preset.code);

  /// Ganancia lineal de la entrada (1.0 = 0 dB).
  void setInputGain(double gain) => _b.loopin_set_input_gain(gain);

  void setMonitorEnabled(bool on) => _b.loopin_set_monitor_enabled(on ? 1 : 0);
  void setMonitorVolume(double v) => _b.loopin_set_monitor_volume(v);
  void measureLatency() => _b.loopin_measure_latency();

  EngineStatus status() {
    _b.loopin_get_status(_status);
    final s = _status.ref;
    return EngineStatus(
      running: s.running != 0,
      disconnected: s.disconnected != 0,
      sampleRate: s.sample_rate,
      framesPerBurst: s.frames_per_burst,
      bufferSizeFrames: s.buffer_size_frames,
      audioApi: switch (s.audio_api) {
        1 => AudioApi.openSles,
        2 => AudioApi.aaudio,
        _ => AudioApi.unknown,
      },
      exclusive: s.exclusive != 0,
      lowLatency: s.low_latency != 0,
      inputChannels: s.input_channels,
      outputChannels: s.output_channels,
      inputPreset: InputPreset.fromCode(s.input_preset),
      presetFallback: s.preset_fallback != 0,
      xrunCount: s.xrun_count,
      outputLatencyMs: s.output_latency_ms,
      inputLatencyMs: s.input_latency_ms,
      playing: s.playing != 0,
      bar: s.bar,
      beat: s.beat,
      beatsPerBar: s.beats_per_bar,
      samplesPerBeat: s.samples_per_beat,
      bpm: s.bpm,
      framePosition: s.frame_position,
      inputPeak: s.input_peak,
      latencyState: LatencyState.values[s.latency_state.clamp(0, 3)],
      latencyProgress: s.latency_progress,
      latencyFrames: s.latency_frames,
      latencyMs: s.latency_ms,
    );
  }

  /// Mensaje legible para un código de error de Oboe.
  static String describeError(int code) => switch (code) {
        -899 => 'El dispositivo de audio se ha desconectado',
        -889 => 'El dispositivo de audio no está disponible',
        -883 => 'Formato de audio no soportado',
        -887 => 'No hay memoria suficiente',
        -881 => 'El servicio de audio de Android no responde',
        _ => 'Error de audio ($code)',
      };
}
