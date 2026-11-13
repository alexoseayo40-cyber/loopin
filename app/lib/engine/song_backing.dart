// Loopin — la canción que suena con los loops: cuál, encendida o no y
// tenerla siempre preparada al tempo de ahora
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/foundation.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'prefs.dart';
import 'songs.dart';

/// En qué está la canción (lo que enseña su fila).
enum BackingPhase {
  /// No hay ninguna elegida.
  noSong,

  /// Elegida, pero sin tempo ni 1: hay que prepararla.
  needsSetup,

  /// Estirándola al tempo de ahora (en segundo plano).
  preparing,

  /// Lista: suena (o sonará en el próximo 1) si está encendida.
  ready,

  /// El tempo de ahora está a más del doble o menos de la mitad del suyo.
  tooFar,

  /// No se ha podido preparar (archivo estropeado, demasiado larga…).
  failed,
}

/// Lo que se le ha pedido al motor: si algo de esto cambia, hay que volver a
/// estirarla.
typedef _Key = ({int id, double bpm, double mark, int spb, int bpb, int rate});

/// La canción elegida y su estado. El motor solo sabe tocar una canción ya
/// estirada al tempo del transporte; aquí se vigila que siempre haya una
/// preparada para el tempo y el compás de ahora: si cambian (tempo con ±, TAP,
/// un loop en libre…), se vuelve a preparar, un poco después de que dejen de
/// cambiar.
class SongBacking {
  SongBacking({required this.engine, required this.prefs, required this.library});

  final LoopinEngine engine;
  final Prefs prefs;
  final SongLibrary library;

  /// Consultas al motor (30 por segundo) que se espera desde el último cambio
  /// de tempo antes de volver a estirarla: si se pulsa + varias veces
  /// seguidas, solo se prepara la última.
  static const settleTicks = 10;

  Song? current;
  bool on = false;
  double volume = 0.7;

  /// La fila de abajo enseña la canción (si no, la batería).
  bool showSong = false;

  _Key? _loaded; // lo que está sonando (o listo para sonar)
  _Key? _pending; // lo pedido y aún sin acabar
  _Key? _wanted; // lo que haría falta, desde hace _wantedTicks consultas
  int _wantedTicks = 0;
  _Key? _failedKey;
  SongError error = SongError.none;

  Future<void> load() async {
    await library.load();
    on = await prefs.getBool(Prefs.backingOn) ?? false;
    showSong = (await prefs.get(Prefs.accompaniment)) == 'song';
    final v = double.tryParse(await prefs.get(Prefs.backingVolume) ?? '');
    if (v != null) volume = v.clamp(0.0, 1.5);
    final id = int.tryParse(await prefs.get(Prefs.songId) ?? '');
    current = id == null ? null : library.byId(id);
  }

  /// Al abrir el audio (el motor empieza sin nada)
  void apply() {
    engine.setBackingVolume(volume);
    engine.setBackingEnabled(on);
    _loaded = _pending = _wanted = null;
  }

  void select(Song? song) {
    current = song;
    prefs.set(Prefs.songId, song == null ? '' : '${song.id}');
    _failedKey = null;
    error = SongError.none;
    if (song == null) {
      engine.backingUnload();
      _loaded = _pending = _wanted = null;
    }
  }

  /// La canción ha cambiado (se ha vuelto a preparar a mano).
  void updated(Song song) {
    if (current?.id == song.id) {
      current = song;
      _failedKey = null;
    }
  }

  void setOn(bool value) {
    on = value;
    engine.setBackingEnabled(value);
    prefs.setBool(Prefs.backingOn, value);
  }

  void setVolume(double v) {
    volume = v.clamp(0.0, 1.5);
    engine.setBackingVolume(volume);
  }

  void saveVolume() => prefs.set(Prefs.backingVolume, volume.toStringAsFixed(2));

  void setShowSong(bool value) {
    showSong = value;
    prefs.set(Prefs.accompaniment, value ? 'song' : 'drums');
  }

