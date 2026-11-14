// Loopin — sesiones: se guardan solas, como las notas (Etapa 6)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Parte de engine_controller.dart (comparte sus campos privados). Cómo se
// guardan en disco: storage/sessions.dart.
//
// Siempre hay una sesión abierta. Lo grabado y sus ajustes (tempo, compás,
// volumen, silencio, REV y ½ de cada pista, batería y canción) se guardan
// solos, poco después de cada cambio, cuando las pistas están quietas (no se
// graba ni se borra). Al abrir la app vuelve la última. Una sesión sin
// pistas no sale en la lista y se borra al dejarla.
part of 'engine_controller.dart';

class _SessionState {
  /// La que está abierta.
  Session? current;

  /// Ya tiene su carpeta.
  bool onDisk = false;

  /// Se ha leído cuál era la última (y la carpeta).
  bool ready = false;

  /// El audio se acaba de abrir: si el motor no tiene las pistas, se cargan.
  bool restorePending = false;
  bool loading = false;
  bool saving = false;

  /// La carga no ha salido (el motor no la ha aceptado).
  bool loadFailed = false;

  /// Lo último que se ha guardado.
  int savedRevision = -1;
  List<int?> savedHashes = List.filled(kTrackCount, null);
  String savedContent = '';
  int ticks = 0;

  /// Las de la lista (sin la abierta si está vacía).
  List<Session> list = const [];

  // Exportar
  List<String> exportFiles = const [];
}

extension SessionControl on EngineController {
  _SessionState get _ss => _sessions;

  /// La sesión abierta.
  Session? get session => _ss.current;
  String get sessionName => _ss.current?.name ?? '';

  /// Las guardadas, la última que se tocó primero (ver [refreshSessions]).
  List<Session> get savedSessions => _ss.list;

  /// Se está abriendo una sesión (el pulsador no hace nada).
  bool get sessionLoading => _ss.loading;
  bool get sessionLoadFailed => _ss.loadFailed;

  /// Se puede cambiar de sesión (no mientras se graba ni se abre otra).
  bool get canSwitchSession => !_ss.loading && !recordingNow;

  Future<void> _loadSessions() async {
    await _library.load();
    final id = await _prefs.get(Prefs.sessionId);
    final s = id == null ? null : await _library.read(id);
    if (s != null) {
      _ss.current = s;
      _ss.onDisk = true;
    } else {
      _ss.current = _freshSession();
      _prefs.set(Prefs.sessionId, _ss.current!.id);
    }
    await _library.purgeEmpty(keep: _ss.current!.id);
    _ss.ready = true;
    await refreshSessions();
  }

  Session _freshSession() {
    final now = DateTime.now();
    return Session(
      id: _library.newId(now),
      name: tr.sessionDefaultName(now),
      created: now,
      updated: now,
    );
  }

  /// Vuelve a leer la lista.
  Future<void> refreshSessions() async {
    if (!_ss.ready) return;
    _ss.list = await _library.list(keep: _ss.onDisk ? _ss.current?.id : null);
    notifyListeners();
  }

  /// En cada consulta al motor (30 por segundo): cargar lo que falte y, cada
  /// medio segundo, guardar si ha cambiado algo.
  void _sessionTick() {
    final ss = _ss;
    if (!ss.ready || ss.loading || !status.running) return;
    if (ss.restorePending) {
      ss.restorePending = false;
      final cur = ss.current;
      // Al abrir la app, o si el audio se ha reabierto a otra frecuencia (las
      // pistas se pierden en el motor): vuelven de la carpeta
      if (cur != null && ss.onDisk && cur.hasTracks && status.loopState == LoopState.empty) {
        unawaited(_openSessionNow(cur, saveFirst: false));
        return;
      }
    }
    if (++ss.ticks % 15 != 0) return;
    _autosave();
  }

