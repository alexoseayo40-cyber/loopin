// Loopin — estado de la app y órdenes al motor
// SPDX-License-Identifier: GPL-3.0-or-later
//
// El controlador está repartido en piezas:
//   engine_controller.dart  audio, metrónomo, looper, pistas, entrada y
//                           apariencia (este archivo)
//   meter.dart              compases
//   latency_routes.dart     latencia guardada por ruta
//   pedal_keys.dart         controles externos (teclas)
//   prefs.dart              ajustes guardados
//   status_change.dart      qué cambios del motor se redibujan
//   report.dart             «Copiar resultados»
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../l10n/strings.dart';
import '../ui/theme.dart';
import 'latency_routes.dart';
import 'meter.dart';
import 'pedal_keys.dart';
import 'prefs.dart';
import 'status_change.dart';

export 'latency_routes.dart' show LatencySource;
export 'meter.dart';
export 'pedal_keys.dart' show LearnedKey, PedalAction;
export 'report.dart';

class EngineController extends ChangeNotifier {
  EngineController({LoopinEngine? engine}) : _engine = engine ?? LoopinEngine.instance {
    _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
    _routes = LatencyRoutes(apply: _engine.setLatencyCompensation, prefs: _prefs);
    _keys = PedalKeys(onAction: _onPedalKey, onChanged: notifyListeners, prefs: _prefs);
    _prefsLoaded = _loadPrefs();
  }

  final LoopinEngine _engine;
  final Prefs _prefs = const Prefs();
  static const _channel = MethodChannel('loopin/permissions');
  late final AppLifecycleListener _lifecycle;
  late final LatencyRoutes _routes;
  late final PedalKeys _keys;
  late final Future<void> _prefsLoaded;
  Timer? _poll;

  /// Avisa en cada consulta al motor (30 veces por segundo). Solo lo escuchan
  /// las piezas que se mueven (anillos, pulsador, nivel de entrada…). El
  /// controlador en sí solo avisa cuando cambia algo que se ve en el resto de
  /// la pantalla (ver [layoutChanged]).
  Listenable get live => _live;
  final _Pulse _live = _Pulse();

  // Lo que el usuario ha pedido (se reaplica si el audio se reinicia)
  double bpm = 92;
  TimeSignature timeSignature = kTimeSignatures.first;
  int get beatsPerBar => timeSignature.beats;
  ClickMode clickMode = ClickMode.always;
  double clickVolume = 0.8;

  /// La primera pista espera a que suene la guitarra y empieza ahí.
  bool startOnSound = false;
  InputPreset inputPreset = InputPreset.unprocessed;
  bool _presetChosenByUser = false;

  /// Entrada elegida (id de Android). -1 = aún sin elegir; 0 = la de Android.
  int inputDeviceId = -1;
  List<AudioDevice> inputDevices = const [];
  List<AudioDevice> outputDevices = const [];
  double inputGainDb = 0;
  bool monitorEnabled = false;
  double monitorVolume = 1.0;

  // Looper
  LoopMode loopMode = LoopMode.sync;
  int syncBars = 4;
  double loopVolume = 1.0;

  /// Tras grabar una pista, la selección pasa sola a la siguiente vacía.
  bool autoAdvance = true;

  /// Volumen de cada pista (lo que marca el deslizador).
  final List<double> trackVolumes = List.filled(kTrackCount, 1.0);

  /// Tema (claro, oscuro o el del sistema) y color del chasis.
  final ValueNotifier<Appearance> appearance = ValueNotifier(const Appearance());

  bool _wantRunning = false;
  bool _wantPlaying = false;
  bool _restarting = false;
  String? error;

  EngineStatus status = const EngineStatus();

  /// Datos del móvil (modelo, si admite micrófono sin procesar…)
  Map<String, Object?> deviceInfo = const {};

  /// El móvil dice si admite el micrófono «sin procesar» (null = no se sabe).
  bool? get unprocessedSupported => switch (deviceInfo['unprocessed']) {
    final bool v => v,
    _ => null,
  };

  /// El modo del micrófono que conviene en este móvil.
  InputPreset get recommendedPreset =>
      unprocessedSupported == false ? InputPreset.voiceRecognition : InputPreset.unprocessed;

  // Prueba de estabilidad: cortes desde que arrancó el metrónomo
  int _xrunsAtPlay = 0;
  int get xrunsSincePlay => status.xrunCount < 0 ? -1 : status.xrunCount - _xrunsAtPlay;

