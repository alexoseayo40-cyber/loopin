// Loopin — el audio importado en la interfaz (Etapa 4b)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/engine/song_editor.dart';
import 'package:loopin/engine/songs.dart';
import 'package:loopin/engine/status_change.dart';
import 'package:loopin/l10n/strings.dart';
import 'package:loopin/ui/looper/accompaniment_row.dart';
import 'package:loopin/ui/looper_screen.dart';
import 'package:loopin/ui/song_screen.dart';
import 'package:loopin/ui/songs_screen.dart';
import 'package:loopin/ui/theme.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'support.dart';

Widget _app(Widget home) =>
    MaterialApp(theme: buildLoopinTheme(Chassis.classic, Brightness.dark), home: home);

const _ready = Song(
  id: 3,
  name: 'Mi canción',
  file: '3.mp3',
  bpm: 97.3,
  mark: 0.73,
  meter: '4/4',
  seconds: 225,
);
const _raw = Song(id: 4, name: 'Otra', file: '4.wav');

/// Un estado del motor con lo que se diga del audio importado.
EngineStatus _st({
  LoopState loop = LoopState.empty,
  bool playing = true,
  int spb = 31304,
  int bpb = 4,
  int prepId = 0,
  JobState prep = JobState.idle,
  double prepProgress = 0,
  SongError prepError = SongError.none,
  int backingId = 0,
  int backingSpb = 0,
  bool backingOn = false,
  bool backingPlaying = false,
  int openId = 0,
  JobState open = JobState.idle,
  int previewId = 0,
  bool previewPlaying = false,
  int previewPosition = 0,
}) {
  final b = fakeStatus(loop, playing: playing);
  return EngineStatus(
    running: true,
    sampleRate: 48000,
    playing: playing,
    bpm: 48000 * 60 / spb,
    beatsPerBar: bpb,
    samplesPerBeat: spb,
    inputDeviceId: b.inputDeviceId,
    outputDeviceId: b.outputDeviceId,
    outputLatencyMs: 40,
    loopState: loop,
    tracks: b.tracks,
    baseLength: b.baseLength,
    loopBarFrames: b.loopBarFrames,
    selectedTrack: b.selectedTrack,
    songPrepId: prepId,
    songPrepState: prep,
    songPrepProgress: prepProgress,
    songPrepError: prepError,
    backingId: backingId,
    backingSamplesPerBeat: backingSpb,
    backingBeatsPerBar: backingSpb > 0 ? bpb : 0,
    backingEnabled: backingOn,
    backingPlaying: backingPlaying,
    songOpenId: openId,
    songOpenState: open,
    songOpenFrames: open == JobState.done ? 48000 * 200 : 0,
    songBpmGuess: 120.04,
    songFirstAttack: 24000,
    previewId: previewId,
    previewPlaying: previewPlaying,
    previewPosition: previewPosition,
  );
}

/// Sin pumpAndSettle: la pantalla se mueve sin parar (sondeo del motor y luces)
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

