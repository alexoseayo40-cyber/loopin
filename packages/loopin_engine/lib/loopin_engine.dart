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

/// Un dispositivo de audio de Android (entrada o salida).
class AudioDevice {
  const AudioDevice({required this.id, required this.type, this.name = '', this.address = ''});

  factory AudioDevice.fromMap(Map<Object?, Object?> m) => AudioDevice(
        id: (m['id'] as num).toInt(),
        type: (m['type'] as num).toInt(),
        name: (m['name'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
      );

  final int id;
  final int type; // AudioDeviceInfo.TYPE_*
  final String name;
  final String address;

  bool get isBuiltinMic => type == 15;

  /// Nombre para mostrar, en español.
  String get label {
    final extra = address.isNotEmpty ? ' ($address)' : '';
    return switch (type) {
      15 => 'Micrófono del móvil$extra',
      2 => 'Altavoz del móvil',
      1 => 'Auricular de llamada',
      3 => 'Auriculares con cable (micro)',
      4 => 'Auriculares con cable',
      5 || 6 => 'Entrada de línea',
      7 || 26 => 'Bluetooth: $name (con retardo)',
      8 || 27 => 'Bluetooth: $name (con retardo)',
      11 || 12 => 'USB: $name',
      22 => 'Cascos USB: $name',
      _ => name.isNotEmpty ? name : 'Dispositivo $type',
    };
  }
}

/// Estado del test de latencia.
enum LatencyState { idle, running, done, failed }

/// Estado del looper (mismo orden que LOOPIN_LOOP_*).
enum LoopState {
  /// Sin loop.
  empty,

  /// Cuenta de entrada o esperando al siguiente compás para grabar.
  armed,

  /// Grabando el primer loop.
  recording,
  playing,
  overdubbing,

  /// Hay loop pero está todo parado.
  stopped;

  bool get hasLoop => this == playing || this == overdubbing || this == stopped;
}

/// Modo de grabación del primer loop (mismo orden que LOOPIN_MODE_*).
enum LoopMode {
  /// Cuenta de entrada y se cierra solo tras N compases.
  sync('Sincronizado'),

  /// Se cierra al pulsar, en el compás más cercano.
  manual('Manual');

  const LoopMode(this.label);
  final String label;
}

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
    this.inputDeviceId = 0,
    this.outputDeviceId = 0,
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
    this.inputFramesPerBurst = 0,
    this.inputBufferFrames = 0,
    this.inputExclusive = false,
    this.inputLowLatency = false,
    this.inputMaxRead = 0,
    this.loopState = LoopState.empty,
    this.loopMode = LoopMode.sync,
    this.loopSyncBars = 4,
    this.loopLayers = 0,
    this.loopCanUndo = false,
    this.loopLatencyFrames = 0,
    this.loopLength = 0,
    this.loopPosition = 0,
    this.loopRecorded = 0,
    this.loopTarget = 0,
    this.loopBarFrames = 0,
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

  /// Ids de Android de los dispositivos en uso (0 si no se sabe).
  final int inputDeviceId;
  final int outputDeviceId;

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

  // Entrada (diagnóstico)
  final int inputFramesPerBurst;
  final int inputBufferFrames;
  final bool inputExclusive;
  final bool inputLowLatency;

  /// Máximo de muestras de entrada leídas en un callback (últimos ~2 s).
  final int inputMaxRead;

  // Looper
  final LoopState loopState;
  final LoopMode loopMode;
  final int loopSyncBars;

  /// Capas que suenan (el loop base cuenta como 1).
  final int loopLayers;
  final bool loopCanUndo;

  /// Compensación de latencia que está usando la grabación (muestras).
  final int loopLatencyFrames;

  /// Longitud del loop en muestras (0 = sin loop).
  final int loopLength;
  final int loopPosition;

  /// Armado: negativo (muestras que faltan para grabar). Grabando: grabadas.
  final int loopRecorded;

  /// Grabando: longitud a la que se cerrará (0 = aún abierta).
  final int loopTarget;
  final int loopBarFrames;

  /// Compases del loop (o grabados hasta ahora).
  double get loopBars {
    if (loopBarFrames <= 0) return 0;
    final frames = loopState.hasLoop ? loopLength : loopRecorded;
    return frames / loopBarFrames;
  }

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

  /// Dispositivo de entrada (id de Android; 0 = el que elija Android).
  /// Se aplica la próxima vez que se abra el audio.
  void setInputDevice(int id) => _b.loopin_set_input_device(id);

  /// Ganancia lineal de la entrada (1.0 = 0 dB).
  void setInputGain(double gain) => _b.loopin_set_input_gain(gain);

  void setMonitorEnabled(bool on) => _b.loopin_set_monitor_enabled(on ? 1 : 0);
  void setMonitorVolume(double v) => _b.loopin_set_monitor_volume(v);
  void measureLatency() => _b.loopin_measure_latency();

  // Looper
  void loopPress() => _b.loopin_loop_press();
  void loopHold() => _b.loopin_loop_hold();
  void loopDoubleTap() => _b.loopin_loop_double_tap();
  void loopUndo() => _b.loopin_loop_undo();
  void loopClear() => _b.loopin_loop_clear();
  void setLoopMode(LoopMode mode) => _b.loopin_set_loop_mode(mode.index);
  void setSyncBars(int bars) => _b.loopin_set_sync_bars(bars);
  void setLoopVolume(double v) => _b.loopin_set_loop_volume(v);

  /// Latencia de ida y vuelta (muestras) que se compensa al grabar.
  void setLatencyCompensation(int frames) => _b.loopin_set_latency_compensation(frames);

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
      inputDeviceId: s.input_device_id,
      outputDeviceId: s.output_device_id,
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
      inputFramesPerBurst: s.input_frames_per_burst,
      inputBufferFrames: s.input_buffer_frames,
      inputExclusive: s.input_exclusive != 0,
      inputLowLatency: s.input_low_latency != 0,
      inputMaxRead: s.input_max_read,
      loopState: LoopState.values[s.loop_state.clamp(0, LoopState.values.length - 1)],
      loopMode: LoopMode.values[s.loop_mode.clamp(0, LoopMode.values.length - 1)],
      loopSyncBars: s.loop_sync_bars,
      loopLayers: s.loop_layers,
      loopCanUndo: s.loop_can_undo != 0,
      loopLatencyFrames: s.loop_latency_frames,
      loopLength: s.loop_length,
      loopPosition: s.loop_position,
      loopRecorded: s.loop_recorded,
      loopTarget: s.loop_target,
      loopBarFrames: s.loop_bar_frames,
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
