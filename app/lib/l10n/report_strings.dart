// Loopin — líneas de «Copiar resultados»
// SPDX-License-Identifier: GPL-3.0-or-later
//
// El informe es para quien arregla la app, no se enseña en pantalla: va en
// español si la app está en español y en inglés en los demás idiomas (las
// incidencias de GitHub se escriben en inglés). Por eso no está en los JSON
// (nadie tiene que traducirlo).
import 'package:loopin_engine/loopin_engine.dart';

import 'strings.dart';

/// Líneas del informe. [ReportStrings.of] da las del idioma del informe.
abstract class ReportStrings {
  const ReportStrings(this.s);

  /// Español si [s] es español; si no, inglés.
  factory ReportStrings.of(Strings s) => s.lang == 'es' ? _Es(s) : _En(s);

  /// Los textos de la app en el idioma del informe (para los nombres de los
  /// modos, «1 compás»…).
  final Strings s;

  String get measured;
  String get estimated;
  String get unmeasured;
  String get normalLatency;
  String get none;
  String loopStateName(LoopState st);
  String phone(String model, String android, String lowLatency, String proAudio);
  String route(String route);
  String mic(String preset, bool fallback, String unprocessed, double gainDb);
  String stream(String api, int rate, int burst, int buffer, String bufferMs);
  String output(String mode, String low);
  String input(String mode, String low, int burst, int buffer, int maxRead, String channels);
  String estimate(String out, String inp);
  String roundTrip(String ms, int frames);
  String compensation(String ms, String source);
  String metronomeRun(int bpm, double minutes, int xruns);
  String xrunsSinceOpen(int n);
  String metronome(String meter, String click, String onSound);
  String drums(String style, bool on, bool playing, int volume, int loaded);
  String song(String? name, String phase, bool on, bool playing, int volume, int count);
  String recordDuck(String setting, bool speaker);
  String playMode(String mode);
  String looper(String state, String mode, int? baseBars, String autoAdvance);
  String track(
    int n,
    String state,
    int? bars,
    int layers,
    bool muted, {
    bool reverse = false,
    bool half = false,
  });
  String live(String stop, bool quantize, String? trainer, double a4);
  String trainerSetting(int step, int bars, int top);
  String controls(String volume, String headset, String learned);
}

class _Es extends ReportStrings {
  const _Es(super.s);

  @override
  String get measured => 'medida';
  @override
  String get estimated => 'estimada por Android';
  @override
  String get unmeasured => 'sin medir';
  @override
  String get normalLatency => 'latencia normal';
  @override
  String get none => 'ninguna';
  @override
  String loopStateName(LoopState st) => switch (st) {
    LoopState.empty => 'vacío',
    LoopState.armed => 'cuenta de entrada o esperando',
    LoopState.recording => 'grabando',
    LoopState.playing => 'sonando',
    LoopState.overdubbing => 'overdub',
    LoopState.stopped => 'parado',
  };
  @override
  String phone(String model, String android, String lowLatency, String proAudio) =>
      'Móvil: $model · Android $android · baja latencia: $lowLatency · pro audio: $proAudio';
  @override
  String route(String route) => 'Ruta: $route';
  @override
  String mic(String preset, bool fallback, String unprocessed, double gainDb) =>
      'Micrófono: $preset${fallback ? ' (el modo pedido falló)' : ''} · '
      'sin procesar admitido: $unprocessed · ganancia +${gainDb.toStringAsFixed(0)} dB';
  @override
  String stream(String api, int rate, int burst, int buffer, String bufferMs) =>
      'API: $api · $rate Hz · bloque $burst · buffer $buffer ($bufferMs)';
  @override
  String output(String mode, String low) => 'Salida: $mode · $low';
  @override
  String input(String mode, String low, int burst, int buffer, int maxRead, String channels) =>
      'Entrada: $mode · $low · bloque $burst · buffer $buffer · '
      'máx. leído por callback $maxRead · $channels';
  @override
  String estimate(String out, String inp) => 'Estimación de Oboe: salida $out + entrada $inp';
  @override
  String roundTrip(String ms, int frames) => 'Ida y vuelta medida: $ms ($frames muestras)';
  @override
  String compensation(String ms, String source) => 'Compensación al grabar: $ms ($source)';
  @override
  String metronomeRun(int bpm, double minutes, int xruns) =>
      'Metrónomo: $bpm BPM · ${s.dec(minutes, 1)} min · cortes: $xruns';
  @override
  String xrunsSinceOpen(int n) => 'Cortes desde que se abrió el audio: $n';
  @override
  String metronome(String meter, String click, String onSound) =>
      'Metrónomo: $meter · clic: $click · empezar al tocar: $onSound';
  @override
  String drums(String style, bool on, bool playing, int volume, int loaded) =>
      'Batería: $style · ${on ? (playing ? 'sonando' : 'encendida') : 'apagada'} · '
      'volumen $volume % · sonidos cargados: $loaded de ${DrumSound.values.length}';
  @override
  String song(String? name, String phase, bool on, bool playing, int volume, int count) =>
      'Canción: ${name ?? 'ninguna'} · $phase · '
      '${on ? (playing ? 'sonando' : 'encendida') : 'apagada'} · volumen $volume % · '
      'en la lista: $count';
  @override
  String recordDuck(String setting, bool speaker) =>
      'Al grabar con el altavoz: $setting'
      '${speaker ? ' (ruta con altavoz: se aplica)' : ' (ahora no se aplica)'}';
  @override
  String playMode(String mode) => 'Modo de la app: $mode';
  @override
  String looper(String state, String mode, int? baseBars, String autoAdvance) =>
      'Looper: $state · $mode'
      '${baseBars != null ? ' · base de ${s.bars(baseBars)}' : ''}'
      ' · avance automático: $autoAdvance';
  @override
  String track(
    int n,
    String state,
    int? bars,
    int layers,
    bool muted, {
    bool reverse = false,
    bool half = false,
  }) =>
      'Pista $n: $state'
      '${bars != null ? ' · ${s.bars(bars)} · ${s.layers(layers)}' : ''}'
      '${muted ? ' · en silencio' : ''}'
      '${reverse ? ' · al revés' : ''}'
      '${half ? ' · a media velocidad' : ''}';
  @override
  String live(String stop, bool quantize, String? trainer, double a4) =>
      'Al parar: $stop · cambios de pista en el 1: ${quantize ? 'sí' : 'no'} · '
      'entrenador: ${trainer ?? 'apagado'} · afinador: La = ${a4.round()} Hz';
  @override
  String trainerSetting(int step, int bars, int top) => '+$step BPM cada $bars C hasta $top';
  @override
  String controls(String volume, String headset, String learned) =>
      'Controles externos: volumen $volume · cascos $headset · teclas aprendidas: $learned';
}

