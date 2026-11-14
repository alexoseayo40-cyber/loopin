// Loopin — tests de la Etapa 7a: letra grande, «Acerca de», versión y TalkBack
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/l10n/strings.dart';
import 'package:loopin/ui/about_screen.dart';
import 'package:loopin/ui/looper_screen.dart';
import 'package:loopin/ui/pedal_widgets.dart';
import 'package:loopin/ui/settings_screen.dart';
import 'package:loopin/ui/stage_screen.dart';
import 'package:loopin/ui/theme.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'support.dart';

Widget _app(Widget home) =>
    MaterialApp(theme: buildLoopinTheme(Chassis.classic, Brightness.dark), home: home);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockPlatform);

  for (final mode in PlayMode.values) {
    for (final st in [LoopState.empty, LoopState.playing]) {
      testWidgets('TalkBack: todo lo que se toca dice qué es (${mode.name}, ${st.name})', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        setScreen(tester, const Size(393, 873));
        final c = EngineController(
          engine: FakeEngine()..next = fakeStatus(st, fx: true, drums: true),
        )..setPlayMode(mode);
        if (mode == PlayMode.advanced) c.setTrackFx(true);
        await c.startAudio();
        await tester.pumpWidget(_app(LooperScreen(controller: c)));
        await tester.pump(const Duration(milliseconds: 100));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        c.stopAudio();
        await tester.pump(const Duration(milliseconds: 400));
        c.dispose();
        handle.dispose();
      });
    }
  }

  testWidgets('TalkBack: el pulsador se toca, se mantiene y hace doble toque', (tester) async {
    final handle = tester.ensureSemantics();
    setScreen(tester, const Size(393, 873));
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine);
    await c.startAudio();
    await tester.pumpWidget(_app(LooperScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    final node = tester.getSemantics(find.byType(Footswitch));
    expect(node.label, startsWith('Botón principal'));
    final pedal = find.semantics.byLabel(RegExp('^Botón principal'));

    engine.calls.clear();
    tester.semantics.tap(pedal);
    expect(engine.calls, ['press']);

    // Que no cuente como doble toque (el controlador mira el reloj de verdad)
    Future<void> wait() =>
        tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
    await wait();
    engine.calls.clear();
    tester.semantics.longPress(pedal);
    await tester.pump(const Duration(seconds: 1));
    expect(engine.calls, ['press', 'hold']);

    await wait();
    engine.calls.clear();
    final data = pedal.evaluate().single.getSemanticsData();
    final action = data.customSemanticsActionIds!
        .map(CustomSemanticsAction.getAction)
        .firstWhere((a) => a?.label == tr.pedalDoubleAction)!;
    tester.semantics.customAction(pedal, action);
    expect(engine.calls, ['press', 'double']);
    c.stopAudio();
    await tester.pump(const Duration(milliseconds: 400));
    c.dispose();
    handle.dispose();
  });

  for (final mode in PlayMode.values) {
    testWidgets('letra del sistema al doble: la cara del pedal cabe (${mode.name})', (
      tester,
    ) async {
      setScreen(tester, const Size(360, 640));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final st in [LoopState.empty, LoopState.recording, LoopState.playing]) {
        final c = EngineController(engine: FakeEngine()..next = fakeStatus(st, drums: true))
          ..setPlayMode(mode);
        await c.startAudio();
        await tester.pumpWidget(_app(LooperScreen(controller: c)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: st.name);
        // Hasta 1,3×, no 2×
        final scale = MediaQuery.textScalerOf(tester.element(find.byType(Footswitch)));
        expect(scale.scale(10), closeTo(13, 0.01));

        // Y el modo escenario
        await tester.pumpWidget(_app(StageScreen(controller: c)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: 'escenario ${st.name}');
        await tester.pumpWidget(const SizedBox());
        c.stopAudio();
        await tester.pump(const Duration(milliseconds: 400));
        c.dispose();
      }
    });
  }

  testWidgets('Acerca de: versión, código, informar de un problema y licencias', (tester) async {
    setScreen(tester, const Size(393, 3000)); // Ajustes, sin desplazar
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing);
    final c = EngineController(engine: engine);
    await c.startAudio();
    await tester.pumpWidget(_app(SettingsScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 100));
    // La versión la da Android
    expect(c.appVersion, '1.0.0 (1)');
    expect(c.report(), startsWith('Loopin 1.0.0 (1)\n'));
    expect(find.text(tr.aboutOpenLine('1.0.0 (1)')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-about')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text(tr.aboutVersion('1.0.0 (1)')), findsOneWidget);
    expect(find.text(tr.aboutPrivacyLine), findsOneWidget);

    // El código: el navegador
    await tester.tap(find.byKey(const ValueKey('about-source')));
    await tester.pump();
    final open = platformCalls.where((m) => m.method == 'openUrl').toList();
    expect((open.last.arguments as Map)['url'], kSourceUrl);
    // Sin navegador (el test), lo dice
    await tester.pump();
    expect(find.text(tr.aboutNoBrowser), findsWidgets);

    // Informar de un problema: copia el informe y abre una incidencia nueva
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    await tester.tap(find.byKey(const ValueKey('about-report')));
    await tester.pump();
    await tester.pump();
    expect(copied, startsWith('Loopin 1.0.0 (1)'));
    expect(
      (platformCalls.where((m) => m.method == 'openUrl').last.arguments as Map)['url'],
      kIssuesUrl,
    );

    // Las licencias de lo que va dentro, con su texto
    registerLicenses();
    final entries = await tester.runAsync(() => LicenseRegistry.licenses.toList());
    final packages = {for (final e in entries!) ...e.packages};
    for (final name in ['Loopin', 'Oboe', 'SoundTouch', 'Barlow Condensed', 'Share Tech Mono']) {
      expect(packages, contains(name));
    }
    expect(packages.any((p) => p.startsWith('dr_libs')), isTrue);
    expect(packages, contains('Virtuosity Drums'));
    final oboe = entries.firstWhere((e) => e.packages.contains('Oboe'));
    expect(oboe.paragraphs.map((p) => p.text).join(' '), contains('Apache License'));
    await tester.tap(find.byKey(const ValueKey('about-licenses')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LicensePage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.stopAudio();
    await tester.pump(const Duration(milliseconds: 400));
    c.dispose();
  });

  testWidgets('el móvil no vibra: ni el pulsador, ni el secundario, ni las pistas', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });
    final engine = FakeEngine()..next = fakeStatus(LoopState.playing, fx: true);
    final c = EngineController(engine: engine)..setPlayMode(PlayMode.advanced);
    c.setTrackFx(true);
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    // Toque, mantener (deshacer) y doble toque
    c.pedalDown();
    c.pedalUp();
    c.pedalDown();
    c.pedalUp();
    c.pedalDown();
    await tester.pump(const Duration(seconds: 1));
    c.pedalUp();
    // El botón secundario (toque y mantener), elegir pista, REV y ½
    c.secondaryDown();
    c.secondaryUp();
    c.secondaryDown();
    await tester.pump(const Duration(seconds: 1));
    c.secondaryUp();
    c.selectTrack(1);
    c.toggleTrackReverse(0);
    c.toggleTrackHalf(0);
    expect(engine.calls, containsAll(['press', 'double', 'hold']));
    expect(calls.where((m) => m.startsWith('HapticFeedback')), isEmpty);
    c.stopAudio();
    await tester.pump(const Duration(milliseconds: 400));
    c.dispose();
  });
}