  /// La sesión tal como está ahora en el motor y en los ajustes.
  Session _sessionNow(Session cur) {
    final s = status;
    final hasLoops = s.hasLoops;
    final forced = simple ? _forced : SimpleForced();
    return Session(
      id: cur.id,
      name: cur.name,
      created: cur.created,
      updated: cur.updated,
      sampleRate: s.sampleRate,
      bpm: hasLoops ? s.bpm : bpm,
      meter: timeSignature.label,
      barFrames: hasLoops ? s.loopBarFrames : 0,
      baseLength: s.baseLength,
      selected: s.selectedTrack,
      tracks: [
        for (var i = 0; i < kTrackCount; i++)
          s.tracks[i].hasLoop
              ? SessionTrack(
                  length: s.tracks[i].length,
                  offset: s.tracks[i].offset,
                  layers: s.tracks[i].layers,
                  volume: trackVolumes[i],
                  muted: s.tracks[i].muted,
                  reverse: s.tracks[i].reverse,
                  half: s.tracks[i].half,
                )
              : null,
      ],
      // En simple la batería y la canción están apagadas por el modo: en la
      // sesión cuenta lo que tenían
      drumsOn: drumsOn || forced[SimpleForced.drumsOn] == '1',
      drumStyle: drumStyle.name,
      drumVolume: drumVolume,
      songId: currentSong?.id,
      songOn: backingOn || forced[SimpleForced.backingOn] == '1',
      songVolume: backingVolume,
    );
  }

  /// Guarda lo que haya cambiado (si las pistas están quietas). Lo grabado se
  /// lee ya y se escribe en segundo plano; solo las pistas que han cambiado.
  void _autosave({bool flush = false}) {
    final ss = _ss;
    final cur = ss.current;
    if (cur == null || ss.saving || !ss.ready || (ss.loading && !flush)) return;
    final s = status;
    if (!s.running || !s.loopSettled) return;
    final next = _sessionNow(cur);
    final content = jsonEncode(next.contentJson());
    final revChanged = s.loopRevision != ss.savedRevision;
    if (!revChanged && content == ss.savedContent) return;
    // Sin pistas y sin carpeta: nada que guardar todavía
    if (!next.hasTracks && !ss.onDisk) {
      ss.savedRevision = s.loopRevision;
      ss.savedContent = content;
      return;
    }
    final writes = <int, Float32List>{};
    final hashes = List<int?>.of(ss.savedHashes);
    for (var i = 0; i < kTrackCount; i++) {
      if (!s.tracks[i].hasLoop) {
        hashes[i] = null;
        continue;
      }
      final h = _engine.readTrack(i, samples: false);
      if (h == null) return; // ya no están quietas: en la siguiente
      if (h.hash == ss.savedHashes[i]) continue;
      final full = _engine.readTrack(i);
      final samples = full?.samples;
      if (full == null || samples == null || full.hash != h.hash) return;
      writes[i] = samples;
      hashes[i] = h.hash;
    }
    ss.saving = true;
    final rev = s.loopRevision;
    final rate = s.sampleRate;
    final before = List<int?>.of(ss.savedHashes);
    final firstTime = !ss.onDisk;
    unawaited(() async {
      try {
        for (final e in writes.entries) {
          await _library.writeTrack(cur.id, e.key, e.value, rate);
        }
        for (var i = 0; i < kTrackCount; i++) {
          if (hashes[i] == null && before[i] != null) await _library.deleteTrack(cur.id, i);
        }
        final saved = next.copyWith(updated: DateTime.now());
        await _library.writeJson(saved);
        if (ss.current?.id == saved.id) {
          ss.current = saved.copyWith(name: ss.current!.name);
          ss.onDisk = true;
        }
        ss.savedRevision = rev;
        ss.savedContent = content;
        ss.savedHashes = hashes;
        if (firstTime) unawaited(refreshSessions());
      } on Object {
        // No se ha podido (sin sitio…): se reintenta en el siguiente
      } finally {
        ss.saving = false;
      }
    }());
  }

