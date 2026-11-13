// Loopin — utilidades de los tests de la interfaz
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
  void play() => calls.add('play');
  @override
  void setRecordDuck(double gain) => calls.add('duck $gain');
  @override
  void pause() => calls.add('pause');
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
  void selectTrack(int track) => calls.add('select $track');
  @override
  void selectNextTrack() => calls.add('selectNext');
  @override
  void setTrackVolume(int track, double v) => calls.add('volume $track $v');
  @override
  void setTrackMuted(int track, bool muted) => calls.add('mute $track $muted');
  @override
  void clearTrack(int track) => calls.add('clearTrack $track');
  @override
  void setAutoAdvance(bool on) => calls.add('autoAdvance $on');
  @override
  void setLatencyCompensation(int frames) => calls.add('latency $frames');
  @override
  void nudgeLatency(int frames) => calls.add('nudge $frames');
  @override
  void setMeter(int beats, int accentMask) => calls.add('meter $beats $accentMask');
  @override
  void setClickMode(ClickMode mode) => calls.add('click ${mode.name}');
  @override
  void setStartOnSound(bool on) => calls.add('onSound $on');
  @override
  void setLoopMode(LoopMode mode) => calls.add('mode ${mode.name}');
  @override
  void setDrumsEnabled(bool on) => calls.add('drums $on');
  @override
  void setDrumStyle(DrumStyle style, {required bool beatIsEighth}) =>
      calls.add('drumStyle ${style.name}${beatIsEighth ? ' 8' : ''}');
  @override
  void setDrumVolume(double v) => calls.add('drumVolume $v');

  /// Sonidos que ha recibido el motor (y cuántas muestras cada uno).
  final Map<DrumSound, int> drumSamples = {};
  @override
  void setDrumSample(DrumSound sound, Float32List data, int sampleRate) =>
      drumSamples[sound] = data.length;
  // Audio importado
  @override
  void backingPrepare({
    required String path,
    required double songBpm,
    required double markSeconds,
    required int samplesPerBeat,
    required int beatsPerBar,
    required int id,
  }) => calls.add('prepare $id $songBpm $markSeconds $samplesPerBeat $beatsPerBar');
  @override
  void backingUnload() => calls.add('unload');
  @override
  void backingCancel() => calls.add('cancel');
  @override
  void setBackingEnabled(bool on) => calls.add('backing $on');
  @override
  void setBackingVolume(double v) => calls.add('backingVolume $v');
  @override
  void songOpen(String path, int id) => calls.add('open $id');
  @override
  void songClose() => calls.add('close');

  /// Lo que devuelve songFindAttack (null = lo mismo que le piden).
  int? attack;
  @override
  int songFindAttack(int center, int radius) => attack ?? center;
  @override
  Float32List songPeaks(int start, int end, int bins) =>
      Float32List.fromList(List.generate(bins, (i) => (i % 10) / 10));
  @override
  void previewPlay(int frame) => calls.add('previewPlay $frame');
  @override
  void previewStop() => calls.add('previewStop');
  @override
  void setPreviewClick(bool on) => calls.add('previewClick $on');
  @override
  void setPreviewGrid(double mark, double beat, int beatsPerBar, int accentMask) =>
      calls.add('grid ${mark.round()} ${beat.toStringAsFixed(1)} $beatsPerBar');

  // Etapa 5
  @override
  void setTrackReverse(int track, bool on) => calls.add('reverse $track $on');
  @override
  void setTrackHalf(int track, bool on) => calls.add('half $track $on');
  @override
  void setQuantize(bool on) => calls.add('quantize $on');
  @override
  void stopPlaying({bool now = false}) => calls.add(now ? 'stopNow' : 'stop');
  @override
  void setStopMode(StopMode mode) => calls.add('stopMode ${mode.name}');
  @override
  void setFadeSeconds(double seconds) => calls.add('fade $seconds');
  @override
  void setTrainer({required int bars, required double step, required double top}) =>
      calls.add('trainer $bars ${step.round()} ${top.round()}');
  @override
  void setTunerEnabled(bool on) => calls.add('tuner $on');
  @override
  void setTone(double hz) => calls.add('tone ${hz.toStringAsFixed(1)}');

  /// Lo que devuelve el afinador.
  TunerReading? tuner;
  @override
  TunerReading? tunerRead() => tuner;

  @override
  void startTapCalibration() => calls.add('tapStart');
  @override
  void cancelTapCalibration() => calls.add('tapCancel');

  // Sesiones (Etapa 6): lo que hay en cada pista (null = vacía)
  List<Float32List?> trackData = List.filled(4, null);

  /// false: las pistas no están quietas (no se pueden leer).
  bool readable = true;
  int reads = 0;
  @override
  TrackRead? readTrack(int track, {bool samples = true}) {
    if (!readable) return null;
    final d = trackData[track];
    if (d == null) return const TrackRead(length: 0, hash: 0);
    if (samples) reads++;
    return TrackRead(length: d.length, hash: Object.hashAll(d), samples: samples ? d : null);
  }

  /// Lo último que se ha cargado y lo que pasa al cargar.
  SessionAudio? loaded;
  int loadResult = 0;
  void Function()? onLoad;
  @override
  int loadSession(SessionAudio a) {
    calls.add('loadSession');
    loaded = a;
    onLoad?.call();
    return loadResult;
  }

  ExportRequest? exported;
  int exportResult = 0;
  @override
  int exportStart(ExportRequest req) {
    calls.add('export');
    exported = req;
    return exportResult;
  }

  @override
  void exportCancel() => calls.add('exportCancel');

  // El resto de órdenes no importan aquí
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _bar = 125216; // un compás a 92 BPM y 48 kHz