  final List<DateTime> _taps = [];

  bool get wantRunning => _wantRunning;

  // ---------- Audio ----------

  Future<void> startAudio() async {
    error = null;
    final mic = await _channel.invokeMethod<String>('requestMicrophone');
    if (mic != 'granted') {
      error = mic == 'permanentlyDenied' ? tr.micDeniedForever : tr.micNeeded;
      notifyListeners();
      return;
    }
    if (deviceInfo.isEmpty) {
      try {
        final info = await _channel.invokeMapMethod<String, Object?>('audioInfo');
        if (info != null) deviceInfo = info;
        // Si el móvil dice que no tiene micro «sin procesar», Android lo trata
        // como el modo normal (que puede llevar control automático de
        // ganancia). «Reconocimiento de voz» está obligado por Android a ir
        // sin control de ganancia ni reducción de ruido: es mejor opción.
        if (!_presetChosenByUser) inputPreset = recommendedPreset;
      } on PlatformException {
        // no pasa nada: solo es informativo
      }
    }
    await _prefsLoaded;
    await refreshDevices();
    _wantRunning = true;
    _openStream();
    _poll ??= Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
    notifyListeners();
  }

  void stopAudio() {
    _wantRunning = false;
    _wantPlaying = false;
    _engine.pause();
    _engine.stop();
    _poll?.cancel();
    _poll = null;
    status = _engine.status();
    notifyListeners();
  }

  bool _openStream() {
    _engine.setInputPreset(inputPreset);
    _engine.setInputDevice(inputDeviceId < 0 ? 0 : inputDeviceId);
    final code = _engine.start();
    if (code != 0) {
      error = tr.audioError(code);
      _wantRunning = false;
      return false;
    }
    _routes.reset(); // la latencia se elige en cuanto se sepa la ruta
    _applySettings();
    if (_wantPlaying) {
      _engine.play();
      _xrunsAtPlay = 0;
    }
    return true;
  }

  void _applySettings() {
    _engine.setBpm(bpm);
    _engine.setMeter(timeSignature.beats, timeSignature.accentMask);
    _engine.setClickMode(clickMode);
    _engine.setClickVolume(clickVolume);
    _engine.setStartOnSound(startOnSound);
    _engine.setMonitorEnabled(monitorEnabled);
    _engine.setMonitorVolume(monitorVolume);
    _engine.setInputGain(_dbToGain(inputGainDb));
    _engine.setLoopMode(loopMode);
    _engine.setSyncBars(syncBars);
    _engine.setLoopVolume(loopVolume);
    _engine.setAutoAdvance(autoAdvance);
    for (var i = 0; i < kTrackCount; i++) {
      _engine.setTrackVolume(i, trackVolumes[i]);
    }
  }

  static double _dbToGain(double db) => math.pow(10, db / 20).toDouble();

  void _tick() {
    final prev = status;
    final source = latencySource;
    final applied = _routes.applied;
    status = _engine.status();
    _statusAt = _clock.elapsedMicroseconds;
    if (status.running) {
      // Con loop, el tempo es el del motor (en libre lo calcula él)
      if (tempoLocked && status.bpm > 0) bpm = status.bpm;
      if (prev.tapState == LatencyState.running && status.tapState == LatencyState.done) {
        _routes.saveMeasured(_currentRouteKey, status.tapFrames);
      }
      // El looper también arranca y para el metrónomo (cuenta de entrada,
      // doble toque): lo que quiere el usuario es lo que está pasando.
      if (status.playing && !prev.playing) {
        _xrunsAtPlay = status.xrunCount < 0 ? 0 : status.xrunCount;
      }
      _wantPlaying = status.playing;
      _updateRoute();
      if (prev.latencyState == LatencyState.running && status.latencyState == LatencyState.done) {
        _routes.saveMeasured(_currentRouteKey, status.latencyFrames);
      }
    }
    // Si se desconecta algo (auriculares, interfaz USB), se reabre solo.
    if (_wantRunning && !status.running && !_restarting) {
      _restarting = true;
      Future.delayed(const Duration(milliseconds: 300), () async {
        await refreshDevices(); // se ha enchufado o quitado algo
        if (_wantRunning) _openStream();
        _restarting = false;
        notifyListeners(); // por si no se ha podido abrir (error)
      });
    }
    _live.fire();
    if (layoutChanged(prev, status) || source != latencySource || applied != _routes.applied) {
      notifyListeners();
    }
  }

