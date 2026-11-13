// Loopin — puente Dart ↔ motor C++
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'loopin_engine_bindings_generated.dart';

/// API de audio que ha elegido Oboe.
enum AudioApi { unknown, openSles, aaudio }

/// Modo del micrófono (InputPreset de Android). Los nombres para mostrar
/// están en los textos de la app.
enum InputPreset {
  unprocessed(9),
  voicePerformance(10),
  voiceRecognition(6),
  camcorder(5),
  generic(1);

  const InputPreset(this.code);
  final int code;

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

  /// El altavoz del móvil (o el auricular de llamada).
  bool get isBuiltinSpeaker => type == 2 || type == 1;
}

/// Estado del test de latencia.
enum LatencyState { idle, running, done, failed }

/// Estado del looper (mismo orden que LOOPIN_LOOP_*).
enum LoopState {
  /// Sin loop.
  empty,

  /// Cuenta de entrada o esperando al siguiente compás para grabar.
  armed,

  /// Grabando una pista vacía.
  recording,
  playing,
  overdubbing,

  /// Hay loop pero está todo parado.
  stopped;

  bool get hasLoop => this == playing || this == overdubbing || this == stopped;
}

/// Modo de grabación (mismo orden que LOOPIN_MODE_*).
enum LoopMode {
  /// Graba N compases y se cierra solo.
  sync,

  /// Se cierra al pulsar.
  manual,

  /// Sin metrónomo: el primer loop dura lo que se toque y marca el tempo.
  free,
}

/// Cuándo suena el clic del metrónomo (mismo orden que LOOPIN_CLICK_*).
enum ClickMode {
  /// Nunca: el metrónomo solo se ve.
  silent,

  /// Solo en la cuenta de entrada.
  countIn,

  /// Siempre.
  always,
}

/// Número de pistas del looper.
const int kTrackCount = 4;

/// Estado de una pista.
/// Sonidos del kit de batería (mismo orden que LOOPIN_DRUM_*).
enum DrumSound { kick, snare, snareSoft, crossStick, hat, hatSoft, hatOpen, ride, crash, sticks }

/// Estilos de batería (mismo orden que LOOPIN_STYLE_*). [basic] sale de los
/// acentos del compás; los demás son de un compás concreto.
enum DrumStyle { basic, rock, pop, shuffle, funk, ballad, reggae, waltz, sixEight, slowBlues }

/// Estado de un trabajo en segundo plano del audio importado (mismo orden
/// que LOOPIN_JOB_*).
enum JobState { idle, running, done, failed }

/// Por qué no se ha podido abrir o preparar una canción (mismo orden que
/// LOOPIN_SONG_ERR_*, con [none] = 0).
enum SongError {
  none,

  /// No se puede abrir o no es WAV, MP3 ni FLAC.
  open,

  /// Más de [kSongMaxSeconds] (a ese tempo).
  tooLong,
  memory,

  /// No suena nada.
  empty,

  /// A más del doble o menos de la mitad de su tempo.
  tempo,
}

/// Duración máxima de una canción (o de lo que dure estirada), en segundos.
const int kSongMaxSeconds = 600;

class TrackStatus {
  const TrackStatus({
    this.state = LoopState.empty,
    this.layers = 0,
    this.muted = false,
    this.volume = 1,
    this.length = 0,
    this.position = 0,
  });

  final LoopState state;

  /// Capas que suenan (la primera grabación cuenta como 1).
  final int layers;
  final bool muted;
  final double volume;

  /// Longitud en muestras: 1, 2 o 4 veces la base (0 = vacía).
  final int length;
  final int position;

  bool get hasLoop => length > 0;

