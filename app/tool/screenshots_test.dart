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
import 'package:loopin/engine/songs.dart';
import 'package:loopin/ui/settings_screen.dart';
import 'package:loopin/ui/song_screen.dart';
import 'package:loopin/ui/songs_screen.dart';
import 'package:loopin/ui/theme.dart';
import 'package:loopin/ui/tuner_screen.dart';
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

const _songs = [
  Song(id: 1, name: 'Blues en La', file: '1.mp3', bpm: 92, mark: 0.41, seconds: 214),
  Song(id: 2, name: 'Mi maqueta (toma 3)', file: '2.wav', bpm: 0),
  Song(id: 3, name: 'Vals para Marta', file: '3.flac', bpm: 84.5, mark: 1.2, meter: '3/4'),
];

/// El mismo estado con una canción cargada y sonando (o abierta para
/// prepararla, si no suena)
EngineStatus _songStatus(EngineStatus s, {required bool playing}) {
  final peaks = <double>[];
  return EngineStatus(
    running: true,
    sampleRate: 48000,
    playing: s.playing,
    bpm: 92,
    beatsPerBar: 4,
    beat: s.beat,
    samplesPerBeat: 31304,
    beatFrames: s.beatFrames,
    inputDeviceId: s.inputDeviceId,
    outputDeviceId: s.outputDeviceId,
    outputLatencyMs: 40,
    inputPeak: s.inputPeak,
    loopState: s.loopState,
    loopBarFrames: s.loopBarFrames,
    loopLength: s.loopLength,
    loopPosition: s.loopPosition,
    loopLayers: s.loopLayers,
    selectedTrack: s.selectedTrack,
    autoAdvance: true,
    baseLength: s.baseLength,
    basePosition: s.basePosition,
    tracks: s.tracks,
    songPrepId: 1,
    songPrepState: JobState.done,
    backingId: playing ? 1 : 0,
    backingSamplesPerBeat: 31304,
    backingBeatsPerBar: 4,
    backingEnabled: playing,
    backingPlaying: playing,
    songOpenId: 2,
    songOpenState: JobState.done,
    songOpenFrames: 48000 * 187,
    songBpmGuess: 101.96,
    songFirstAttack: 30000,
    previewId: 2,
    previewPosition: 400000 + peaks.length,
  );
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
    DrumStyle? drums,
    bool song = false,
    PlayMode mode = PlayMode.advanced,
    Widget Function(EngineController c)? home,
    bool fx = false,
    int stopping = 0,
    TunerReading? tuner,
    Future<void> Function(WidgetTester t, EngineController c)? after,
  }) async {
    setScreen(tester, size, pixelRatio: 2);
    final engine = FakeEngine()
      ..tuner = tuner
      ..next = fakeStatus(
        state,
        playing: state != LoopState.stopped,
        drums: drums != null,
        fx: fx,
        stopping: stopping,
      );
    if (song || home != null) engine.next = _songStatus(engine.next, playing: song);
    final c = EngineController(engine: engine, songs: SongLibrary.memory(_songs))
      ..setPlayMode(mode);
    final base = buildLoopinTheme(chassis, brightness);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Roboto')),
        home: home != null
            ? home(c)
            : audio
            ? AudioSettingsScreen(controller: c)
            : (settings ? SettingsScreen(controller: c) : LooperScreen(controller: c)),
      ),
    );
    await c.startAudio();
    if (song) {
      await tester.pump(const Duration(milliseconds: 50));
      c.selectSong(_songs.first);
      c.setBackingOn(true);
    }
    if (drums != null) {
      c.setDrumStyle(drums);
      c.setDrumsOn(true);
    }
    await tester.pump(const Duration(milliseconds: 100));
    if (after != null) await after(tester, c);
    await tester.pump(const Duration(milliseconds: 400)); // que acaben las animaciones
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
    c.stopAudio();
    c.dispose();
  }

  const phone = Size(393, 873);
  // Modo simple
  testWidgets(
    'simple',
    (t) => shot(t, 'simple-sonando', phone, state: LoopState.playing, mode: PlayMode.simple),
  );
  testWidgets(
    'simple vacío',
    (t) => shot(
      t,
      'simple-vacio',
      phone,
      state: LoopState.empty,
      brightness: Brightness.light,
      mode: PlayMode.simple,
    ),
  );
  testWidgets(
    'simple pequeño',
    (t) => shot(
      t,
      'simple-pequeno',
      const Size(360, 640),
      state: LoopState.playing,
      mode: PlayMode.simple,
    ),
  );
  testWidgets(
    'simple apaisado',
    (t) => shot(
      t,
      'simple-apaisado',
      const Size(873, 393),
      state: LoopState.playing,
      mode: PlayMode.simple,
    ),
  );
  testWidgets(
    'ajustes simple',
    (t) => shot(
      t,
      'ajustes-simple',
      const Size(393, 1000),
      settings: true,
      state: LoopState.playing,
      mode: PlayMode.simple,
    ),
  );
  testWidgets(
    'audio simple',
    (t) => shot(
      t,
      'audio-simple',
      const Size(393, 1100),
      audio: true,
      state: LoopState.playing,
      mode: PlayMode.simple,
    ),
  );
  testWidgets(
    'canción',
    (t) => shot(t, 'movil-cancion', phone, state: LoopState.playing, song: true),
  );
  testWidgets(
    'canción pequeño',
    (t) => shot(
      t,
      'movil-cancion-pequeno',
      const Size(360, 640),
      state: LoopState.playing,
      song: true,
    ),
  );
  testWidgets(
    'canciones',
    (t) => shot(
      t,
      'canciones',
      phone,
      state: LoopState.empty,
      home: (c) => SongsScreen(controller: c),
    ),
  );
  testWidgets(
    'preparar canción',
    (t) => shot(
      t,
      'preparar-cancion',
      const Size(393, 1250),
      state: LoopState.empty,
      home: (c) => SongScreen(controller: c, song: _songs[1]),
    ),
  );
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
    'batería',
    (t) => shot(t, 'movil-bateria', phone, state: LoopState.playing, drums: DrumStyle.rock),
  );
  testWidgets(
    'batería clara',
    (t) => shot(
      t,
      'movil-bateria-claro',
      phone,
      state: LoopState.playing,
      brightness: Brightness.light,
      drums: DrumStyle.funk,
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
  testWidgets('ajustes', (t) => shot(t, 'ajustes', const Size(393, 1500), settings: true));
  // Etapa 5: directo y práctica
  testWidgets(
    'reverse, media velocidad y parando',
    (t) => shot(t, 'directo', phone, state: LoopState.playing, fx: true, stopping: 2),
  );
  testWidgets(
    'reverse en pequeño',
    (t) => shot(t, 'directo-pequeno', const Size(360, 640), state: LoopState.playing, fx: true),
  );
  testWidgets(
    'entrenador',
    (t) => shot(
      t,
      'entrenador',
      phone,
      state: LoopState.empty,
      after: (t, c) async {
        c.setTrainerOn(true);
        await t.pump();
      },
    ),
  );
  testWidgets(
    'entrenador: ajustes',
    (t) => shot(
      t,
      'entrenador-hoja',
      phone,
      state: LoopState.empty,
      after: (t, c) async {
        c.setTrainerOn(true);
        await t.pump();
        await t.tap(find.byKey(const ValueKey('trainer-button')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
      },
    ),
  );
  Widget tunerHome(EngineController c) => TunerScreen(controller: c);
  testWidgets(
    'afinador',
    (t) => shot(
      t,
      'afinador',
      phone,
      state: LoopState.empty,
      home: tunerHome,
      tuner: const TunerReading(frequency: 81.95, clarity: 0.97, levelDb: -18),
      after: (t, c) async {
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 40));
        }
      },
    ),
  );
  testWidgets(
    'afinador: afinada',
    (t) => shot(
      t,
      'afinador-afinada',
      const Size(360, 640),
      state: LoopState.empty,
      home: tunerHome,
      mode: PlayMode.simple,
      tuner: const TunerReading(frequency: 196.1, clarity: 0.97, levelDb: -25),
      after: (t, c) async {
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 40));
        }
      },
    ),
  );
  testWidgets('audio', (t) => shot(t, 'audio-y-latencia', const Size(393, 1700), audio: true));
}
