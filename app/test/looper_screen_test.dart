// Loopin — la pantalla del looper se dibuja bien en todos los estados
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/ui/audio_settings_screen.dart';
import 'package:loopin/ui/looper_screen.dart';
import 'package:loopin_engine/loopin_engine.dart';

/// Motor de mentira: devuelve el estado que le digamos y apunta las órdenes.
class FakeEngine implements LoopinEngine {
  EngineStatus next = const EngineStatus();
  final List<String> calls = [];

  @override
  EngineStatus status() => next;
  @override
  int start() => 0;
  @override
  void loopPress() => calls.add('press');
  @override
  void loopHold() => calls.add('hold');
  @override
  void loopDoubleTap() => calls.add('double');
  @override
  void loopUndo() => calls.add('undo');
  @override
  void loopClear() => calls.add('clear');
  @override
  void setLatencyCompensation(int frames) => calls.add('latency $frames');

  // El resto de órdenes no importan aquí
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _channel = MethodChannel('loopin/permissions');

EngineStatus _status(LoopState st, {bool playing = true}) => EngineStatus(
  running: true,
  sampleRate: 48000,
  playing: playing,
  bpm: 92,
  beatsPerBar: 4,
  samplesPerBeat: 31304,
  inputDeviceId: 10,
  outputDeviceId: 20,
  outputLatencyMs: 45,
  inputLatencyMs: 60,
  loopState: st,
  loopBarFrames: 125216,
  loopLength: st.hasLoop ? 4 * 125216 : 0,
  loopPosition: st.hasLoop ? 200000 : 0,
  loopRecorded: switch (st) {
    LoopState.armed => -40000,
    LoopState.recording => 180000,
    _ => 0,
  },
  loopTarget: st == LoopState.recording ? 4 * 125216 : 0,
  loopLayers: st.hasLoop ? 2 : 0,
  loopCanUndo: st != LoopState.empty,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async {
        switch (call.method) {
          case 'requestMicrophone':
            return 'granted';
          case 'audioInfo':
            return {'model': 'Test', 'android': '16', 'unprocessed': false};
          case 'audioDevices':
            return {
              'inputs': [
                {'id': 10, 'type': 15, 'name': 'mic', 'address': 'bottom'},
              ],
              'outputs': [
                {'id': 20, 'type': 2, 'name': 'speaker', 'address': ''},
              ],
            };
          case 'prefsGet':
            return null;
          default:
            return null;
        }
      },
    );
  });

  for (final size in const [Size(393, 873), Size(360, 640)]) {
    for (final st in LoopState.values) {
      testWidgets('looper ${st.name} en ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        final engine = FakeEngine()..next = _status(st, playing: st != LoopState.stopped);
        final c = EngineController(engine: engine);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.deepOrange,
                brightness: Brightness.dark,
              ),
            ),
            home: LooperScreen(controller: c),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100)); // arranca el audio y sondea
        expect(c.status.loopState, st);
        expect(tester.takeException(), isNull);
        expect(find.text('Deshacer'), findsOneWidget);
        c.stopAudio();
        c.dispose();
      });
    }
  }

  testWidgets('el botón grande: toque, doble toque y mantener', (tester) async {
    final engine = FakeEngine()..next = _status(LoopState.playing);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(MaterialApp(home: LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    final button = find.text('Sonando');
    expect(button, findsOneWidget);

    // Toque normal
    var g = await tester.startGesture(tester.getCenter(button));
    await g.up();
    expect(engine.calls.where((e) => e == 'press').length, 1);

    // Doble toque: el segundo es «double», no «press»
    await tester.pump(const Duration(milliseconds: 100));
    g = await tester.startGesture(tester.getCenter(button));
    await g.up();
    expect(engine.calls.last, 'double');

    // Mantener (después de que pase la ventana del doble toque)
    await tester.pump(const Duration(milliseconds: 500));
    engine.calls.clear();
    g = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 700));
    await g.up();
    expect(engine.calls.where((e) => e == 'press' || e == 'hold').toList(), ['press', 'hold']);

    // Soltar antes de tiempo no es mantener
    await tester.pump(const Duration(milliseconds: 500));
    engine.calls.clear();
    g = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 200));
    await g.up();
    await tester.pump(const Duration(milliseconds: 700));
    expect(engine.calls.contains('hold'), isFalse);

    c.stopAudio();
    c.dispose();
  });

  testWidgets('latencia: usa la estimación y avisa si no está medida', (tester) async {
    final engine = FakeEngine()..next = _status(LoopState.empty, playing: false);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(MaterialApp(home: LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    // 45 + 60 ms a 48 kHz = 5040 muestras
    expect(engine.calls, contains('latency 5040'));
    expect(c.latencySource, LatencySource.estimated);
    expect(find.textContaining('Latencia sin medir'), findsOneWidget);
    c.stopAudio();
    c.dispose();
  });

  testWidgets('ajustes de audio se dibujan', (tester) async {
    tester.view.physicalSize = const Size(360, 640) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final engine = FakeEngine()..next = _status(LoopState.playing);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(MaterialApp(home: AudioSettingsScreen(controller: c)));
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.textContaining('Compensación al grabar'), 200);
    expect(find.textContaining('Compensación al grabar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    c.stopAudio();
    c.dispose();
  });
}