  /// Por dónde va, de 0 a 1.
  double get progress => length > 0 ? position / length : 0;
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
    this.selectedTrack = 0,
    this.activeTrack = -1,
    this.autoAdvance = false,
    this.baseLength = 0,
    this.basePosition = 0,
    this.tracks = const [TrackStatus(), TrackStatus(), TrackStatus(), TrackStatus()],
    this.beatFrames = 0,
    this.accentMask = 0,
    this.clickMode = ClickMode.always,
    this.startOnSound = false,
    this.loopWaiting = false,
    this.tapState = LatencyState.idle,
    this.tapClicks = 0,
    this.tapHits = 0,
    this.tapFrames = 0,
    this.tapSpread = 0,
    this.cpuLoad = 0,
    this.cpuLoadPeak = 0,
    this.cpuLoadMax = 0,
    this.drumsEnabled = false,
    this.drumStyle = DrumStyle.basic,
    this.drumsPlaying = false,
    this.drumVolume = 0.7,
    this.songOpenId = 0,
    this.songOpenState = JobState.idle,
    this.songOpenProgress = 0,
    this.songOpenError = SongError.none,
    this.songOpenFrames = 0,
    this.songBpmGuess = 0,
    this.songFirstAttack = -1,
    this.songPrepId = 0,
    this.songPrepState = JobState.idle,
    this.songPrepProgress = 0,
    this.songPrepError = SongError.none,
    this.backingEnabled = false,
    this.backingPlaying = false,
    this.backingId = 0,
    this.backingSamplesPerBeat = 0,
    this.backingBeatsPerBar = 0,
    this.backingPosition = 0,
    this.backingLength = 0,
    this.backingVolume = 0.7,
    this.previewId = 0,
    this.previewPlaying = false,
    this.previewClick = false,
    this.previewPosition = 0,
    this.previewLength = 0,
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

  /// Pista que usará el siguiente toque del botón principal (0..3).
  final int selectedTrack;

  /// Pista en la que se está grabando o a punto (-1 si ninguna).
  final int activeTrack;

  /// Tras grabar una pista se elige sola la siguiente vacía.
  final bool autoAdvance;

  /// Duración base en muestras: la de la primera pista grabada (0 = sin loops).
  final int baseLength;
  final int basePosition;

  /// Las [kTrackCount] pistas.
  final List<TrackStatus> tracks;

  /// Muestras ya sonadas del tiempo actual (para dibujar el pulso).
  final int beatFrames;

  /// Tiempos con acento medio (bit k = tiempo k; el 0 siempre es fuerte).
  final int accentMask;
  final ClickMode clickMode;

  /// La primera pista espera a que suene la guitarra.
  final bool startOnSound;

  /// Esperando a que suene la guitarra para empezar la primera pista.
  final bool loopWaiting;

  /// Calibración tocando al clic.
  final LatencyState tapState;

  /// Clics que ya han sonado (de [tapTotalClicks]).
  final int tapClicks;

  /// Golpes que cuentan (de [tapCountedClicks]).
  final int tapHits;
  final int tapFrames;

  /// Dispersión de los golpes en muestras.
  final int tapSpread;

  /// Carga del callback de audio: fracción del tiempo disponible (1.0 =
  /// 100 %; por encima, el audio se corta). Media y pico del último segundo y
  /// mayor pico desde que se abrió el audio.
  final double cpuLoad;
  final double cpuLoadPeak;
  final double cpuLoadMax;

  /// Batería: encendida, estilo pedido, si ya ha entrado y suena (entra en
  /// un primer tiempo) y su volumen.
  final bool drumsEnabled;
  final DrumStyle drumStyle;
  final bool drumsPlaying;
  final double drumVolume;

  /// Audio importado: abrir una canción para prepararla (vista previa). El
  /// progreso va de 0 a 1.
  final int songOpenId;
  final JobState songOpenState;
  final double songOpenProgress;
  final SongError songOpenError;

  /// Duración de la abierta, en muestras (a [sampleRate]).
  final int songOpenFrames;

  /// Tempo sugerido (0 = ni idea).
  final double songBpmGuess;

  /// Primer golpe claro de la abierta (muestra; -1 = ninguno).
  final int songFirstAttack;

  /// Audio importado: preparar la canción para que suene (estirarla).
  final int songPrepId;
  final JobState songPrepState;
  final double songPrepProgress;
  final SongError songPrepError;

  /// La canción que suena con el transporte: encendida, si ya ha entrado
  /// (en un 1) y suena, cuál está cargada (0 = ninguna) y a qué tempo y
  /// compás está estirada.
  final bool backingEnabled;
  final bool backingPlaying;
  final int backingId;
  final int backingSamplesPerBeat;
  final int backingBeatsPerBar;
  final int backingPosition;
  final int backingLength;
  final double backingVolume;

  /// Vista previa (la canción abierta, sin estirar).
  final int previewId;
  final bool previewPlaying;
  final bool previewClick;
  final int previewPosition;
  final int previewLength;

  /// La canción cargada está estirada al tempo y compás de ahora.
  bool get backingFits =>
      backingId != 0 &&
      backingSamplesPerBeat == samplesPerBeat &&
      backingBeatsPerBar == beatsPerBar;

  static const tapCountInClicks = 4;
  static const tapCountedClicks = 12;
  static const tapTotalClicks = tapCountInClicks + tapCountedClicks;

