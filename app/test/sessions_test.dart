// Loopin — tests de la Etapa 6: sesiones (guardar solas, abrir, biblioteca),
// exportar, modo escenario, guía de la primera vez y tablet en vertical
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/l10n/strings.dart';
import 'package:loopin/storage/wav.dart';
import 'package:loopin/ui/export_sheet.dart';
import 'package:loopin/ui/looper_screen.dart';
import 'package:loopin/ui/pedal_widgets.dart';
import 'package:loopin/ui/sessions_screen.dart';
import 'package:loopin/ui/stage_screen.dart';
import 'package:loopin/ui/theme.dart';
import 'package:loopin/ui/tutorial_screen.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'support.dart';

const _bar = 125216; // un compás a 92 BPM y 48 kHz (como fakeStatus)

Widget _app(Widget home) =>
    MaterialApp(theme: buildLoopinTheme(Chassis.classic, Brightness.dark), home: home);

Float32List _signal(int n, int seed) =>
    Float32List.fromList(List.generate(n, (i) => ((i * (seed + 3)) % 97) / 970 - 0.05));

/// Espera (de verdad) a que se cumpla algo: el guardado va en segundo plano.
Future<void> _until(bool Function() ok, {int ms = 4000}) async {
  for (var t = 0; t < ms && !ok(); t += 20) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(ok(), isTrue, reason: 'no ha llegado a tiempo');
}

