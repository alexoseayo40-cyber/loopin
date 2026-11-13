// Loopin — exportar la sesión a WAV y compartirla (Etapa 6)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Parte de engine_controller.dart. El motor exporta en segundo plano lo que
// suena (ver Export.h); aquí se eligen los archivos y se comparten.
part of 'engine_controller.dart';

/// Vueltas del ciclo entero que se pueden exportar.
const List<int> kExportLoops = [1, 2, 4, 8];

/// Lo más largo que se exporta (10 min).
const int kExportMaxSeconds = 600;

extension ExportControl on EngineController {
  /// Hay algo que exportar y las pistas están quietas.
  bool get canExport => status.running && status.hasLoops && !recordingNow && !_ss.loading;

  /// La batería y la canción suenan (se pueden quitar de lo exportado).
  bool get exportCanDrums => drumsOn;
  bool get exportCanSong => backingOn && status.backingFits;

  /// Lo que dura una vuelta del ciclo entero (la pista más larga), en s.
  double get cycleSeconds {
    final s = status;
    if (s.sampleRate <= 0) return 0;
    final longest = s.tracks.fold<int>(0, (m, t) => math.max(m, t.length));
    return longest / s.sampleRate;
  }

  /// Las vueltas que caben en [kExportMaxSeconds].
  List<int> get exportLoopOptions {
    final cycle = cycleSeconds;
    final out = [
      for (final n in kExportLoops)
        if (cycle <= 0 || n == 1 || n * cycle <= kExportMaxSeconds) n,
    ];
    return out;
  }

  JobState get exportState => status.exportState;
  double get exportProgress => status.exportProgress;

  /// Lo que se ha exportado (ya escrito).
  List<String> get exportedFiles => [
    for (final f in _ss.exportFiles)
      if (File(f).existsSync()) f,
  ];

  /// Exporta. [mix]: lo que suena; [stems]: cada pista por separado (y la
  /// batería y la canción, si van). 0 si ha empezado; -1 si se está
  /// grabando; -2 sin pistas; -3 ya hay otra; -4 no hay dónde escribir.
  Future<int> startExport({
    required bool mix,
    required bool stems,
    required bool withDrums,
    required bool withSong,
    required int loops,
  }) async {
    if (!canExport) return -1;
    String? dir;
    try {
      dir = await EngineController._channel.invokeMethod<String>('exportsDir', {'clear': true});
    } on Object {
      dir = null;
    }
    dir ??= exportDirForTests;
    if (dir == null) return -4;
    final base = tr.exportFileBase(sessionName);
    final s = status;
    String path(String name) => '$dir/${tr.exportFileName(base, name)}';
    final drums = withDrums && exportCanDrums;
    final song = withSong && exportCanSong;
    final req = ExportRequest(
      loops: loops,
      withDrums: drums,
      withSong: song,
      mixPath: mix ? '$dir/$base.wav' : null,
      trackPaths: [
        for (var i = 0; i < kTrackCount; i++)
          stems && s.tracks[i].hasLoop ? path(tr.exportTrack(i + 1)) : null,
      ],
      drumsPath: stems && drums ? path(tr.exportDrums) : null,
      songPath: stems && song ? path(tr.exportSong) : null,
    );
    final code = _engine.exportStart(req);
    if (code == 0) {
      _ss.exportFiles = [
        ?req.mixPath,
        for (final p in req.trackPaths) ?p,
        ?req.drumsPath,
        ?req.songPath,
      ];
    }
    notifyListeners();
    return code;
  }

  void cancelExport() => _engine.exportCancel();

  /// Abre «Compartir» de Android con lo exportado.
  Future<void> shareExport() async {
    final files = exportedFiles;
    if (files.isEmpty) return;
    try {
      await EngineController._channel.invokeMethod<void>('shareFiles', {'paths': files});
    } on Object {
      // sin Android (tests) o sin apps para compartir
    }
  }

  /// Copia lo exportado en una carpeta que elige el usuario. Devuelve
  /// cuántos archivos (null si se cancela).
  Future<int?> saveExport() async {
    final files = exportedFiles;
    if (files.isEmpty) return 0;
    try {
      return await EngineController._channel.invokeMethod<int>('saveFiles', {'paths': files});
    } on PlatformException {
      return -1;
    } on Object {
      return null;
    }
  }
}