  /// Hay algún loop grabado.
  bool get hasLoops => baseLength > 0;

  /// Compases de la base.
  int get baseBars => loopBarFrames > 0 ? (baseLength / loopBarFrames).round() : 0;

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

  /// Compás: tiempos y acentos medios (bit k = tiempo k).
  void setMeter(int beats, int accentMask) => _b.loopin_set_meter(beats, accentMask);
  void setClickEnabled(bool on) => _b.loopin_set_click_enabled(on ? 1 : 0);
  void setClickMode(ClickMode mode) => _b.loopin_set_click_mode(mode.index);
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

  /// Calibración tocando al clic (para cascos).
  void startTapCalibration() => _b.loopin_start_tap_calibration();
  void cancelTapCalibration() => _b.loopin_cancel_tap_calibration();

  // Looper
  void loopPress() => _b.loopin_loop_press();
  void loopHold() => _b.loopin_loop_hold();
  void loopDoubleTap() => _b.loopin_loop_double_tap();
  void loopUndo() => _b.loopin_loop_undo();
  void loopClear() => _b.loopin_loop_clear();
  void selectTrack(int track) => _b.loopin_select_track(track);
  void selectNextTrack() => _b.loopin_select_next_track();
  void setTrackVolume(int track, double v) => _b.loopin_set_track_volume(track, v);
  void setTrackMuted(int track, bool muted) => _b.loopin_set_track_muted(track, muted ? 1 : 0);
  void clearTrack(int track) => _b.loopin_clear_track(track);
  void setAutoAdvance(bool on) => _b.loopin_set_auto_advance(on ? 1 : 0);
  void setLoopMode(LoopMode mode) => _b.loopin_set_loop_mode(mode.index);
  void setSyncBars(int bars) => _b.loopin_set_sync_bars(bars);
  void setLoopVolume(double v) => _b.loopin_set_loop_volume(v);

  /// Volumen de lo que ya suena mientras se graba (1 = normal, 0 = silencio).
  void setRecordDuck(double gain) => _b.loopin_set_record_duck(gain);

  /// Latencia de ida y vuelta (muestras) que se compensa al grabar.
  void setLatencyCompensation(int frames) => _b.loopin_set_latency_compensation(frames);

  /// Ajuste a mano: nueva compensación; lo ya grabado se mueve lo mismo.
  void nudgeLatency(int frames) => _b.loopin_nudge_latency(frames);

  /// La primera pista espera a que suene la guitarra.
  void setStartOnSound(bool on) => _b.loopin_set_start_on_sound(on ? 1 : 0);

  // Batería
  /// Muestra de un sonido (mono). Se aplica la próxima vez que se abra el
  /// audio ([start]): hay que darlas antes.
  void setDrumSample(DrumSound sound, Float32List data, int sampleRate) {
    if (data.isEmpty) return;
    final p = calloc<Float>(data.length);
    try {
      p.asTypedList(data.length).setAll(0, data);
      _b.loopin_set_drum_sample(sound.index, p, data.length, sampleRate);
    } finally {
      calloc.free(p);
    }
  }

  void setDrumsEnabled(bool on) => _b.loopin_set_drums_enabled(on ? 1 : 0);

  /// [beatIsEighth]: el tiempo es la corchea (compases de 8).
  void setDrumStyle(DrumStyle style, {required bool beatIsEighth}) =>
      _b.loopin_set_drum_style(style.index, beatIsEighth ? 1 : 0);
  void setDrumVolume(double v) => _b.loopin_set_drum_volume(v);

  // Audio importado
  /// Abre una canción para prepararla (en segundo plano: ver
  /// [EngineStatus.songOpenState]).
  void songOpen(String path, int id) {
    final p = path.toNativeUtf8();
    try {
      _b.loopin_song_open(p.cast(), id);
    } finally {
      calloc.free(p);
    }
  }

  void songClose() => _b.loopin_song_close();

  /// Picos (0..1) de la canción abierta entre [start] y [end] (muestras).
  Float32List songPeaks(int start, int end, int bins) {
    if (bins <= 0) return Float32List(0);
    final p = calloc<Float>(bins);
    try {
      final n = _b.loopin_song_peaks(start, end, bins, p);
      return Float32List.fromList(p.asTypedList(bins).sublist(0, n));
    } finally {
      calloc.free(p);
    }
  }

  /// El ataque más claro cerca de [center] (± [radius] muestras).
  int songFindAttack(int center, int radius) => _b.loopin_song_find_attack(center, radius);

