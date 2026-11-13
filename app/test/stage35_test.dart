// Loopin — Etapa 3.5: redibujado, textos y recomendación del micrófono
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/engine/status_change.dart';
import 'package:loopin/l10n/strings.dart';
import 'package:loopin/ui/audio_settings_screen.dart';
import 'package:loopin/ui/theme.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'support.dart';

/// El mismo estado con las pistas un poco más adelante y otro nivel.
EngineStatus _later(EngineStatus s) => EngineStatus(
  running: s.running,
  sampleRate: s.sampleRate,
  playing: s.playing,
  bpm: s.bpm,
  beatsPerBar: s.beatsPerBar,
  beat: (s.beat + 1) % 4,
  samplesPerBeat: s.samplesPerBeat,
  beatFrames: s.beatFrames + 500,
  inputDeviceId: s.inputDeviceId,
  outputDeviceId: s.outputDeviceId,
  outputLatencyMs: s.outputLatencyMs + 0.3,
  inputLatencyMs: s.inputLatencyMs,
  inputPeak: s.inputPeak / 2,
  loopState: s.loopState,
  loopBarFrames: s.loopBarFrames,
  loopLength: s.loopLength,
  loopPosition: s.loopPosition + 1600,
  loopRecorded: s.loopRecorded + 1600,
  loopTarget: s.loopTarget,
  loopLayers: s.loopLayers,
  loopCanUndo: s.loopCanUndo,
  selectedTrack: s.selectedTrack,
  activeTrack: s.activeTrack,
  autoAdvance: s.autoAdvance,
  tapFrames: s.tapFrames,
  tapSpread: s.tapSpread,
  loopWaiting: s.loopWaiting,
  baseLength: s.baseLength,
  basePosition: s.basePosition + 1600,
  cpuLoad: 0.07,
  cpuLoadPeak: 0.12,
  cpuLoadMax: 0.2,
  tracks: [
    for (final t in s.tracks)
      TrackStatus(
        state: t.state,
        layers: t.layers,
        muted: t.muted,
        length: t.length,
        position: t.length > 0 ? (t.position + 1600) % t.length : 0,
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockPlatform);

  test('lo que se mueve no cuenta como cambio de pantalla; el estado sí', () {
    final a = fakeStatus(LoopState.recording);
    expect(layoutChanged(a, a), isFalse);
    expect(layoutChanged(a, _later(a)), isFalse);
    expect(layoutChanged(a, fakeStatus(LoopState.playing)), isTrue);
    expect(layoutChanged(a, fakeStatus(LoopState.recording, playing: false)), isTrue);
    // Pasar de esperar al compás a grabar sí cambia la pantalla
    expect(layoutChanged(fakeStatus(LoopState.armed), fakeStatus(LoopState.recording)), isTrue);
  });

  testWidgets('el controlador solo avisa si cambia algo; live, en cada consulta', (tester) async {
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine);
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    var slow = 0, fast = 0;
    c.addListener(() => slow++);
    c.live.addListener(() => fast++);

    // Solo se mueven las pistas: avisa live, no el controlador
    engine.next = _later(engine.next);
    await tester.pump(const Duration(milliseconds: 200));
    expect(fast, greaterThanOrEqualTo(5));
    expect(slow, 0);

    // Cambia el estado: avisa también el controlador
    engine.next = fakeStatus(LoopState.overdubbing);
    await tester.pump(const Duration(milliseconds: 40));
    expect(slow, 1);

    c.stopAudio();
    c.dispose();
  });

  testWidgets('micro: si no hay «sin procesar», se recomienda reconocimiento de voz', (
    tester,
  ) async {
    setScreen(tester, const Size(393, 2400)); // todo a la vista, sin desplazar
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine)
      ..setPlayMode(PlayMode.advanced); // lo que se prueba es del avanzado
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLoopinTheme(Chassis.classic, Brightness.dark),
        home: AudioSettingsScreen(controller: c),
      ),
    );
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    // El móvil de prueba dice que no lo admite
    expect(c.inputPreset, InputPreset.voiceRecognition);
    expect(find.text(tr.unprocessedUnsupported), findsOneWidget);
    expect(find.text(tr.recommended), findsOneWidget);
    final badge = find.ancestor(
      of: find.text(tr.recommended),
      matching: find.byKey(const ValueKey('preset-voiceRecognition')),
    );
    expect(badge, findsOneWidget);

    // La explicación del modo está plegada detrás del «?»
    expect(find.text(tr.micModeHelp), findsNothing);
    await tester.tap(find.byTooltip(tr.showHelp).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(tr.micModeHelp), findsOneWidget);

    // Elegir otro modo
    await tester.tap(find.text(tr.presetName(InputPreset.generic)));
    await tester.pump();
    expect(c.inputPreset, InputPreset.generic);

    // La carga del motor está en los detalles técnicos
    await tester.tap(find.text(tr.technicalDetails));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Carga del motor'), findsOneWidget);
    expect(tester.takeException(), isNull);
    c.stopAudio();
    c.dispose();
  });

  test('plurales y el informe', () {
    expect(tr.bars(1), '1 compás');
    expect(tr.bars(4), '4 compases');
    expect(tr.layers(1), '1 capa');
    expect(tr.layers(2), '2 capas');
    expect(tr.hits(1), '1 golpe');
    expect(tr.channels(1), 'mono');

    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine);
    c.status = engine.next;
    final report = c.report();
    expect(report, contains('Pista 2: sonando · 4 compases · 2 capas'));
    expect(report, contains('Pista 1: sonando · 4 compases · 1 capa'));
    expect(report, contains('Carga del motor'));
    expect(report, isNot(contains('(s)')));
    expect(report, isNot(contains('(es)')));
    c.dispose();
  });
}
