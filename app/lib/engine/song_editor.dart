// Loopin — preparar una canción: escucharla, su tempo y dónde cae el 1
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'engine_controller.dart';

/// Lo que se está preparando de una canción. El motor la abre (la decodifica
/// sin estirar) para la vista previa: se oye desde donde se toque, con un clic
/// opcional en su rejilla (el 1 marcado + su tempo), para comprobar a oído
/// que todo cuadra de principio a fin.
///
/// El tempo se escribe, se marca con TAP o, el más exacto, se saca de dos
/// unos: el marcado y otro más adelante. Entre los dos hay un número entero de
/// compases, así que el tempo sale con decimales y sin error que se acumule.
class SongEditor extends ChangeNotifier {
  SongEditor({required this.controller, required Song song}) : draft = song;

  final EngineController controller;
  Song draft;

  LoopinEngine get _engine => controller.engine;
  EngineStatus get _s => controller.status;

  /// Picos de toda la canción (para la vista entera) y de cerca del 1.
  Float32List overview = Float32List(0);
  Float32List zoom = Float32List(0);
  static const overviewBins = 480;
  static const zoomBins = 400;

  /// Media anchura de la vista de cerca, en segundos.
  static const zoomRadius = 0.15;

  /// Hasta dónde se busca el golpe al marcar el 1 (± segundos).
  static const snapRadius = 0.07;

  bool _opened = false;
  bool _started = false;
  bool get started => _started;

  /// Dónde empieza a sonar la vista previa (muestras).
  int cursor = 0;
  bool click = true;
  final List<DateTime> _taps = [];

  int get rate => _s.sampleRate > 0 ? _s.sampleRate : 48000;

  /// Abierta y lista para escucharla.
  bool get ready => _opened && _s.previewId == draft.id;
  bool get failed => _s.songOpenId == draft.id && _s.songOpenState == JobState.failed;
  SongError get error => _s.songOpenError;
  double get progress => _s.songOpenId == draft.id ? _s.songOpenProgress : 0;
  int get frames => _s.songOpenFrames;
  bool get playing => ready && _s.previewPlaying;
  double get bpmGuess => _s.songBpmGuess;

  TimeSignature get meter => kTimeSignatures.firstWhere(
    (t) => t.label == draft.meter,
    orElse: () => kTimeSignatures.first,
  );

  int get markFrame => (draft.mark * rate).round();
  int? get mark2Frame => draft.mark2 == null ? null : (draft.mark2! * rate).round();

  /// Compases entre los dos unos (si hay otro marcado).
  int? get barsBetween {
    final m2 = draft.mark2;
    if (m2 == null || draft.bpm <= 0) return null;
    return ((m2 - draft.mark) * draft.bpm / 60 / meter.beats).round();
  }

  /// Muestras por tiempo de la canción (con decimales), 0 si no hay tempo.
  double get beatFrames => draft.bpm > 0 ? rate * 60 / draft.bpm : 0;

  // ---------------------------------------------------------------- abrir

  void start() {
    if (_started) return;
    _started = true;
    controller.stopAll();
    final path = controller.songPath(draft);
    if (path != null) _engine.songOpen(path, draft.id);
    controller.live.addListener(_onTick);
  }

  void _onTick() {
    if (_opened || _s.songOpenId != draft.id) return;
    if (_s.songOpenState == JobState.failed) {
      notifyListeners();
      return;
    }
    if (_s.songOpenState != JobState.done || _s.previewId != draft.id) return;
    _opened = true;
    overview = _engine.songPeaks(0, frames, overviewBins);
    var d = draft.copyWith(seconds: frames / rate);
    if (!draft.ready) {
      // Lo que sugiere el motor: su tempo (o el del metrónomo) y el primer golpe
      final guess = bpmGuess >= 40 && bpmGuess <= 240 ? bpmGuess : controller.bpm;
      d = d.copyWith(
        bpm: (guess * 10).round() / 10,
        mark: _s.songFirstAttack > 0 ? _s.songFirstAttack / rate : 0,
      );
    }
    draft = d;
    cursor = math.max(0, markFrame - _barFrames());
    _engine.setPreviewClick(click);
    _sendGrid();
    _updateZoom();
    notifyListeners();
  }

  int _barFrames() => (beatFrames * meter.beats).round();

  void _sendGrid() {
    if (!_opened) return;
    _engine.setPreviewGrid(markFrame.toDouble(), beatFrames, meter.beats, meter.accentMask);
  }

  void _updateZoom() {
    if (!_opened) return;
    final r = (zoomRadius * rate).round();
    zoom = _engine.songPeaks(markFrame - r, markFrame + r, zoomBins);
  }