class _En extends ReportStrings {
  const _En(super.s);

  @override
  String get measured => 'measured';
  @override
  String get estimated => 'estimated by Android';
  @override
  String get unmeasured => 'not measured';
  @override
  String get normalLatency => 'normal latency';
  @override
  String get none => 'none';
  @override
  String loopStateName(LoopState st) => switch (st) {
    LoopState.empty => 'empty',
    LoopState.armed => 'count-in or waiting',
    LoopState.recording => 'recording',
    LoopState.playing => 'playing',
    LoopState.overdubbing => 'overdub',
    LoopState.stopped => 'stopped',
  };
  @override
  String phone(String model, String android, String lowLatency, String proAudio) =>
      'Phone: $model · Android $android · low latency: $lowLatency · pro audio: $proAudio';
  @override
  String route(String route) => 'Route: $route';
  @override
  String mic(String preset, bool fallback, String unprocessed, double gainDb) =>
      'Microphone: $preset${fallback ? ' (the requested mode failed)' : ''} · '
      'unprocessed supported: $unprocessed · gain +${gainDb.toStringAsFixed(0)} dB';
  @override
  String stream(String api, int rate, int burst, int buffer, String bufferMs) =>
      'API: $api · $rate Hz · burst $burst · buffer $buffer ($bufferMs)';
  @override
  String output(String mode, String low) => 'Output: $mode · $low';
  @override
  String input(String mode, String low, int burst, int buffer, int maxRead, String channels) =>
      'Input: $mode · $low · burst $burst · buffer $buffer · '
      'max read per callback $maxRead · $channels';
  @override
  String estimate(String out, String inp) => 'Oboe estimate: output $out + input $inp';
  @override
  String roundTrip(String ms, int frames) => 'Measured round trip: $ms ($frames frames)';
  @override
  String compensation(String ms, String source) => 'Recording compensation: $ms ($source)';
  @override
  String metronomeRun(int bpm, double minutes, int xruns) =>
      'Metronome: $bpm BPM · ${s.dec(minutes, 1)} min · glitches: $xruns';
  @override
  String xrunsSinceOpen(int n) => 'Glitches since audio was opened: $n';
  @override
  String metronome(String meter, String click, String onSound) =>
      'Metronome: $meter · click: $click · start on play: $onSound';
  @override
  String drums(String style, bool on, bool playing, int volume, int loaded) =>
      'Drums: $style · ${on ? (playing ? 'playing' : 'on') : 'off'} · '
      'volume $volume% · sounds loaded: $loaded of ${DrumSound.values.length}';
  @override
  String song(String? name, String phase, bool on, bool playing, int volume, int count) =>
      'Song: ${name ?? 'none'} · $phase · '
      '${on ? (playing ? 'playing' : 'on') : 'off'} · volume $volume% · '
      'in the list: $count';
  @override
  String recordDuck(String setting, bool speaker) =>
      'While recording through the speaker: $setting'
      '${speaker ? ' (speaker route: applies)' : ' (does not apply now)'}';
  @override
  String playMode(String mode) => 'App mode: $mode';
  @override
  String looper(String state, String mode, int? baseBars, String autoAdvance) =>
      'Looper: $state · $mode'
      '${baseBars != null ? ' · base of ${s.bars(baseBars)}' : ''}'
      ' · auto advance: $autoAdvance';
  @override
  String track(
    int n,
    String state,
    int? bars,
    int layers,
    bool muted, {
    bool reverse = false,
    bool half = false,
  }) =>
      'Track $n: $state'
      '${bars != null ? ' · ${s.bars(bars)} · ${s.layers(layers)}' : ''}'
      '${muted ? ' · muted' : ''}'
      '${reverse ? ' · reversed' : ''}'
      '${half ? ' · half speed' : ''}';
  @override
  String live(String stop, bool quantize, String? trainer, double a4) =>
      'On stop: $stop · track changes on the 1: ${quantize ? 'yes' : 'no'} · '
      'trainer: ${trainer ?? 'off'} · tuner: A = ${a4.round()} Hz';
  @override
  String trainerSetting(int step, int bars, int top) => '+$step BPM every $bars bars up to $top';
  @override
  String controls(String volume, String headset, String learned) =>
      'External controls: volume $volume · headset $headset · learned keys: $learned';
}