  void _onHide() {
    // La versión 1 solo suena en primer plano
    if (_wantRunning) {
      stopAudio();
      _resumeOnShow = true;
    }
  }

  bool _resumeOnShow = false;
  void _onShow() {
    if (_resumeOnShow) {
      _resumeOnShow = false;
      startAudio();
    }
  }

  // ---------- Metrónomo ----------

  /// Con un loop grabado (o grabándose) el tempo y el compás no se tocan.
  bool get tempoLocked => status.loopState != LoopState.empty;

  void togglePlay() {
    if (!status.running) return;
    _wantPlaying = !status.playing;
    if (_wantPlaying) {
      _xrunsAtPlay = status.xrunCount < 0 ? 0 : status.xrunCount;
      _engine.play();
    } else {
      _engine.pause();
    }
    notifyListeners();
  }

  void setBpm(double value) {
    if (tempoLocked) return;
    bpm = value.clamp(40, 240).roundToDouble();
    _engine.setBpm(bpm);
    _prefs.set(Prefs.bpm, bpm.toStringAsFixed(0));
    notifyListeners();
  }

  void tapTempo() {
    if (tempoLocked) return;
    final now = DateTime.now();
    if (_taps.isNotEmpty && now.difference(_taps.last).inMilliseconds > 2000) {
      _taps.clear();
    }
    _taps.add(now);
    if (_taps.length > 5) _taps.removeAt(0);
    if (_taps.length >= 2) {
      final ms = _taps.last.difference(_taps.first).inMicroseconds / 1000 / (_taps.length - 1);
      setBpm(60000 / ms);
    }
  }

  void setTimeSignature(TimeSignature ts) {
    if (tempoLocked) return;
    timeSignature = ts;
    _engine.setMeter(ts.beats, ts.accentMask);
    _prefs.set(Prefs.meter, ts.label);
    notifyListeners();
  }

  void setClickMode(ClickMode mode) {
    clickMode = mode;
    _engine.setClickMode(mode);
    _prefs.set(Prefs.clickMode, mode.name);
    notifyListeners();
  }

  // Reloj para dibujar el pulso: el motor dice en qué tiempo va cada vez que
  // se le pregunta (30 veces por segundo); entre medias se calcula con el
  // reloj del móvil. Se resta la latencia de salida para que la luz vaya con
  // lo que se oye, no con lo que el motor acaba de calcular.
  final Stopwatch _clock = Stopwatch()..start();
  int _statusAt = 0;

  /// El tiempo del compás que se está oyendo ahora (null si está parado).
  BeatNow? beatNow() {
    final s = status;
    final spb = s.samplesPerBeat;
    final bpb = s.beatsPerBar;
    if (!s.running || !s.playing || spb <= 0 || bpb <= 0 || s.sampleRate <= 0) return null;
    final elapsed = (_clock.elapsedMicroseconds - _statusAt) / 1e6;
    final out = s.outputLatencyMs > 0 ? s.outputLatencyMs / 1000 : 0.0;
    // Sin noticias del motor en un rato: no se inventa
    if (elapsed > 0.5) return (beat: s.beat, phase: 0.0);
    var frames = s.beatFrames + ((elapsed - out) * s.sampleRate).round();
    var beat = s.beat;
    final steps = (frames / spb).floor();
    frames -= steps * spb;
    beat = (beat + steps) % bpb;
    if (beat < 0) beat += bpb;
    return (beat: beat, phase: frames / spb);
  }

  void setClickVolume(double v) {
    clickVolume = v;
    _engine.setClickVolume(v);
    notifyListeners();
  }

  // ---------- Looper ----------

  /// Tiempo máximo entre dos toques para que cuenten como doble toque.
  static const doubleTapWindow = Duration(milliseconds: 300);

  /// Tiempo pulsado para que cuente como «mantener» (deshacer).
  static const holdDelay = Duration(milliseconds: 600);

  DateTime? _lastPedalDown;
  Timer? _holdTimer;