  void _changed() {
    _sendGrid();
    _updateZoom();
    notifyListeners();
  }

  // ---------------------------------------------------------------- escuchar

  void togglePlay() {
    if (!ready) return;
    if (playing) {
      cursor = controller.previewHeardFrame();
      _engine.previewStop();
    } else {
      _engine.previewPlay(cursor);
    }
    notifyListeners();
  }

  void seek(int frame) {
    cursor = frame.clamp(0, math.max(0, frames - 1));
    if (playing) _engine.previewPlay(cursor);
    notifyListeners();
  }

  /// Un compás antes del 1 (para oír cómo entra).
  void playFromMark() {
    if (!ready) return;
    cursor = math.max(0, markFrame - _barFrames());
    _engine.previewPlay(cursor);
    notifyListeners();
  }

  void setClick(bool on) {
    click = on;
    _engine.setPreviewClick(on);
    notifyListeners();
  }

  // ---------------------------------------------------------------- el 1

  /// Lo que se está oyendo (o el cursor, parado), ajustado al golpe más
  /// claro de ahí cerca.
  int _snap(int frame) {
    final f = _engine.songFindAttack(frame, (snapRadius * rate).round());
    return f >= 0 ? f : frame;
  }

  int get _here => playing ? controller.previewHeardFrame() : cursor;

  void markOne() {
    if (!ready) return;
    final f = _snap(_here);
    draft = draft.copyWith(mark: f / rate);
    _fitSecond();
    _changed();
  }

  /// Mueve el 1 (en milisegundos).
  void nudgeMark(double ms) {
    if (!ready) return;
    final double secs = (draft.mark + ms / 1000).clamp(0.0, math.max(0.0, frames / rate));
    draft = draft.copyWith(mark: secs);
    _fitSecond();
    _changed();
  }

  /// Pone el 1 en esa muestra (al arrastrar en la vista de cerca).
  void setMarkFrame(int frame) {
    draft = draft.copyWith(mark: frame.clamp(0, math.max(0, frames - 1)).toDouble() / rate);
    _fitSecond();
    _changed();
  }

  /// Otro 1 más adelante: el tempo sale de los compases que hay entre los dos.
  void markSecond() {
    if (!ready || draft.bpm <= 0) return;
    final f = _snap(_here);
    final secs = f / rate;
    if ((secs - draft.mark).abs() * draft.bpm / 60 < meter.beats) return; // menos de un compás
    draft = draft.copyWith(mark2: () => secs);
    _fitSecond();
    _changed();
  }

  void clearSecond() {
    draft = draft.copyWith(mark2: () => null);
    _changed();
  }

  /// Corrige cuántos compases hay entre los dos unos (si se ha contado mal).
  void setBarsBetween(int bars) {
    final m2 = draft.mark2;
    if (m2 == null || bars < 1) return;
    final bpm = bars * meter.beats * 60 / (m2 - draft.mark).abs();
    if (bpm < 40 || bpm > 240) return;
    draft = draft.copyWith(bpm: (bpm * 100).round() / 100);
    _changed();
  }

  /// Con dos unos, el tempo es el que hace caber un número entero de compases.
  void _fitSecond() {
    final bars = barsBetween;
    if (bars == null || bars < 1) return;
    setBarsBetween(bars);
  }

  // ---------------------------------------------------------------- tempo y compás

  void setBpm(double value) {
    draft = draft.copyWith(bpm: (value.clamp(40.0, 240.0) * 10).round() / 10, mark2: () => null);
    _changed();
  }

  /// Toca al ritmo de la canción (la media de los últimos toques).
  void tap() {
    final now = DateTime.now();
    if (_taps.isNotEmpty && now.difference(_taps.last).inMilliseconds > 2000) _taps.clear();
    _taps.add(now);
    if (_taps.length > 8) _taps.removeAt(0);
    if (_taps.length < 2) return;
    final ms = _taps.last.difference(_taps.first).inMicroseconds / 1000 / (_taps.length - 1);
    setBpm(60000 / ms);
  }

  void setMeter(TimeSignature ts) {
    draft = draft.copyWith(meter: ts.label);
    _fitSecond();
    _changed();
  }

  void setName(String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    draft = draft.copyWith(name: n);
  }

  // ---------------------------------------------------------------- acabar

  /// Guarda lo preparado y la elige para que suene con los loops.
  Future<void> save() async {
    await controller.saveSong(draft);
    controller.selectSong(draft);
  }

  bool _closed = false;

  /// Al salir: se calla y el motor suelta la canción abierta.
  void close() {
    if (_closed) return;
    _closed = true;
    controller.live.removeListener(_onTick);
    if (_started) {
      _engine.previewStop();
      _engine.songClose();
    }
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
