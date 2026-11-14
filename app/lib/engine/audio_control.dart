// Loopin — entrada, monitor y latencia (por ruta)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Parte de engine_controller.dart (comparte sus campos privados): las
// entradas y salidas conectadas, el modo del micrófono, la ganancia,
// escucharse en directo y la latencia (medirla, a mano, por ruta).
part of 'engine_controller.dart';

extension AudioControl on EngineController {
  // ---------- Entrada ----------

  /// Lee las entradas y salidas conectadas. Si la entrada elegida ya no está,
  /// vuelve al micrófono del móvil (el de abajo, que es el principal).
  Future<void> refreshDevices() async {
    try {
      final m = await EngineController._channel.invokeMapMethod<String, Object?>('audioDevices');
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
    if (simple) return; // en simple va siempre el recomendado
    _userPreset = preset;
    _prefs.set(Prefs.inputPreset, '${preset.code}');
    _applyPreset();
    notifyListeners();
  }

  /// Pone el modo del micrófono que toca (reabre el audio si cambia).
  void _applyPreset() {
    final preset = _presetForMode;
    if (preset == inputPreset) return;
    inputPreset = preset;
    if (_wantRunning) {
      _engine.stop();
      _openStream();
    }
  }

  void setInputGainDb(double db) {
    inputGainDb = db.clamp(0, 24).roundToDouble();
    _engine.setInputGain(EngineController._dbToGain(inputGainDb));
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
}