  /// El botón principal se ha pulsado. Actúa en el momento de pulsar (no al
  /// soltar) para que la grabación empiece y acabe justo donde toca. Si
  /// luego resulta ser un doble toque o se mantiene, el motor corrige lo que
  /// hizo este toque.
  void pedalDown() {
    if (!status.running) return;
    final now = DateTime.now();
    final last = _lastPedalDown;
    _holdTimer?.cancel();
    if (last != null && now.difference(last) < doubleTapWindow) {
      _lastPedalDown = null;
      _engine.loopDoubleTap();
      HapticFeedback.heavyImpact();
      return;
    }
    _lastPedalDown = now;
    _engine.loopPress();
    HapticFeedback.lightImpact();
    _holdTimer = Timer(holdDelay, () {
      _engine.loopHold();
      _lastPedalDown = null;
      HapticFeedback.heavyImpact();
    });
  }

  void pedalUp() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  Timer? _secondaryTimer;

  /// Botón secundario (solo externo): toque = siguiente pista; mantener =
  /// deshacer. Como no graba nada, puede esperar a que se suelte.
  void secondaryDown() {
    if (!status.running) return;
    _secondaryTimer?.cancel();
    _secondaryTimer = Timer(holdDelay, () {
      _secondaryTimer = null;
      _engine.loopUndo();
      HapticFeedback.heavyImpact();
    });
  }

  void secondaryUp() {
    final timer = _secondaryTimer;
    if (timer == null) return; // ya contó como «mantener»
    timer.cancel();
    _secondaryTimer = null;
    _engine.selectNextTrack();
    HapticFeedback.selectionClick();
  }

  void undo() => _engine.loopUndo();

  /// Borra todas las pistas.
  void clearLoop() => _engine.loopClear();

  // ---------- Pistas ----------

  void selectTrack(int track) {
    _engine.selectTrack(track);
    HapticFeedback.selectionClick();
  }

  void setTrackVolume(int track, double v) {
    trackVolumes[track] = v;
    _engine.setTrackVolume(track, v);
    notifyListeners();
  }

  void toggleTrackMuted(int track) {
    _engine.setTrackMuted(track, !status.tracks[track].muted);
  }

  void clearTrack(int track) => _engine.clearTrack(track);

  void setAutoAdvance(bool on) {
    autoAdvance = on;
    _engine.setAutoAdvance(on);
    _prefs.setBool(Prefs.autoAdvance, on);
    notifyListeners();
  }

  /// Para o arranca todo (lo mismo que el doble toque).
  void toggleTransport() => togglePlay();

  void setLoopMode(LoopMode mode) {
    loopMode = mode;
    _engine.setLoopMode(mode);
    _prefs.set(Prefs.loopMode, mode.name);
    notifyListeners();
  }

  void setSyncBars(int bars) {
    syncBars = bars;
    _engine.setSyncBars(bars);
    _prefs.set(Prefs.syncBars, '$bars');
    notifyListeners();
  }

  void setStartOnSound(bool on) {
    startOnSound = on;
    _engine.setStartOnSound(on);
    _prefs.setBool(Prefs.startOnSound, on);
    notifyListeners();
  }

  void setLoopVolume(double v) {
    loopVolume = v;
    _engine.setLoopVolume(v);
    notifyListeners();
  }

  // ---------- Entrada ----------