  Future<void> _waitSaved() async {
    for (var k = 0; k < 500 && _ss.saving; k++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Guarda ya lo pendiente (antes de cambiar de sesión o de salir).
  Future<void> _flushSave() async {
    await _waitSaved();
    _autosave(flush: true);
    await _waitSaved();
  }

  /// Al salir de la app: se guarda lo que haya (la escritura sigue sola).
  void _saveOnHide() => _autosave(flush: true);

  /// Abre otra sesión (la de ahora ya está guardada).
  Future<bool> openSession(Session target) async {
    if (!canSwitchSession) return false;
    if (target.id == _ss.current?.id) return true;
    return _openSessionNow(target);
  }

  Future<bool> _openSessionNow(Session target, {bool saveFirst = true}) async {
    final ss = _ss;
    if (ss.loading) return false;
    ss.loading = true;
    ss.loadFailed = false;
    notifyListeners();
    var ok = true;
    try {
      if (saveFirst) await _flushSave();
      final leaving = ss.current;
      // Lo grabado, de la carpeta
      final data = <Float32List?>[];
      for (var i = 0; i < kTrackCount; i++) {
        final t = target.tracks[i];
        final wav = t == null ? null : await _library.readTrack(target.id, i);
        data.add(
          wav == null || wav.samples.length < t!.length
              ? null
              : Float32List.sublistView(wav.samples, 0, t.length),
        );
      }
      // Todo parado y sin pistas
      _wantPlaying = false;
      _engine.pause();
      _engine.loopClear();
      if (leaving != null && leaving.id != target.id && !leaving.hasTracks) {
        await _library.delete(leaving.id);
      }
      ss.current = target;
      ss.onDisk = true;
      ss.savedHashes = List.filled(kTrackCount, null);
      ss.savedContent = '';
      _prefs.set(Prefs.sessionId, target.id);
      final ts = kTimeSignatures.firstWhere(
        (t) => t.label == target.meter,
        orElse: () => timeSignature,
      );
      final lengths = [
        for (var i = 0; i < kTrackCount; i++) data[i] == null ? 0 : target.tracks[i]!.length,
      ];
      if (lengths.any((l) => l > 0) && target.barFrames > 0 && target.bpm > 0) {
        final audio = SessionAudio(
          bpm: target.bpm,
          beatsPerBar: ts.beats,
          accentMask: ts.accentMask,
          sampleRate: target.sampleRate,
          barFrames: target.barFrames,
          baseLength: target.baseLength,
          lengths: lengths,
          offsets: [for (final t in target.tracks) t?.offset ?? 0],
          layers: [for (final t in target.tracks) t?.layers ?? 0],
          data: data,
          selected: target.selected,
        );
        // Espera a que el motor haya borrado todo y carga
        var code = kSessionNotReady;
        for (var k = 0; k < 150 && code == kSessionNotReady; k++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          final st = _engine.status();
          if (!st.running || st.loopState != LoopState.empty || !st.loopSettled) continue;
          code = _engine.loadSession(audio);
        }
        ok = code == 0;
        if (ok) {
          // Hasta que el motor diga que las tiene; entonces lo guardado es eso
          for (var k = 0; k < 100; k++) {
            final st = _engine.status();
            if (st.hasLoops && st.loopSettled) {
              status = st;
              final hashes = List<int?>.filled(kTrackCount, null);
              for (var i = 0; i < kTrackCount; i++) {
                if (st.tracks[i].hasLoop) hashes[i] = _engine.readTrack(i, samples: false)?.hash;
              }
              // A otra frecuencia se vuelven a escribir (el motor las ha pasado a la suya)
              if (st.sampleRate == target.sampleRate) ss.savedHashes = hashes;
              ss.savedRevision = st.loopRevision;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        }
      }
      _applySessionSettings(target, ts);
    } on Object {
      ok = false;
    } finally {
      ss.loading = false;
      ss.loadFailed = !ok;
    }
    notifyListeners();
    unawaited(refreshSessions());
    return ok;
  }

  /// Tempo, compás, volúmenes, silencio y efectos, batería y canción.
  void _applySessionSettings(Session s, TimeSignature ts) {
    if (s.bpm > 0) {
      bpm = s.bpm;
      _prefs.set(Prefs.bpm, bpm.toStringAsFixed(2));
    }
    timeSignature = ts;
    _prefs.set(Prefs.meter, ts.label);
    _engine.setBpm(bpm);
    _engine.setMeter(ts.beats, ts.accentMask);
    for (var i = 0; i < kTrackCount; i++) {
      final t = s.tracks[i];
      trackVolumes[i] = t?.volume ?? 1.0;
      _engine.setTrackVolume(i, trackVolumes[i]);
      _engine.setTrackMuted(i, t?.muted ?? false);
      if (t != null && trackFxShown) {
        // Con todo parado se aplican al momento
        if (t.reverse) _engine.setTrackReverse(i, true);
        if (t.half) _engine.setTrackHalf(i, true);
      }
    }
    // Batería
    final style = DrumStyle.values.where((d) => d.name == s.drumStyle);
    if (style.isNotEmpty) {
      drumStyle = style.first;
      _prefs.set(Prefs.drumStyle, drumStyle.name);
    }
    _applyDrumStyle();
    if (s.drumVolume != null) {
      drumVolume = s.drumVolume!.clamp(0.0, 1.5);
      _engine.setDrumVolume(drumVolume);
      saveDrumVolume();
    }
    // En simple no suenan: se apunta para cuando se vuelva al avanzado. No
    // arranca nada (suenan al darle a ▶ o al grabar).
    if (simple) {
      _forced.values.remove(SimpleForced.drumsOn);
      if (s.drumsOn) _forced.remember(SimpleForced.drumsOn, '1');
    } else if (drumsOn != s.drumsOn) {
      drumsOn = s.drumsOn;
      _engine.setDrumsEnabled(drumsOn);
      _prefs.setBool(Prefs.drumsOn, drumsOn);
    }
    // Canción
    final song = s.songId == null ? null : _backing.library.byId(s.songId!);
    if (song?.id != currentSong?.id) _backing.select(song);
    if (s.songVolume != null) {
      _backing.setVolume(s.songVolume!.clamp(0.0, 1.5));
      _backing.saveVolume();
    }
    final songOn = song != null && s.songOn;
    if (simple) {
      _forced.values.remove(SimpleForced.backingOn);
      if (songOn) _forced.remember(SimpleForced.backingOn, '1');
    } else if (backingOn != songOn) {
      _backing.setOn(songOn);
    }
    if (simple) _saveForced();
  }

  /// Empieza una sesión nueva, vacía (la de ahora queda guardada).
  Future<void> newSession() async {
    if (!canSwitchSession) return;
    final ss = _ss;
    ss.loading = true;
    notifyListeners();
    try {
      await _flushSave();
      final leaving = ss.current;
      _clearForNewSession();
      if (leaving != null && !leaving.hasTracks) await _library.delete(leaving.id);
    } finally {
      ss.loading = false;
    }
    notifyListeners();
    unawaited(refreshSessions());
  }

  void _clearForNewSession() {
    final ss = _ss;
    _wantPlaying = false;
    _engine.pause();
    _engine.loopClear();
    for (var i = 0; i < kTrackCount; i++) {
      trackVolumes[i] = 1.0;
      _engine.setTrackVolume(i, 1.0);
      _engine.setTrackMuted(i, false);
    }
    ss.current = _freshSession();
    ss.onDisk = false;
    ss.savedHashes = List.filled(kTrackCount, null);
    ss.savedContent = '';
    _prefs.set(Prefs.sessionId, ss.current!.id);
  }

  /// Cambia el nombre (de la abierta o de otra).
  Future<void> renameSession(Session s, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    if (s.id == _ss.current?.id) {
      await _waitSaved();
      final renamed = _ss.current!.copyWith(name: clean);
      _ss.current = renamed;
      // Aunque esté vacía: así el nombre se queda
      await _library.writeJson(_ss.onDisk ? renamed : _sessionNow(renamed));
      _ss.onDisk = true;
    } else {
      await _library.writeJson(s.copyWith(name: clean));
    }
    notifyListeners();
    await refreshSessions();
  }

  /// Hace una copia (no se abre: sigue la de ahora).
  Future<Session?> duplicateSession(Session s) async {
    var from = s;
    if (s.id == _ss.current?.id) {
      await _flushSave();
      if (!_ss.onDisk) return null;
      from = _ss.current!;
    }
    final copy = await _library.duplicate(
      from,
      name: tr.sessionCopyName(from.name),
      now: DateTime.now(),
    );
    await refreshSessions();
    return copy;
  }

  /// Borra una sesión. Si es la abierta, se borran sus pistas y se empieza
  /// otra vacía.
  Future<void> deleteSession(Session s) async {
    if (s.id == _ss.current?.id) {
      if (!canSwitchSession) return;
      _ss.loading = true;
      notifyListeners();
      try {
        await _waitSaved();
        _clearForNewSession();
        await _library.delete(s.id);
      } finally {
        _ss.loading = false;
      }
    } else {
      await _library.delete(s.id);
    }
    notifyListeners();
    await refreshSessions();
  }
}
