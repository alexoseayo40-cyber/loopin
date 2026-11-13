// Loopin — canciones importadas: la lista y lo que se sabe de cada una
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Una canción importada. El archivo se copia dentro de la app al importarlo
/// (así sigue aunque se borre el original). Para que suene con los loops
/// hace falta su tempo y dónde cae un 1.
class Song {
  const Song({
    required this.id,
    required this.name,
    required this.file,
    this.bpm = 0,
    this.mark = 0,
    this.mark2,
    this.meter = '4/4',
    this.seconds = 0,
  });

  factory Song.fromJson(Map<String, Object?> j) => Song(
    id: (j['id'] as num).toInt(),
    name: (j['name'] as String?) ?? '',
    file: j['file'] as String,
    bpm: (j['bpm'] as num?)?.toDouble() ?? 0,
    mark: (j['mark'] as num?)?.toDouble() ?? 0,
    mark2: (j['mark2'] as num?)?.toDouble(),
    meter: (j['meter'] as String?) ?? '4/4',
    seconds: (j['seconds'] as num?)?.toDouble() ?? 0,
  );

  /// Distinto de 0 (es también el id que se le pasa al motor).
  final int id;
  final String name;

  /// Nombre del archivo dentro de la carpeta de canciones.
  final String file;

  /// Tempo de la canción (0 = aún sin preparar).
  final double bpm;

  /// Dónde cae un 1, en segundos desde el principio del archivo.
  final double mark;

  /// Otro 1 más adelante (para sacar el tempo exacto), o null.
  final double? mark2;

  /// Compás (la etiqueta de [TimeSignature]).
  final String meter;

  /// Duración en segundos (0 = no se sabe aún).
  final double seconds;

  /// Ya tiene tempo y 1: puede sonar con los loops.
  bool get ready => bpm > 0;

  Song copyWith({
    String? name,
    double? bpm,
    double? mark,
    double? Function()? mark2,
    String? meter,
    double? seconds,
  }) => Song(
    id: id,
    name: name ?? this.name,
    file: file,
    bpm: bpm ?? this.bpm,
    mark: mark ?? this.mark,
    mark2: mark2 != null ? mark2() : this.mark2,
    meter: meter ?? this.meter,
    seconds: seconds ?? this.seconds,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'file': file,
    'bpm': bpm,
    'mark': mark,
    if (mark2 != null) 'mark2': mark2,
    'meter': meter,
    'seconds': seconds,
  };

  /// El nombre del archivo sin la extensión (para mostrar).
  static String nameFromFile(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    return base.replaceAll('_', ' ').trim();
  }
}

/// Por qué no se ha podido importar.
enum ImportError {
  /// El archivo pesa demasiado.
  tooBig,

  /// No se ha podido copiar.
  copy,

  /// No hay donde guardarlo (no debería pasar).
  noStorage,
}

class ImportException implements Exception {
  const ImportException(this.error);
  final ImportError error;
}

/// La lista de canciones: los archivos en la carpeta `songs` de la app y un
/// `songs.json` con lo que se sabe de cada una.
class SongLibrary {
  SongLibrary({Future<String?> Function()? folder})
    : _folder = folder ?? _androidFolder,
      _memory = false;

  /// Solo en memoria, sin archivos (para los tests).
  SongLibrary.memory(List<Song> songs, {String? dir = '/canciones'})
    : _folder = _none,
      _memory = true {
    _dir = dir;
    _songs.addAll(songs);
  }

  static Future<String?> _none() async => null;
  final bool _memory;

  static const _channel = MethodChannel('loopin/permissions');

  static Future<String?> _androidFolder() async {
    try {
      return await _channel.invokeMethod<String>('songsDir');
    } on Object {
      return null; // en un test sin Android
    }
  }

  final Future<String?> Function() _folder;
  String? _dir;
  final List<Song> _songs = [];

  /// Las canciones, en el orden en que se importaron.
  List<Song> get songs => List.unmodifiable(_songs);

  /// La carpeta (null si no hay).
  String? get dir => _dir;

  Song? byId(int id) {
    for (final s in _songs) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Ruta completa del archivo de una canción.
  String? pathOf(Song s) => _dir == null ? null : '$_dir/${s.file}';

  Future<void> load() async {
    if (_memory) return;
    _dir = await _folder();
    _songs.clear();
    final dir = _dir;
    if (dir == null) return;
    try {
      final f = File('$dir/songs.json');
      if (!await f.exists()) return;
      final list = jsonDecode(await f.readAsString()) as List;
      for (final e in list) {
        final song = Song.fromJson((e as Map).cast<String, Object?>());
        // Si falta el archivo, la canción ya no sirve
        if (await File('$dir/${song.file}').exists()) _songs.add(song);
      }
    } on Object {
      // Lista estropeada: se empieza de cero (los archivos siguen ahí)
      _songs.clear();
    }
  }

  Future<void> _save() async {
    final dir = _dir;
    if (dir == null || _memory) return;
    final f = File('$dir/songs.json');
    final tmp = File('$dir/songs.json.tmp');
    await tmp.writeAsString(jsonEncode([for (final s in _songs) s.toJson()]));
    await tmp.rename(f.path);
  }

  int _nextId() => _songs.fold<int>(0, (m, s) => math.max(m, s.id)) + 1;

  /// Una canción nueva a partir de un archivo que ya está en la carpeta.
  Future<Song> add(String file, {String? name}) async {
    final song = Song(id: _nextId(), name: name ?? Song.nameFromFile(file), file: file);
    _songs.add(song);
    await _save();
    return song;
  }

  /// Abre el selector de archivos de Android y copia el elegido. Devuelve la
  /// canción nueva (null si se cancela). Lanza [ImportException].
  Future<Song?> import() async {
    if (_dir == null) await load();
    if (_dir == null) throw const ImportException(ImportError.noStorage);
    Map<Object?, Object?>? r;
    try {
      r = await _channel.invokeMapMethod<Object?, Object?>('pickAudio');
    } on PlatformException catch (e) {
      throw ImportException(e.code == 'tooBig' ? ImportError.tooBig : ImportError.copy);
    }
    if (r == null) return null;
    final file = r['file'] as String;
    return add(file, name: Song.nameFromFile((r['name'] as String?) ?? file));
  }

  Future<void> update(Song song) async {
    final i = _songs.indexWhere((s) => s.id == song.id);
    if (i < 0) return;
    _songs[i] = song;
    await _save();
  }

  Future<void> remove(Song song) async {
    _songs.removeWhere((s) => s.id == song.id);
    await _save();
    final path = pathOf(song);
    if (path == null || _memory) return;
    try {
      await File(path).delete();
    } on Object {
      // ya no estaba
    }
  }
}
