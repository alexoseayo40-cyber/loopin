// Loopin — todos los textos de la app
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Los textos están en `assets/l10n/<idioma>.json` (`es.json` es la referencia;
// cómo se escriben, en `docs/TRANSLATING.md`). Esta clase da a cada uno un
// nombre en Dart y rellena sus parámetros, para que el resto de la app no sepa
// nada de claves. Lo que se compone aquí (el «·», los números, el orden de las
// piezas) no se traduce; las palabras, sí, y siempre en el JSON.
//
// Reglas de estilo: una línea por opción; la explicación larga va en un
// texto `…Help`, que la app enseña plegado detrás de un «?».
import 'dart:convert';

import 'package:loopin_engine/loopin_engine.dart';

import '../engine/engine_controller.dart' show RecordDuck;
import '../engine/song_backing.dart' show BackingPhase;
import '../engine/songs.dart' show ImportError;
import '../engine/meter.dart';
import '../engine/pedal_keys.dart';
import '../engine/play_mode.dart';
import '../ui/theme.dart';
import 'message.dart';
import 'report_strings.dart';

/// Los idiomas de la app, en el orden en que se ofrecen.
const kLanguages = ['es', 'en', 'fr', 'de', 'it', 'pt'];

/// El nombre de cada idioma en su idioma (no se traduce).
const kLanguageNames = {
  'es': 'Español',
  'en': 'English',
  'fr': 'Français',
  'de': 'Deutsch',
  'it': 'Italiano',
  'pt': 'Português',
};

/// Los textos que se están usando.
Strings get tr => _strings;
Strings _strings = Strings('es', const {});

/// Cambia el idioma de los textos.
void useStrings(Strings strings) => _strings = strings;

/// Textos en un idioma.
class Strings {
  Strings(this.lang, Map<String, String> texts, {this.fallback}) : _texts = texts;

  /// Lee un `<idioma>.json`. Lo que falte se toma de [fallback].
  factory Strings.fromJson(String lang, String json, {Strings? fallback}) {
    final map = (jsonDecode(json) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
    return Strings(lang, map, fallback: fallback);
  }

  /// «es», «en», «fr», «de», «it» o «pt».
  final String lang;

  /// Los textos de referencia, para lo que falte (no debería faltar nada: lo
  /// comprueba `test/l10n_test.dart`).
  final Strings? fallback;

  final Map<String, String> _texts;
  final _parsed = <String, Message>{};

  /// Las claves de este idioma (para los tests).
  Iterable<String> get keys => _texts.keys;

  /// El texto sin rellenar (para los tests).
  String? raw(String key) => _texts[key];

  String _t(String key, [Map<String, Object?> args = const {}]) {
    final text = _texts[key];
    if (text == null) return fallback?._t(key, args) ?? key;
    final msg = _parsed.putIfAbsent(key, () => Message.parse(text));
    return msg.format(args, lang: lang);
  }

  String _e(String group, Enum value) => _t('$group.${value.name}');

  /// Un número con [digits] decimales, con la coma o el punto del idioma.
  String dec(double v, int digits) =>
      v.toStringAsFixed(digits).replaceAll('.', _t('format.decimal'));

  ReportStrings get report => ReportStrings.of(this);

  // ---------------------------------------------------------------- comunes

  String get appName => _t('appName');
  String get cancel => _t('cancel');
  String get ok => _t('ok');
  String get showHelp => _t('showHelp');
  String get hideHelp => _t('hideHelp');
  String get yes => _t('yes');
  String get no => _t('no');
  String yesNo(Object? v) => v == true ? yes : (v == false ? no : '—');
  String ms(double v) => v < 0 ? '—' : '${dec(v, 1)} ms';
  String percent(double fraction) => _t('format.percent', {'n': (fraction * 100).round()});

  /// «1 compás», «4 compases»
  String bars(int n) => _t('bars', {'n': n});

  /// «1 capa», «2 capas»
  String layers(int n) => _t('layers', {'n': n});

  /// «1 golpe», «7 golpes»
  String hits(int n) => _t('hits', {'n': n});

  // ---------------------------------------------------------------- motor

  String presetName(InputPreset p) => _e('presetName', p);

  /// Una línea por modo del micrófono.
  String presetLine(InputPreset p) => _e('presetLine', p);

  String get unprocessedUnsupported => _t('unprocessedUnsupported');
  String get recommended => _t('recommended');

  String loopModeName(LoopMode m) => _e('loopModeName', m);
  String loopModeLine(LoopMode m) => _e('loopModeLine', m);

  /// En la pantalla de tempo
  String loopModeShort(LoopMode m) => _e('loopModeShort', m);

  /// Los 3 modos del clic (el motor también sabe «solo la cuenta», que la app
  /// ya no usa).
  String _clickKey(ClickMode m) => switch (m) {
    ClickMode.always => 'always',
    ClickMode.untilRecording => 'untilRecording',
    _ => 'off',
  };
  String clickModeName(ClickMode m) => _t('clickModeName.${_clickKey(m)}');

  /// «Clic: siempre»
  String clickLabel(ClickMode m) => _t('clickLabel.${_clickKey(m)}');

  /// Al tocar el botón del clic (dice el modo al que pasa).
  String clickSnack(ClickMode m) => _t('clickSnack.${_clickKey(m)}');
  String get clickFree => _t('clickFree');

  /// Nombre de un dispositivo de audio de Android.
  String deviceName(AudioDevice d) {
    final extra = d.address.isNotEmpty ? ' (${d.address})' : '';
    return switch (d.type) {
      15 => '${_t('device.mic')}$extra',
      2 => _t('device.speaker'),
      1 => _t('device.earpiece'),
      3 => _t('device.wiredHeadset'),
      4 => _t('device.wiredHeadphones'),
      5 || 6 => _t('device.line'),
      7 || 26 || 8 || 27 => _t('device.bluetooth', {'name': d.name}),
      11 || 12 => _t('device.usb', {'name': d.name}),
      22 => _t('device.usbHeadset', {'name': d.name}),
      _ => d.name.isNotEmpty ? d.name : _t('device.other', {'type': d.type}),
    };
  }

  String unknownDevice(int id) => _t('unknownDevice', {'id': id});

  /// Mensaje para un código de error de Oboe.
  String audioError(int code) => switch (code) {
    -899 => _t('audioError.disconnected'),
    -889 => _t('audioError.unavailable'),
    -883 => _t('audioError.format'),
    -887 => _t('audioError.memory'),
    -881 => _t('audioError.service'),
    _ => _t('audioError.other', {'code': code}),
  };

  String get micDeniedForever => _t('micDeniedForever');
  String get micNeeded => _t('micNeeded');

  // ---------------------------------------------------------------- looper: cabecera

  String get settings => _t('settings');
  String get latencyChipUnmeasured => _t('latencyChipUnmeasured');
  String get latencyChipUnmeasuredSemantics => _t('latencyChipUnmeasuredSemantics');

  // ---------------------------------------------------------------- looper: tempo

  String get tempoDown => _t('tempoDown');
  String get tempoUp => _t('tempoUp');
  String get bpmUnit => 'BPM';
  String get bpmUnitEighths => 'BPM ♪';
  String get noTempoYet => '- - -';
  String get tapTempo => _t('tapTempo');
  String get tempoLocked => _t('tempoLocked');
  String get tempoFromLoop => _t('tempoFromLoop');
  String get tempoFromLoopSemantics => _t('tempoFromLoopSemantics');
  String bpmSemantics(int bpm, {required bool locked}) => _t('bpmSemantics', {
    'bpm': bpm,
    'hint': _t(locked ? 'bpmSemanticsLocked' : 'bpmSemanticsTap'),
  });

  String get stopAll => _t('stopAll');
  String get startAll => _t('startAll');
  String get stopMetronome => _t('stopMetronome');
  String get startMetronome => _t('startMetronome');
  String get metronomeStopped => _t('metronomeStopped');
  String beatOf(int beat, int beats) => _t('beatOf', {'beat': beat, 'beats': beats});

  String get meter => _t('meter');

  /// En el menú: «7/8  (2+2+3)»
  String meterItem(TimeSignature ts) =>
      ts.grouping.isEmpty ? ts.label : '${ts.label}  (${ts.grouping})';

  /// En la pantalla: «7/8 2+2+3»
  String meterChip(TimeSignature ts) =>
      ts.grouping.isEmpty ? ts.label : '${ts.label} ${ts.grouping}';

  String get recordMode => _t('recordMode');
  String get syncBars => _t('syncBars');

  /// «4 C»
  String barsShort(int n) => _t('barsShort', {'n': n});

  String get startOnSound => _t('startOnSound');
  String startOnSoundTooltip(bool on) => _t('startOnSoundTooltip', {'state': on ? yes : no});
  String get startOnSoundOn => _t('startOnSoundOn');
  String get startOnSoundOff => _t('startOnSoundOff');

  // ---------------------------------------------------------------- looper: pistas

  String trackLabel(int n) => _t('trackLabel', {'n': n});
  String trackStateName(LoopState st, {bool muted = false}) =>
      st == LoopState.playing && muted ? _t('trackState.muted') : _e('trackState', st);

  /// «Pista 2, sonando, 4 compases, 2 capas»
  String trackSemantics(int n, String state, {int? bars, int layers = 0}) =>
      '${_t('trackSemantics', {'n': n, 'state': state})}'
      '${bars != null ? ', ${this.bars(bars)}' : ''}'
      '${layers > 1 ? ', ${this.layers(layers)}' : ''}';

  /// Debajo del anillo: «4 C · 2» (compases y capas, si hay más de una)
  String trackRingLabel(int bars, int layers) =>
      '${barsShort(bars)}${layers > 1 ? ' · $layers' : ''}';
  String get trackRingEmpty => '—';

  String trackVolume(int n, double v) => _t('trackVolume', {'n': n, 'volume': percent(v)});
  String unmuteTrack(int n) => _t('unmuteTrack', {'n': n});
  String muteTrack(int n) => _t('muteTrack', {'n': n});
  String clearTrack(int n) => _t('clearTrack', {'n': n});

  // Etapa 5: reverse y media velocidad
  String get reverseShort => _t('reverseShort');
  String get halfShort => '½';
  String reverseTrack(int n, bool on) => _t(on ? 'reverseTrackOn' : 'reverseTrackOff', {'n': n});
  String halfTrack(int n, bool on) => _t(on ? 'halfTrackOn' : 'halfTrackOff', {'n': n});

  /// Para lectores de pantalla, cuando el cambio espera al siguiente 1
  String get atNextOne => _t('atNextOne');

  /// Debajo del anillo, si la pista va al revés o a media velocidad: «2 C · REV ½»
  String trackRingFx(String label, {required bool reverse, required bool half}) =>
      '$label${reverse || half ? ' ·' : ''}${reverse ? ' $reverseShort' : ''}'
      '${half ? ' $halfShort' : ''}';

  // ---------------------------------------------------------------- entrenador de tempo

  String get trainer => _t('trainer');
  String trainerTooltip(bool on) => _t(on ? 'trainerTooltipOn' : 'trainerTooltipOff');
  String get trainerLine => _t('trainerLine');
  String get trainerHelp => _t('trainerHelp');
  String get trainerStep => _t('trainerStep');
  String get trainerEvery => _t('trainerEvery');
  String get trainerTop => _t('trainerTop');
  String trainerBpm(num v) => _t('trainerBpm', {'bpm': v.round()});
  String trainerBarsShort(int n) => barsShort(n);
  String trainerSummary(int from, int to, int step, int bars, int steps) => steps <= 0
      ? _t('trainerSummaryDone', {'to': to})
      : _t('trainerSummary', {
          'from': from,
          'to': to,
          'step': step,
          'bars': this.bars(bars),
          'steps': steps,
        });

  /// En la pantalla de tempo, en lugar del TAP: «ENTRENADOR +5 / 4 C · HASTA 132»
  String trainerPill(int step, int bars, int top) =>
      _t('trainerPill', {'step': step, 'bars': barsShort(bars), 'top': top});
  String get trainerNeedsNoLoops => _t('trainerNeedsNoLoops');
  String get trainerDecrease => _t('trainerDecrease');
  String get trainerIncrease => _t('trainerIncrease');

  // ---------------------------------------------------------------- afinador

  String get tuner => _t('tuner');
  String get tunerHelp => _t('tunerHelp');

  /// Nombre de la nota (0 = Do … 11 = Si). Con «#» y no «♯»: las tipografías
  /// de la app no tienen ese signo.
  String noteName(int pitchClass) => _t('note.${pitchClass % 12}');

  /// En letras, con la octava: «E2» (en alemán, «H2» para el si)
  String noteLetter(int pitchClass, int octave) => '${_t('noteLetter.${pitchClass % 12}')}$octave';
  String get tunerListening => _t('tunerListening');
  String get tunerNoAudio => _t('tunerNoAudio');
  String get tunerInTune => _t('tunerInTune');
  String get tunerFlat => _t('tunerFlat');
  String get tunerSharp => _t('tunerSharp');
  String tunerCents(double c) =>
      _t('tunerCents', {'cents': '${c >= 0 ? '+' : '−'}${c.abs().round()}'});
  String tunerHz(double f) => _t('tunerHz', {'hz': dec(f, 1)});
  String get tunerStandard => _t('tunerStandard');
  String tunerSemantics(String note, double cents) => _t('tunerSemantics', {
    'note': note,
    'state': _t(
      cents.abs() <= 3 ? 'tunerState.inTune' : (cents < 0 ? 'tunerState.flat' : 'tunerState.sharp'),
    ),
    'cents': tunerCents(cents),
  });
  String get tunerA4 => _t('tunerA4');
  String tunerA4Value(double hz) => _t('tunerA4Value', {'hz': hz.round()});
  String get tunerA4Help => _t('tunerA4Help');
  String get tunerSpeaker => _t('tunerSpeaker');
  String get tunerStopAll => _t('tunerStopAll');
  String get tunerOpen => _t('tunerOpen');
  String get referenceNotes => _t('referenceNotes');
  String get referenceNotesLine => _t('referenceNotesLine');
  String get referenceStop => _t('referenceStop');

  /// El botón del La de referencia: «LA 440»
  String referenceA4(double hz) => _t('referenceA4', {'hz': hz.round()});
  String referenceNoteSemantics(String note, double hz, bool on) =>
      _t(on ? 'referenceNoteOn' : 'referenceNoteOff', {'note': note, 'hz': tunerHz(hz)});

  // ---------------------------------------------------------------- looper: batería

  String get drums => _t('drums');
  String drumStyleName(DrumStyle st) => _e('drumStyle', st);
  String drumStyleChip(DrumStyle st) => _e('drumChip', st);

  /// En el menú: «Rock · 4/4», «Básico · cualquier compás»
  String drumStyleItem(DrumStyle st, String? meter) =>
      _t('drumStyleItem', {'style': drumStyleName(st), 'meter': meter ?? _t('drumAnyMeter')});
  String get drumStyleMenu => _t('drumStyleMenu');
  String get drumsTurnOn => _t('drumsTurnOn');
  String get drumsTurnOff => _t('drumsTurnOff');
  String drumVolume(double v) => _t('drumVolume', {'volume': percent(v)});
  String drumsSemantics(String style, bool on, bool playing) => _t('drumsSemantics', {
    'style': style,
    'state': _t(!on ? 'drumsState.off' : (playing ? 'drumsState.playing' : 'drumsState.waiting')),
  });
  String get drumsBleed => _t('drumsBleed');
  String get drumsBleedHelp => _t('drumsBleedHelp');

  // ---------------------------------------------------------------- looper: acompañamiento

  /// El selector de la fila de abajo: batería o canción
  String get accDrums => _t('accDrums');
  String get accSong => _t('accSong');
  String accShow(String what) => _t(what == accSong ? 'accShow.song' : 'accShow.drums');

  // ---------------------------------------------------------------- canción (audio importado)

  /// «97,3», «120», «97,34»: con los decimales que tenga
  String bpmNumber(double v) {
    var t = v.toStringAsFixed(2);
    while (t.contains('.') && (t.endsWith('0') || t.endsWith('.'))) {
      t = t.substring(0, t.length - 1);
    }
    return t.replaceAll('.', _t('format.decimal'));
  }

  /// «3:45»
  String duration(double seconds) {
    final s = seconds.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// «1:23,4» (para la vista previa)
  String clock(double seconds) {
    final t = seconds < 0 ? 0.0 : seconds;
    final m = t ~/ 60;
    final rest = t - m * 60;
    return '$m:${rest.toStringAsFixed(1).padLeft(4, '0').replaceAll('.', _t('format.decimal'))}';
  }

  // En la fila
  String get songChoose => _t('songChoose');
  String get songSetup => _t('songSetup');
  String get songTooFar => _t('songTooFar');
  String get songFailedChip => _t('songFailedChip');
  String songChip(String name) => name.toUpperCase();
  String songSpeed(double v) => percent(v);
  String get songMenu => _t('songMenu');
  String get songTurnOn => _t('songTurnOn');
  String get songTurnOff => _t('songTurnOff');
  String songVolume(double v) => _t('songVolume', {'volume': percent(v)});
  String songSemantics(String? name, bool on, bool playing) => _t('songSemantics', {
    'name': name ?? _t('songNoName'),
    'state': _t(!on ? 'songState.off' : (playing ? 'songState.playing' : 'songState.waiting')),
  });
  String get songBleed => _t('songBleed');
  String get songBleedHelp => _t('songBleedHelp');

  /// En qué está la elegida (en la lista de canciones)
  String backingPhase(BackingPhase p, {required String bpm, double progress = 0}) => _t(
    'backingPhase.${p.name}',
    {'bpm': bpm, 'progress': progress > 0 ? percent(progress) : ''},
  ).trim();

  // Lista de canciones
  String get songsTitle => _t('songsTitle');
  String get songsHow => _t('songsHow');
  String get songsImport => _t('songsImport');
  String get songsEmpty => _t('songsEmpty');
  String get songsEmptyLine => _t('songsEmptyLine');
  String get songsHelp => _t('songsHelp');
  String get songsCurrent => _t('songsCurrent');
  String songRestoreTempo(String bpm) => _t('songRestoreTempo', {'bpm': bpm});
  String get songsNone => _t('songsNone');
  String songSubtitle(String bpm, String meter, double seconds) =>
      '${_t('songSubtitle', {'bpm': bpm, 'meter': meter})}'
      '${seconds > 0 ? ' · ${duration(seconds)}' : ''}';
  String get songNotReady => _t('songNotReady');
  String get songPrepare => _t('songPrepare');
  String get songDelete => _t('songDelete');
  String get songOptions => _t('songOptions');
  String songDeleteTitle(String name) => _t('songDeleteTitle', {'name': name});
  String get songDeleteBody => _t('songDeleteBody');
  String get importing => _t('importing');
  String importError(ImportError e) => _e('importError', e);
  String songError(SongError e) => e == SongError.none ? '' : _e('songError', e);

  // Preparar una canción
  String get editorTitle => _t('editorTitle');
  String editorOpening(double p) =>
      _t('editorOpening', {'progress': p > 0 ? percent(p) : ''}).trim();
  String get editorName => _t('editorName');
  String get editorPlay => _t('editorPlay');
  String get editorPause => _t('editorPause');
  String get editorFromMark => _t('editorFromMark');
  String get editorClick => _t('editorClick');
  String get editorClickTip => _t('editorClickTip');
  String get editorWaveTip => _t('editorWaveTip');
  String get editorMarkOne => _t('editorMarkOne');
  String get editorMarkLine => _t('editorMarkLine');
  String get editorMarkHelp => _t('editorMarkHelp');
  String get editorZoom => _t('editorZoom');
  String editorNudge(int ms) => _t('editorNudge', {'ms': '${ms > 0 ? '+' : ''}$ms'});
  String get editorTempo => _t('editorTempo');
  String editorBpm(String bpm) => _t('editorBpm', {'bpm': bpm});
  String get editorTap => _t('editorTap');
  String get editorTapTip => _t('editorTapTip');
  String editorGuess(String bpm) => _t('editorGuess', {'bpm': bpm});
  String get editorTempoMinus => _t('editorTempoMinus');
  String get editorTempoPlus => _t('editorTempoPlus');
  String get editorTempoHelp => _t('editorTempoHelp');
  String get editorBpmDialog => _t('editorBpmDialog');
  String get editorMeter => _t('editorMeter');
  String get editorSecond => _t('editorSecond');
  String get editorSecondLine => _t('editorSecondLine');
  String editorBarsBetween(int bars) => _t('editorBarsBetween', {'bars': this.bars(bars)});
  String get editorFewerBars => _t('editorFewerBars');
  String get editorMoreBars => _t('editorMoreBars');
  String get editorClearSecond => _t('editorClearSecond');
  String get editorSave => _t('editorSave');

  // ---------------------------------------------------------------- looper: pulsador

  String get pedal => _t('pedal');
  String pedalSemantics(String title, String subtitle) =>
      _t('pedalSemantics', {'title': title, 'subtitle': subtitle});
  String get pedalTapHint => _t('pedalTapHint');
  String get pedalHoldHint => _t('pedalHoldHint');
  String get pedalDoubleAction => _t('pedalDoubleAction');

  String get ready => _t('ready');
  String readyOnSound(int track) => _t('readyOnSound', {'track': track});
  String readyFree(int track) => _t('readyFree', {'track': track});
  String readyCountIn(int track) => _t('readyCountIn', {'track': track});

  String get waiting => _t('waiting');
  String get waitingLine => _t('waitingLine');

  String get getReady => _t('getReady');
  String trackStartsNextBar(int track) => _t('trackStartsNextBar', {'track': track});
  String get countIn => _t('countIn');

  String recordingTitle(int track) => _t('recordingTitle', {'track': track});
  String get recordingFree => _t('recordingFree');
  String barOf(int bar, int of) => _t('barOf', {'bar': bar, 'of': of});
  String barOpen(int bar) => _t('barOpen', {'bar': bar});

  String get playing => _t('playing');
  String overdubOn(int track) => _t('overdubOn', {'track': track});
  String recordOn(int track) => _t('recordOn', {'track': track});

  String overdubNextBar(int track) => _t('overdubNextBar', {'track': track});
  String overdubTitle(int track) => _t('overdubTitle', {'track': track});
  String get tapToFinish => _t('tapToFinish');

  String get stopped => _t('stopped');
  String get tapToStart => _t('tapToStart');

  // Parar en el 1 o con fundido
  String get stoppingAtOne => _t('stoppingAtOne');
  String get fadingOut => _t('fadingOut');
  String get tapToStopNow => _t('tapToStopNow');

  String get audioOn => _t('audioOn');

  // ---------------------------------------------------------------- looper: abajo

  String get gestures => _t('gestures');
  String get undo => _t('undo');
  String get stop => _t('stop');
  String get start => _t('start');
  String get clearAll => _t('clearAll');
  String get clearAllTitle => _t('clearAllTitle');
  String clearAllBody(String session) => _t('clearAllBody', {'session': session});
  String get clearAllConfirm => _t('clearAllConfirm');
  String get clearAllNewSession => _t('clearAllNewSession');
  String get stageOpen => _t('stageOpen');
  String get inputLevel => _t('inputLevel');
  String get monitor => _t('monitor');

  // ---------------------------------------------------------------- sesiones (Etapa 6)

  String _two(int n) => n.toString().padLeft(2, '0');
  String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
  String _dayMonth(DateTime d) =>
      _t('date.dayMonth', {'day': d.day, 'month': _t('date.month.${d.month}')});

  /// «Sesión 13 nov · 18:50»
  String sessionDefaultName(DateTime d) =>
      _t('sessionDefaultName', {'date': _dayMonth(d), 'time': _time(d)});
  String sessionCopyName(String name) => _t('sessionCopyName', {'name': name});

  /// «hoy 18:50», «ayer 09:12», «13 nov», «13 nov 2025»
  String sessionWhen(DateTime d, DateTime now) {
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return _t('date.today', {'time': _time(d)});
    if (diff == 1) return _t('date.yesterday', {'time': _time(d)});
    return d.year == now.year
        ? _dayMonth(d)
        : _t('date.dayMonthYear', {
            'day': d.day,
            'month': _t('date.month.${d.month}'),
            'year': d.year,
          });
  }

  String sessionsOpenSemantics(String name) => _t('sessionsOpenSemantics', {'name': name});

  /// No se ha podido guardar la sesión (casi siempre, el móvil está lleno).
  String saveFailedLine(bool noSpace) =>
      _t(noSpace ? 'saveFailedLine.noSpace' : 'saveFailedLine.other');
  String get saveFailedSemantics => _t('saveFailedSemantics');
  String saveFailedBody(bool noSpace) =>
      _t(noSpace ? 'saveFailedBody.noSpace' : 'saveFailedBody.other');
  String get saveFailedExitTitle => _t('saveFailedExitTitle');
  String get saveFailedExitBody => _t('saveFailedExitBody');
  String get saveFailedExit => _t('saveFailedExit');
  String get saveFailedStay => _t('saveFailedStay');
  String get sessionsTitle => _t('sessionsTitle');
  String get sessionsHow => _t('sessionsHow');
  String get sessionsHelp => _t('sessionsHelp');
  String get sessionOpenNow => _t('sessionOpenNow');
  String get sessionsSaved => _t('sessionsSaved');
  String get sessionsEmpty => _t('sessionsEmpty');
  String get sessionEmptyNow => _t('sessionEmptyNow');

  /// «92 BPM · 4/4 · 3 pistas · 8 C»
  String sessionSummary(({String bpm, String meter, int tracks, int bars}) f) =>
      '${_t('sessionSummary', {'bpm': f.bpm, 'meter': f.meter, 'tracks': f.tracks})}'
      '${f.bars > 0 ? ' · ${barsShort(f.bars)}' : ''}';
  String get sessionNew => _t('sessionNew');
  String get sessionOpen => _t('sessionOpen');
  String get sessionRename => _t('sessionRename');
  String get sessionRenameSave => _t('sessionRenameSave');
  String get sessionNameLabel => _t('sessionNameLabel');
  String get sessionDuplicate => _t('sessionDuplicate');
  String sessionDuplicated(String name) => _t('sessionDuplicated', {'name': name});
  String get sessionDuplicateEmpty => _t('sessionDuplicateEmpty');
  String get sessionDelete => _t('sessionDelete');
  String get sessionOptions => _t('sessionOptions');
  String sessionDeleteTitle(String name) => _t('sessionDeleteTitle', {'name': name});
  String get sessionDeleteBody => _t('sessionDeleteBody');
  String get sessionDeleteOpenBody => _t('sessionDeleteOpenBody');
  String get sessionBusy => _t('sessionBusy');
  String get sessionOpenFailed => _t('sessionOpenFailed');

  // ---------------------------------------------------------------- exportar

  String get exportButton => _t('exportButton');
  String exportTitle(String session) => _t('exportTitle', {'session': session});
  String get exportWhat => _t('exportWhat');
  String get exportHelp => _t('exportHelp');
  String get exportMix => _t('exportMix');
  String get exportStems => _t('exportStems');
  String get exportWithDrums => _t('exportWithDrums');
  String get exportWithSong => _t('exportWithSong');
  String get exportLoops => _t('exportLoops');

  /// «2 vueltas · 34 s»
  String exportLength(int loops, double seconds) {
    final s = seconds.round();
    final time = s >= 60
        ? _t('exportMinutes', {'m': s ~/ 60, 's': _two(s % 60)})
        : _t('exportSeconds', {'s': s});
    return _t('exportLength', {'loops': loops, 'time': time});
  }

  String get exportStart => _t('exportStart');
  String exporting(double progress) => _t('exporting', {'progress': percent(progress)});
  String exportDone(int files) => _t('exportDone', {'files': files});
  String get exportShare => _t('exportShare');
  String get exportSave => _t('exportSave');
  String exportSaved(int files) => _t('exportSaved', {'files': files});
  String get exportSaveFailed => _t('exportSaveFailed');
  String get exportAgain => _t('exportAgain');
  String exportStartError(int code) => switch (code) {
    -1 => _t('exportStartError.recording'),
    -2 => _t('exportStartError.noTracks'),
    -3 => _t('exportStartError.busy'),
    _ => _t('exportStartError.other'),
  };
  String exportError(ExportError e) => switch (e) {
    ExportError.write => _t('exportError.write'),
    ExportError.memory => _t('exportError.memory'),
    ExportError.nothing => _t('exportError.nothing'),
    _ => _t('exportError.other'),
  };

  /// Nombre de los archivos: el de la sesión sin lo que no vale en un archivo.
  String exportFileBase(String session) {
    final clean = session
        .replaceAll(RegExp(r'[\\/:*?"<>|·]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return clean.isEmpty ? 'Loopin' : clean;
  }

  String exportFileName(String base, String part) => '$base - $part.wav';
  String exportTrack(int n) => _t('exportTrack', {'n': n});
  String get exportDrums => _t('exportDrums');
  String get exportSong => _t('exportSong');

  // ---------------------------------------------------------------- modo escenario

  /// «92 BPM · 4/4»
  String stageTempo(String bpm, String meter) => '$bpm BPM · $meter';
  String get stageGestures => _t('stageGestures');
  String get stageExitHold => _t('stageExitHold');
  String get stageExit => _t('stageExit');

  // ---------------------------------------------------------------- guía de la primera vez

  String get helpSection => _t('helpSection');

  // ---------------------------------------------------------------- acerca de

  String get aboutOpen => _t('aboutOpen');
  String aboutOpenLine(String version) =>
      version.isEmpty ? _t('aboutOpenLineNoVersion') : _t('aboutOpenLine', {'version': version});
  String get aboutTitle => _t('aboutTitle');
  String get aboutTagline => _t('aboutTagline');
  String aboutVersion(String version) => _t('aboutVersion', {'version': version});
  String get aboutLicenseTitle => _t('aboutLicenseTitle');
  String get aboutLicenseLine => _t('aboutLicenseLine');
  String get aboutPrivacyTitle => _t('aboutPrivacyTitle');
  String get aboutPrivacyLine => _t('aboutPrivacyLine');
  String get aboutSource => _t('aboutSource');
  String get aboutSourceLine => _t('aboutSourceLine');
  String get aboutReport => _t('aboutReport');
  String get aboutReportLine => _t('aboutReportLine');
  String get aboutReportCopy => _t('aboutReportCopy');
  String get aboutReportCopied => _t('aboutReportCopied');
  String get aboutLicenses => _t('aboutLicenses');
  String get aboutLicensesLine => _t('aboutLicensesLine');
  String get aboutNoBrowser => _t('aboutNoBrowser');
  String get aboutLegalese => _t('aboutLegalese');
  String get tutorialOpen => _t('tutorialOpen');
  String get tutorialOpenLine => _t('tutorialOpenLine');
  String get tutorialSkip => _t('tutorialSkip');
  String get tutorialNext => _t('tutorialNext');
  String get tutorialStart => _t('tutorialStart');
  String get tutorialWelcome => _t('tutorialWelcome');
  String get tutorialWelcomeBody => _t('tutorialWelcomeBody');
  String tutorialModeLine(PlayMode m) => _e('tutorialModeLine', m);
  String get tutorialModeLater => _t('tutorialModeLater');
  String get tutorialPedal => _t('tutorialPedal');
  String get tutorialPedalBody => _t('tutorialPedalBody');
  String get tutorialTap => _t('tutorialTap');
  String get tutorialHold => _t('tutorialHold');
  String get tutorialDouble => _t('tutorialDouble');
  String get tutorialTempo => _t('tutorialTempo');
  String get tutorialTempoBody => _t('tutorialTempoBody');
  String get tutorialCount => _t('tutorialCount');
  String get tutorialLights => _t('tutorialLights');
  String get tutorialLatency => _t('tutorialLatency');
  String get tutorialLatencyBody => _t('tutorialLatencyBody');
  String get tutorialMeasureNow => _t('tutorialMeasureNow');
  String get tutorialMeasureLater => _t('tutorialMeasureLater');
  String get tutorialSaved => _t('tutorialSaved');
  String get tutorialSavedBody => _t('tutorialSavedBody');
  String get tutorialSessions => _t('tutorialSessions');
  String get tutorialExport => _t('tutorialExport');
  String get tutorialStage => _t('tutorialStage');

  // ---------------------------------------------------------------- ajustes

  String get playModeTitle => _t('playModeTitle');
  String playModeName(PlayMode m) => _e('playModeName', m);
  String playModeLine(PlayMode m) => _e('playModeLine', m);
  String get playModeHelp => _t('playModeHelp');
  String get playModeBusy => _t('playModeBusy');

  String get appearance => _t('appearance');
  String get themeSystem => _t('themeSystem');
  String get themeLight => _t('themeLight');
  String get themeDark => _t('themeDark');
  String get pedalColor => _t('pedalColor');
  String chassisName(Chassis c) => _e('chassis', c);
  String chassisSemantics(Chassis c) => _t('chassisSemantics', {'name': chassisName(c)});

  String get language => _t('language');

  /// «El del móvil: Deutsch»
  String languageSystemLine(String code) =>
      _t('languageSystemLine', {'name': kLanguageNames[code] ?? code});

  String get looper => _t('looper');
  String get autoAdvance => _t('autoAdvance');
  String get autoAdvanceLine => _t('autoAdvanceLine');
  String get autoAdvanceHelp => _t('autoAdvanceHelp');

  String get stopModeTitle => _t('stopModeTitle');
  String get stopModeLine => _t('stopModeLine');
  String get stopModeHelp => _t('stopModeHelp');
  String stopModeName(StopMode m) => _e('stopModeName', m);

  String get trackFxTitle => _t('trackFxTitle');
  String get trackFxLine => _t('trackFxLine');
  String get trackFxHelp => _t('trackFxHelp');
  // «el 1»: con letra grande, el 1 no se queda solo en otra línea
  String get quantizeTitle => _t('quantizeTitle');
  String get quantizeLine => _t('quantizeLine');
  String get quantizeLineSimple => _t('quantizeLineSimple');
  String get quantizeHelp => _t('quantizeHelp');

  String get recordDuckTitle => _t('recordDuckTitle');
  String get recordDuckLine => _t('recordDuckLine');
  String get recordDuckHelp => _t('recordDuckHelp');
  String recordDuckName(RecordDuck d) => _e('recordDuckName', d);

  /// Al grabar con lo demás callado: «Compás 2 de 4 · lo demás, en silencio»
  String withDuck(String line, RecordDuck d) => switch (d) {
    RecordDuck.normal => line,
    RecordDuck.silent => _t('withDuckSilent', {'line': line}),
  };

  String get externalControls => _t('externalControls');
  String get externalControlsHelp => _t('externalControlsHelp');
  String get volumeKeys => _t('volumeKeys');
  String get volumeKeysLine => _t('volumeKeysLine');
  String get volumeKeysHelp => _t('volumeKeysHelp');
  String get headsetKey => _t('headsetKey');
  String get headsetKeyLine => _t('headsetKeyLine');
  String get headsetKeyHelp => _t('headsetKeyHelp');
  String pedalActionName(PedalAction a) => _e('pedalActionName', a);
  String bluetoothPedal(PedalAction a) => _e('bluetoothPedal', a);
  String get pressPedalNow => _t('pressPedalNow');
  String get notAssigned => _t('notAssigned');
  String get learnHelp => _t('learnHelp');
  String get learn => _t('learn');
  String removeKey(String key) => _t('removeKey', {'key': key});

  /// «PAGE_DOWN», o «tecla 93» si Android no da el nombre
  String keyName(int code, String name) =>
      name.isEmpty ? _t('keyCode', {'code': code}) : shortKeyName(name);
  String lastKey(String key, PedalAction? action) =>
      _t('lastKey', {'key': key, 'action': action == null ? '—' : _e('lastKeyAction', action)});

  String get audio => _t('audio');
  String get moreInAdvanced => _t('moreInAdvanced');
  String get audioAndLatency => _t('audioAndLatency');
  String get audioAndLatencyLine => _t('audioAndLatencyLine');

  // ---------------------------------------------------------------- audio y latencia

  String get copyResults => _t('copyResults');
  String get resultsCopied => _t('resultsCopied');
  String get turnAudioOn => _t('turnAudioOn');
  String get turnAudioOff => _t('turnAudioOff');

  String get input => _t('input');
  String get inputDevice => _t('inputDevice');
  String get inputAuto => _t('inputAuto');
  String get micMode => _t('micMode');
  String micOtherModes(int n) => _t('micOtherModes', {'n': n});
  String get micModeHelp => _t('micModeHelp');
  String presetFallback(InputPreset used) => _t('presetFallback', {'preset': presetName(used)});
  String nowRoute(String input, String output) => '$input → $output';
  String gain(double db) => _t('gain', {'db': db.toStringAsFixed(0)});
  String get gainLine => _t('gainLine');
  String get level => _t('level');
  String get monitorTitle => _t('monitorTitle');
  String get monitorLine => _t('monitorLine');
  String get monitorHelp => _t('monitorHelp');
  String get monitorVolume => _t('monitorVolume');

  String get latency => _t('latency');
  String get latencyHelp => _t('latencyHelp');
  String route(String route) => _t('route', {'route': route});
  String latencySourceName(bool measured, bool estimated) => _t(
    measured
        ? 'latencySource.measured'
        : (estimated ? 'latencySource.estimated' : 'latencySource.none'),
  );
  String compensation(String ms, String source) => _t('compensation', {'ms': ms, 'source': source});

  String get measureAlone => _t('measureAlone');
  String measuringClick(int n) => _t('measuringClick', {'n': n});
  String get measureAloneLine => _t('measureAloneLine');
  String get measureAloneHelp => _t('measureAloneHelp');
  String measured(String ms) => _t('measured', {'ms': ms});
  String get clicksNotHeard => _t('clicksNotHeard');

  String get measureTapping => _t('measureTapping');
  String get measureTappingLine => _t('measureTappingLine');
  String get measureTappingHelp => _t('measureTappingHelp');

  String get byHand => _t('byHand');
  String get byHandLine => _t('byHandLine');
  String get byHandHelp => _t('byHandHelp');
  String get minus1ms => _t('minus1ms');
  String get plus1ms => _t('plus1ms');
  String msValue(int ms) => '$ms ms';
  String msSemantics(int ms) => _t('msSemantics', {'ms': ms});
  String get forgetLatency => _t('forgetLatency');
  String get finishRecordingFirst => _t('finishRecordingFirst');

  String get technicalDetails => _t('technicalDetails');
  String get sharedMode => _t('sharedMode');
  String get exclusiveMode => _t('exclusiveMode');
  String get lowLatency => _t('lowLatency');
  String get noLowLatency => _t('noLowLatency');
  String channels(int n) => n == 1 ? _t('channelsMono') : _t('channels', {'n': n});
  String detailsStream(String api, int rate, int burst) =>
      _t('detailsStream', {'api': api, 'rate': rate, 'burst': burst});
  String detailsOutput(String mode, String low, int buffer, String ms) =>
      _t('detailsOutput', {'mode': mode, 'low': low, 'buffer': buffer, 'ms': ms});
  String detailsInput(String mode, String low, String ch, int burst, int buffer, int maxRead) =>
      _t('detailsInput', {
        'mode': mode,
        'low': low,
        'channels': ch,
        'burst': burst,
        'buffer': buffer,
        'maxRead': maxRead,
      });
  String detailsEstimate(String out, String inp, String total) =>
      _t('detailsEstimate', {'out': out, 'inp': inp, 'total': total});
  String detailsXruns(int n) => _t('detailsXruns', {'n': n < 0 ? '—' : n});
  String engineLoad(String avg, String peak, String max) =>
      _t('engineLoad', {'avg': avg, 'peak': peak, 'max': max});
  String get engineLoadHelp => _t('engineLoadHelp');

  // ---------------------------------------------------------------- medir tocando

  String get measureTappingTitle => _t('measureTappingTitle');
  String get tapIntro => _t('tapIntro');
  String get tapSteps => _t('tapSteps');
  String tapListen(int click) => _t('tapListen', {'click': click});
  String tapCount(int n, int of) => '$n / $of';
  String tapHits(int n) => _t('tapHits', {'n': n});
  String get tapGetReady => _t('tapGetReady');
  String tapResult(int ms) => _t('tapResult', {'ms': ms});
  String tapQuality(int spreadMs, int hitCount) {
    final args = {'spread': spreadMs, 'hits': hits(hitCount)};
    if (spreadMs <= 10) return _t('tapQuality.good', args);
    if (spreadMs <= 25) return _t('tapQuality.ok', args);
    return _t('tapQuality.bad', args);
  }

  String get tapFailed => _t('tapFailed');
  String get tapStart => _t('tapStart');
  String get tapRepeat => _t('tapRepeat');
  String get tapStop => _t('tapStop');
  String get tapWhat => _t('tapWhat');
  String get tapHelp => _t('tapHelp');

  // ---------------------------------------------------------------- informe («Copiar resultados»)

  /// «Loopin 1.0.0 (1)»
  String reportTitle(String version) => version.isEmpty ? 'Loopin' : 'Loopin $version';
}
