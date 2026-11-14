// Loopin — tests de los idiomas (Etapa 7b): que no falte ni sobre ningún texto,
// que los parámetros y plurales cuadren y que todo quepa en cada idioma
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/l10n/language.dart';
import 'package:loopin/l10n/message.dart';
import 'package:loopin/l10n/strings.dart';
import 'package:loopin/ui/audio_settings_screen.dart';
import 'package:loopin/ui/looper_screen.dart';
import 'package:loopin/ui/sessions_screen.dart';
import 'package:loopin/ui/settings_screen.dart';
import 'package:loopin/ui/stage_screen.dart';
import 'package:loopin/ui/theme.dart';
import 'package:loopin/ui/tuner_screen.dart';
import 'package:loopin/ui/tutorial_screen.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'support.dart';

Widget _app(Widget home) =>
    MaterialApp(theme: buildLoopinTheme(Chassis.classic, Brightness.dark), home: home);

Map<String, String> _json(String lang) =>
    (jsonDecode(File('assets/l10n/$lang.json').readAsStringSync()) as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as String),
    );

/// Unos valores para cada parámetro, para rellenar los textos.
Map<String, Object> _sample(Message m) => {for (final a in m.argNames) a: 2};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockPlatform);
  tearDown(() => AppLanguage.useForTests('es'));

  final es = _json('es');

  group('los JSON', () {
    for (final lang in kLanguages) {
      test('$lang: las mismas claves que es.json, bien escritas y con los mismos parámetros', () {
        final texts = _json(lang);
        final missing = es.keys.where((k) => !texts.containsKey(k)).toList();
        final extra = texts.keys.where((k) => !es.containsKey(k)).toList();
        expect(missing, isEmpty, reason: 'A $lang.json le faltan textos');
        expect(extra, isEmpty, reason: 'A $lang.json le sobran textos');
        for (final key in es.keys) {
          final ref = Message.parse(es[key]!);
          final Message msg;
          try {
            msg = Message.parse(texts[key]!);
          } on FormatException catch (e) {
            fail('$lang.json, «$key» está mal escrito: ${e.message}');
          }
          expect(msg.argNames, ref.argNames, reason: '$lang.json, «$key»: parámetros');
          // Cada plural o select del español está también en la traducción
          expect(msg.choices.keys.toSet(), ref.choices.keys.toSet(), reason: '$lang «$key»');
          final filled = msg.format(_sample(msg), lang: lang);
          expect(filled, isNot(contains('{')), reason: '$lang «$key»');
          expect(filled.trim(), isNotEmpty, reason: '$lang «$key» está vacío');
        }
      });
    }

    test('ningún texto de es.json sobra: todos se usan en strings.dart', () {
      final dart = File('lib/l10n/strings.dart').readAsStringSync();
      final unused = es.keys.where((key) {
        if (dart.contains("'$key'")) return false;
        // Las de un grupo («presetName.unprocessed») se piden por su prefijo
        final dot = key.lastIndexOf('.');
        if (dot < 0) return true;
        final group = key.substring(0, dot);
        return !dart.contains("'$group'") && !dart.contains("'$group.");
      }).toList();
      expect(unused, isEmpty);
    });

    test('los textos se pueden copiar a Weblate: un JSON plano de texto a texto', () {
      for (final lang in kLanguages) {
        final raw = jsonDecode(File('assets/l10n/$lang.json').readAsStringSync());
        expect(raw, isA<Map<String, dynamic>>());
        for (final v in (raw as Map).values) {
          expect(v, isA<String>());
        }
      }
    });
  });

  group('el formato de los textos', () {
    test('parámetros, plural y select', () {
      String f(String src, Map<String, Object> a, [String lang = 'es']) =>
          Message.parse(src).format(a, lang: lang);
      expect(f('Pista {n}', {'n': 2}), 'Pista 2');
      const bars = '{n, plural, one {# compás} other {# compases}}';
      expect(f(bars, {'n': 1}), '1 compás');
      expect(f(bars, {'n': 4}), '4 compases');
      expect(f(bars, {'n': 0}), '0 compases');
      expect(f(bars, {'n': 0}, 'fr'), '0 compás'); // en francés, 0 es singular
      expect(f('{n, plural, =0 {nada} one {uno} other {#}}', {'n': 0}), 'nada');
      expect(f('{x, select, on {encendida} other {apagada}}', {'x': 'on'}), 'encendida');
      expect(f('{x, select, on {encendida} other {apagada}}', {'x': 'otra'}), 'apagada');
      expect(f("l'app {n}", {'n': 1}), "l'app 1"); // el apóstrofo es texto
      for (final bad in ['{n', 'a}', '{n, plural, one {x}}', '{n, other}', '{1}']) {
        expect(() => Message.parse(bad), throwsFormatException, reason: bad);
      }
    });

    test('números, fechas y plurales en cada idioma', () {
      AppLanguage.useForTests('en');
      expect(tr.bars(1), '1 bar');
      expect(tr.bars(4), '4 bars');
      expect(tr.ms(85.7), '85.7 ms');
      expect(tr.percent(0.7), '70%');
      expect(tr.bpmNumber(97.3), '97.3');
      expect(tr.sessionDefaultName(DateTime(2026, 11, 13, 18, 50)), 'Session Nov 13 · 18:50');
      // «:» no vale en un nombre de archivo
      expect(
        tr.exportFileName(tr.exportFileBase('Session Nov 13 · 18:50'), tr.exportTrack(1)),
        'Session Nov 13 18 50 - track 1.wav',
      );
      expect(tr.sessionWhen(DateTime(2025, 3, 2, 9, 5), DateTime(2026, 11, 14)), 'Mar 2, 2025');

      AppLanguage.useForTests('es');
      expect(tr.ms(85.7), '85,7 ms');
      expect(tr.percent(0.7), '70 %');
      expect(tr.sessionDefaultName(DateTime(2026, 11, 13, 18, 50)), 'Sesión 13 nov · 18:50');
      expect(tr.sessionWhen(DateTime(2026, 11, 14, 9, 5), DateTime(2026, 11, 14)), 'hoy 09:05');

      AppLanguage.useForTests('de');
      expect(tr.bpmNumber(97.3), '97,3');
      expect(tr.sessionWhen(DateTime(2026, 3, 2), DateTime(2026, 11, 14)), '2. März');
      expect(tr.exportDone(1), 'Fertig: 1 Datei.');
      expect(tr.exportDone(3), 'Fertig: 3 Dateien.');

      AppLanguage.useForTests('fr');
      expect(tr.bars(0), '0 mesure');
      expect(tr.clickLabel(ClickMode.always), 'Clic : toujours');

      AppLanguage.useForTests('pt');
      expect(tr.sessionDefaultName(DateTime(2026, 11, 13, 18, 50)), 'Sessão 13 nov · 18:50');
    });

    test('las notas del afinador: letras en inglés y alemán (con H), do-re-mi en los demás', () {
      final names = {
        for (final lang in kLanguages)
          lang: [for (var i = 0; i < 12; i++) AppLanguage.loaded(lang)!.noteName(i)],
      };
      expect(names['en'], ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']);
      expect(names['de']!.last, 'H');
      expect(names['de']!.first, 'C');
      expect(names['es']!.take(3), ['DO', 'DO#', 'RE']);
      expect(names['fr']![2], 'RÉ');
      expect(names['it']![2], 'RE');
      expect(names['pt']![0], 'DÓ');
      expect(names['pt']![9], 'LÁ');
      expect(AppLanguage.loaded('de')!.noteLetter(11, 2), 'H2');
      expect(AppLanguage.loaded('en')!.noteLetter(4, 2), 'E2');
      expect(AppLanguage.loaded('en')!.referenceA4(440), 'A 440');
    });
  });

  group('elegir el idioma', () {
    test('el del móvil: el primero que tenga la app; si no, inglés', () {
      expect(languageFor(const [Locale('ca', 'ES'), Locale('es', 'ES')]), 'es');
      expect(languageFor(const [Locale('pt', 'BR')]), 'pt');
      expect(languageFor(const [Locale('de', 'AT'), Locale('en')]), 'de');
      expect(languageFor(const [Locale('ja'), Locale('ko')]), 'en');
      expect(languageFor(const []), 'en');
    });

    test('se guarda, y «el del móvil» lo sigue', () async {
      final prefs = <String, String>{};
      mockPlatform(prefs);
      final saved = AppLanguage.systemLocales;
      addTearDown(() => AppLanguage.systemLocales = saved);
      AppLanguage.systemLocales = () => const [Locale('it', 'IT')];

      await AppLanguage.init();
      expect(AppLanguage.setting, '');
      expect(tr.lang, 'it');
      expect(tr.settings, 'Impostazioni');

      await AppLanguage.choose('de');
      expect(prefs['language'], 'de');
      expect(tr.settings, 'Einstellungen');
      expect(AppLanguage.current.value, 'de');

      // Al abrir la app otra vez
      await AppLanguage.init();
      expect(tr.lang, 'de');

      await AppLanguage.choose('');
      expect(prefs['language'], '');
      expect(tr.lang, 'it');

      // Un valor raro guardado: el del móvil
      prefs['language'] = 'xx';
      await AppLanguage.init();
      expect(AppLanguage.setting, '');
    });

    test('«Copiar resultados»: en español con la app en español; si no, en inglés', () async {
      final c = EngineController(engine: FakeEngine()..next = fakeStatus(LoopState.playing));
      await c.startAudio();
      AppLanguage.useForTests('es');
      expect(c.report(), contains('Móvil: Test · Android 16'));
      AppLanguage.useForTests('fr');
      final r = c.report();
      expect(r, contains('Phone: Test · Android 16'));
      expect(r, contains('Metronome: 4/4 · click: until recording'));
      expect(r, contains('App mode: simple'));
      expect(r, isNot(contains('Métronome')));
      c.stopAudio();
      c.dispose();
    });

    testWidgets('en Ajustes: cambia el idioma de todo al momento', (tester) async {
      final prefs = <String, String>{};
      mockPlatform(prefs);
      setScreen(tester, const Size(393, 3000));
      final c = EngineController(engine: FakeEngine()..next = fakeStatus(LoopState.playing));
      await c.startAudio();
      await tester.pumpWidget(_app(SettingsScreen(controller: c)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Idioma'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('language')));
      await tester.pumpAndSettle();
      // Cada idioma con su nombre en su idioma
      for (final name in kLanguageNames.values) {
        expect(find.text(name), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('language-de')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(prefs['language'], 'de');
      expect(AppLanguage.current.value, 'de');
      // La pantalla se redibuja (en la app lo hace main.dart; aquí, un pump nuevo)
      await tester.pumpWidget(_app(SettingsScreen(controller: c, key: const ValueKey('de'))));
      await tester.pump();
      expect(find.text('Einstellungen'), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.stopAudio();
      await tester.pump(const Duration(milliseconds: 400));
      c.dispose();
    });
  });

  // ------------------------------------------------------------- que todo quepa

  for (final lang in kLanguages) {
    for (final size in const [Size(360, 640), Size(412, 760), Size(732, 360)]) {
      for (final scale in const [1.0, 1.3]) {
        testWidgets('$lang: el looper cabe en ${size.width.round()}×${size.height.round()} '
            'con la letra a $scale', (tester) async {
          AppLanguage.useForTests(lang);
          setScreen(tester, size);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          for (final mode in PlayMode.values) {
            for (final st in LoopState.values) {
              final c = EngineController(
                engine: FakeEngine()..next = fakeStatus(st, drums: true, fx: true),
              )..setPlayMode(mode);
              if (mode == PlayMode.advanced) c.setTrackFx(true);
              await c.startAudio();
              await tester.pumpWidget(_app(LooperScreen(controller: c)));
              await tester.pump(const Duration(milliseconds: 100));
              expect(tester.takeException(), isNull, reason: '$lang ${mode.name} ${st.name}');
              if (st == LoopState.playing || st == LoopState.recording) {
                await tester.pumpWidget(_app(StageScreen(controller: c)));
                await tester.pump(const Duration(milliseconds: 100));
                expect(tester.takeException(), isNull, reason: '$lang escenario ${st.name}');
              }
              await tester.pumpWidget(const SizedBox());
              c.stopAudio();
              await tester.pump(const Duration(milliseconds: 400));
              c.dispose();
            }
          }
        });
      }
    }

    testWidgets('$lang: Ajustes, Audio y latencia, afinador, sesiones y guía caben en 360×640', (
      tester,
    ) async {
      AppLanguage.useForTests(lang);
      setScreen(tester, const Size(360, 640));
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final mode in PlayMode.values) {
        final c = EngineController(engine: FakeEngine()..next = fakeStatus(LoopState.playing))
          ..setPlayMode(mode);
        await c.startAudio();
        final screens = <String, Widget>{
          'ajustes': SettingsScreen(controller: c),
          'audio': AudioSettingsScreen(controller: c),
          'afinador': TunerScreen(controller: c),
          'sesiones': SessionsScreen(controller: c),
          'guía': TutorialScreen(controller: c),
        };
        for (final MapEntry(key: name, value: screen) in screens.entries) {
          await tester.pumpWidget(_app(screen));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull, reason: '$lang ${mode.name} $name');
          // Desplazando hasta abajo (lo que no se ve tampoco puede desbordarse)
          final scrollable = find.byType(Scrollable);
          if (scrollable.evaluate().isNotEmpty) {
            await tester.drag(scrollable.first, const Offset(0, -3000));
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.takeException(), isNull, reason: '$lang ${mode.name} $name abajo');
          }
        }
        // Las páginas de la guía
        await tester.pumpWidget(_app(TutorialScreen(controller: c)));
        await tester.pump(const Duration(milliseconds: 100));
        for (var page = 0; page < 4; page++) {
          await tester.tap(find.text(tr.tutorialNext));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$lang guía página ${page + 2}');
        }
        await tester.pumpWidget(const SizedBox());
        c.stopAudio();
        await tester.pump(const Duration(milliseconds: 400));
        c.dispose();
      }
    });
  }
}