/// Un estado creíble del motor: la pista 1 con loop, la 2 elegida (y en ella
/// lo que diga [st]), la 3 en silencio y el doble de larga, la 4 vacía.
EngineStatus fakeStatus(
  LoopState st, {
  bool playing = true,
  bool waiting = false,
  LatencyState tapState = LatencyState.idle,
  int tapClicks = 0,
  bool drums = false,
  bool fx = false,
  int stopping = 0,
  int revision = 0,
  bool settled = true,
  double bpm = 92,
  JobState exportState = JobState.idle,
  double exportProgress = 0,
}) {
  final any = st != LoopState.empty;
  final rest = st == LoopState.stopped ? LoopState.stopped : LoopState.playing;
  final busy = st == LoopState.armed || st == LoopState.recording || st == LoopState.overdubbing;
  return EngineStatus(
    running: true,
    sampleRate: 48000,
    playing: playing,
    bpm: bpm,
    beatsPerBar: 4,
    beat: 2,
    samplesPerBeat: 31304,
    beatFrames: 1000,
    inputDeviceId: 10,
    outputDeviceId: 20,
    outputLatencyMs: 45,
    inputLatencyMs: 60,
    inputPeak: 0.4,
    loopState: st,
    loopWaiting: waiting,
    drumsEnabled: drums,
    drumsPlaying: drums,
    tapState: tapState,
    tapClicks: tapClicks,
    tapHits: tapClicks > 4 ? tapClicks - 4 : 0,
    tapFrames: 5760,
    tapSpread: 240,
    stopping: stopping,
    quantize: true,
    loopRevision: revision,
    loopSettled: settled,
    exportState: exportState,
    exportProgress: exportProgress,
    loopBarFrames: _bar,
    loopLength: st.hasLoop ? 4 * _bar : 0,
    loopPosition: st.hasLoop ? 200000 : 0,
    loopRecorded: switch (st) {
      LoopState.armed => -40000,
      LoopState.recording => 180000,
      _ => 0,
    },
    loopTarget: st == LoopState.recording ? 4 * _bar : 0,
    loopLayers: st.hasLoop ? 2 : 0,
    loopCanUndo: any,
    selectedTrack: 1,
    activeTrack: busy ? 1 : -1,
    autoAdvance: true,
    baseLength: any ? 4 * _bar : 0,
    basePosition: any ? 200000 : 0,
    tracks: [
      // Con [fx], la pista 1 al revés y la 2 a media velocidad, con el
      // reverse esperando al siguiente 1
      TrackStatus(
        state: any ? rest : LoopState.empty,
        layers: any ? 1 : 0,
        length: any ? 4 * _bar : 0,
        position: any ? 200000 : 0,
        reverse: fx && any,
      ),
      TrackStatus(
        state: st,
        layers: st.hasLoop ? 2 : 0,
        length: st.hasLoop ? 4 * _bar : 0,
        position: st.hasLoop ? 200000 : 0,
        half: fx && st.hasLoop,
        reverse: fx && st.hasLoop,
        pending: fx && st.hasLoop ? 2 : 0,
      ),
      TrackStatus(
        state: any ? rest : LoopState.empty,
        layers: any ? 3 : 0,
        muted: any,
        length: any ? 8 * _bar : 0,
        position: any ? 700000 : 0,
      ),
      const TrackStatus(),
    ],
  );
}

const _channel = MethodChannel('loopin/permissions');
const _keys = MethodChannel('loopin/keys');

/// Lo que respondería Android (permiso del micro, dispositivos, ajustes).
/// Con [prefs], los ajustes se guardan ahí (si no, no se guarda nada).
void mockPlatform([Map<String, String>? prefs]) {
  // Sin esto la llamada no vuelve nunca dentro de un test
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    _keys,
    (call) async => null,
  );
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
              {'id': 30, 'type': 4, 'name': 'cascos', 'address': ''},
            ],
          };
        case 'prefsGet':
          return prefs?[(call.arguments as Map)['key']];
        case 'prefsSet':
          final args = call.arguments as Map;
          prefs?[args['key'] as String] = args['value'] as String;
          return null;
        default:
          return null;
      }
    },
  );
}

/// Tamaño de la pantalla, en puntos.
void setScreen(WidgetTester tester, Size size, {double pixelRatio = 3}) {
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
}

/// Contraste entre dos colores según WCAG (de 1 a 21).
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
