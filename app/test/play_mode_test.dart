// Loopin — modo simple y avanzado (Etapa 4.5)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/engine/play_mode.dart';
import 'package:loopin/ui/audio_settings_screen.dart';
import 'package:loopin/ui/looper/accompaniment_row.dart';
import 'package:loopin/ui/looper/tempo_display.dart';
import 'package:loopin/ui/looper/tempo_menus.dart';
import 'package:loopin/ui/looper_screen.dart';
import 'package:loopin/ui/pedal_widgets.dart';
import 'package:loopin/ui/settings_screen.dart';
import 'package:loopin/ui/theme.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'support.dart';

Widget _app(Widget home) =>
    MaterialApp(theme: buildLoopinTheme(Chassis.classic, Brightness.dark), home: home);

TimeSignature _ts(String label) => kTimeSignatures.firstWhere((t) => t.label == label);

/// Un controlador con los ajustes en [prefs] ya cargados y el audio abierto.
Future<EngineController> _open(
  WidgetTester tester,
  FakeEngine engine,
  Map<String, String> prefs,
) async {
  mockPlatform(prefs);
  final c = EngineController(engine: engine);
  await c.startAudio();
  await tester.pump(const Duration(milliseconds: 100));
  return c;
}

Future<void> _close(WidgetTester tester, EngineController c) async {
  c.stopAudio();
  await tester.pump(const Duration(milliseconds: 400));
  c.dispose();
}

/// Todo lo del avanzado puesto (lo que el simple no enseña).
void _setAllAdvanced(EngineController c) {
  c.setDrumStyle(DrumStyle.funk); // de 4/4: primero, que no cambie el compás de después
  c.setTimeSignature(_ts('7/8'));
  c.setLoopMode(LoopMode.free);
  c.setStartOnSound(true);
  c.setClickMode(ClickMode.countIn);
  c.setRecordDuck(RecordDuck.low);
  c.setInputPreset(InputPreset.generic);
  c.setDrumsOn(true);
  c.setBackingOn(true);
}

