// Loopin — la pantalla del looper se dibuja bien en todos los estados y tamaños
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/ui/audio_settings_screen.dart';
import 'package:loopin/ui/looper_screen.dart';
import 'package:loopin/ui/pedal_widgets.dart';
import 'package:loopin/ui/settings_screen.dart';
import 'package:loopin/ui/theme.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'support.dart';

/// Vertical y apaisado, en un móvil normal, uno pequeño y una tablet.
const _sizes = [
  Size(393, 873),
  Size(360, 640),
  Size(873, 393),
  Size(640, 360),
  Size(800, 1280),
  Size(1280, 800),
];

Widget _app(
  Widget home, {
  Chassis chassis = Chassis.classic,
  Brightness brightness = Brightness.dark,
}) => MaterialApp(theme: buildLoopinTheme(chassis, brightness), home: home);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockPlatform);

  for (final size in _sizes) {
    for (final st in LoopState.values) {
      testWidgets('looper ${st.name} en ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        setScreen(tester, size);
        final engine = FakeEngine()..next = fakeStatus(st, playing: st != LoopState.stopped);
        final c = EngineController(engine: engine);
        await tester.pumpWidget(_app(LooperScreen(controller: c)));
        await tester.pump(const Duration(milliseconds: 100)); // arranca el audio y sondea
        expect(c.status.loopState, st);
        expect(tester.takeException(), isNull);
        expect(find.text('DESHACER'), findsOneWidget);
        expect(find.byType(Footswitch), findsOneWidget);
        // En vertical todo cabe sin desplazar: el pulsador se ve entero
        if (size.height > size.width) {
          final rect = tester.getRect(find.byType(Footswitch));
          expect(rect.top >= 0 && rect.bottom <= size.height, isTrue);
        }
        c.stopAudio();
        c.dispose();
      });
    }
  }

  for (final chassis in Chassis.values) {
    for (final brightness in Brightness.values) {
      testWidgets('chasis ${chassis.name} ${brightness.name}', (tester) async {
        setScreen(tester, const Size(393, 873));
        final engine = FakeEngine()..next = fakeStatus(LoopState.recording);
        final c = EngineController(engine: engine);
        await tester.pumpWidget(
          _app(
            LooperScreen(controller: c),
            chassis: chassis,
            brightness: brightness,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        // El texto se lee sobre el chasis (contraste de al menos 4,5:1)
        final p = LoopinPalette.forChassis(chassis, brightness);
        expect(contrast(p.ink, p.chassis), greaterThan(4.5));
        expect(contrast(p.ink, p.panel), greaterThan(4.5));
        expect(contrast(p.dim, p.chassis), greaterThan(3.0));
        c.stopAudio();
        c.dispose();
      });
    }
  }

  testWidgets('con el audio apagado se ofrece encenderlo', (tester) async {
    setScreen(tester, const Size(360, 640));
    final engine = FakeEngine()..next = const EngineStatus();
    final c = EngineController(engine: engine);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ENCENDER AUDIO'), findsOneWidget);
    expect(tester.takeException(), isNull);
    c.stopAudio();
    // El controlador había programado un reintento de abrir el audio
    await tester.pump(const Duration(milliseconds: 400));
    c.dispose();
  });

  testWidgets('el botón grande: toque, doble toque y mantener', (tester) async {
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    final button = find.byType(Footswitch);
    expect(button, findsOneWidget);
    expect(find.text('SONANDO'), findsOneWidget);

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

  testWidgets('pistas: elegir, silenciar, borrar y borrar todo', (tester) async {
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    // Al abrir se aplican el avance automático y los volúmenes
    expect(engine.calls, contains('autoAdvance true'));
    expect(engine.calls, contains('volume 3 1.0'));

    // En un móvil se ven los controles de la pista elegida (la 2)
    expect(find.text('PISTA 2'), findsOneWidget);
    expect(find.text('PISTA 1'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('track-ring-2')));
    expect(engine.calls.last, 'select 2');

    await tester.tap(find.byTooltip('Silenciar la pista 2'));
    expect(engine.calls.last, 'mute 1 true');
    await tester.tap(find.byTooltip('Borrar la pista 2'));
    expect(engine.calls.last, 'clearTrack 1');

    // Borrar todo pide confirmación
    engine.calls.clear();
    await tester.tap(find.byTooltip('Borrar todas las pistas'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.calls.contains('clear'), isFalse);
    await tester.tap(find.text('Borrar todo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.calls, contains('clear'));

    // Parar y arrancar
    await tester.tap(find.text('PARAR'));
    expect(engine.calls.last, 'pause');

    c.stopAudio();
    c.dispose();
  });

  testWidgets('en una tablet se ven los controles de las 4 pistas', (tester) async {
    setScreen(tester, const Size(1280, 800));
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    for (var n = 1; n <= kTrackCount; n++) {
      expect(find.text('PISTA $n'), findsOneWidget);
    }
    c.stopAudio();
    c.dispose();
  });

  testWidgets('latencia: usa la estimación y avisa si no está medida', (tester) async {
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    // 45 + 60 ms a 48 kHz = 5040 muestras
    expect(engine.calls, contains('latency 5040'));
    expect(c.latencySource, LatencySource.estimated);
    expect(find.text('LATENCIA SIN MEDIR'), findsOneWidget);
    // El aviso lleva a medirla
    await tester.tap(find.text('LATENCIA SIN MEDIR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Audio y latencia'), findsOneWidget);
    c.stopAudio();
    c.dispose();
  });

  testWidgets('controles externos: volumen, cascos y pedal aprendido', (tester) async {
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    engine.calls.clear();

    // Los botones de volumen no hacen nada hasta que se activan
    c.handleKey(24, down: true);
    c.handleKey(24, down: false);
    expect(engine.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 700));

    // El botón de los cascos es el principal de serie
    c.handleKey(79, down: true, name: 'KEYCODE_HEADSETHOOK');
    c.handleKey(79, down: false);
    expect(engine.calls, ['press']);
    // El doble toque se mide con el reloj de verdad: hay que dejarlo pasar
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
    engine.calls.clear();

    c.setVolumeKeys(true);
    c.handleKey(24, down: true);
    c.handleKey(24, down: true, repeat: 1); // repetición por mantener: se ignora
    await tester.pump(const Duration(milliseconds: 700));
    c.handleKey(24, down: false);
    expect(engine.calls, ['press', 'hold']);
    engine.calls.clear();

    // Bajar volumen: toque = siguiente pista; mantener = deshacer
    c.handleKey(25, down: true);
    c.handleKey(25, down: false);
    expect(engine.calls, ['selectNext']);
    engine.calls.clear();
    c.handleKey(25, down: true);
    await tester.pump(const Duration(milliseconds: 700));
    c.handleKey(25, down: false);
    expect(engine.calls, ['undo']);
    engine.calls.clear();

    // Aprender una tecla de un pedal Bluetooth
    c.startLearning(PedalAction.secondary);
    c.handleKey(93, down: true, name: 'KEYCODE_PAGE_DOWN');
    c.handleKey(93, down: false);
    expect(c.learning, isNull);
    expect(c.learnedKeys.single.label, 'PAGE_DOWN');
    expect(engine.calls, isEmpty); // la pulsación de aprender no hace nada más
    c.handleKey(93, down: true);
    c.handleKey(93, down: false);
    expect(engine.calls, ['selectNext']);
    c.forgetKey(93);
    engine.calls.clear();
    c.handleKey(93, down: true);
    expect(engine.calls, isEmpty);

    c.stopAudio();
    c.dispose();
  });

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('ajustes en ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      setScreen(tester, size);
      final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
      final c = EngineController(engine: engine);
      await tester.pumpWidget(_app(SettingsScreen(controller: c)));
      await c.startAudio();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      // Apariencia
      await tester.tap(find.text('Claro'));
      await tester.pump();
      expect(c.appearance.value.mode, ThemeMode.light);
      await tester.tap(find.text('Verde'));
      await tester.pump();
      expect(c.appearance.value.chassis, Chassis.green);

      await tester.tap(find.text('Avance automático'));
      await tester.pump();
      expect(c.autoAdvance, isFalse);
      expect(engine.calls.last, 'autoAdvance false');

      final learn = find.byKey(const ValueKey('learn-main'));
      await tester.scrollUntilVisible(learn, 200);
      await tester.pump();
      await tester.tap(learn);
      await tester.pump();
      expect(c.learning, PedalAction.main);
      expect(find.text('Pulsa ahora el botón del pedal…'), findsOneWidget);
      c.handleKey(62, down: true, name: 'KEYCODE_SPACE');
      await tester.pump();
      expect(find.text('SPACE'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(find.text('Audio y latencia'), 200);
      expect(tester.takeException(), isNull);
      c.stopAudio();
      c.dispose();
    });
  }

  testWidgets('ajustes de audio se dibujan', (tester) async {
    setScreen(tester, const Size(360, 640));
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(_app(AudioSettingsScreen(controller: c)));
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
