// Loopin — sesiones guardadas: las pistas grabadas con todo lo que hace
// falta para que vuelvan a sonar igual (Etapa 6)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Cada sesión es una carpeta dentro de la de la app: `session.json` y un WAV
// por pista (`pista1.wav`…, mono en float de 32 bits). Se guardan solas
// (ver session_control.dart).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'wav.dart';

/// Una pista de una sesión.
class SessionTrack {
  const SessionTrack({
    required this.length,
    this.offset = 0,
    this.layers = 1,
    this.volume = 1,
    this.muted = false,
    this.reverse = false,
    this.half = false,
  });

  factory SessionTrack.fromJson(Map<String, Object?> j) => SessionTrack(
    length: (j['length'] as num).toInt(),
    offset: (j['offset'] as num?)?.toInt() ?? 0,
    layers: (j['layers'] as num?)?.toInt() ?? 1,
    volume: (j['volume'] as num?)?.toDouble() ?? 1,
    muted: j['muted'] == true,
    reverse: j['reverse'] == true,
    half: j['half'] == true,
  );

  /// Muestras (a la frecuencia de la sesión).
  final int length;

  /// Dónde empieza respecto al ciclo base (muestras).
  final int offset;
  final int layers;
  final double volume;
  final bool muted;
  final bool reverse;
  final bool half;

  Map<String, Object?> toJson() => {
    'length': length,
    'offset': offset,
    'layers': layers,
    'volume': volume,
    'muted': muted,
    'reverse': reverse,
    'half': half,
  };

  /// Nombre del archivo de la pista i (de 0 a 3).
  static String file(int i) => 'pista${i + 1}.wav';
}

/// Una sesión: pistas, tempo, compás, batería y canción.
class Session {
  const Session({
    required this.id,
    required this.name,
    required this.created,
    required this.updated,
    this.sampleRate = 0,
    this.bpm = 0,
    this.meter = '4/4',
    this.barFrames = 0,
    this.baseLength = 0,
    this.selected = 0,
    this.tracks = const [null, null, null, null],
    this.drumsOn = false,
    this.drumStyle,
    this.drumVolume,
    this.songId,
    this.songOn = false,
    this.songVolume,
  });

  factory Session.fromJson(String id, Map<String, Object?> j) {
    final list = (j['tracks'] as List?) ?? const [];
    final drums = (j['drums'] as Map?)?.cast<String, Object?>();
    final song = (j['song'] as Map?)?.cast<String, Object?>();
    return Session(
      id: id,
      name: (j['name'] as String?) ?? '',
      created: DateTime.fromMillisecondsSinceEpoch((j['created'] as num?)?.toInt() ?? 0),
      updated: DateTime.fromMillisecondsSinceEpoch((j['updated'] as num?)?.toInt() ?? 0),
      sampleRate: (j['sampleRate'] as num?)?.toInt() ?? 0,
      bpm: (j['bpm'] as num?)?.toDouble() ?? 0,
      meter: (j['meter'] as String?) ?? '4/4',
      barFrames: (j['barFrames'] as num?)?.toInt() ?? 0,
      baseLength: (j['baseLength'] as num?)?.toInt() ?? 0,
      selected: (j['selected'] as num?)?.toInt() ?? 0,
      tracks: [
        for (var i = 0; i < 4; i++)
          i < list.length && list[i] is Map
              ? SessionTrack.fromJson((list[i] as Map).cast<String, Object?>())
              : null,
      ],
      drumsOn: drums?['on'] == true,
      drumStyle: drums?['style'] as String?,
      drumVolume: (drums?['volume'] as num?)?.toDouble(),
      songId: (song?['id'] as num?)?.toInt(),
      songOn: song?['on'] == true,
      songVolume: (song?['volume'] as num?)?.toDouble(),
    );
  }

  /// La carpeta (no cambia nunca).
  final String id;
  final String name;
  final DateTime created;
  final DateTime updated;

