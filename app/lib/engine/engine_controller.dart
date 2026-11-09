// Loopin — estado de la app y órdenes al motor
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:loopin_engine/loopin_engine.dart';

/// Compases disponibles: tiempos por compás → nombre.
const Map<int, String> kTimeSignatures = {4: '4/4', 3: '3/4', 6: '6/8'};

/// Compases que se pueden grabar en modo sincronizado.
const List<int> kSyncBarOptions = [1, 2, 4, 8];

/// De dónde sale la compensación de latencia que se está usando.
enum LatencySource {
  /// Medida con el test para esta entrada y salida.
  measured,

  /// Sin medir: estimación de Android (puede fallar bastante).
  estimated,

  /// Sin medir y sin estimación.
  none,
}

class EngineController extends ChangeNotifier {
  EngineController({LoopinEngine? engine}) : _engine = engine ?? LoopinEngine.instance {
    _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
    _loadPrefs();
  }

  final LoopinEngine _engine;
  static const _channel = MethodChannel('loopin/permissions');
  late final AppLifecycleListener _lifecycle;
  Timer? _poll;

  // Lo que el usuario ha pedido (se reaplica si el audio se reinicia)
  double bpm = 92;
  int beatsPerBar = 4;
  bool clickEnabled = true;
  double clickVolume = 0.8;
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

  bool _wantRunning = false;
  bool _wantPlaying = false;
  bool _restarting = false;
  String? error;

  EngineStatus status = const EngineStatus();

