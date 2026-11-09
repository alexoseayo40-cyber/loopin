// Loopin — estado de la app y órdenes al motor
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:loopin_engine/loopin_engine.dart';

/// Compases disponibles: tiempos por compás → nombre.
const Map<int, String> kTimeSignatures = {4: '4/4', 3: '3/4', 6: '6/8'};

class EngineController extends ChangeNotifier {
  EngineController({LoopinEngine? engine}) : _engine = engine ?? LoopinEngine.instance {
    _lifecycle = AppLifecycleListener(
      onHide: _onHide,
      onShow: _onShow,
    );
  }

  final LoopinEngine _engine;
  static const _permissions = MethodChannel('loopin/permissions');
  late final AppLifecycleListener _lifecycle;
  Timer? _poll;

  // Lo que el usuario ha pedido (se reaplica si el audio se reinicia)
  double bpm = 92;
  int beatsPerBar = 4;
  bool clickEnabled = true;
  double clickVolume = 0.8;
  InputPreset inputPreset = InputPreset.unprocessed;

  /// Entrada elegida (id de Android). -1 = aún sin elegir; 0 = la de Android.
  int inputDeviceId = -1;
  List<AudioDevice> inputDevices = const [];
  List<AudioDevice> outputDevices = const [];
  double inputGainDb = 0;
  bool monitorEnabled = false;
  double monitorVolume = 1.0;

  bool _wantRunning = false;
  bool _wantPlaying = false;
  bool _restarting = false;
  String? error;

  EngineStatus status = const EngineStatus();

  /// Datos del móvil (modelo, si admite micrófono sin procesar…)
  Map<String, Object?> deviceInfo = const {};

  // Prueba de estabilidad: cortes desde que arrancó el metrónomo
  int _xrunsAtPlay = 0;
  int get xrunsSincePlay =>
      status.xrunCount < 0 ? -1 : status.xrunCount - _xrunsAtPlay;

  final List<DateTime> _taps = [];

  bool get wantRunning => _wantRunning;

  // ---------- Audio ----------

  Future<void> startAudio() async {
    error = null;
    final mic = await _permissions.invokeMethod<String>('requestMicrophone');
    if (mic != 'granted') {
      error = mic == 'permanentlyDenied'
          ? 'Sin permiso de micrófono. Actívalo en Ajustes › Apps › Loopin › Permisos.'
          : 'Loopin necesita el micrófono para escuchar la guitarra.';
      notifyListeners();
      return;
    }
    if (deviceInfo.isEmpty) {
      try {
        final info = await _permissions.invokeMapMethod<String, Object?>('audioInfo');
        if (info != null) deviceInfo = info;
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
  }

  static double _dbToGain(double db) => math.pow(10, db / 20).toDouble();

  void _tick() {
    status = _engine.status();
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
      final playing = _wantPlaying;
      stopAudio();
      _resumeOnShow = true;
      _wantPlaying = playing;
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
    bpm = value.clamp(40, 240).roundToDouble();
    _engine.setBpm(bpm);
    notifyListeners();
  }

  void tapTempo() {
    final now = DateTime.now();
    if (_taps.isNotEmpty && now.difference(_taps.last).inMilliseconds > 2000) {
      _taps.clear();
    }
    _taps.add(now);
    if (_taps.length > 5) _taps.removeAt(0);
    if (_taps.length >= 2) {
      final ms = _taps.last.difference(_taps.first).inMicroseconds /
          1000 /
          (_taps.length - 1);
      setBpm(60000 / ms);
    }
  }

  void setBeatsPerBar(int value) {
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

  // ---------- Entrada ----------

  /// Lee las entradas y salidas conectadas. Si la entrada elegida ya no está,
  /// vuelve al micrófono del móvil (el de abajo, que es el principal).
  Future<void> refreshDevices() async {
    try {
      final m = await _permissions.invokeMapMethod<String, Object?>('audioDevices');
      if (m == null) return;
      List<AudioDevice> parse(Object? l) => [
            for (final e in (l as List? ?? const []))
              AudioDevice.fromMap(e as Map<Object?, Object?>),
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
      inputDeviceId = bottom.isNotEmpty
          ? bottom.first.id
          : (mics.isNotEmpty ? mics.first.id : 0);
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

  String deviceLabel(int id, {required bool input}) {
    if (id <= 0) return '—';
    for (final d in input ? inputDevices : outputDevices) {
      if (d.id == id) return d.label;
    }
    return 'dispositivo $id';
  }

  /// Cambiar el modo del micrófono obliga a reabrir el audio.
  void setInputPreset(InputPreset preset) {
    inputPreset = preset;
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

  void measureLatency() {
    if (!status.running) return;
    _engine.measureLatency();
  }

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
    return [
      'Loopin · prototipo de audio',
      'Móvil: $model · Android $android · baja latencia: ${yesNo(deviceInfo['lowLatency'])} · '
          'pro audio: ${yesNo(deviceInfo['proAudio'])}',
      'Entrada: ${deviceLabel(s.inputDeviceId, input: true)} · '
          'salida: ${deviceLabel(s.outputDeviceId, input: false)}',
      'Micrófono: ${s.inputPreset?.label ?? '—'}${s.presetFallback ? ' (el modo pedido falló)' : ''} · '
          'sin procesar admitido: ${yesNo(deviceInfo['unprocessed'])} · ganancia +${inputGainDb.toStringAsFixed(0)} dB',
      'API: $api · ${s.sampleRate} Hz · bloque ${s.framesPerBurst} · '
          'buffer ${s.bufferSizeFrames} (${ms(s.bufferMs)})',
      'Modo: ${s.exclusive ? 'exclusivo' : 'compartido'} · '
          '${s.lowLatency ? 'baja latencia' : 'latencia normal'} · '
          'entrada ${s.inputChannels} canal(es)',
      'Estimación de Oboe: salida ${ms(s.outputLatencyMs)} + entrada ${ms(s.inputLatencyMs)}',
      if (s.latencyState == LatencyState.done)
        'Ida y vuelta medida: ${ms(s.latencyMs)} (${s.latencyFrames} muestras)',
      if (s.playing || s.framePosition > 0)
        'Metrónomo: ${s.bpm.toStringAsFixed(0)} BPM · '
            '${(s.playSeconds / 60).toStringAsFixed(1)} min · cortes: $xrunsSincePlay',
    ].join('\n');
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _poll?.cancel();
    _engine.stop();
    super.dispose();
  }
}
