// Loopin — la batería en la interfaz (Etapa 4a)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/drums.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/engine/status_change.dart';
import 'package:loopin/l10n/strings.dart';
import 'package:loopin/ui/looper/accompaniment_row.dart';
import 'package:loopin/ui/looper_screen.dart';
import 'package:loopin/ui/theme.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'support.dart';

Widget _app(Widget home) =>
    MaterialApp(theme: buildLoopinTheme(Chassis.classic, Brightness.dark), home: home);

TimeSignature _ts(String label) => kTimeSignatures.firstWhere((t) => t.label == label);

/// El mismo estado con la batería como diga.
EngineStatus _withDrums(EngineStatus s, {bool on = true, bool playing = true}) => EngineStatus(
  running: s.running,
  sampleRate: s.sampleRate,
  playing: s.playing,
  bpm: s.bpm,
  beatsPerBar: s.beatsPerBar,
  samplesPerBeat: s.samplesPerBeat,
  inputDeviceId: s.inputDeviceId,
  outputDeviceId: s.outputDeviceId,
  loopState: s.loopState,
  tracks: s.tracks,
  baseLength: s.baseLength,
  selectedTrack: s.selectedTrack,
  drumsEnabled: on,
  drumsPlaying: playing,
);

/// Sin pumpAndSettle: la pantalla se mueve sin parar (sondeo del motor y luces)
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockPlatform);

  test('los 10 sonidos del kit se leen bien (WAV mono de 16 bits a 48 kHz)', () async {
    for (final s in DrumSound.values) {
      final wav = decodeWav16(await rootBundle.load(drumAsset(s)));
      expect(wav, isNotNull, reason: s.name);
      expect(wav!.sampleRate, 48000);
      expect(wav.samples.length, greaterThan(4800), reason: s.name); // más de 0,1 s
      var peak = 0.0;
      for (final v in wav.samples) {
        if (v.abs() > peak) peak = v.abs();
      }
      expect(peak, inInclusiveRange(0.05, 1.0), reason: s.name);
    }
    expect(decodeWav16(ByteData(10)), isNull);
  });

  testWidgets('el kit se carga en el motor antes de abrir el audio', (tester) async {
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = EngineController(engine: engine);
    await c.startAudio();
    expect(engine.drumSamples.length, DrumSound.values.length);
    expect(c.drumSoundsLoaded, DrumSound.values.length);
    // Y se aplican sus ajustes con los demás
    expect(engine.calls, containsAll(['drums false', 'drumStyle basic', 'drumVolume 0.7']));
    c.stopAudio();
    c.dispose();
  });

  testWidgets('encender con todo parado arranca; apagar no para', (tester) async {
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = EngineController(engine: engine);
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    engine.calls.clear();
    c.toggleDrums();
    expect(engine.calls, ['drums true', 'play']);
    engine.next = _withDrums(fakeStatus(LoopState.empty));
    await tester.pump(const Duration(milliseconds: 100));
    engine.calls.clear();
    c.toggleDrums();
    expect(engine.calls, ['drums false']);
    c.stopAudio();
    c.dispose();
  });

  testWidgets('elegir un estilo de otro compás cambia el compás; con loops, no se puede', (
    tester,
  ) async {
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = EngineController(engine: engine)
      ..setPlayMode(PlayMode.advanced); // lo que se prueba es del avanzado
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    engine.calls.clear();
    c.setDrumStyle(DrumStyle.waltz);
    expect(c.timeSignature.label, '3/4');
    expect(engine.calls, containsAllInOrder(['meter 3 0', 'drumStyle waltz']));
    c.setDrumStyle(DrumStyle.slowBlues);
    expect(c.timeSignature.label, '12/8');
    expect(engine.calls.last, 'drumStyle slowBlues 8'); // en 12/8 el tiempo es la corchea
    // Un estilo de 4/4 con 7/8: suena el básico (y se ve)
    c.setDrumStyle(DrumStyle.rock);
    c.setTimeSignature(_ts('7/8'));
    expect(c.drumStyle, DrumStyle.rock);
    expect(c.drumStyleNow, DrumStyle.basic);
    expect(engine.calls.last, 'drumStyle rock 8');
    // Con un loop grabado el compás no cambia: los estilos de otro compás no valen
    c.setTimeSignature(_ts('4/4'));
    engine.next = fakeStatus(LoopState.playing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.drumStyleAvailable(DrumStyle.funk), isTrue);
    expect(c.drumStyleAvailable(DrumStyle.basic), isTrue);
    expect(c.drumStyleAvailable(DrumStyle.waltz), isFalse);
    c.setDrumStyle(DrumStyle.waltz);
    expect(c.drumStyle, DrumStyle.rock);
    expect(c.timeSignature.label, '4/4');
    c.stopAudio();
    c.dispose();
  });

  test('que entre o se apague la batería redibuja la pantalla', () {
    final a = fakeStatus(LoopState.playing);
    expect(layoutChanged(a, _withDrums(a, playing: false)), isTrue);
    expect(layoutChanged(_withDrums(a, playing: false), _withDrums(a, playing: true)), isTrue);
    expect(layoutChanged(_withDrums(a), _withDrums(a)), isFalse);
  });

  for (final size in const [Size(360, 640), Size(393, 873), Size(873, 393), Size(800, 1280)]) {
    testWidgets('fila de la batería en ${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      setScreen(tester, size);
      final engine = FakeEngine()..next = _withDrums(fakeStatus(LoopState.playing));
      final c = EngineController(engine: engine)
        ..setPlayMode(PlayMode.advanced); // lo que se prueba es del avanzado
      await tester.pumpWidget(_app(LooperScreen(controller: c)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.byType(AccompanimentRow), findsOneWidget);
      // Tocar el estilo abre el menú con los 10
      await tester.tap(find.text(tr.drumStyleChip(DrumStyle.basic)));
      await _settle(tester);
      expect(find.text(tr.drumStyleItem(DrumStyle.funk, '4/4')), findsOneWidget);
      await tester.tap(find.text(tr.drumStyleItem(DrumStyle.funk, '4/4')));
      await _settle(tester);
      expect(c.drumStyle, DrumStyle.funk);
      expect(find.text('FUNK'), findsOneWidget);
      // El volumen se mueve
      c.setDrumVolume(1.2);
      await tester.pump();
      expect(
        tester
            .widget<Slider>(
              find.descendant(of: find.byType(AccompanimentRow), matching: find.byType(Slider)),
            )
            .value,
        1.2,
      );
      c.stopAudio();
      c.dispose();
    });
  }

  testWidgets('con el altavoz avisa de que el micro graba la batería', (tester) async {
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.speakerRoute, isTrue);
    expect(find.byTooltip(tr.drumsBleed), findsNothing); // apagada: no hay aviso
    c.setDrumsOn(true);
    engine.next = _withDrums(fakeStatus(LoopState.playing));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip(tr.drumsBleed), findsOneWidget);
    await tester.tap(find.byTooltip(tr.drumsBleed));
    await _settle(tester);
    expect(find.text(tr.drumsBleedHelp), findsOneWidget);
    await tester.tap(find.text(tr.ok));
    await _settle(tester);
    c.stopAudio();
    c.dispose();
  });
}
