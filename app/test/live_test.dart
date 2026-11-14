// Loopin — directo y práctica (Etapa 5): afinador, reverse y media velocidad,
// cambios al compás, cómo parar y entrenador de tempo
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/engine/status_change.dart';
import 'package:loopin/engine/tuner.dart';
import 'package:loopin/ui/looper/pedal_area.dart';
import 'package:loopin/ui/looper_screen.dart';
import 'package:loopin/ui/settings_screen.dart';
import 'package:loopin/ui/theme.dart';
import 'package:loopin/ui/tuner_screen.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'support.dart';

Widget _app(Widget home) =>
    MaterialApp(theme: buildLoopinTheme(Chassis.classic, Brightness.dark), home: home);

Future<EngineController> _open(
  WidgetTester tester,
  FakeEngine engine,
  Map<String, String> prefs, {
  PlayMode mode = PlayMode.advanced,
}) async {
  prefs.putIfAbsent('playMode', () => mode.name);
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

void main() {
  // ---------------------------------------------------------------- afinador

  test('de la frecuencia a la nota y los cents', () {
    final e2 = noteFor(82.41)!;
    expect(e2.midi, 40);
    expect(e2.pitchClass, 4); // Mi
    expect(e2.octave, 2);
    expect(e2.cents.abs(), lessThan(0.5));
    expect(e2.standardString, 0);
    expect(e2.inTune, isTrue);
    final flat = noteFor(440 * 0.99)!; // 17 cents por debajo del La
    expect(flat.midi, 69);
    expect(flat.cents, closeTo(-17.4, 0.1));
    expect(flat.inTune, isFalse);
    expect(flat.standardString, isNull);
    // Con La = 432, 432 Hz es un La afinado
    expect(noteFor(432, a4: 432)!.cents.abs(), lessThan(0.01));
    expect(noteFor(0), isNull);
  });

  test('filtro del afinador: quita lecturas sueltas, no salta de nota y mantiene la última', () {
    final f = TunerFilter();
    TunerReading r(double hz, [double clarity = 0.95]) =>
        TunerReading(frequency: hz, clarity: clarity, levelDb: -20);
    var d = f.update(r(110), Duration.zero);
    expect(d.note!.midi, 45);
    expect(d.live, isTrue);
    // Una lectura suelta a la octava: la mediana la quita
    d = f.update(r(220), const Duration(milliseconds: 33));
    expect(d.note!.midi, 45);
    d = f.update(r(110.2), const Duration(milliseconds: 66));
    expect(d.note!.midi, 45);
    // Los cents se suavizan (no saltan de golpe a lo último)
    d = f.update(r(111.5), const Duration(milliseconds: 100));
    expect(d.note!.cents, greaterThan(0));
    expect(d.note!.cents, lessThan(noteFor(111.5)!.cents));
    // Otra nota: hace falta oírla dos veces seguidas
    f.reset();
    f.update(r(110), Duration.zero);
    f.update(r(146.8), const Duration(milliseconds: 33));
    f.update(r(146.8), const Duration(milliseconds: 66));
    d = f.update(r(146.8), const Duration(milliseconds: 100));
    expect(d.note!.midi, 50);
    // Poco clara: no cuenta, pero la última se mantiene un momento (apagada)
    d = f.update(r(300, 0.4), const Duration(milliseconds: 500));
    expect(d.note!.midi, 50);
    expect(d.live, isFalse);
    d = f.update(null, const Duration(seconds: 3));
    expect(d.note, isNull);
  });

  testWidgets('pantalla del afinador: enciende la toma, enseña la nota y la apaga al salir', (
    tester,
  ) async {
    setScreen(tester, const Size(393, 1400));
    final engine = FakeEngine()
      ..next = fakeStatus(LoopState.empty, playing: false)
      ..tuner = const TunerReading(frequency: 81.95, clarity: 0.97, levelDb: -18);
    final c = await _open(tester, engine, {}, mode: PlayMode.simple);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    // Está en la cabecera (también en simple)
    await tester.tap(find.byKey(const ValueKey('open-tuner')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TunerScreen), findsOneWidget);
    expect(engine.calls, contains('tuner true'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.text('MI'), findsWidgets);
    expect(find.text('E2'), findsOneWidget);
    expect(find.text('BAJA · aprieta'), findsOneWidget);
    // También en simple: el La de referencia y las notas para afinar de oído
    expect(find.text('La de referencia'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('tone-40')), 100);
    await tester.tap(find.byKey(const ValueKey('tone-40')));
    await tester.pump();
    expect(engine.calls.last, 'tone 82.4'); // Mi grave
    expect(c.toneMidi, 40);
    await tester.tap(find.byKey(const ValueKey('tone-69')));
    await tester.pump();
    expect(engine.calls.last, 'tone 440.0');
    // Cambiar el La mueve la nota que suena
    c.setTunerA4(442);
    expect(engine.calls.last, 'tone 442.0');
    c.setTunerA4(440);
    // Otra vez la misma: se calla
    await tester.tap(find.byKey(const ValueKey('tone-69')));
    await tester.pump();
    expect(engine.calls.last, 'tone 0.0');
    expect(c.toneMidi, isNull);
    await tester.tap(find.byKey(const ValueKey('tone-45')));
    await tester.pump();
    expect(engine.calls.last, 'tone 110.0');
    await tester.scrollUntilVisible(find.text('E2'), -100);
    // Afinada
    engine.tuner = const TunerReading(frequency: 82.41, clarity: 0.97, levelDb: -18);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.text('AFINADA'), findsOneWidget);
    // Al salir, la toma se apaga y la nota se calla
    await tester.pageBack();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(TunerScreen), findsNothing);
    expect(engine.calls.lastWhere((e) => e.startsWith('tuner')), 'tuner false');
    expect(engine.calls.lastWhere((e) => e.startsWith('tone')), 'tone 0.0');
    expect(tester.takeException(), isNull);
    await _close(tester, c);
  });

  testWidgets('afinador: La de referencia, guardado, en los dos modos', (tester) async {
    setScreen(tester, const Size(393, 1400));
    final prefs = <String, String>{};
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = await _open(tester, engine, prefs);
    await tester.pumpWidget(_app(TunerScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('La = 440 Hz'), findsOneWidget);
    expect(find.text('Toca una cuerda al aire'), findsWidgets);
    c.setTunerA4(442);
    await tester.pump();
    expect(find.text('La = 442 Hz'), findsOneWidget);
    expect(prefs['tunerA4'], '442');
    // En simple, el mismo
    c.setPlayMode(PlayMode.simple);
    expect(c.tunerA4, 442);
    await tester.pump();
    expect(find.text('La = 442 Hz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _close(tester, c);
  });

  // ---------------------------------------------------------------- pistas

  testWidgets('REV y ½ de la pista elegida (solo en avanzado), con punto si esperan al 1', (
    tester,
  ) async {
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing, fx: true);
    final c = await _open(tester, engine, {'trackFx': '1'});
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    // La pista 2 (elegida) va al revés (esperando al 1) y a media velocidad
    expect(find.byKey(const ValueKey('reverse-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('pending-dot')), findsOneWidget);
    expect(find.text('4 C · 2 · REV ½'), findsOneWidget);
    expect(find.text('4 C · REV'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reverse-1')));
    expect(engine.calls.last, 'reverse 1 false');
    await tester.tap(find.byKey(const ValueKey('half-1')));
    expect(engine.calls.last, 'half 1 false');
    // En una pista vacía no se puede
    expect(c.trackFxAvailable(3), isFalse);
    c.toggleTrackReverse(3);
    expect(engine.calls.last, isNot('reverse 3 true'));
    // Ni en la que se está grabando
    engine.next = fakeStatus(LoopState.overdubbing, fx: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.trackFxAvailable(1), isFalse);
    expect(c.trackFxAvailable(0), isTrue);
    // En simple no están y, al entrar, se quitan los efectos de todas
    engine.next = fakeStatus(LoopState.playing, fx: true);
    await tester.pump(const Duration(milliseconds: 100));
    engine.calls.clear();
    c.setPlayMode(PlayMode.simple);
    await tester.pump();
    expect(engine.calls, containsAll(['reverse 0 false', 'reverse 1 false', 'half 1 false']));
    expect(find.byKey(const ValueKey('reverse-1')), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester, c);
  });

  testWidgets('efectos de pista: apagados de serie; al apagarlos se quitan', (tester) async {
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing, fx: true);
    final prefs = <String, String>{};
    final c = await _open(tester, engine, prefs);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.trackFx, isFalse);
    expect(find.byKey(const ValueKey('reverse-1')), findsNothing);
    expect(c.trackFxAvailable(1), isFalse);
    c.toggleTrackReverse(1);
    expect(engine.calls, isNot(contains('reverse 1 false')));
    // Se encienden en Ajustes
    c.setTrackFx(true);
    await tester.pump();
    expect(prefs['trackFx'], '1');
    expect(find.byKey(const ValueKey('reverse-1')), findsOneWidget);
    // Al apagarlos, se quitan de las pistas que los tienen
    engine.calls.clear();
    c.setTrackFx(false);
    await tester.pump();
    expect(engine.calls, containsAll(['reverse 0 false', 'reverse 1 false', 'half 1 false']));
    expect(find.byKey(const ValueKey('reverse-1')), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester, c);
  });

  test('un cambio de reverse, ½ o pendiente redibuja la pantalla', () {
    final a = fakeStatus(LoopState.playing);
    final b = fakeStatus(LoopState.playing, fx: true);
    expect(layoutChanged(a, b), isTrue);
    expect(layoutChanged(a, fakeStatus(LoopState.playing, stopping: 1)), isTrue);
    expect(layoutChanged(a, fakeStatus(LoopState.playing)), isFalse);
  });

  // ---------------------------------------------------------------- parar

  testWidgets('al parar: el modo va al motor, se guarda y vale en los dos modos', (tester) async {
    setScreen(tester, const Size(393, 1500));
    final prefs = <String, String>{};
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = await _open(tester, engine, prefs);
    // De serie: al momento y cambios en el 1
    expect(engine.calls, containsAll(['stopMode now', 'quantize true', 'fade 4.0']));
    await tester.pumpWidget(_app(SettingsScreen(controller: c)));
    await tester.pump();
    await tester.tap(find.text('Fundido'));
    await tester.pump();
    expect(engine.calls.last, 'stopMode fade');
    expect(prefs['stopMode'], 'fade');
    await tester.tap(find.byKey(const ValueKey('quantize')));
    await tester.pump();
    expect(engine.calls.last, 'quantize false');
    expect(prefs['quantize'], '0');
    // ■ pide parar (el motor sabe cómo)
    c.togglePlay();
    expect(engine.calls.last, 'stop');
    // En simple, igual (y se ve en Ajustes)
    engine.calls.clear();
    c.setPlayMode(PlayMode.simple);
    expect(c.stopMode, StopMode.fade);
    expect(c.quantize, isFalse);
    expect(engine.calls, isNot(contains('stopMode now')));
    await tester.pump();
    expect(find.text('Al parar'), findsOneWidget);
    expect(find.text('Silenciar una pista espera al siguiente 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _close(tester, c);
  });

  test('parando: el pulsador lo dice y para ya', () {
    final s = fakeStatus(LoopState.playing, stopping: 2);
    final look = pedalLook(s, mode: LoopMode.sync, startOnSound: false);
    expect(look.title, 'BAJANDO…');
    expect(look.subtitle, 'Toca para parar ya');
    final bar = pedalLook(
      fakeStatus(LoopState.playing, stopping: 1),
      mode: LoopMode.sync,
      startOnSound: false,
    );
    expect(bar.title, 'PARA EN EL 1');
  });

  // ---------------------------------------------------------------- entrenador

  testWidgets('entrenador: se enciende en su hoja, sube en el motor y enseña su tempo', (
    tester,
  ) async {
    setScreen(tester, const Size(393, 873));
    final prefs = <String, String>{};
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = await _open(tester, engine, prefs);
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('TAP · TOCA AL RITMO'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trainer-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('trainer-switch')));
    await tester.pump();
    expect(c.trainerOn, isTrue);
    // De 92 (el tempo de serie) a 140, +5 cada 4 compases
    expect(engine.calls.last, 'trainer 4 5 140');
    expect(find.text('De 92 a 140 BPM: +5 cada 4 compases (10 subidas)'), findsOneWidget);
    await tester.tap(find.text('2 C'));
    await tester.pump();
    expect(engine.calls.last, 'trainer 2 5 140');
    expect(prefs['trainerBars'], '2');
    await tester.tap(find.byKey(const ValueKey('trainer-step-up')));
    await tester.pump();
    expect(engine.calls.last, 'trainer 2 6 140');
    await tester.tap(find.byKey(const ValueKey('trainer-top-down')));
    await tester.pump();
    expect(engine.calls.last, 'trainer 2 6 135');
    expect(prefs['trainerTop'], '135');
    // Se cierra la hoja: en lugar del TAP, lo que hará
    await tester.tapAt(const Offset(200, 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('ENTRENADOR +6 / 2 C · HASTA 135'), findsOneWidget);
    // Sonando, el tempo que se ve es el del motor (el que ha subido)
    engine.next = fakeStatus(LoopState.empty);
    final s = engine.next;
    engine.next = EngineStatus(
      running: true,
      playing: true,
      sampleRate: s.sampleRate,
      bpm: 104,
      beatsPerBar: 4,
      samplesPerBeat: s.samplesPerBeat,
      inputDeviceId: s.inputDeviceId,
      outputDeviceId: s.outputDeviceId,
      trainerBars: 2,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.shownBpm, 104);
    expect(find.text('104'), findsOneWidget);
    expect(c.bpm, 92); // el del usuario no cambia
    // Con loops no se puede encender (el tempo es suyo)
    c.setTrainerOn(false);
    engine.next = fakeStatus(LoopState.playing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.trainerAvailable, isFalse);
    c.setTrainerOn(true);
    expect(c.trainerOn, isFalse);
    expect(tester.takeException(), isNull);
    await _close(tester, c);
  });

  testWidgets('entrenador en simple: está y sigue encendido al cambiar de modo', (tester) async {
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = await _open(tester, engine, {});
    c.setTrainerOn(true);
    expect(engine.calls.last, 'trainer 4 5 140');
    engine.calls.clear();
    c.setPlayMode(PlayMode.simple);
    expect(c.trainerOn, isTrue);
    expect(engine.calls, isNot(contains('trainer 0 5 140')));
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('trainer-button')), findsOneWidget);
    expect(find.text('ENTRENADOR +5 / 4 C · HASTA 140'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester, c);
  });

  testWidgets('los ajustes de directo y práctica se guardan entre sesiones', (tester) async {
    final prefs = <String, String>{
      'stopMode': 'bar',
      'quantize': '0',
      'trainerStep': '3',
      'trainerBars': '8',
      'trainerTop': '180',
      'tunerA4': '438',
    };
    final engine = FakeEngine()..next = fakeStatus(LoopState.empty, playing: false);
    final c = await _open(tester, engine, prefs);
    expect(c.stopMode, StopMode.bar);
    expect(c.quantize, isFalse);
    expect(c.trainerStep, 3);
    expect(c.trainerBars, 8);
    expect(c.trainerTop, 180);
    expect(c.tunerA4, 438);
    expect(engine.calls, containsAll(['stopMode bar', 'quantize false', 'trainer 0 3 180']));
    await _close(tester, c);
  });
}
