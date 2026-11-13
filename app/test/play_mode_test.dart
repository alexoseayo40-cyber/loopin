// Loopin — modo simple y avanzado (Etapa 4.5)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/drums.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/engine/play_mode.dart';
import 'package:loopin/ui/audio_settings_screen.dart';
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
}

/// En simple no queda nada que no se vea.
void _expectSimpleValues(EngineController c) {
  expect(c.loopMode, LoopMode.manual);
  expect(c.startOnSound, isFalse);
  expect(kSimpleMeters, contains(c.timeSignature.label));
  expect(kSimpleClickModes, contains(c.clickMode));
  expect(kSimpleDrumStyles, contains(c.drumStyle));
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
    expect(c.clickMode, ClickMode.always);
    expect(c.drumStyle, DrumStyle.basic);
    expect(c.inputPreset, InputPreset.voiceRecognition);
    // Y el motor lo sabe
    expect(
      engine.calls,
      containsAll(['mode manual', 'onSound false', 'meter 4 0', 'click always', 'drumStyle basic']),
    );
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
    c.setPlayMode(PlayMode.advanced);
    expect(c.loopMode, LoopMode.free);
    expect(c.startOnSound, isTrue);
    expect(c.timeSignature.label, '7/8');
    expect(c.clickMode, ClickMode.countIn);
    expect(c.drumStyle, DrumStyle.funk);
    expect(c.recordDuck, RecordDuck.low);
    expect(c.inputPreset, InputPreset.generic);
    expect(prefs['simpleForced'], '');
    await _close(tester, c);
  });

  testWidgets('lo que se cambia en simple se queda al volver al avanzado', (tester) async {
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = await _open(tester, engine, {'playMode': 'advanced'});
    c.setTimeSignature(_ts('7/8'));
    c.setClickMode(ClickMode.countIn);
    c.setDrumStyle(DrumStyle.reggae); // de 4/4: cambia el compás
    c.setLoopMode(LoopMode.sync);
    c.setPlayMode(PlayMode.simple);
    expect(c.timeSignature.label, '4/4');
    // En simple elige otro compás, apaga el clic y pone el vals
    c.setTimeSignature(_ts('6/8'));
    c.setClickMode(ClickMode.silent);
    c.setDrumStyle(DrumStyle.waltz); // cambia a 3/4
    expect(c.timeSignature.label, '3/4');
    c.setPlayMode(PlayMode.advanced);
    expect(c.timeSignature.label, '3/4');
    expect(c.clickMode, ClickMode.silent);
    expect(c.drumStyle, DrumStyle.waltz);
    expect(c.loopMode, LoopMode.sync); // eso no se puede tocar en simple: vuelve
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
    expect(c.drumStyleAvailable(DrumStyle.funk), isFalse);
    c.setDrumStyle(DrumStyle.funk);
    expect(c.drumStyle, DrumStyle.basic);
    expect(c.timeSignatures.map((t) => t.label), kSimpleMeters);
    expect(c.drumStyles, kSimpleDrumStyles);
    expect(c.report(), contains('Modo de la app: simple'));
    await _close(tester, c);
  });

  testWidgets('pantalla en simple: tempo con dos filas, clic de un toque y pulsador más grande', (
    tester,
  ) async {
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = EngineController(engine: engine);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.simple, isTrue);
    expect(find.byType(ModeMenu), findsNothing);
    expect(find.byType(BarsMenu), findsNothing);
    expect(find.byType(OnSoundToggle), findsNothing);
    expect(find.byType(ClickMenu), findsNothing);
    expect(find.byType(MeterMenu), findsOneWidget);
    expect(find.text('TAP · TOCA AL RITMO'), findsOneWidget);
    expect(find.textContaining('1 compás de cuenta'), findsOneWidget); // lo que pasa al pulsar
    final simplePedal = tester.getSize(find.byType(Footswitch)).width;
    final simpleTempo = tester.getSize(find.byType(TempoDisplay)).height;

    // El clic: un toque lo apaga y otro lo enciende
    await tester.tap(find.byKey(const ValueKey('simple-click')));
    await tester.pump();
    expect(c.clickMode, ClickMode.silent);
    expect(find.textContaining('Clic apagado'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('simple-click')));
    await tester.pump();
    expect(c.clickMode, ClickMode.always);

    // El compás: solo 3
    await tester.tap(find.byTooltip('Compás'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PopupMenuItem<TimeSignature>), findsNWidgets(3));
    await tester.tap(find.text('6/8  (3+3)').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.timeSignature.label, '6/8');

    // La batería: los estilos del simple
    await tester.tap(find.byTooltip('Estilo de la batería'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PopupMenuItem<DrumStyle>), findsNWidgets(kSimpleDrumStyles.length));
    expect(find.text('Funk · 4/4'), findsNothing);
    expect(find.text('Rock · 4/4'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // cierra el menú
    await tester.pump(const Duration(milliseconds: 400));

    // En avanzado vuelve todo y el pulsador es más pequeño
    c.setPlayMode(PlayMode.advanced);
    await tester.pump();
    expect(find.byType(ModeMenu), findsOneWidget);
    expect(find.byType(OnSoundToggle), findsOneWidget);
    expect(find.byType(ClickMenu), findsOneWidget);
    expect(find.byType(SimpleClickToggle), findsNothing);
    final advancedPedal = tester.getSize(find.byType(Footswitch)).width;
    // La fila que falta en simple es justo lo que crece el pulsador
    final saved = tester.getSize(find.byType(TempoDisplay)).height - simpleTempo;
    expect(saved, 44);
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
      expect(widths[PlayMode.simple]! - widths[PlayMode.advanced]!, greaterThanOrEqualTo(36));
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
    expect(find.text('Lo justo para grabar y tocar'), findsOneWidget);
    expect(find.text('Al grabar con el altavoz'), findsNothing);
    expect(find.text('Avance automático'), findsOneWidget);

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
    // Los estilos del simple son de sus compases
    for (final s in kSimpleDrumStyles) {
      final m = drumStyleMeter(s);
      expect(m == null || kSimpleMeters.contains(m), isTrue, reason: s.name);
    }
  });
}