  void previewPlay(int frame) => _b.loopin_preview_play(frame);
  void previewStop() => _b.loopin_preview_stop();
  void setPreviewClick(bool on) => _b.loopin_preview_set_click(on ? 1 : 0);

  /// Rejilla del clic de la vista previa: el 1 en [mark] y un tiempo cada
  /// [beat] muestras (con decimales).
  void setPreviewGrid(double mark, double beat, int beatsPerBar, int accentMask) =>
      _b.loopin_preview_set_grid(mark, beat, beatsPerBar, accentMask);

  /// Estira la canción para que un tiempo dure [samplesPerBeat] muestras, con
  /// el 1 ([markSeconds] en el archivo) en un inicio de compás.
  void backingPrepare({
    required String path,
    required double songBpm,
    required double markSeconds,
    required int samplesPerBeat,
    required int beatsPerBar,
    required int id,
  }) {
    final p = path.toNativeUtf8();
    try {
      _b.loopin_backing_prepare(p.cast(), songBpm, markSeconds, samplesPerBeat, beatsPerBar, id);
    } finally {
      calloc.free(p);
    }
  }

  /// Si se acaba de preparar igual (las 2 últimas se guardan), suena enseguida.
  void backingCancel() => _b.loopin_backing_cancel();
  void backingUnload() => _b.loopin_backing_unload();
  void setBackingEnabled(bool on) => _b.loopin_set_backing_enabled(on ? 1 : 0);
  void setBackingVolume(double v) => _b.loopin_set_backing_volume(v);

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
      selectedTrack: s.loop_selected.clamp(0, kTrackCount - 1),
      activeTrack: s.loop_active,
      autoAdvance: s.loop_auto_advance != 0,
      baseLength: s.loop_base_length,
      basePosition: s.loop_base_position,
      tracks: [
        for (var i = 0; i < kTrackCount; i++)
          TrackStatus(
            state: LoopState.values[s.track_state[i].clamp(0, LoopState.values.length - 1)],
            layers: s.track_layers[i],
            muted: s.track_muted[i] != 0,
            volume: s.track_volume[i],
            length: s.track_length[i],
            position: s.track_position[i],
          ),
      ],
      beatFrames: s.beat_frames,
      accentMask: s.accent_mask,
      clickMode: ClickMode.values[s.click_mode.clamp(0, ClickMode.values.length - 1)],
      startOnSound: s.start_on_sound != 0,
      loopWaiting: s.loop_waiting != 0,
      tapState: LatencyState.values[s.tap_state.clamp(0, 3)],
      tapClicks: s.tap_clicks,
      tapHits: s.tap_hits,
      tapFrames: s.tap_frames,
      tapSpread: s.tap_spread,
      cpuLoad: s.cpu_load_avg,
      cpuLoadPeak: s.cpu_load_peak,
      cpuLoadMax: s.cpu_load_max,
      drumsEnabled: s.drums_enabled != 0,
      drumStyle: DrumStyle.values[s.drum_style.clamp(0, DrumStyle.values.length - 1)],
      drumsPlaying: s.drums_playing != 0,
      drumVolume: s.drum_volume,
      songOpenId: s.song_open_id,
      songOpenState: JobState.values[s.song_open_state.clamp(0, 3)],
      songOpenProgress: s.song_open_progress / 1000,
      songOpenError: SongError.values[s.song_open_error.clamp(0, SongError.values.length - 1)],
      songOpenFrames: s.song_open_frames,
      songBpmGuess: s.song_bpm_guess,
      songFirstAttack: s.song_first_attack,
      songPrepId: s.song_prep_id,
      songPrepState: JobState.values[s.song_prep_state.clamp(0, 3)],
      songPrepProgress: s.song_prep_progress / 1000,
      songPrepError: SongError.values[s.song_prep_error.clamp(0, SongError.values.length - 1)],
      backingEnabled: s.backing_enabled != 0,
      backingPlaying: s.backing_playing != 0,
      backingId: s.backing_id,
      backingSamplesPerBeat: s.backing_samples_per_beat,
      backingBeatsPerBar: s.backing_beats_per_bar,
      backingPosition: s.backing_position,
      backingLength: s.backing_length,
      backingVolume: s.backing_volume,
      previewId: s.preview_id,
      previewPlaying: s.preview_playing != 0,
      previewClick: s.preview_click != 0,
      previewPosition: s.preview_position,
      previewLength: s.preview_length,
    );
  }
}