Map<String, Object?> _json(Directory dir, String id) =>
    (jsonDecode(File('${dir.path}/$id/session.json').readAsStringSync()) as Map)
        .cast<String, Object?>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------- disco

  test('WAV: float de 32 bits sin perder nada y 16 bits', () {
    final x = Float32List.fromList([0, 0.5, -1.25, 1e-7, 0.999]);
    final w = decodeWav(encodeWavFloat(x, 44100))!;
    expect(w.sampleRate, 44100);
    expect(w.samples, x);
    // Uno de 16 bits estéreo (se lee el primer canal)
    final b = BytesBuilder()
      ..add(ascii.encode('RIFF'))
      ..add(Uint8List(4))
      ..add(ascii.encode('WAVEfmt '))
      ..add(
        (ByteData(20)
              ..setUint32(0, 16, Endian.little)
              ..setUint16(4, 1, Endian.little)
              ..setUint16(6, 2, Endian.little)
              ..setUint32(8, 48000, Endian.little)
              ..setUint32(12, 192000, Endian.little)
              ..setUint16(16, 4, Endian.little)
              ..setUint16(18, 16, Endian.little))
            .buffer
            .asUint8List(),
      )
      ..add(ascii.encode('data'))
      ..add((ByteData(4)..setUint32(0, 8, Endian.little)).buffer.asUint8List())
      ..add(
        (ByteData(8)
              ..setInt16(0, 16384, Endian.little)
              ..setInt16(2, 1, Endian.little)
              ..setInt16(4, -32768, Endian.little)
              ..setInt16(6, 1, Endian.little))
            .buffer
            .asUint8List(),
      );
    final w16 = decodeWav(b.toBytes())!;
    expect(w16.samples, [0.5, -1.0]);
    expect(decodeWav(Uint8List.fromList(ascii.encode('hola, no soy un wav'))), isNull);
  });

  test('biblioteca: guardar, leer, listar (sin las vacías), duplicar y borrar', () async {
    final dir = await Directory.systemTemp.createTemp('loopin_lib');
    addTearDown(() => dir.delete(recursive: true));
    final lib = SessionLibrary(folder: () async => dir.path);
    await lib.load();
    final t0 = DateTime(2026, 11, 13, 18, 50);
    Session make(String id, String name, int minutes, {bool tracks = true}) => Session(
      id: id,
      name: name,
      created: t0,
      updated: t0.add(Duration(minutes: minutes)),
      sampleRate: 48000,
      bpm: 92,
      meter: '7/8',
      barFrames: 1000,
      baseLength: 2000,
      tracks: [
        if (tracks)
          const SessionTrack(length: 2000, offset: 137, layers: 2, volume: 0.5, muted: true),
        if (tracks) const SessionTrack(length: 4000, reverse: true, half: true),
        null,
        null,
        if (!tracks) ...[null, null],
      ],
      drumsOn: true,
      drumStyle: 'rock',
      drumVolume: 0.4,
      songId: 7,
      songOn: true,
      songVolume: 1.2,
    );
    final a = make(lib.newId(t0), 'Uno', 1);
    await lib.writeJson(a);
    await lib.writeTrack(a.id, 0, _signal(2000, 1), 48000);
    await lib.writeTrack(a.id, 1, _signal(4000, 2), 48000);
    final b = make('otra', 'Dos', 5);
    await lib.writeJson(b);
    await lib.writeJson(make('vacia', 'Vacía', 9, tracks: false));

    final back = (await lib.read(a.id))!;
    expect(jsonEncode(back.toJson()), jsonEncode(a.toJson()));
    expect(back.tracks[0]!.offset, 137);
    expect(back.tracks[1]!.reverse && back.tracks[1]!.half, isTrue);
    expect(back.cycleBars, 4);
    expect((await lib.readTrack(a.id, 1))!.samples, _signal(4000, 2));
    expect(await lib.readTrack(a.id, 2), isNull);

    // La más reciente primero; la vacía no sale (salvo si es la abierta)
    expect([for (final s in await lib.list()) s.name], ['Dos', 'Uno']);
    expect([for (final s in await lib.list(keep: 'vacia')) s.name], ['Vacía', 'Dos', 'Uno']);

    final copy = (await lib.duplicate(back, name: 'Uno (copia)', now: t0))!;
    expect(copy.id, isNot(a.id));
    expect((await lib.readTrack(copy.id, 0))!.samples, _signal(2000, 1));
    expect((await lib.read(copy.id))!.name, 'Uno (copia)');

    await lib.purgeEmpty(keep: a.id);
    expect(lib.exists('vacia'), isFalse);
    await lib.delete(b.id);
    expect([for (final s in await lib.list()) s.name], unorderedEquals(['Uno', 'Uno (copia)']));
  });

  test('textos: nombre de sesión, fechas, resumen y nombres de archivo', () {
    expect(tr.sessionDefaultName(DateTime(2026, 11, 3, 8, 5)), 'Sesión 3 nov · 08:05');
    final now = DateTime(2026, 11, 13, 20);
    expect(tr.sessionWhen(DateTime(2026, 11, 13, 18, 50), now), 'hoy 18:50');
    expect(tr.sessionWhen(DateTime(2026, 11, 12, 9, 1), now), 'ayer 09:01');
    expect(tr.sessionWhen(DateTime(2026, 2, 1), now), '1 feb');
    expect(tr.sessionWhen(DateTime(2025, 2, 1), now), '1 feb 2025');
    expect(
      tr.sessionSummary((bpm: '92', meter: '4/4', tracks: 1, bars: 8)),
      '92 BPM · 4/4 · 1 pista · 8 C',
    );
    expect(tr.exportFileBase('Sesión 3 nov · 08:05'), 'Sesión 3 nov 08 05');
    expect(tr.exportFileBase('a/b\\c?'), 'a b c');
    expect(tr.exportFileBase('  '), 'Loopin');
    expect(tr.exportLength(2, 94.4), '2 vueltas · 1 min 34 s');
  });

  // ---------------------------------------------------------------- guardar solas

  test('se guarda sola: las pistas al quedarse quietas, solo lo que cambia, y una nueva', () async {
    final dir = await Directory.systemTemp.createTemp('loopin_auto');
    addTearDown(() => dir.delete(recursive: true));
    final prefs = <String, String>{'playMode': 'advanced'};
    mockPlatform(prefs);
    final engine = FakeEngine()
      ..next = fakeStatus(LoopState.recording, revision: 1, settled: false)
      ..trackData = [_signal(4 * _bar, 1), null, _signal(8 * _bar, 3), null];
    final c = EngineController(
      engine: engine,
      sessions: SessionLibrary(folder: () async => dir.path),
    );
    await c.startAudio();
    await _until(() => c.session != null);
    final id = c.session!.id;
    expect(prefs['sessionId'], id);
    // Grabando: no se guarda nada
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(File('${dir.path}/$id/session.json').existsSync(), isFalse);

    // Quieta: se guarda (las pistas que hay y su JSON)
    engine.next = fakeStatus(LoopState.playing, revision: 2);
    engine.trackData[1] = _signal(4 * _bar, 2);
    await _until(() => File('${dir.path}/$id/session.json').existsSync());
    var j = _json(dir, id);
    expect(j['bpm'], 92);
    expect(j['meter'], '4/4');
    expect(j['barFrames'], _bar);
    final tracks = j['tracks'] as List;
    expect((tracks[0] as Map)['length'], 4 * _bar);
    expect((tracks[2] as Map)['muted'], isTrue);
    expect(tracks[3], isNull);
    final wav1 = File('${dir.path}/$id/pista1.wav');
    expect(decodeWav(wav1.readAsBytesSync())!.samples, engine.trackData[0]);
    expect(File('${dir.path}/$id/pista3.wav').existsSync(), isTrue);
    final readsAfterFirst = engine.reads;
    expect(readsAfterFirst, 3);

    // Solo el volumen: el JSON, sin volver a leer ni escribir las pistas
    c.setTrackVolume(0, 0.5);
    await _until(() => ((_json(dir, id)['tracks'] as List)[0] as Map)['volume'] == 0.5);
    expect(engine.reads, readsAfterFirst);

    // Cambia una pista (otra orden): solo se escribe esa
    engine.trackData[2] = _signal(8 * _bar, 9);
    engine.next = fakeStatus(LoopState.playing, revision: 3);
    await _until(() => engine.reads == readsAfterFirst + 1);
    await _until(
      () =>
          decodeWav(File('${dir.path}/$id/pista3.wav').readAsBytesSync())!.samples[5] ==
          engine.trackData[2]![5],
    );

    // Sesión nueva: se borran las pistas del motor y empieza otra; la de
    // antes queda en la lista
    engine.calls.clear();
    await c.newSession();
    expect(engine.calls, contains('clear'));
    expect(c.session!.id, isNot(id));
    expect(prefs['sessionId'], c.session!.id);
    expect([for (final s in c.savedSessions) s.id], contains(id));
    c.stopAudio();
    c.dispose();
  });

  test('al abrir la app vuelve la última sesión: carga las pistas y sus ajustes', () async {
    final dir = await Directory.systemTemp.createTemp('loopin_open');
    addTearDown(() => dir.delete(recursive: true));
    final lib = SessionLibrary(folder: () async => dir.path);
    await lib.load();
    final now = DateTime(2026, 11, 13, 20);
    final s = Session(
      id: 'ultima',
      name: 'La última',
      created: now,
      updated: now,
      sampleRate: 44100,
      bpm: 120,
      meter: '7/8',
      barFrames: 7 * 22050,
      baseLength: 2 * 7 * 22050,
      selected: 1,
      tracks: const [
        SessionTrack(length: 2 * 7 * 22050, offset: 300, layers: 3, volume: 0.6),
        SessionTrack(length: 4 * 7 * 22050, muted: true, reverse: true),
        null,
        null,
      ],
      drumsOn: true,
      drumStyle: 'funk',
      drumVolume: 0.9,
    );
    await lib.writeJson(s);
    await lib.writeTrack(s.id, 0, _signal(2 * 7 * 22050, 1), 44100);
    await lib.writeTrack(s.id, 1, _signal(4 * 7 * 22050, 2), 44100);

    final prefs = <String, String>{'playMode': 'advanced', 'sessionId': 'ultima', 'trackFx': '1'};
    mockPlatform(prefs);
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    // El motor la acepta y enseña sus pistas
    engine.onLoad = () =>
        engine.next = fakeStatus(LoopState.stopped, playing: false, revision: 5, bpm: 120);
    final c = EngineController(
      engine: engine,
      sessions: SessionLibrary(folder: () async => dir.path),
    );
    await c.startAudio();
    await _until(() => engine.loaded != null && !c.sessionLoading);
    final a = engine.loaded!;
    expect(a.bpm, 120);
    expect(a.beatsPerBar, 7);
    expect(a.accentMask, (1 << 2) | (1 << 4));
    expect(a.sampleRate, 44100);
    expect(a.lengths, [2 * 7 * 22050, 4 * 7 * 22050, 0, 0]);
    expect(a.offsets[0], 300);
    expect(a.layers[0], 3);
    expect(a.selected, 1);
    expect(a.data[1], _signal(4 * 7 * 22050, 2));
    expect(c.session!.name, 'La última');
    expect(c.bpm, 120);
    expect(c.timeSignature.label, '7/8');
    expect(c.trackVolumes[0], 0.6);
    expect(engine.calls, containsAll(['volume 0 0.6', 'mute 1 true', 'reverse 1 true']));
    expect(c.drumsOn, isTrue);
    expect(c.drumStyle, DrumStyle.funk);
    expect(engine.calls, contains('drums true'));
    expect(prefs['bpm'], '120.00');
    c.stopAudio();
    c.dispose();

    // En simple: la batería no suena (se apunta para el avanzado) y sin REV
    final prefs2 = <String, String>{'playMode': 'simple', 'sessionId': 'ultima'};
    mockPlatform(prefs2);
    final engine2 = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    engine2.onLoad = () => engine2.next = fakeStatus(LoopState.stopped, playing: false);
    final c2 = EngineController(
      engine: engine2,
      sessions: SessionLibrary(folder: () async => dir.path),
    );
    await c2.startAudio();
    await _until(() => engine2.loaded != null && !c2.sessionLoading);
    expect(c2.drumsOn, isFalse);
    expect(engine2.calls, isNot(contains('reverse 1 true')));
    expect(prefs2['simpleForced'], contains('drumsOn=1'));
    c2.stopAudio();
    c2.dispose();
  });

  // ---------------------------------------------------------------- pantallas

  Future<EngineController> open(WidgetTester tester, FakeEngine engine, {String? exportDir}) async {
    mockPlatform({'playMode': 'advanced'});
    final c = EngineController(
      engine: engine,
      sessions: SessionLibrary(folder: () async => null),
      exportDirForTests: exportDir,
    );
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    return c;
  }

  Future<void> close(WidgetTester tester, EngineController c) async {
    c.stopAudio();
    await tester.pump(const Duration(milliseconds: 400));
    c.dispose();
  }

  testWidgets('el nombre de arriba abre las sesiones; la abierta se exporta', (tester) async {
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing, drums: true);
    final dir = Directory.systemTemp.createTempSync('loopin_export');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = await open(tester, engine, exportDir: dir.path);
    c.setDrumsOn(true);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    // Arriba, el nombre de la sesión
    expect(find.text(c.sessionName), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-sessions')));
    await tester.pumpAndSettle();
    expect(find.byType(SessionsScreen), findsOneWidget);
    expect(find.text(tr.sessionOpenNow), findsOneWidget);
    expect(
      find.text(tr.sessionSummary((bpm: '92', meter: '4/4', tracks: 3, bars: 8))),
      findsOneWidget,
    );

    // Exportar: la mezcla de serie, con la batería (suena); 2 vueltas
    await tester.tap(find.byKey(const ValueKey('export')));
    await tester.pumpAndSettle();
    expect(find.byType(ExportSheet), findsOneWidget);
    final drums = tester.widget<CheckboxListTile>(find.byKey(const ValueKey('export-drums')));
    expect(drums.value, isTrue);
    expect(find.byKey(const ValueKey('export-song')), findsNothing); // no hay canción
    await tester.tap(find.byKey(const ValueKey('export-stems')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('export-start')));
    await tester.pump();
    final req = engine.exported!;
    expect(req.loops, 2);
    expect(req.withDrums, isTrue);
    expect(req.withSong, isFalse);
    final base = tr.exportFileBase(c.sessionName);
    expect(req.mixPath, '${dir.path}/$base.wav');
    expect(req.trackPaths, [
      '${dir.path}/$base - pista 1.wav',
      '${dir.path}/$base - pista 2.wav',
      '${dir.path}/$base - pista 3.wav',
      null,
    ]);
    expect(req.drumsPath, '${dir.path}/$base - batería.wav');

    // En marcha: progreso; hecho: compartir
    engine.next = fakeStatus(
      LoopState.playing,
      drums: true,
      exportState: JobState.running,
      exportProgress: 0.4,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(tr.exporting(0.4)), findsOneWidget);
    File(req.mixPath!).writeAsBytesSync([0]);
    File(req.trackPaths[0]!).writeAsBytesSync([0]);
    engine.next = fakeStatus(LoopState.playing, drums: true, exportState: JobState.done);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(tr.exportDone(2)), findsOneWidget);
    expect(find.byKey(const ValueKey('export-share')), findsOneWidget);
    expect(c.exportedFiles.length, 2);
    expect(tester.takeException(), isNull);
    await close(tester, c);
  });

  testWidgets('sin pistas no se exporta; grabando no se cambia de sesión', (tester) async {
    setScreen(tester, const Size(360, 640));
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = await open(tester, engine);
    await tester.pumpWidget(_app(SessionsScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('export'))).onPressed, isNull);
    expect(find.text(tr.sessionEmptyNow), findsOneWidget);
    expect(find.text(tr.sessionsEmpty), findsOneWidget);
    engine.next = fakeStatus(LoopState.recording);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.canSwitchSession, isFalse);
    expect(find.text(tr.sessionBusy), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester, c);
  });

  testWidgets('borrar todo: o se borra, o se deja guardada y se empieza otra', (tester) async {
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = await open(tester, engine);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    final first = c.session!.id;
    await tester.tap(find.byTooltip(tr.clearAll));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(tr.clearAllBody(c.sessionName)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('clear-new-session')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(engine.calls, contains('clear'));
    expect(c.session!.id, isNot(first));
    await close(tester, c);
  });

  testWidgets('modo escenario: toda la pantalla pisa; se sale manteniendo', (tester) async {
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = fakeStatus(LoopState.recording);
    final c = await open(tester, engine);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('open-stage')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StageScreen), findsOneWidget);
    expect(
      find.descendant(of: find.byType(StageScreen), matching: find.text(tr.recordingTitle(2))),
      findsOneWidget,
    );
    // Pisar en una esquina del pulsador (no en el centro) también vale
    engine.calls.clear();
    final box = tester.getRect(find.byKey(const ValueKey('stage-pedal')));
    final g = await tester.startGesture(box.bottomLeft + const Offset(30, -30));
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.calls, ['press']);
    // Otro dedo a la vez no cuenta
    final g2 = await tester.startGesture(box.center);
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.calls, ['press']);
    await g2.up();
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    // Un toque en «salir» no sale; mantenerlo, sí
    await tester.tap(find.byKey(const ValueKey('stage-exit')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(StageScreen), findsOneWidget);
    final hold = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('stage-exit'))),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await hold.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StageScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await close(tester, c);
  });

  testWidgets('modo escenario en un móvil pequeño y apaisado', (tester) async {
    for (final size in const [Size(360, 640), Size(640, 360)]) {
      setScreen(tester, size);
      final engine = FakeEngine()..next = fakeStatus(LoopState.armed);
      final c = await open(tester, engine);
      await tester.pumpWidget(_app(StageScreen(controller: c)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('stage-title')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size');
      await close(tester, c);
    }
  });

  testWidgets('guía: elige el modo, pasa las páginas y no vuelve a salir', (tester) async {
    setScreen(tester, const Size(393, 873));
    final prefs = <String, String>{};
    mockPlatform(prefs);
    final c = EngineController(
      engine: FakeEngine(),
      sessions: SessionLibrary(folder: () async => null),
    );
    // Instalación nueva: sale
    expect(await c.needsTutorial(), isTrue);
    await tester.pumpWidget(_app(TutorialScreen(controller: c)));
    await tester.pump();
    expect(c.playMode, PlayMode.simple);
    await tester.tap(find.byKey(const ValueKey('tutorial-mode-advanced')));
    await tester.pump();
    expect(c.playMode, PlayMode.advanced);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const ValueKey('tutorial-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text(tr.tutorialSaved), findsOneWidget);
    expect(find.text(tr.tutorialStart), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await tester.pumpAndSettle();
    expect(prefs['tutorialDone'], '1');
    expect(await c.needsTutorial(), isFalse);
    expect(tester.takeException(), isNull);
    c.dispose();

    // Quien ya usaba la app no la ve sola (está en Ajustes)
    mockPlatform({'loopMode': 'sync'});
    final old = EngineController(
      engine: FakeEngine(),
      sessions: SessionLibrary(folder: () async => null),
    );
    expect(await old.needsTutorial(), isFalse);
    old.dispose();
  });

  testWidgets('guía en un móvil pequeño', (tester) async {
    setScreen(tester, const Size(360, 640));
    mockPlatform({});
    final c = EngineController(
      engine: FakeEngine(),
      sessions: SessionLibrary(folder: () async => null),
    );
    await tester.pumpWidget(_app(TutorialScreen(controller: c, onMeasure: () {})));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      expect(tester.takeException(), isNull, reason: 'página $i');
      if (i < 4) {
        await tester.tap(find.byKey(const ValueKey('tutorial-next')));
        await tester.pumpAndSettle();
      }
    }
    c.dispose();
  });

  test('tablet en vertical: todo más grande; el móvil, igual', () {
    expect(tabletScale(const BoxConstraints.tightFor(width: 393, height: 873)), 1);
    expect(tabletScale(const BoxConstraints.tightFor(width: 1280, height: 800)), 1); // apaisada
    expect(tabletScale(const BoxConstraints.tightFor(width: 600, height: 960)), 1); // 7"
    expect(
      tabletScale(const BoxConstraints.tightFor(width: 800, height: 1232)),
      closeTo(1.232, 0.01),
    );
  });

  testWidgets('tablet en vertical: el pulsador y la letra crecen y cabe todo', (tester) async {
    Future<(double, double)> measure(Size size) async {
      setScreen(tester, size, pixelRatio: 2);
      final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
      final c = await open(tester, engine);
      await tester.pumpWidget(_app(LooperScreen(controller: c)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: '$size');
      final pedal = tester.getRect(find.byType(Footswitch)).width;
      final title = tester.getRect(find.text(tr.playing)).height;
      await tester.pumpWidget(const SizedBox());
      await close(tester, c);
      return (pedal, title);
    }

    final (_, phoneTitle) = await measure(const Size(600, 960));
    final (tabletPedal, tabletTitle) = await measure(const Size(800, 1280));
    expect(tabletTitle, greaterThan(phoneTitle * 1.2));
    expect(tabletPedal, greaterThan(380));
  });

  testWidgets('sin sitio: se avisa (pulsador, cabecera, Sesiones y al salir) y se reintenta', (
    tester,
  ) async {
    setScreen(tester, const Size(393, 873));
    mockPlatform({'playMode': 'advanced'});
    final lib = _FullLibrary();
    final engine = FakeEngine()
      ..next = fakeStatus(LoopState.playing, revision: 2)
      ..trackData = [_signal(4 * _bar, 1), _signal(4 * _bar, 2), _signal(8 * _bar, 3), null];
    final c = EngineController(engine: engine, sessions: lib);
    await c.startAudio();
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 800));
    expect(lib.tries, greaterThan(0));
    expect(c.sessionSaveFailed, isTrue);
    expect(c.sessionSaveNoSpace, isTrue);
    final line = tr.saveFailedLine(true);
    expect(find.text('⚠ $line'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets); // en la cabecera
    // Se reintenta cada 5 s (no cada medio segundo)
    final tries = lib.tries;
    await tester.pump(const Duration(seconds: 2));
    expect(lib.tries, tries);

    // «Atrás» pregunta antes de salir
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text(tr.saveFailedExitBody), findsOneWidget);
    await tester.tap(find.text(tr.saveFailedStay));
    await tester.pump(const Duration(milliseconds: 300));

    // Tocar el aviso lleva a Sesiones, con la explicación
    await tester.tap(find.byKey(const ValueKey('pedal-save-failed')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('save-failed')), findsOneWidget);
    expect(find.text(tr.saveFailedBody(true)), findsOneWidget);

    // Con sitio otra vez, se guarda solo y el aviso se va
    lib.full = false;
    await tester.pump(const Duration(seconds: 6));
    expect(c.sessionSaveFailed, isFalse);
    expect(find.byKey(const ValueKey('save-failed')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.stopAudio();
    await tester.pump(const Duration(milliseconds: 400));
    c.dispose();
  });
}

/// Una biblioteca con el móvil lleno: escribir falla (sin tocar el disco).
class _FullLibrary extends SessionLibrary {
  _FullLibrary() : super(folder: () async => null);

  bool full = true;
  int tries = 0;

  static const _error = FileSystemException(
    'Cannot write',
    'pista1.wav',
    OSError('No space left on device', 28),
  );

  @override
  Future<void> writeTrack(String id, int track, Float32List samples, int sampleRate) async {
    tries++;
    if (full) throw _error;
  }

  @override
  Future<void> writeJson(Session s) async {
    if (full) throw _error;
  }
}