  _Key? _keyFor(EngineStatus s) {
    final song = current;
    if (song == null || !song.ready || !s.running) return null;
    if (s.samplesPerBeat <= 0 || s.beatsPerBar <= 0 || s.sampleRate <= 0) return null;
    return (
      id: song.id,
      bpm: song.bpm,
      mark: song.mark,
      spb: s.samplesPerBeat,
      bpb: s.beatsPerBar,
      rate: s.sampleRate,
    );
  }

  /// En cada consulta al motor. Devuelve true si cambia algo que se ve.
  bool tick(EngineStatus s) {
    final key = _keyFor(s);
    final song = current;
    if (key == null || song == null) return false;
    var changed = false;
    // ¿Ha acabado lo pedido?
    final pending = _pending;
    if (pending != null && s.songPrepId == song.id) {
      // (y que lo cargado sea lo pedido: el estado de antes puede seguir ahí)
      if (s.songPrepState == JobState.done &&
          s.backingId == song.id &&
          s.backingSamplesPerBeat == pending.spb &&
          s.backingBeatsPerBar == pending.bpb) {
        _loaded = pending;
        _pending = null;
        changed = true;
      } else if (s.songPrepState == JobState.failed) {
        _failedKey = pending;
        error = s.songPrepError;
        _pending = null;
        changed = true;
      }
    }
    // El motor ya no tiene lo que se cargó (se ha reabierto el audio a otra
    // frecuencia, o ha llegado otra versión)
    final loaded = _loaded;
    if (loaded != null &&
        _pending == null &&
        (s.backingId != song.id ||
            s.backingSamplesPerBeat != loaded.spb ||
            s.backingBeatsPerBar != loaded.bpb)) {
      _loaded = null;
      changed = true;
    }
    // Se ha vuelto al tempo de lo que suena antes de que acabe la otra: fuera
    if (_loaded == key && _pending != null) {
      engine.backingCancel();
      _pending = null;
      changed = true;
    }
    if (_loaded == key || _pending == key || _failedKey == key) return changed;
    // Hace falta otra: se pide cuando el tempo deja de cambiar
    if (_wanted != key) {
      _wanted = key;
      _wantedTicks = 0;
      return true;
    }
    if (++_wantedTicks < settleTicks) return changed;
    final path = library.pathOf(song);
    if (path == null) return changed;
    engine.backingPrepare(
      path: path,
      songBpm: song.bpm,
      markSeconds: song.mark,
      samplesPerBeat: key.spb,
      beatsPerBar: key.bpb,
      id: song.id,
    );
    _pending = key;
    _failedKey = null;
    error = SongError.none;
    return true;
  }

  BackingPhase phase(EngineStatus s) {
    final song = current;
    if (song == null) return BackingPhase.noSong;
    if (!song.ready) return BackingPhase.needsSetup;
    final key = _keyFor(s);
    if (key != null && _failedKey == key) {
      return error == SongError.tempo ? BackingPhase.tooFar : BackingPhase.failed;
    }
    if (key != null && _loaded == key && s.backingId == song.id && s.backingFits) {
      return BackingPhase.ready;
    }
    return BackingPhase.preparing;
  }

  /// Lo que lleva preparado (0–1), si se está preparando.
  double progress(EngineStatus s) {
    final song = current;
    if (song == null || _pending == null || s.songPrepId != song.id) return 0;
    return s.songPrepState == JobState.running ? s.songPrepProgress : 0;
  }

  /// A qué velocidad suena respecto a la suya (1 = su tempo), con el tempo de
  /// ahora. null si no se sabe.
  double? speed(EngineStatus s) {
    final song = current;
    if (song == null || !song.ready || s.samplesPerBeat <= 0 || s.sampleRate <= 0) return null;
    return s.sampleRate * 60 / song.bpm / s.samplesPerBeat;
  }

  @visibleForTesting
  bool get hasPending => _pending != null;
}