  /// Frecuencia a la que están las pistas.
  final int sampleRate;
  final double bpm;

  /// Etiqueta del compás («7/8»).
  final String meter;
  final int barFrames;
  final int baseLength;
  final int selected;

  /// Las 4 pistas (null = vacía).
  final List<SessionTrack?> tracks;

  final bool drumsOn;
  final String? drumStyle;
  final double? drumVolume;

  /// La canción (id de la lista de canciones), o null.
  final int? songId;
  final bool songOn;
  final double? songVolume;

  int get trackCount => tracks.where((t) => t != null).length;
  bool get hasTracks => trackCount > 0;

  /// Compases de la base y del ciclo entero (la pista más larga).
  int get baseBars => barFrames > 0 ? (baseLength / barFrames).round() : 0;
  int get cycleBars {
    final longest = tracks.fold<int>(0, (m, t) => math.max(m, t?.length ?? 0));
    return barFrames > 0 ? (longest / barFrames).round() : 0;
  }

  /// Lo que dura el ciclo entero, en segundos.
  double get cycleSeconds {
    final longest = tracks.fold<int>(0, (m, t) => math.max(m, t?.length ?? 0));
    return sampleRate > 0 ? longest / sampleRate : 0;
  }

  Session copyWith({String? name, DateTime? updated}) => Session(
    id: id,
    name: name ?? this.name,
    created: created,
    updated: updated ?? this.updated,
    sampleRate: sampleRate,
    bpm: bpm,
    meter: meter,
    barFrames: barFrames,
    baseLength: baseLength,
    selected: selected,
    tracks: tracks,
    drumsOn: drumsOn,
    drumStyle: drumStyle,
    drumVolume: drumVolume,
    songId: songId,
    songOn: songOn,
    songVolume: songVolume,
  );

  /// Lo mismo con otro id (para duplicarla).
  Session withId(String newId, {required String name, required DateTime now}) => Session(
    id: newId,
    name: name,
    created: now,
    updated: now,
    sampleRate: sampleRate,
    bpm: bpm,
    meter: meter,
    barFrames: barFrames,
    baseLength: baseLength,
    selected: selected,
    tracks: tracks,
    drumsOn: drumsOn,
    drumStyle: drumStyle,
    drumVolume: drumVolume,
    songId: songId,
    songOn: songOn,
    songVolume: songVolume,
  );

  /// Lo que cuenta para saber si hay que guardar (todo menos nombre y fechas).
  Map<String, Object?> contentJson() => {
    'sampleRate': sampleRate,
    'bpm': bpm,
    'meter': meter,
    'barFrames': barFrames,
    'baseLength': baseLength,
    'selected': selected,
    'tracks': [for (final t in tracks) t?.toJson()],
    'drums': {'on': drumsOn, 'style': drumStyle, 'volume': drumVolume},
    'song': songId == null ? null : {'id': songId, 'on': songOn, 'volume': songVolume},
  };

  Map<String, Object?> toJson() => {
    'version': 1,
    'name': name,
    'created': created.millisecondsSinceEpoch,
    'updated': updated.millisecondsSinceEpoch,
    ...contentJson(),
  };
}

/// Las sesiones guardadas: una carpeta por sesión dentro de [dir].
class SessionLibrary {
  SessionLibrary({Future<String?> Function()? folder}) : _folder = folder ?? _androidFolder;

  static const _channel = MethodChannel('loopin/permissions');

  static Future<String?> _androidFolder() async {
    try {
      return await _channel.invokeMethod<String>('sessionsDir');
    } on Object {
      return null; // en un test sin Android
    }
  }

  final Future<String?> Function() _folder;
  String? _dir;

  /// La carpeta (null si no hay: no se guarda nada).
  String? get dir => _dir;

  Future<String?> load() async => _dir ??= await _folder();

  String? _path(String id, [String? file]) {
    final d = _dir;
    if (d == null) return null;
    return file == null ? '$d/$id' : '$d/$id/$file';
  }