/// En simple no queda nada que no se vea.
void _expectSimpleValues(EngineController c) {
  expect(kSimpleLoopModes, contains(c.loopMode));
  expect(kSimpleMeters, contains(c.timeSignature.label));
  expect(kSimpleClickModes, contains(c.clickMode));
  expect(c.drumsOn, isFalse);
  expect(c.backingOn, isFalse);
  expect(c.recordDuck, RecordDuck.silent);
  expect(c.inputPreset, c.recommendedPreset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockPlatform);

  testWidgets('de serie, el simple; quien ya usaba la app sigue en el avanzado', (tester) async {
    var engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    var c = await _open(tester, engine, {});
    expect(c.playMode, PlayMode.simple);
    _expectSimpleValues(c);
    expect(engine.calls, contains('mode manual'));
    await _close(tester, c);

    engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    c = await _open(tester, engine, {'loopMode': 'sync', 'syncBars': '2'});
    expect(c.playMode, PlayMode.advanced);
    expect(c.loopMode, LoopMode.sync);
    expect(c.syncBars, 2);
    await _close(tester, c);
  });

  testWidgets('pasar a simple fija lo que no se ve; volver al avanzado lo recupera', (
    tester,
  ) async {
    final prefs = <String, String>{'playMode': 'advanced'};
    var engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    var c = await _open(tester, engine, prefs);
    expect(c.playMode, PlayMode.advanced);
    _setAllAdvanced(c);
    expect(c.inputPreset, InputPreset.generic);
    expect(c.recommendedPreset, InputPreset.voiceRecognition); // el móvil no tiene «sin procesar»

    engine.calls.clear();
    c.setPlayMode(PlayMode.simple);
    _expectSimpleValues(c);
    expect(c.timeSignature.label, '4/4');
    expect(c.loopMode, LoopMode.manual); // el libre no está en simple
    expect(c.startOnSound, isTrue); // empezar al tocar sí está
    expect(c.clickMode, ClickMode.untilRecording); // «solo la cuenta» no está
    expect(c.inputPreset, InputPreset.voiceRecognition);
    // Y el motor lo sabe (apagar la batería y la canción no para nada)
    expect(
      engine.calls,
      containsAll([
        'mode manual',
        'meter 4 0',
        'click untilRecording',
        'drums false',
        'backing false',
      ]),
    );
    expect(engine.calls, isNot(contains('onSound false')));
    expect(engine.calls, isNot(contains('pause')));
    expect(engine.calls, isNot(contains('stop')));
    expect(prefs['playMode'], 'simple');
    expect(prefs['simpleForced'], contains('meter=7/8'));
    // Lo que eligió en el avanzado sigue guardado para cuando vuelva
    expect(prefs['inputPreset'], '${InputPreset.generic.code}');
    await _close(tester, c);

    // Al abrir la app otra vez sigue en simple y se acuerda de lo del avanzado
    engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    c = await _open(tester, engine, prefs);
    expect(c.playMode, PlayMode.simple);
    _expectSimpleValues(c);
    engine.calls.clear();
    c.setPlayMode(PlayMode.advanced);
    expect(c.loopMode, LoopMode.free);
    expect(c.startOnSound, isTrue);
    expect(c.timeSignature.label, '7/8');
    expect(c.clickMode, ClickMode.countIn);
    expect(c.drumStyle, DrumStyle.funk);
    expect(c.recordDuck, RecordDuck.low);
    expect(c.inputPreset, InputPreset.generic);
    // La batería y la canción vuelven encendidas, sin arrancar nada
    expect(c.drumsOn, isTrue);
    expect(c.backingOn, isTrue);
    expect(engine.calls, containsAll(['drums true', 'backing true']));
    expect(engine.calls, isNot(contains('play')));
    expect(prefs['simpleForced'], '');
    await _close(tester, c);
  });

  testWidgets('lo que se cambia en simple se queda al volver al avanzado', (tester) async {
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = await _open(tester, engine, {'playMode': 'advanced'});
    c.setTimeSignature(_ts('7/8'));
    c.setClickMode(ClickMode.countIn);
    c.setLoopMode(LoopMode.sync);
    c.setPlayMode(PlayMode.simple);
    expect(c.timeSignature.label, '4/4');
    // En simple elige otro compás y apaga el clic
    c.setTimeSignature(_ts('3/4'));
    c.setClickMode(ClickMode.silent);
    c.setPlayMode(PlayMode.advanced);
    expect(c.timeSignature.label, '3/4');
    expect(c.clickMode, ClickMode.silent);
    expect(c.loopMode, LoopMode.sync); // sincronizado también está en simple: se queda
    await _close(tester, c);
  });

  testWidgets('con loops, el compás se queda (y se ve); mientras se graba no se cambia', (
    tester,
  ) async {
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = await _open(tester, engine, {'playMode': 'advanced'});
    c.setTimeSignature(_ts('7/8'));
    c.setLoopMode(LoopMode.free);
    engine.next = fakeStatus(LoopState.playing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.tempoLocked, isTrue);
    c.setPlayMode(PlayMode.simple);
    expect(c.timeSignature.label, '7/8');
    expect(c.loopMode, LoopMode.manual);

    engine.next = fakeStatus(LoopState.recording);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.canChangePlayMode, isFalse);
    c.setPlayMode(PlayMode.advanced);
    expect(c.playMode, PlayMode.simple);

    engine.next = fakeStatus(LoopState.playing);
    await tester.pump(const Duration(milliseconds: 100));
    c.setPlayMode(PlayMode.advanced);
    expect(c.playMode, PlayMode.advanced);
    expect(c.loopMode, LoopMode.free);
    await _close(tester, c);
  });

  testWidgets('en simple no se puede poner lo del avanzado', (tester) async {
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = await _open(tester, engine, {});
    c.setInputPreset(InputPreset.generic);
    expect(c.inputPreset, c.recommendedPreset);
    expect(c.timeSignatures.map((t) => t.label), kSimpleMeters);
    expect(c.report(), contains('Modo de la app: simple'));
    await _close(tester, c);
  });

  testWidgets('pantalla en simple: modo y compases, clic de un toque, sin acompañamiento', (
    tester,
  ) async {
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.simple, isTrue);
    // Manual de serie (sin selector de compases), empezar al tocar y entrenador
    expect(c.loopMode, LoopMode.manual);
    expect(find.byType(ModeMenu), findsOneWidget);
    expect(find.byType(BarsMenu), findsNothing);
    expect(find.byType(OnSoundToggle), findsOneWidget);
    expect(find.byKey(const ValueKey('trainer-button')), findsOneWidget);
    expect(find.byType(ClickMenu), findsNothing);
    expect(find.byType(SimpleClickToggle), findsOneWidget);
    expect(find.byType(MeterMenu), findsOneWidget);
    expect(find.byType(AccompanimentRow), findsNothing);
    expect(find.text('TAP · TOCA AL RITMO'), findsOneWidget);
    expect(find.textContaining('1 compás de cuenta'), findsOneWidget); // lo que pasa al pulsar
    final simplePedal = tester.getSize(find.byType(Footswitch)).width;
    final simpleTempo = tester.getSize(find.byType(TempoDisplay)).height;

    // El modo: sincronizado o manual (sin el libre), y sincronizado con sus compases
    await tester.tap(find.byTooltip('Modo de grabación'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PopupMenuItem<LoopMode>), findsNWidgets(2));
    await tester.tap(find.text('Sincronizado').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.loopMode, LoopMode.sync);
    expect(find.byType(BarsMenu), findsOneWidget);

    // El clic: hasta grabar (de serie) → apagado → siempre → hasta grabar
    expect(c.clickMode, ClickMode.untilRecording);
    await tester.tap(find.byKey(const ValueKey('simple-click')));
    await tester.pump();
    expect(c.clickMode, ClickMode.silent);
    expect(find.textContaining('Clic apagado'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('simple-click')));
    await tester.pump();
    expect(c.clickMode, ClickMode.always);
    await tester.tap(find.byKey(const ValueKey('simple-click')));
    await tester.pump();
    expect(c.clickMode, ClickMode.untilRecording);

    // El compás: solo 3
    await tester.tap(find.byTooltip('Compás'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PopupMenuItem<TimeSignature>), findsNWidgets(3));
    await tester.tap(find.text('6/8  (3+3)').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.timeSignature.label, '6/8');

    // En avanzado vuelve todo y el pulsador es más pequeño
    c.setPlayMode(PlayMode.advanced);
    await tester.pump();
    expect(find.byType(ModeMenu), findsOneWidget);
    expect(find.byType(OnSoundToggle), findsOneWidget);
    expect(find.byType(ClickMenu), findsOneWidget);
    expect(find.byType(SimpleClickToggle), findsNothing);
    expect(find.byType(AccompanimentRow), findsOneWidget);
    final advancedPedal = tester.getSize(find.byType(Footswitch)).width;
    // Lo que falta en simple (la fila de acompañamiento con su hueco) es justo
    // lo que crece el pulsador; la pantalla de tempo mide lo mismo
    expect(tester.getSize(find.byType(TempoDisplay)).height, simpleTempo);
    final saved = tester.getSize(find.byType(AccompanimentRow)).height + 6;
    expect(saved, 52);
    expect(simplePedal - advancedPedal, closeTo(saved, 0.5));
    expect(tester.takeException(), isNull);
    c.stopAudio();
    c.dispose();
  });

  for (final size in const [Size(360, 640), Size(393, 760)]) {
    testWidgets('en ${size.width.toInt()}x${size.height.toInt()} el pulsador también crece', (
      tester,
    ) async {
      setScreen(tester, size);
      final widths = <PlayMode, double>{};
      for (final mode in PlayMode.values) {
        final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
        final c = EngineController(engine: engine)..setPlayMode(mode);
        await tester.pumpWidget(_app(LooperScreen(controller: c)));
        await tester.pump(const Duration(milliseconds: 100));
        widths[mode] = tester.getSize(find.byType(Footswitch)).width;
        // Todo cabe sin desplazar
        expect(tester.getRect(find.text('DESHACER')).bottom, lessThanOrEqualTo(size.height));
        c.stopAudio();
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
      expect(widths[PlayMode.simple]! - widths[PlayMode.advanced]!, greaterThanOrEqualTo(40));
    });
  }

  testWidgets('Ajustes: elegir el modo; en simple no está lo de grabar con el altavoz', (
    tester,
  ) async {
    setScreen(tester, const Size(393, 1400));
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(_app(SettingsScreen(controller: c)));
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Lo justo para grabar, tocar y practicar'), findsOneWidget);
    expect(find.text('Al grabar con el altavoz'), findsNothing);
    expect(find.text('Avance automático'), findsOneWidget);
    // Cómo parar y los cambios en el 1, también en simple
    expect(find.text('Al parar'), findsOneWidget);
    expect(find.text('Cambios de pista en el 1'), findsOneWidget);

    await tester.tap(find.text('Avanzado'));
    await tester.pump();
    expect(c.playMode, PlayMode.advanced);
    expect(find.text('Todos los controles'), findsOneWidget);
    expect(find.text('Al grabar con el altavoz'), findsOneWidget);

    // Mientras se graba no se cambia
    engine.next = fakeStatus(LoopState.recording);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Acaba de grabar para cambiarlo'), findsOneWidget);
    await tester.tap(find.text('Simple'));
    await tester.pump();
    expect(c.playMode, PlayMode.advanced);
    expect(tester.takeException(), isNull);
    c.stopAudio();
    c.dispose();
  });

  for (final mode in PlayMode.values) {
    testWidgets('Audio y latencia en ${mode.name}', (tester) async {
      setScreen(tester, const Size(393, 2400)); // todo a la vista
      final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
      final c = EngineController(engine: engine)..setPlayMode(mode);
      await tester.pumpWidget(_app(AudioSettingsScreen(controller: c)));
      await c.startAudio();
      await tester.pump(const Duration(milliseconds: 100));
      final advanced = mode == PlayMode.advanced;
      final there = advanced ? findsOneWidget : findsNothing;
      // Medir (sola y tocando), ganancia y escucharme, en los dos
      expect(find.text('Medir sola'), findsOneWidget);
      expect(find.text('Medir tocando al clic'), findsOneWidget);
      expect(find.text('Escucharme en directo'), findsOneWidget);
      // Lo del avanzado
      expect(find.text('Modo del micrófono'), there);
      expect(find.text('A mano'), there);
      expect(find.text('Detalles técnicos'), there);
      expect(find.textContaining('en el modo avanzado'), advanced ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
      c.stopAudio();
      c.dispose();
    });
  }

  test('lo que cambió el simple se guarda como texto', () {
    final f = SimpleForced()
      ..remember(SimpleForced.meter, '7/8')
      ..remember(SimpleForced.loopMode, 'free')
      ..remember(SimpleForced.meter, '5/4'); // se queda el primero
    final back = SimpleForced.decode(f.encode());
    expect(back[SimpleForced.meter], '7/8');
    expect(back[SimpleForced.loopMode], 'free');
    expect(SimpleForced.decode(null).isEmpty, isTrue);
    expect(SimpleForced.decode('').isEmpty, isTrue);
  });
}
