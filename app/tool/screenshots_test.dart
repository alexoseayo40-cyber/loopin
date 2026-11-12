// Loopin — capturas de la pantalla del looper con un motor de mentira
// SPDX-License-Identifier: GPL-3.0-or-later
//
// No es un test: sirve para ver cómo queda la interfaz sin móvil (y para las
// capturas del README). Uso, desde app/:
//   flutter test tool/screenshots_test.dart --update-goldens
// Deja los PNG en app/tool/screenshots/.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/engine/engine_controller.dart';
import 'package:loopin/ui/audio_settings_screen.dart';
import 'package:loopin/ui/looper_screen.dart';
import 'package:loopin/ui/settings_screen.dart';
import 'package:loopin/ui/theme.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../test/support.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockPlatform);

  setUpAll(() async {
    // Las tipografías de la app y las de Material (están en el SDK de Flutter)
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
    final material = '$flutterRoot/bin/cache/artifacts/material_fonts';
    await _loadFont(LoopinFonts.label, ['assets/fonts/BarlowCondensed-SemiBold.ttf']);
    await _loadFont(LoopinFonts.display, ['assets/fonts/ShareTechMono-Regular.ttf']);
    await _loadFont('Roboto', [
      '$material/Roboto-Regular.ttf',
      '$material/Roboto-Medium.ttf',
      '$material/Roboto-Bold.ttf',
    ]);
    await _loadFont('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  });

  Future<void> shot(
    WidgetTester tester,
    String name,
    Size size, {
    LoopState state = LoopState.recording,
    Chassis chassis = Chassis.classic,
    Brightness brightness = Brightness.dark,
    bool settings = false,
    bool audio = false,
  }) async {
    setScreen(tester, size, pixelRatio: 2);
    final engine = FakeEngine()..next = fakeStatus(state, playing: state != LoopState.stopped);
    final c = EngineController(engine: engine);
    final base = buildLoopinTheme(chassis, brightness);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Roboto')),
        home: audio
            ? AudioSettingsScreen(controller: c)
            : (settings ? SettingsScreen(controller: c) : LooperScreen(controller: c)),
      ),
    );
    await c.startAudio();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400)); // que acaben las animaciones
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
    c.stopAudio();
    c.dispose();
  }

  const phone = Size(393, 873);
  testWidgets('vertical oscuro', (t) => shot(t, 'movil-oscuro-grabando', phone));
  testWidgets(
    'vertical sonando',
    (t) => shot(t, 'movil-oscuro-sonando', phone, state: LoopState.playing),
  );
  testWidgets(
    'vertical vacío',
    (t) => shot(t, 'movil-oscuro-vacio', phone, state: LoopState.empty),
  );
  testWidgets(
    'vertical claro',
    (t) => shot(
      t,
      'movil-claro-sonando',
      phone,
      state: LoopState.playing,
      brightness: Brightness.light,
    ),
  );
  testWidgets(
    'cuenta',
    (t) =>
        shot(t, 'movil-claro-cuenta', phone, state: LoopState.armed, brightness: Brightness.light),
  );
  testWidgets(
    'rojo claro',
    (t) => shot(
      t,
      'movil-rojo-overdub',
      phone,
      state: LoopState.overdubbing,
      chassis: Chassis.red,
      brightness: Brightness.light,
    ),
  );
  testWidgets(
    'verde oscuro',
    (t) => shot(t, 'movil-verde-oscuro', phone, state: LoopState.playing, chassis: Chassis.green),
  );
  testWidgets(
    'azul claro',
    (t) => shot(
      t,
      'movil-azul-claro',
      phone,
      state: LoopState.stopped,
      chassis: Chassis.blue,
      brightness: Brightness.light,
    ),
  );
  testWidgets(
    'pequeño',
    (t) => shot(t, 'movil-pequeno', const Size(360, 640), state: LoopState.playing),
  );
  testWidgets(
    'apaisado',
    (t) => shot(t, 'movil-apaisado', const Size(873, 393), state: LoopState.playing),
  );
  testWidgets('apaisado pequeño', (t) => shot(t, 'movil-apaisado-pequeno', const Size(640, 360)));
  testWidgets(
    'tablet vertical',
    (t) => shot(
      t,
      'tablet-vertical',
      const Size(800, 1280),
      state: LoopState.playing,
      brightness: Brightness.light,
    ),
  );
  testWidgets(
    'tablet apaisada',
    (t) => shot(t, 'tablet-apaisada', const Size(1280, 800), state: LoopState.playing),
  );
  // Pantallas largas: se hacen altas para que se vea todo
  testWidgets('ajustes', (t) => shot(t, 'ajustes', const Size(393, 1100), settings: true));
  testWidgets('audio', (t) => shot(t, 'audio-y-latencia', const Size(393, 1700), audio: true));
}