  /// Un id nuevo (también es el nombre de la carpeta).
  String newId(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    final base =
        '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    var id = base;
    var k = 2;
    while (_dir != null && Directory(_path(id)!).existsSync()) {
      id = '$base-${k++}';
    }
    return id;
  }

  bool exists(String id) {
    final p = _path(id, 'session.json');
    return p != null && File(p).existsSync();
  }

  Future<Session?> read(String id) async {
    final p = _path(id, 'session.json');
    if (p == null) return null;
    try {
      final f = File(p);
      if (!await f.exists()) return null;
      final j = (jsonDecode(await f.readAsString()) as Map).cast<String, Object?>();
      return Session.fromJson(id, j);
    } on Object {
      return null; // estropeada
    }
  }

  /// Todas, la última que se tocó primero. Las vacías no salen (salvo
  /// [keep], la que está abierta).
  Future<List<Session>> list({String? keep}) async {
    final d = _dir;
    if (d == null) return const [];
    final out = <Session>[];
    try {
      await for (final e in Directory(d).list()) {
        if (e is! Directory) continue;
        final id = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final s = await read(id);
        if (s != null && (s.hasTracks || id == keep)) out.add(s);
      }
    } on Object {
      return out;
    }
    out.sort((a, b) => b.updated.compareTo(a.updated));
    return out;
  }

  Future<void> writeJson(Session s) async {
    final p = _path(s.id, 'session.json');
    if (p == null) return;
    await Directory(_path(s.id)!).create(recursive: true);
    final tmp = File('$p.tmp');
    await tmp.writeAsString(jsonEncode(s.toJson()));
    await tmp.rename(p);
  }

  Future<void> writeTrack(String id, int track, Float32List samples, int sampleRate) async {
    final p = _path(id, SessionTrack.file(track));
    if (p == null) return;
    await Directory(_path(id)!).create(recursive: true);
    final tmp = File('$p.tmp');
    await tmp.writeAsBytes(encodeWavFloat(samples, sampleRate), flush: true);
    await tmp.rename(p);
  }

  Future<void> deleteTrack(String id, int track) async {
    final p = _path(id, SessionTrack.file(track));
    if (p == null) return;
    try {
      await File(p).delete();
    } on Object {
      // ya no estaba
    }
  }

  /// Lo grabado en una pista (null si falta o está estropeada).
  Future<WavData?> readTrack(String id, int track) async {
    final p = _path(id, SessionTrack.file(track));
    if (p == null) return null;
    try {
      return decodeWav(await File(p).readAsBytes());
    } on Object {
      return null;
    }
  }

  Future<void> delete(String id) async {
    final p = _path(id);
    if (p == null) return;
    try {
      await Directory(p).delete(recursive: true);
    } on Object {
      // ya no estaba
    }
  }

  /// Copia una sesión con otro nombre. Devuelve la copia (null si no se pudo).
  Future<Session?> duplicate(Session s, {required String name, required DateTime now}) async {
    final from = _path(s.id);
    if (from == null) return null;
    final copy = s.withId(newId(now), name: name, now: now);
    await Directory(_path(copy.id)!).create(recursive: true);
    for (var i = 0; i < 4; i++) {
      final f = File('$from/${SessionTrack.file(i)}');
      if (s.tracks[i] != null && await f.exists()) {
        await f.copy(_path(copy.id, SessionTrack.file(i))!);
      }
    }
    await writeJson(copy);
    return copy;
  }

  /// Borra las sesiones sin pistas (menos [keep]).
  Future<void> purgeEmpty({String? keep}) async {
    final d = _dir;
    if (d == null) return;
    try {
      await for (final e in Directory(d).list()) {
        if (e is! Directory) continue;
        final id = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (id == keep) continue;
        final s = await read(id);
        if (s != null && !s.hasTracks) await delete(id);
      }
    } on Object {
      // nada que limpiar
    }
  }
}
