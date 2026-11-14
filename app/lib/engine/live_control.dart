// Loopin — directo y práctica: efectos de pista, cambios al compás, cómo
// parar, entrenador de tempo y afinador (Etapa 5)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Parte de engine_controller.dart (comparte sus campos privados). Los ajustes
// guardados están en live_settings.dart.
//
// Modos: todo está en los dos menos REV y ½ (solo en avanzado).
part of 'engine_controller.dart';

extension LiveControl on EngineController {
  LiveSettings get _ls => _liveSettings;

  // ---------- Pistas ----------

  /// Ajustes › «Efectos de pista» (REV y ½), apagado de serie.
  bool get trackFx => _ls.trackFx;

  /// Se ven los botones REV y ½: en avanzado y con el ajuste encendido.
  bool get trackFxShown => !simple && _ls.trackFx;

  /// Al apagarlo se quitan los que hubiera puestos (si no, sonarían sin verse).
  void setTrackFx(bool on) {
    _ls.trackFx = on;
    _prefs.setBool(Prefs.trackFx, on);
    if (!on) _clearTrackFx();
    notifyListeners();
  }

  /// Reverse y media velocidad: solo si se ven, en pistas con loop y no en la
  /// que se está grabando.
  bool trackFxAvailable(int track) {
    if (!trackFxShown || track < 0 || track >= kTrackCount) return false;
    final t = status.tracks[track];
    return t.hasLoop && !(recordingNow && status.activeTrack == track);
  }

  void toggleTrackReverse(int track) {
    if (!trackFxAvailable(track)) return;
    _engine.setTrackReverse(track, !status.tracks[track].reverse);
    HapticFeedback.selectionClick();
  }

  void toggleTrackHalf(int track) {
    if (!trackFxAvailable(track)) return;
    _engine.setTrackHalf(track, !status.tracks[track].half);
    HapticFeedback.selectionClick();
  }

  /// Quita reverse y media velocidad de todas las pistas (al pasar a simple o
  /// al apagar «Efectos de pista»: donde no se ven).
  void _clearTrackFx() {
    for (var i = 0; i < kTrackCount; i++) {
      final t = status.tracks[i];
      if (t.reverse) _engine.setTrackReverse(i, false);
      if (t.half) _engine.setTrackHalf(i, false);
    }
  }

  // ---------- Cambios de pista al compás ----------

  /// Silenciar, reverse y media velocidad esperan al siguiente 1.
  bool get quantize => _ls.quantize;

  void setQuantize(bool on) {
    _ls.quantize = on;
    _prefs.setBool(Prefs.quantize, on);
    _engine.setQuantize(quantize);
    notifyListeners();
  }

  // ---------- Parar ----------

  /// Cómo para el botón de parar y el doble toque.
  StopMode get stopMode => _ls.stopMode;

  void setStopMode(StopMode mode) {
    _ls.stopMode = mode;
    _prefs.set(Prefs.stopMode, mode.name);
    _engine.setStopMode(stopMode);
    notifyListeners();
  }

  /// Esperando al 1 o bajando para parar (pulsar otra vez para ya).
  bool get stoppingNow => status.stopping != 0;

  // ---------- Entrenador de tempo ----------

  /// Sin loops (con loops el tempo es suyo).
  bool get trainerAvailable => !tempoLocked;
  bool get trainerOn => _ls.trainerOn;
  double get trainerStep => _ls.trainerStep;
  int get trainerBars => _ls.trainerBars;
  double get trainerTop => _ls.trainerTop;

  /// Está subiendo el tempo ahora mismo (el que se ve es el del motor).
  bool get trainerRunning => trainerOn && status.playing && !tempoLocked;

  /// El tempo que hay que enseñar: con loop o con el entrenador, el del motor.
  double get shownBpm => tempoLocked || trainerRunning ? status.bpm : bpm;

  /// Cuántas veces subirá hasta llegar arriba.
  int get trainerSteps =>
      _ls.trainerTop > bpm ? ((_ls.trainerTop - bpm) / _ls.trainerStep).ceil() : 0;

  void setTrainerOn(bool on) {
    if (on && !trainerAvailable) return;
    _ls.trainerOn = on;
    // Que haya adónde subir
    if (on && _ls.trainerTop <= bpm) _ls.trainerTop = math.min(240, bpm.roundToDouble() + 40);
    _applyTrainer();
    notifyListeners();
  }

  void setTrainerStep(double step) {
    _ls.trainerStep = step.clamp(1, 20).roundToDouble();
    _prefs.set(Prefs.trainerStep, _ls.trainerStep.toStringAsFixed(0));
    _applyTrainer();
    notifyListeners();
  }

  void setTrainerBars(int bars) {
    if (!kTrainerBarOptions.contains(bars)) return;
    _ls.trainerBars = bars;
    _prefs.set(Prefs.trainerBars, '$bars');
    _applyTrainer();
    notifyListeners();
  }

  void setTrainerTop(double top) {
    _ls.trainerTop = top.clamp(41, 240).roundToDouble();
    _prefs.set(Prefs.trainerTop, _ls.trainerTop.toStringAsFixed(0));
    _applyTrainer();
    notifyListeners();
  }

  void _applyTrainer() => _engine.setTrainer(
    bars: trainerOn ? _ls.trainerBars : 0,
    step: _ls.trainerStep,
    top: _ls.trainerTop,
  );

  // ---------- Afinador ----------

  /// El La de referencia.
  double get tunerA4 => _ls.tunerA4;

  void setTunerA4(double hz) {
    _ls.tunerA4 = hz.clamp(LiveSettings.minA4, LiveSettings.maxA4).roundToDouble();
    _prefs.set(Prefs.tunerA4, _ls.tunerA4.toStringAsFixed(0));
    // La nota que suena sigue al La nuevo
    final midi = _toneMidi;
    if (midi != null) _engine.setTone(noteHz(midi));
    notifyListeners();
  }

  /// La pantalla del afinador está abierta: la entrada se copia para él. Al
  /// cerrarla se calla la nota de referencia.
  void setTunerOpen(bool open) {
    _engine.setTunerEnabled(open);
    // Al cerrar (desde dispose de la pantalla) no se avisa: el árbol está bloqueado
    if (!open && _toneMidi != null) {
      _toneMidi = null;
      _engine.setTone(0);
    }
  }

  /// Frecuencia de una nota (número MIDI) con el La de referencia.
  double noteHz(int midi) => tunerA4 * math.pow(2, (midi - 69) / 12).toDouble();

  /// La nota de referencia que suena (número MIDI), o null.
  int? get toneMidi => _toneMidi;

  /// Hace sonar una nota para afinar de oído (otra vez la misma, la calla).
  void toggleTone(int midi) {
    if (_toneMidi == midi) {
      stopTone();
      return;
    }
    _toneMidi = midi;
    _engine.setTone(noteHz(midi));
    notifyListeners();
  }

  void stopTone() {
    if (_toneMidi == null) return;
    _toneMidi = null;
    _engine.setTone(0);
    notifyListeners();
  }

  /// Lo que oye el afinador ahora (null si aún no ha llegado audio).
  TunerReading? readTuner() => status.running ? _engine.tunerRead() : null;

  // ---------- Todo junto ----------

  /// Manda al motor lo de este archivo (al abrir el audio y al cambiar de modo).
  void _applyLive() {
    _engine.setQuantize(quantize);
    _engine.setStopMode(stopMode);
    _engine.setFadeSeconds(LiveSettings.fadeSeconds);
    _applyTrainer();
  }
}
