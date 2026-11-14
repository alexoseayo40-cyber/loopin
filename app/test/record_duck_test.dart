// Loopin — al grabar con el altavoz, lo que ya suena se calla (o sigue normal)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/l10n/strings.dart';
import 'package:loopin/ui/looper/pedal_area.dart';
import 'package:loopin/ui/settings_screen.dart';
import 'package:loopin/ui/theme.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockPlatform);

  testWidgets('con altavoz y micro del móvil se calla; con cascos, no', (tester) async {
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine);
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    // De serie: silencio (la ruta de prueba es micro + altavoz del móvil)
    expect(c.speakerRoute, isTrue);
    expect(c.recordDuck, RecordDuck.silent);
    expect(engine.calls.where((x) => x.startsWith('duck')).last, 'duck 0.0');

    c.setRecordDuck(RecordDuck.normal);
    expect(engine.calls.last, 'duck 1.0');
    c.setRecordDuck(RecordDuck.silent);

    // Con cascos de cable (otra salida) suena normal
    engine.next = fakeStatus(LoopState.playing).copyWithOutput(30);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.speakerRoute, isFalse);
    expect(engine.calls.where((x) => x.startsWith('duck')).last, 'duck 1.0');
    c.stopAudio();
    c.dispose();
  });

  test('el pulsador avisa de que lo demás está callado', () {
    final rec = pedalLook(
      fakeStatus(LoopState.recording),
      mode: LoopMode.sync,
      startOnSound: false,
      duck: RecordDuck.silent,
    );
    expect(rec.subtitle, endsWith('lo demás, en silencio'));
    final dub = pedalLook(
      fakeStatus(LoopState.overdubbing),
      mode: LoopMode.sync,
      startOnSound: false,
      duck: RecordDuck.silent,
    );
    expect(dub.subtitle, '${tr.tapToFinish} · lo demás, en silencio');
    final normal = pedalLook(
      fakeStatus(LoopState.recording),
      mode: LoopMode.sync,
      startOnSound: false,
    );
    expect(normal.subtitle, isNot(contains('lo demás')));
  });

  testWidgets('ajuste en Ajustes › Looper', (tester) async {
    setScreen(tester, const Size(393, 1400));
    final c = EngineController(engine: FakeEngine()..next = fakeStatus(LoopState.playing))
      ..setPlayMode(PlayMode.advanced); // lo que se prueba es del avanzado
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLoopinTheme(Chassis.classic, Brightness.dark),
        home: SettingsScreen(controller: c),
      ),
    );
    await tester.pump();
    expect(find.text(tr.recordDuckTitle), findsOneWidget);
    // Dos opciones: silencio (de serie) y normal
    expect(find.text(tr.recordDuckName(RecordDuck.silent)), findsOneWidget);
    await tester.tap(find.text(tr.recordDuckName(RecordDuck.normal)));
    await tester.pump();
    expect(c.recordDuck, RecordDuck.normal);
    expect(tester.takeException(), isNull);
    c.dispose();
  });
}

extension on EngineStatus {
  /// El mismo estado con otra salida.
  EngineStatus copyWithOutput(int id) => EngineStatus(
    running: running,
    sampleRate: sampleRate,
    playing: playing,
    bpm: bpm,
    beatsPerBar: beatsPerBar,
    samplesPerBeat: samplesPerBeat,
    inputDeviceId: inputDeviceId,
    outputDeviceId: id,
    loopState: loopState,
    loopBarFrames: loopBarFrames,
    loopLength: loopLength,
    baseLength: baseLength,
    tracks: tracks,
  );
}