  /// Datos del móvil (modelo, si admite micrófono sin procesar…)
  Map<String, Object?> deviceInfo = const {};

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
      error = mic == 'permanentlyDenied'
          ? 'Sin permiso de micrófono. Actívalo en Ajustes › Apps › Loopin › Permisos.'
          : 'Loopin necesita el micrófono para escuchar la guitarra.';
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
        if (!_presetChosenByUser && deviceInfo['unprocessed'] == false) {
          inputPreset = InputPreset.voiceRecognition;
        }
      } on PlatformException {
        // no pasa nada: solo es informativo
      }
    }
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
      error = LoopinEngine.describeError(code);
      _wantRunning = false;
      return false;
    }
    _routeKey = null; // la latencia se elige en cuanto se sepa la ruta
    _appliedLatency = -1;
    _applySettings();
    if (_wantPlaying) {
      _engine.play();
      _xrunsAtPlay = 0;
    }
    return true;
  }

  void _applySettings() {
    _engine.setBpm(bpm);
    _engine.setBeatsPerBar(beatsPerBar);
    _engine.setClickEnabled(clickEnabled);
    _engine.setClickVolume(clickVolume);
    _engine.setMonitorEnabled(monitorEnabled);
    _engine.setMonitorVolume(monitorVolume);
    _engine.setInputGain(_dbToGain(inputGainDb));
    _engine.setLoopMode(loopMode);
    _engine.setSyncBars(syncBars);
    _engine.setLoopVolume(loopVolume);
  }

  static double _dbToGain(double db) => math.pow(10, db / 20).toDouble();

  void _tick() {
    final prev = status;
    status = _engine.status();
    if (status.running) {
      // El looper también arranca y para el metrónomo (cuenta de entrada,
      // doble toque): lo que quiere el usuario es lo que está pasando.
      if (status.playing && !prev.playing) {
        _xrunsAtPlay = status.xrunCount < 0 ? 0 : status.xrunCount;
      }
      _wantPlaying = status.playing;
      _updateRoute();
      if (prev.latencyState == LatencyState.running && status.latencyState == LatencyState.done) {
        _saveMeasuredLatency(status.latencyFrames);
      }
    }
    // Si se desconecta algo (auriculares, interfaz USB), se reabre solo.
    if (_wantRunning && !status.running && !_restarting) {
      _restarting = true;
      Future.delayed(const Duration(milliseconds: 300), () async {
        await refreshDevices(); // se ha enchufado o quitado algo
        if (_wantRunning) _openStream();
        _restarting = false;
      });
    }
    notifyListeners();
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

  void setBeatsPerBar(int value) {
    if (tempoLocked) return;
    beatsPerBar = value;
    _engine.setBeatsPerBar(value);
    notifyListeners();
  }

  void setClickEnabled(bool on) {
    clickEnabled = on;
    _engine.setClickEnabled(on);
    notifyListeners();
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

  void undo() => _engine.loopUndo();

  void clearLoop() => _engine.loopClear();

  void setLoopMode(LoopMode mode) {
    loopMode = mode;
    _engine.setLoopMode(mode);
    notifyListeners();
  }

  void setSyncBars(int bars) {
    syncBars = bars;
    _engine.setSyncBars(bars);
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
    return _device(id, input: input)?.label ?? 'dispositivo $id';
  }

  /// Cambiar el modo del micrófono obliga a reabrir el audio (el loop se
  /// conserva: queda parado).
  void setInputPreset(InputPreset preset) {
    inputPreset = preset;
    _presetChosenByUser = true;
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
  // La latencia de ida y vuelta depende de por dónde entra y sale el sonido
  // (altavoz + micro, cascos USB + micro, interfaz…). Se guarda una medida por
  // cada combinación y se aplica sola al cambiar de ruta.

  /// Medidas guardadas: clave de ruta → muestras (a la frecuencia de la ruta).
  Map<String, int> _savedLatencies = {};
  String? _routeKey;
  LatencySource latencySource = LatencySource.none;

  /// Nombre legible de la ruta actual.
  String get routeLabel =>
      '${deviceLabel(status.inputDeviceId, input: true)} → '
      '${deviceLabel(status.outputDeviceId, input: false)}'
      ' · ${status.inputPreset?.label ?? '—'}';

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

  int _appliedLatency = -1;

  void _applyLatency(int frames, LatencySource source) {
    latencySource = source;
    if (frames != _appliedLatency) {
      _appliedLatency = frames;
      _engine.setLatencyCompensation(frames);
    }
  }

  void _updateRoute() {
    if (status.inputDeviceId <= 0 || status.outputDeviceId <= 0) return;
    final key = _currentRouteKey;
    // Con la misma ruta solo se vuelve a mirar si aún no había ningún valor
    // (la estimación de Android tarda un poco en estar disponible).
    if (key == _routeKey && latencySource != LatencySource.none) return;
    if (key != _routeKey) _appliedLatency = -1;
    _routeKey = key;
    final saved = _savedLatencies[key];
    if (saved != null) {
      _applyLatency(saved, LatencySource.measured);
      return;
    }
    // Sin medir: la estimación de Android (salida + entrada) si la hay
    final est = status.outputLatencyMs >= 0 && status.inputLatencyMs >= 0
        ? status.outputLatencyMs + status.inputLatencyMs
        : -1.0;
    if (est > 0) {
      _applyLatency((est * status.sampleRate / 1000).round(), LatencySource.estimated);
    } else {
      _applyLatency(0, LatencySource.none);
    }
  }

  void _saveMeasuredLatency(int frames) {
    final key = _routeKey ?? _currentRouteKey;
    _savedLatencies[key] = frames;
    _applyLatency(frames, LatencySource.measured);
    _savePrefs();
  }

  /// Olvida la medida de la ruta actual (vuelve a la estimación).
  void forgetLatency() {
    final key = _routeKey;
    if (key == null) return;
    _savedLatencies.remove(key);
    _routeKey = null;
    _savePrefs();
    notifyListeners();
  }

  void measureLatency() {
    if (!status.running) return;
    _engine.measureLatency();
  }

  /// Compensación en uso, en ms.
  double get compensationMs =>
      status.sampleRate > 0 ? 1000 * status.loopLatencyFrames / status.sampleRate : 0;

  // ---------- Ajustes guardados ----------

  static const _latencyPrefKey = 'latencies';

  Future<void> _loadPrefs() async {
    try {
      final raw = await _channel.invokeMethod<String>('prefsGet', {'key': _latencyPrefKey});
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _savedLatencies = {for (final e in m.entries) e.key: (e.value as num).toInt()};
      _routeKey = null; // volver a elegir con lo cargado
    } on Object {
      // sin ajustes guardados (o en un test sin Android): no pasa nada
    }
  }

  Future<void> _savePrefs() async {
    try {
      await _channel.invokeMethod<void>('prefsSet', {
        'key': _latencyPrefKey,
        'value': jsonEncode(_savedLatencies),
      });
    } on Object {
      // no se pudo guardar: se usará solo en esta sesión
    }
  }

  // ---------- Informe ----------

  /// Resumen para copiar y pegar en el plan del proyecto.
  String report() {
    final s = status;
    String ms(double v) => v < 0 ? '—' : '${v.toStringAsFixed(1)} ms';
    final api = switch (s.audioApi) {
      AudioApi.aaudio => 'AAudio',
      AudioApi.openSles => 'OpenSL ES',
      AudioApi.unknown => '—',
    };
    final model = deviceInfo['model'] ?? '—';
    final android = deviceInfo['android'] ?? '—';
    String yesNo(Object? v) => v == true ? 'sí' : (v == false ? 'no' : '—');
    final source = switch (latencySource) {
      LatencySource.measured => 'medida',
      LatencySource.estimated => 'estimada por Android',
      LatencySource.none => 'sin medir',
    };
    return [
      'Loopin · Etapa 2',
      'Móvil: $model · Android $android · baja latencia: ${yesNo(deviceInfo['lowLatency'])} · '
          'pro audio: ${yesNo(deviceInfo['proAudio'])}',
      'Ruta: $routeLabel',
      'Micrófono: ${s.inputPreset?.label ?? '—'}${s.presetFallback ? ' (el modo pedido falló)' : ''} · '
          'sin procesar admitido: ${yesNo(deviceInfo['unprocessed'])} · ganancia +${inputGainDb.toStringAsFixed(0)} dB',
      'API: $api · ${s.sampleRate} Hz · bloque ${s.framesPerBurst} · '
          'buffer ${s.bufferSizeFrames} (${ms(s.bufferMs)})',
      'Salida: ${s.exclusive ? 'exclusivo' : 'compartido'} · '
          '${s.lowLatency ? 'baja latencia' : 'latencia normal'}',
      'Entrada: ${s.inputExclusive ? 'exclusivo' : 'compartido'} · '
          '${s.inputLowLatency ? 'baja latencia' : 'latencia normal'} · '
          'bloque ${s.inputFramesPerBurst} · buffer ${s.inputBufferFrames} · '
          'máx. leído por callback ${s.inputMaxRead} · ${s.inputChannels} canal(es)',
      'Estimación de Oboe: salida ${ms(s.outputLatencyMs)} + entrada ${ms(s.inputLatencyMs)}',
      if (s.latencyState == LatencyState.done)
        'Ida y vuelta medida: ${ms(s.latencyMs)} (${s.latencyFrames} muestras)',
      'Compensación al grabar: ${ms(compensationMs)} ($source)',
      if (s.playing || s.framePosition > 0)
        'Metrónomo: ${s.bpm.toStringAsFixed(0)} BPM · '
            '${(s.playSeconds / 60).toStringAsFixed(1)} min · cortes: $xrunsSincePlay',
      // Cortes desde que se abrió el audio (el buffer sube si los hay)
      if (s.xrunCount >= 0) 'Cortes desde que se abrió el audio: ${s.xrunCount}',
      'Loop: ${switch (s.loopState) {
        LoopState.empty => 'vacío',
        LoopState.armed => 'cuenta de entrada',
        LoopState.recording => 'grabando',
        LoopState.playing => 'sonando',
        LoopState.overdubbing => 'overdub',
        LoopState.stopped => 'parado',
      }}${s.loopState.hasLoop ? ' · ${s.loopBars.toStringAsFixed(0)} compases · ${s.loopLayers} capa(s) · ${loopMode.label}' : ''}',
    ].join('\n');
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _poll?.cancel();
    _holdTimer?.cancel();
    _engine.stop();
    super.dispose();
  }
}