// La batería y las canciones son del avanzado (en simple no se ven)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockPlatform);

  test('una canción se guarda y se lee igual', () {
    final s = _ready.copyWith(mark2: () => 60.25);
    final back = Song.fromJson(s.toJson());
    expect(back.toJson(), s.toJson());
    expect(back.mark2, 60.25);
    expect(_raw.ready, isFalse);
    expect(_ready.ready, isTrue);
    expect(Song.nameFromFile('Mi_tema.final.mp3'), 'Mi tema.final');
    expect(Song.nameFromFile('blues'), 'blues');
  });

  test('la lista guarda, cambia y borra (con su archivo)', () async {
    final dir = await Directory.systemTemp.createTemp('loopin_songs');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/a.mp3').writeAsStringSync('x');
    final lib = SongLibrary(folder: () async => dir.path);
    await lib.load();
    expect(lib.songs, isEmpty);
    final a = await lib.add('a.mp3');
    expect(a.id, 1);
    expect(a.name, 'a');
    expect(lib.pathOf(a), '${dir.path}/a.mp3');
    await lib.update(a.copyWith(bpm: 100, mark: 1.5));
    // Otra vez desde el disco
    final again = SongLibrary(folder: () async => dir.path);
    await again.load();
    expect(again.songs.single.bpm, 100);
    expect(again.songs.single.mark, 1.5);
    // Una cuyo archivo ya no está no sale
    final b = await again.add('b.wav');
    expect(b.id, 2);
    final third = SongLibrary(folder: () async => dir.path);
    await third.load();
    expect(third.songs.map((s) => s.file), ['a.mp3']);
    // Borrar quita también el archivo
    await third.remove(third.songs.single);
    expect(File('${dir.path}/a.mp3').existsSync(), isFalse);
    expect(third.songs, isEmpty);
  });

  testWidgets('elegir una canción pone su tempo y su compás; con loops, no', (tester) async {
    final engine = FakeEngine()..next = _st(playing: false);
    final c = EngineController(
      engine: engine,
      songs: SongLibrary.memory([_ready.copyWith(meter: '3/4'), _raw]),
    )..setPlayMode(PlayMode.advanced);
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.backingPhase, BackingPhase.noSong);
    c.selectSong(c.songs.first);
    expect(c.currentSong?.id, 3);
    expect(c.showSong, isTrue);
    expect(c.bpm, 97.3);
    expect(c.timeSignature.label, '3/4');
    expect(engine.calls, containsAll(['meter 3 0']));
    // Con loops grabados el tempo y el compás no cambian
    c.setTimeSignature(kTimeSignatures.first);
    engine.next = _st(loop: LoopState.playing, spb: 32000);
    await tester.pump(const Duration(milliseconds: 100));
    c.selectSong(_ready);
    expect(c.bpm, 90);
    expect(c.timeSignature.label, '4/4');
    // Una sin preparar se elige, pero no cambia nada
    c.selectSong(_raw);
    expect(c.backingPhase, BackingPhase.needsSetup);
    c.selectSong(null);
    expect(engine.calls.last, 'unload');
    c.stopAudio();
    c.dispose();
  });

  testWidgets('se prepara al tempo de ahora y otra vez si el tempo cambia', (tester) async {
    final engine = FakeEngine()..next = _st();
    final c = EngineController(engine: engine, songs: SongLibrary.memory([_ready]))
      ..setPlayMode(PlayMode.advanced);
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    c.selectSong(_ready); // con el transporte sonando: aquí no cambia nada más
    engine.calls.clear();
    // Espera a que el tempo deje de cambiar (unas 10 consultas)
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.calls.where((x) => x.startsWith('prepare')), isEmpty);
    expect(c.backingPhase, BackingPhase.preparing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.calls.where((x) => x.startsWith('prepare')), ['prepare 3 97.3 0.73 31304 4']);
    engine.next = _st(prepId: 3, prep: JobState.running, prepProgress: 0.4);
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.backingProgress, 0.4);
    engine.next = _st(prepId: 3, prep: JobState.done, backingId: 3, backingSpb: 31304);
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.backingPhase, BackingPhase.ready);
    expect(c.songSpeed, closeTo(48000 * 60 / 97.3 / 31304, 1e-9));
    // Otro tempo: se calla (lo hace el motor) y se vuelve a preparar
    engine.calls.clear();
    engine.next = _st(spb: 30000, prepId: 3, prep: JobState.done, backingId: 3, backingSpb: 31304);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.backingPhase, BackingPhase.preparing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.calls.where((x) => x.startsWith('prepare')), ['prepare 3 97.3 0.73 30000 4']);
    // Demasiado lejos de su tempo
    engine.next = _st(spb: 30000, prepId: 3, prep: JobState.failed, prepError: SongError.tempo);
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.backingPhase, BackingPhase.tooFar);
    // Y no se vuelve a intentar con el mismo tempo
    engine.calls.clear();
    await tester.pump(const Duration(milliseconds: 600));
    expect(engine.calls.where((x) => x.startsWith('prepare')), isEmpty);
    c.stopAudio();
    c.dispose();
  });

  testWidgets('volver a su tempo: botón en la lista y, si se vuelve antes de acabar, cancela', (
    tester,
  ) async {
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = _st(playing: false, spb: 29599);
    final c = EngineController(engine: engine, songs: SongLibrary.memory([_ready]))
      ..setPlayMode(PlayMode.advanced);
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    c.selectSong(_ready);
    expect(c.canRestoreSongTempo, isFalse); // ya está a su tempo
    // Preparada a su tempo
    await tester.pump(const Duration(milliseconds: 500));
    engine.next = _st(
      playing: false,
      spb: 29599,
      prepId: 3,
      prep: JobState.done,
      backingId: 3,
      backingSpb: 29599,
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.backingPhase, BackingPhase.ready);
    // Más despacio: se pide otra versión…
    c.setBpm(80);
    engine.next = _st(
      playing: false,
      spb: 36000,
      prepId: 3,
      prep: JobState.done,
      backingId: 3,
      backingSpb: 29599,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(engine.calls.last, startsWith('prepare 3 97.3 0.73 36000'));
    expect(c.canRestoreSongTempo, isTrue);
    // …y antes de que acabe se vuelve a su tempo: se cancela y sigue la que había
    engine.next = _st(
      playing: false,
      spb: 36000,
      prepId: 3,
      prep: JobState.running,
      backingId: 3,
      backingSpb: 29599,
    );
    await tester.pumpWidget(_app(SongsScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(tr.songRestoreTempo('97,3')), findsOneWidget);
    await tester.tap(find.text(tr.songRestoreTempo('97,3')));
    engine.next = _st(
      playing: false,
      spb: 29599,
      prepId: 3,
      prep: JobState.running,
      backingId: 3,
      backingSpb: 29599,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.bpm, 97.3);
    expect(engine.calls, contains('cancel'));
    expect(c.backingPhase, BackingPhase.ready);
    c.stopAudio();
    c.dispose();
  });

  testWidgets('encender la canción con todo parado arranca', (tester) async {
    final engine = FakeEngine()..next = _st(playing: false);
    final c = EngineController(engine: engine, songs: SongLibrary.memory([_ready]))
      ..setPlayMode(PlayMode.advanced);
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    // Al abrir el audio se le dice al motor cómo está
    expect(engine.calls, containsAll(['backingVolume 0.7', 'backing false']));
    engine.calls.clear();
    c.toggleBacking();
    expect(engine.calls, ['backing true', 'play']);
    c.stopAudio();
    c.dispose();
  });

  test('que entre, se prepare o se abra la canción redibuja la pantalla', () {
    final a = _st();
    expect(layoutChanged(a, _st(backingPlaying: true)), isTrue);
    expect(layoutChanged(a, _st(backingId: 3, backingSpb: 31304)), isTrue);
    expect(layoutChanged(a, _st(prepId: 3, prep: JobState.running)), isTrue);
    expect(layoutChanged(a, _st(open: JobState.done)), isTrue);
    expect(layoutChanged(a, _st(previewPlaying: true)), isTrue);
    // Por dónde va la vista previa no cuenta (se mueve sin parar)
    expect(layoutChanged(_st(previewPosition: 10), _st(previewPosition: 9000)), isFalse);
  });

  for (final size in const [Size(360, 640), Size(393, 873), Size(873, 393)]) {
    testWidgets(
      'fila: el selector cambia a la canción (${size.width.toInt()}x${size.height.toInt()})',
      (tester) async {
        setScreen(tester, size);
        final engine = FakeEngine()..next = _st();
        final c = EngineController(
          engine: engine,
          songs: SongLibrary.memory([
            _ready.copyWith(name: 'Un nombre larguísimo que no cabe en la fila de abajo'),
          ]),
        )..setPlayMode(PlayMode.advanced);
        await tester.pumpWidget(_app(LooperScreen(controller: c)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(AccompanimentRow), findsOneWidget);
        expect(find.text(tr.drumStyleChip(c.drumStyle)), findsOneWidget);
        await tester.tap(find.text(tr.accSong));
        await tester.pump();
        expect(c.showSong, isTrue);
        expect(find.text(tr.songChoose), findsOneWidget);
        // Con una elegida sale su nombre (cortado si no cabe) y su luz
        c.selectSong(c.songs.first);
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('UN NOMBRE'), findsOneWidget);
        c.setBackingVolume(1.1);
        await tester.pump();
        expect(
          tester
              .widget<Slider>(
                find.descendant(of: find.byType(AccompanimentRow), matching: find.byType(Slider)),
              )
              .value,
          1.1,
        );
        c.setBackingOn(true);
        engine.next = _st(backingOn: true);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byTooltip(tr.songBleed), findsOneWidget); // con el altavoz
        await tester.tap(find.text(tr.accDrums));
        await tester.pump();
        expect(c.showSong, isFalse);
        c.stopAudio();
        c.dispose();
      },
    );
  }

  testWidgets('lista: tocar una preparada la elige y vuelve; una sin preparar, a prepararla', (
    tester,
  ) async {
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = _st(playing: false);
    final c = EngineController(engine: engine, songs: SongLibrary.memory([_ready, _raw]))
      ..setPlayMode(PlayMode.advanced);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    c.setShowSong(true);
    await tester.pump();
    await tester.tap(find.text(tr.songChoose));
    await _settle(tester);
    expect(find.byType(SongsScreen), findsOneWidget);
    expect(find.text(tr.songSubtitle('97,3', '4/4', 225)), findsOneWidget);
    expect(find.text(tr.songNotReady), findsOneWidget);
    await tester.tap(find.text('Mi canción'));
    await _settle(tester);
    expect(find.byType(SongsScreen), findsNothing);
    expect(c.currentSong?.id, 3);
    expect(c.bpm, 97.3);
    expect(find.text('MI CANCIÓN'), findsOneWidget);
    // La otra no tiene tempo: se abre para prepararla
    await tester.tap(find.text('MI CANCIÓN'));
    await _settle(tester);
    await tester.tap(find.text('Otra'));
    await _settle(tester);
    expect(find.byType(SongScreen), findsOneWidget);
    expect(engine.calls, contains('open 4'));
    expect(find.textContaining('Abriendo'), findsOneWidget);
    c.stopAudio();
    c.dispose();
  });

  testWidgets('lista vacía: invita a importar', (tester) async {
    final engine = FakeEngine()..next = _st();
    final c = EngineController(engine: engine, songs: SongLibrary.memory([]))
      ..setPlayMode(PlayMode.advanced);
    await tester.pumpWidget(_app(SongsScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(tr.songsEmpty), findsOneWidget);
    expect(find.text(tr.songsImport), findsOneWidget);
    c.dispose();
  });

  testWidgets('preparar: sugiere, marca el 1, tempo exacto con dos unos y guardar', (tester) async {
    final engine = FakeEngine()..next = _st(playing: false);
    final c = EngineController(engine: engine, songs: SongLibrary.memory([_raw]))
      ..setPlayMode(PlayMode.advanced);
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    final e = SongEditor(controller: c, song: _raw)..start();
    expect(engine.calls, containsAll(['open 4']));
    expect(e.ready, isFalse);
    // Ya abierta: tempo sugerido (redondeado a 0,1) y el primer golpe
    engine.next = _st(playing: false, openId: 4, open: JobState.done, previewId: 4);
    await tester.pump(const Duration(milliseconds: 100));
    expect(e.ready, isTrue);
    expect(e.draft.bpm, 120.0);
    expect(e.draft.mark, 0.5);
    expect(e.overview.length, SongEditor.overviewBins);
    expect(e.zoom.length, SongEditor.zoomBins);
    expect(engine.calls, contains('grid 24000 24000.0 4'));
    // Marcar el 1 parado: en el cursor, ajustado al golpe de ahí cerca
    engine.attack = 30000;
    e.markOne();
    expect(e.draft.mark, 0.625);
    // Otro 1 treinta compases (a 121 BPM) más adelante: el tempo sale exacto
    final later = 30000 + (30 * 4 * 60 / 121 * 48000).round();
    e.seek(later);
    engine.attack = later;
    e.markSecond();
    expect(e.barsBetween, 30);
    expect(e.draft.bpm, closeTo(121.0, 0.01));
    e.setBarsBetween(31);
    expect(e.draft.bpm, closeTo(125.03, 0.01));
    e.setBarsBetween(30);
    // Escribir el tempo quita el segundo 1
    e.setBpm(118.04);
    expect(e.draft.bpm, 118.0);
    expect(e.draft.mark2, isNull);
    e.nudgeMark(-10);
    expect(e.draft.mark, closeTo(0.615, 1e-9));
    // Escuchar y parar
    e.seek(1000);
    e.togglePlay();
    expect(engine.calls.last, 'previewPlay 1000');
    engine.next = _st(
      playing: false,
      openId: 4,
      open: JobState.done,
      previewId: 4,
      previewPlaying: true,
      previewPosition: 50000,
    );
    await tester.pump(const Duration(milliseconds: 40));
    e.togglePlay();
    expect(engine.calls.last, 'previewStop');
    // Guardar: queda guardada y elegida, con su tempo
    e.setName('  Blues en La ');
    await e.save();
    expect(c.songs.single.bpm, 118.0);
    expect(c.songs.single.name, 'Blues en La');
    expect(c.currentSong?.id, 4);
    expect(c.bpm, 118.0);
    e.dispose();
    expect(engine.calls.sublist(engine.calls.length - 2), ['previewStop', 'close']);
    c.stopAudio();
    c.dispose();
  });

  for (final size in const [Size(360, 640), Size(800, 1280)]) {
    testWidgets('pantalla de preparar en ${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      setScreen(tester, size);
      final engine = FakeEngine()
        ..next = _st(playing: false, openId: 4, open: JobState.done, previewId: 4);
      final c = EngineController(engine: engine, songs: SongLibrary.memory([_raw]))
        ..setPlayMode(PlayMode.advanced);
      await c.startAudio();
      await tester.pumpWidget(_app(SongScreen(controller: c, song: _raw)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text(tr.editorMarkOne), findsOneWidget);
      expect(find.text(tr.editorBpm('120')), findsOneWidget);
      await tester.ensureVisible(find.text(tr.editorTap));
      await tester.pump();
      await tester.tap(find.text(tr.editorTap));
      await tester.tap(find.byTooltip(tr.editorTempoPlus));
      await tester.pump();
      expect(find.text(tr.editorBpm('120,1')), findsOneWidget);
      // Guardar desde arriba (la barra no se mueve)
      await tester.tap(find.text(tr.editorSave).first);
      await _settle(tester);
      expect(c.songs.single.ready, isTrue);
      c.stopAudio();
      c.dispose();
    });
  }

  test('textos: números con coma y duraciones', () {
    expect(tr.bpmNumber(97.3), '97,3');
    expect(tr.bpmNumber(120), '120');
    expect(tr.bpmNumber(121.004), '121');
    expect(tr.bpmNumber(97.34), '97,34');
    expect(tr.duration(225), '3:45');
    expect(tr.clock(83.42), '1:23,4');
    expect(tr.clock(5), '0:05,0');
  });

  testWidgets('el informe dice cómo está la canción', (tester) async {
    final engine = FakeEngine()..next = _st();
    final c = EngineController(engine: engine, songs: SongLibrary.memory([_ready]))
      ..setPlayMode(PlayMode.advanced);
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    c.selectSong(_ready);
    expect(c.report(), contains('Canción: Mi canción'));
    expect(c.report(), contains('en la lista: 1'));
    c.stopAudio();
    c.dispose();
  });
}