  /// Lee las entradas y salidas conectadas. Si la entrada elegida ya no está,
  /// vuelve al micrófono del móvil (el de abajo, que es el principal).
  Future<void> refreshDevices() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('audioDevices');
      if (m == null) return;
      List<AudioDevice> parse(Object? l) => [
        for (final e in (l as List? ?? const [])) AudioDevice.fromMap(e as Map<Object?, Object?>),
      ];
      inputDevices = parse(m['inputs']);
      outputDevices = parse(m['outputs']);
    } on PlatformException {
      return;
    }
    final stillThere = inputDeviceId == 0 || inputDevices.any((d) => d.id == inputDeviceId);
    if (inputDeviceId < 0 || !stillThere) {
      final mics = inputDevices.where((d) => d.isBuiltinMic).toList();
      final bottom = mics.where((d) => d.address.toLowerCase().contains('bottom'));
      inputDeviceId = bottom.isNotEmpty ? bottom.first.id : (mics.isNotEmpty ? mics.first.id : 0);
    }
    notifyListeners();
  }

  void setInputDevice(int id) {
    inputDeviceId = id;
    if (_wantRunning) {
      _engine.stop();
      _openStream();
    }
    notifyListeners();
  }

  AudioDevice? _device(int id, {required bool input}) {
    for (final d in input ? inputDevices : outputDevices) {
      if (d.id == id) return d;
    }
    return null;
  }

  String deviceLabel(int id, {required bool input}) {
    if (id <= 0) return '—';
    final d = _device(id, input: input);
    return d == null ? tr.unknownDevice(id) : tr.deviceName(d);
  }

  /// Cambiar el modo del micrófono obliga a reabrir el audio (el loop se
  /// conserva: queda parado).
  void setInputPreset(InputPreset preset) {
    inputPreset = preset;
    _presetChosenByUser = true;
    _prefs.set(Prefs.inputPreset, '${preset.code}');
    if (_wantRunning) {
      _engine.stop();
      _openStream();
    }
    notifyListeners();
  }

  void setInputGainDb(double db) {
    inputGainDb = db.clamp(0, 24).roundToDouble();
    _engine.setInputGain(_dbToGain(inputGainDb));
    notifyListeners();
  }

  // ---------- Monitor ----------

  void setMonitorEnabled(bool on) {
    monitorEnabled = on;
    _engine.setMonitorEnabled(on);
    notifyListeners();
  }

  void setMonitorVolume(double v) {
    monitorVolume = v;
    _engine.setMonitorVolume(v);
    notifyListeners();
  }

  // ---------- Latencia ----------
  //
  // Se guarda una por ruta (ver LatencyRoutes) y se aplica sola al cambiar.

  LatencySource get latencySource => _routes.source;

  /// Nombre legible de la ruta actual.
  String get routeLabel =>
      '${tr.nowRoute(deviceLabel(status.inputDeviceId, input: true), deviceLabel(status.outputDeviceId, input: false))}'
      ' · ${status.inputPreset == null ? '—' : tr.presetName(status.inputPreset!)}';

  String _deviceKey(int id, {required bool input}) {
    final d = _device(id, input: input);
    if (d == null) return 'id$id';
    return '${d.type}:${d.name}:${d.address}';
  }

  String get _currentRouteKey =>
      'in=${_deviceKey(status.inputDeviceId, input: true)}'
      '|out=${_deviceKey(status.outputDeviceId, input: false)}'
      '|${status.sampleRate}'
      // El modo del micro también cambia la latencia (más o menos procesado)
      '|preset=${status.inputPreset?.code ?? 0}';

  void _updateRoute() {
    if (status.inputDeviceId <= 0 || status.outputDeviceId <= 0) return;
    // Sin medir: la estimación de Android (salida + entrada) si la hay
    final est = status.outputLatencyMs >= 0 && status.inputLatencyMs >= 0
        ? status.outputLatencyMs + status.inputLatencyMs
        : -1.0;
    _routes.update(
      _currentRouteKey,
      estimateFrames: est > 0 ? (est * status.sampleRate / 1000).round() : 0,
    );
  }

  /// Olvida la medida de la ruta actual (vuelve a la estimación).
  void forgetLatency() {
    if (_routes.forget()) notifyListeners();
  }

  void measureLatency() {
    if (!status.running) return;
    _engine.measureLatency();
  }

  /// Calibración tocando al clic (con cascos).
  void startTapCalibration() {
    if (!status.running) return;
    _engine.startTapCalibration();
  }

  void cancelTapCalibration() => _engine.cancelTapCalibration();

  /// Se está grabando algo (no se puede medir ni mover la latencia).
  bool get recordingNow =>
      status.loopState == LoopState.armed ||
      status.loopState == LoopState.recording ||
      status.loopState == LoopState.overdubbing;

  /// Ajuste a mano (en ms). Lo ya grabado se mueve lo mismo, así se puede
  /// afinar a oído con un loop sonando sobre el clic.
  void setLatencyManually(double ms) {
    if (!status.running || status.sampleRate <= 0 || recordingNow) return;
    final frames = (ms.clamp(0, 500) * status.sampleRate / 1000).round();
    _routes.setManually(_currentRouteKey, frames);
    _engine.nudgeLatency(frames);
    notifyListeners();
  }

  /// Compensación que se ha pedido (aunque el motor aún no la haya aplicado).
  double get compensationTargetMs => status.sampleRate > 0 && _routes.applied >= 0
      ? 1000 * _routes.applied / status.sampleRate
      : compensationMs;

  /// Compensación en uso, en ms.
  double get compensationMs =>
      status.sampleRate > 0 ? 1000 * status.loopLatencyFrames / status.sampleRate : 0;

  // ---------- Apariencia ----------

  void setThemeMode(ThemeMode mode) {
    appearance.value = appearance.value.copyWith(mode: mode);
    _prefs.set(Prefs.themeMode, mode.name);
  }

  void setChassis(Chassis chassis) {
    appearance.value = appearance.value.copyWith(chassis: chassis);
    _prefs.set(Prefs.chassis, chassis.name);
  }

  // ---------- Controles externos ----------
  //
  // Ver PedalKeys. Aquí solo se reparte lo que hace cada acción.

  bool get volumeKeys => _keys.volumeKeys;
  bool get headsetKey => _keys.headsetKey;
  List<LearnedKey> get learnedKeys => _keys.learned;
  PedalAction? get learning => _keys.learning;
  int? get lastKeyCode => _keys.lastKeyCode;
  String get lastKeyName => _keys.lastKeyName;
  PedalAction? get lastKeyAction => _keys.lastKeyAction;

  void _onPedalKey(PedalAction action, {required bool down}) {
    switch (action) {
      case PedalAction.main:
        down ? pedalDown() : pedalUp();
      case PedalAction.secondary:
        down ? secondaryDown() : secondaryUp();
    }
  }

  /// Una tecla externa se ha pulsado o soltado.
  void handleKey(int code, {required bool down, int repeat = 0, String name = ''}) =>
      _keys.handle(code, down: down, repeat: repeat, name: name);

  void setVolumeKeys(bool on) => _keys.setVolumeKeys(on);
  void setHeadsetKey(bool on) => _keys.setHeadsetKey(on);
  void startLearning(PedalAction action) => _keys.startLearning(action);
  void cancelLearning() => _keys.cancelLearning();
  void forgetKey(int code) => _keys.forget(code);

  // ---------- Ajustes guardados ----------

  Future<void> _loadPrefs() async {
    // Modo del micrófono elegido por el usuario
    final preset = await _prefs.get(Prefs.inputPreset);
    for (final p in InputPreset.values) {
      if (preset != null && '${p.code}' == preset) {
        inputPreset = p;
        _presetChosenByUser = true;
      }
    }

    autoAdvance = await _prefs.getBool(Prefs.autoAdvance) ?? autoAdvance;

    // Metrónomo y looper
    final savedBpm = double.tryParse(await _prefs.get(Prefs.bpm) ?? '');
    if (savedBpm != null) bpm = savedBpm.clamp(40, 240);
    final meter = await _prefs.get(Prefs.meter);
    timeSignature = kTimeSignatures.firstWhere(
      (t) => t.label == meter,
      orElse: () => kTimeSignatures.first,
    );
    final click = await _prefs.get(Prefs.clickMode);
    clickMode = ClickMode.values.firstWhere((m) => m.name == click, orElse: () => ClickMode.always);
    final mode = await _prefs.get(Prefs.loopMode);
    loopMode = LoopMode.values.firstWhere((m) => m.name == mode, orElse: () => LoopMode.sync);
    final bars = int.tryParse(await _prefs.get(Prefs.syncBars) ?? '');
    if (bars != null && kSyncBarOptions.contains(bars)) syncBars = bars;
    startOnSound = await _prefs.getBool(Prefs.startOnSound) ?? false;

    // Apariencia
    final theme = await _prefs.get(Prefs.themeMode);
    final chassis = await _prefs.get(Prefs.chassis);
    appearance.value = Appearance(
      mode: ThemeMode.values.firstWhere((m) => m.name == theme, orElse: () => ThemeMode.system),
      chassis: Chassis.values.firstWhere((c) => c.name == chassis, orElse: () => Chassis.classic),
    );

    await _keys.load();
    await _routes.load();
    notifyListeners();
  }

  bool _disposed = false;

  // Los ajustes guardados se cargan en segundo plano: si llegan cuando ya se
  // ha cerrado, no hay a quién avisar
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle.dispose();
    _keys.dispose();
    appearance.dispose();
    _live.dispose();
    _poll?.cancel();
    _holdTimer?.cancel();
    _secondaryTimer?.cancel();
    _engine.stop();
    super.dispose();
  }
}

/// Avisa a quien escuche, sin más.
class _Pulse extends ChangeNotifier {
  void fire() => notifyListeners();
}
