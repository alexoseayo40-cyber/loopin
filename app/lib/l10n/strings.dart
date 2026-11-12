// Loopin — todos los textos de la app
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Para traducir (Etapa 7): crear `class StringsEn implements Strings` con los
// mismos nombres (el compilador avisa si falta alguno) y elegirla en
// [useStrings] según el idioma del móvil.
//
// Reglas de estilo: una línea por opción; la explicación larga va en un
// texto `…Help`, que la app enseña plegado detrás de un «?».
import 'package:loopin_engine/loopin_engine.dart';

import '../engine/engine_controller.dart' show RecordDuck;
import '../engine/meter.dart';
import '../engine/pedal_keys.dart';
import '../ui/theme.dart';

/// Los textos que se están usando.
Strings get tr => _strings;
Strings _strings = const Strings();

/// Cambia el idioma de los textos.
void useStrings(Strings strings) => _strings = strings;

/// Textos en español.
class Strings {
  const Strings();

  // ---------------------------------------------------------------- comunes

  String get appName => 'Loopin';
  String get cancel => 'Cancelar';
  String get showHelp => 'Explicación';
  String get hideHelp => 'Ocultar la explicación';
  String get yes => 'sí';
  String get no => 'no';
  String yesNo(Object? v) => v == true ? yes : (v == false ? no : '—');
  String ms(double v) => v < 0 ? '—' : '${v.toStringAsFixed(1)} ms';
  String percent(double fraction) => '${(fraction * 100).round()} %';

  /// «1 compás», «4 compases»
  String bars(int n) => '$n ${n == 1 ? 'compás' : 'compases'}';

  /// «1 capa», «2 capas»
  String layers(int n) => '$n ${n == 1 ? 'capa' : 'capas'}';

  /// «1 golpe», «7 golpes»
  String hits(int n) => '$n ${n == 1 ? 'golpe' : 'golpes'}';

  // ---------------------------------------------------------------- motor

  String presetName(InputPreset p) => switch (p) {
    InputPreset.unprocessed => 'Sin procesar',
    InputPreset.voicePerformance => 'Actuación en directo',
    InputPreset.voiceRecognition => 'Reconocimiento de voz',
    InputPreset.camcorder => 'Vídeo',
    InputPreset.generic => 'Normal',
  };

  /// Una línea por modo del micrófono.
  String presetLine(InputPreset p) => switch (p) {
    InputPreset.unprocessed => 'Tal cual, sin arreglos. El mejor para guitarra.',
    InputPreset.voicePerformance => 'Poco retardo. No todos los móviles lo tienen.',
    InputPreset.voiceRecognition => 'Natural, sin cambios de volumen. A veces más retardo.',
    InputPreset.camcorder => 'El de la cámara. Puede llevar filtros.',
    InputPreset.generic => 'Sube y baja el volumen solo. Evítalo.',
  };

  String get unprocessedUnsupported => 'Este móvil no lo admite: Android usa el Normal.';
  String get recommended => 'RECOMENDADO';

  String loopModeName(LoopMode m) => switch (m) {
    LoopMode.sync => 'Sincronizado',
    LoopMode.manual => 'Manual',
    LoopMode.free => 'Libre',
  };

  String loopModeLine(LoopMode m) => switch (m) {
    LoopMode.sync => 'Graba los compases que elijas y se cierra solo',
    LoopMode.manual => 'Se cierra cuando vuelves a pulsar',
    LoopMode.free => 'Sin metrónomo: el tempo sale del primer loop',
  };

  /// En la pantalla de tempo
  String loopModeShort(LoopMode m) => switch (m) {
    LoopMode.sync => 'SYNC',
    LoopMode.manual => 'MANUAL',
    LoopMode.free => 'LIBRE',
  };

  String clickModeName(ClickMode m) => switch (m) {
    ClickMode.silent => 'Solo visual',
    ClickMode.countIn => 'Solo la cuenta',
    ClickMode.always => 'Siempre',
  };

  String clickModeLine(ClickMode m) => switch (m) {
    ClickMode.always => 'Suena todo el rato',
    ClickMode.countIn => 'Solo el compás antes de grabar la pista 1',
    ClickMode.silent => 'No suena nunca: solo las luces',
  };

  /// «Clic: siempre»
  String click(ClickMode m) => 'Clic: ${clickModeName(m).toLowerCase()}';

  /// Nombre de un dispositivo de audio de Android.
  String deviceName(AudioDevice d) {
    final extra = d.address.isNotEmpty ? ' (${d.address})' : '';
    return switch (d.type) {
      15 => 'Micrófono del móvil$extra',
      2 => 'Altavoz del móvil',
      1 => 'Auricular de llamada',
      3 => 'Auriculares con cable (micro)',
      4 => 'Auriculares con cable',
      5 || 6 => 'Entrada de línea',
      7 || 26 || 8 || 27 => 'Bluetooth: ${d.name} (con retardo)',
      11 || 12 => 'USB: ${d.name}',
      22 => 'Cascos USB: ${d.name}',
      _ => d.name.isNotEmpty ? d.name : 'Dispositivo ${d.type}',
    };
  }

  String unknownDevice(int id) => 'dispositivo $id';

  /// Mensaje para un código de error de Oboe.
  String audioError(int code) => switch (code) {
    -899 => 'El dispositivo de audio se ha desconectado',
    -889 => 'El dispositivo de audio no está disponible',
    -883 => 'Formato de audio no soportado',
    -887 => 'No hay memoria suficiente',
    -881 => 'El servicio de audio de Android no responde',
    _ => 'Error de audio ($code)',
  };

  String get micDeniedForever =>
      'Sin permiso de micrófono. Actívalo en Ajustes › Apps › Loopin › Permisos.';
  String get micNeeded => 'Loopin necesita el micrófono para escuchar la guitarra.';

  // ---------------------------------------------------------------- looper: cabecera

  String get settings => 'Ajustes';
  String latencyChip(int ms) => 'LATENCIA $ms MS';
  String get latencyChipUnmeasured => 'LATENCIA SIN MEDIR';
  String latencyChipSemantics(int ms) => 'Latencia medida: $ms milisegundos';
  String get latencyChipUnmeasuredSemantics =>
      'Latencia sin medir: el loop puede ir desfasado. Toca para medirla';

  // ---------------------------------------------------------------- looper: tempo

  String get tempoDown => 'Bajar el tempo';
  String get tempoUp => 'Subir el tempo';
  String get bpmUnit => 'BPM';
  String get bpmUnitEighths => 'BPM ♪';
  String get noTempoYet => '- - -';
  String get tapTempo => 'TAP · TOCA AL RITMO';
  String get tempoLocked => 'FIJO MIENTRAS HAYA LOOP';
  String get tempoFromLoop => 'LIBRE: EL TEMPO SALDRÁ DEL LOOP';
  String get tempoFromLoopSemantics => 'Modo libre: el tempo saldrá del primer loop';
  String bpmSemantics(int bpm, {required bool locked}) =>
      '$bpm pulsos por minuto. '
      '${locked ? 'Fijo mientras haya loop' : 'Toca varias veces al ritmo para marcar el tempo'}';

  String get stopAll => 'Parar todo';
  String get startAll => 'Arrancar todo';
  String get stopMetronome => 'Parar el metrónomo';
  String get startMetronome => 'Arrancar el metrónomo';
  String get metronomeStopped => 'Metrónomo parado';
  String beatOf(int beat, int beats) => 'Tiempo $beat de $beats';

  String get meter => 'Compás';

  /// En el menú: «7/8  (2+2+3)»
  String meterItem(TimeSignature ts) =>
      ts.grouping.isEmpty ? ts.label : '${ts.label}  (${ts.grouping})';

  /// En la pantalla: «7/8 2+2+3»
  String meterChip(TimeSignature ts) =>
      ts.grouping.isEmpty ? ts.label : '${ts.label} ${ts.grouping}';

  String get recordMode => 'Modo de grabación';
  String get syncBars => 'Compases que graba';

  /// «4 C»
  String barsShort(int n) => '$n C';

  String get startOnSound => 'Empezar al tocar';
  String startOnSoundTooltip(bool on) => 'Empezar al tocar: ${on ? yes : no}';
  String get startOnSoundOn =>
      'Empezar al tocar: la pista 1 arranca con tu primera nota, sin cuenta';
  String get startOnSoundOff => 'Empezar al tocar, apagado: la pista 1 tiene 1 compás de cuenta';

  // ---------------------------------------------------------------- looper: pistas

  String trackLabel(int n) => 'PISTA $n';
  String trackStateName(LoopState st, {bool muted = false}) => switch (st) {
    LoopState.empty => 'vacía',
    LoopState.armed => 'a punto de grabar',
    LoopState.recording => 'grabando',
    LoopState.playing => muted ? 'en silencio' : 'sonando',
    LoopState.overdubbing => 'grabando encima',
    LoopState.stopped => 'parada',
  };

  /// «Pista 2, sonando, 4 compases, 2 capas»
  String trackSemantics(int n, String state, {int? bars, int layers = 0}) =>
      'Pista $n, $state'
      '${bars != null ? ', ${this.bars(bars)}' : ''}'
      '${layers > 1 ? ', ${this.layers(layers)}' : ''}';

  /// Debajo del anillo: «4 C · 2» (compases y capas, si hay más de una)
  String trackRingLabel(int bars, int layers) => '$bars C${layers > 1 ? ' · $layers' : ''}';
  String get trackRingEmpty => '—';

  String trackVolume(int n, double v) => 'Volumen de la pista $n: ${(v * 100).round()} %';
  String unmuteTrack(int n) => 'Volver a oír la pista $n';
  String muteTrack(int n) => 'Silenciar la pista $n';
  String clearTrack(int n) => 'Borrar la pista $n';

  // ---------------------------------------------------------------- looper: pulsador

  String get pedal => 'Botón principal';
  String pedalSemantics(String title, String subtitle) => 'Botón principal. $title. $subtitle';

  String get ready => 'LISTO';
  String readyOnSound(int track) =>
      'Toca y empieza a tocar: la pista $track arranca con tu primera nota';
  String readyFree(int track) => 'Toca para grabar la pista $track (sin metrónomo)';
  String readyCountIn(int track) => 'Toca para grabar la pista $track, con 1 compás de cuenta';

  String get waiting => 'ESPERANDO';
  String get waitingLine => 'Empieza a tocar: la grabación arranca con tu primera nota';

  String get getReady => 'PREPÁRATE';
  String trackStartsNextBar(int track) => 'La pista $track empieza en el próximo compás';
  String get countIn => 'Cuenta de entrada';

  String recordingTitle(int track) => 'GRABANDO · PISTA $track';
  String get recordingFree => 'Toca para cerrar: el tempo saldrá del loop';
  String barOf(int bar, int of) => 'Compás $bar de $of';
  String barOpen(int bar) => 'Compás $bar · toca para cerrar';

  String get playing => 'SONANDO';
  String overdubOn(int track) => 'Toca para grabar encima de la pista $track';
  String recordOn(int track) => 'Toca para grabar la pista $track';

  String overdubNextBar(int track) => 'Overdub de la pista $track en el próximo compás';
  String overdubTitle(int track) => 'OVERDUB · PISTA $track';
  String get tapToFinish => 'Toca para terminar';

  String get stopped => 'PARADO';
  String get tapToStart => 'Toca para arrancar';

  String get audioOn => 'ENCENDER AUDIO';

  // ---------------------------------------------------------------- looper: abajo

  String get gestures => 'Toca: grabar · Mantén: deshacer · Doble toque: parar';
  String get undo => 'DESHACER';
  String get stop => 'PARAR';
  String get start => 'ARRANCAR';
  String get clearAll => 'Borrar todas las pistas';
  String get clearAllTitle => '¿Borrar las 4 pistas?';
  String get clearAllBody => 'Se pierde todo lo grabado. No se puede deshacer.';
  String get clearAllConfirm => 'Borrar todo';
  String get inputLevel => 'Nivel de entrada';
  String get monitor => 'ESCUCHARME';

  // ---------------------------------------------------------------- ajustes

  String get appearance => 'Apariencia';
  String get themeSystem => 'Sistema';
  String get themeLight => 'Claro';
  String get themeDark => 'Oscuro';
  String get pedalColor => 'Color del pedal';
  String chassisName(Chassis c) => switch (c) {
    Chassis.classic => 'Clásico',
    Chassis.red => 'Rojo',
    Chassis.green => 'Verde',
    Chassis.blue => 'Azul',
  };
  String chassisSemantics(Chassis c) => 'Color ${chassisName(c)}';

  String get looper => 'Looper';
  String get autoAdvance => 'Avance automático';
  String get autoAdvanceLine => 'Cada toque graba una pista nueva';
  String get autoAdvanceHelp =>
      'Al cerrar una pista se elige sola la siguiente vacía, así cada toque graba una '
      'pista nueva sin mirar la pantalla. Con las 4 llenas, el toque graba encima de la '
      'última. Apagado, todo va a la misma pista, como en un pedal clásico.';

  String get recordDuckTitle => 'Al grabar con el altavoz';
  String get recordDuckLine => 'Lo que ya suena, mientras grabas';
  String get recordDuckHelp =>
      'Con el altavoz y el micrófono del móvil, el micrófono recoge lo que suena y lo graba '
      'otra vez en la pista nueva (o en el overdub): se duplica y se acumula. Mientras '
      'grabas, lo que ya suena puede seguir normal, sonar más bajo o callarse; vuelve al '
      'acabar de grabar. El tempo lo sigues viendo en las luces y en el pulsador. Con '
      'cascos o una interfaz suena siempre normal. El clic en «siempre» también se graba: '
      'mejor «solo la cuenta».';
  String recordDuckName(RecordDuck d) => switch (d) {
    RecordDuck.normal => 'Normal',
    RecordDuck.low => 'Más bajo',
    RecordDuck.silent => 'Silencio',
  };

  /// Al grabar con lo demás callado o más bajo: «Compás 2 de 4 · lo demás, en silencio»
  String withDuck(String line, RecordDuck d) => switch (d) {
    RecordDuck.normal => line,
    RecordDuck.low => '$line · lo demás, más bajo',
    RecordDuck.silent => '$line · lo demás, en silencio',
  };

  String get externalControls => 'Controles externos';
  String get externalControlsHelp =>
      'Para tocar sin manos. El botón principal hace lo mismo que el pulsador grande '
      '(toque, mantener y doble toque). El secundario cambia de pista con un toque y '
      'deshace si lo mantienes.';
  String get volumeKeys => 'Botones de volumen';
  String get volumeKeysLine => 'Subir: principal · Bajar: secundario';
  String get volumeKeysHelp =>
      'Valen los del móvil y los del cable de los cascos. Mientras esté activado, no '
      'cambian el volumen dentro de Loopin.';
  String get headsetKey => 'Botón de los cascos';
  String get headsetKeyLine => 'Hace de botón principal';
  String get headsetKeyHelp =>
      'El botón central de los cascos (o de un mando multimedia). Mejor solo con '
      'toques: en muchos cascos, mantenerlo abre el asistente de voz.';
  String pedalActionName(PedalAction a) => switch (a) {
    PedalAction.main => 'Botón principal',
    PedalAction.secondary => 'Botón secundario',
  };
  String bluetoothPedal(PedalAction a) => 'Pedal Bluetooth: ${pedalActionName(a).toLowerCase()}';
  String get pressPedalNow => 'Pulsa ahora el botón del pedal…';
  String get notAssigned => 'Sin asignar';
  String get learnHelp =>
      'Para un pedal Bluetooth o un teclado: toca «Aprender» y pulsa el botón. Vale '
      'cualquier pedal que el móvil vea como teclado.';
  String get learn => 'Aprender';
  String removeKey(String key) => 'Quitar $key';

  /// «PAGE_DOWN», o «tecla 93» si Android no da el nombre
  String keyName(int code, String name) => name.isEmpty ? 'tecla $code' : shortKeyName(name);
  String lastKey(String key, PedalAction? action) =>
      'Última tecla: $key → ${action == null ? '—' : pedalActionName(action).toLowerCase()}';

  String get audio => 'Audio';
  String get audioAndLatency => 'Audio y latencia';
  String get audioAndLatencyLine => 'Entrada, micrófono y latencia';

  // ---------------------------------------------------------------- audio y latencia

  String get copyResults => 'Copiar resultados';
  String get resultsCopied => 'Resultados copiados';
  String get turnAudioOn => 'Encender audio';
  String get turnAudioOff => 'Apagar audio';

  String get input => 'Guitarra (entrada)';
  String get inputDevice => 'Entrada';
  String get inputAuto => 'Automática (la elige Android)';
  String get micMode => 'Modo del micrófono';
  String get micModeHelp =>
      'Cuánto «arregla» Android el sonido antes de que llegue a Loopin. Si dos modos te '
      'suenan igual, quédate con el que dé menos latencia. Solo se nota al escucharte en '
      'directo: los loops cuadran con cualquiera, porque la latencia se compensa.';
  String presetFallback(InputPreset used) =>
      'El modo elegido no funciona en este móvil: se usa ${presetName(used)}.';
  String nowRoute(String input, String output) => '$input → $output';
  String gain(double db) => 'Ganancia +${db.toStringAsFixed(0)} dB';
  String get gainLine => 'Toca fuerte: que llegue a naranja sin ponerse rojo.';
  String get level => 'Nivel';
  String get monitorTitle => 'Escucharme en directo';
  String get monitorLine => 'Solo con auriculares de cable';
  String get monitorHelp =>
      'Por el altavoz se acopla (pitido). Con auriculares Bluetooth llega con mucho '
      'retardo (150–300 ms) y no sirve para tocar.';
  String get monitorVolume => 'Volumen de escucha';

  String get latency => 'Latencia';
  String get latencyHelp =>
      'Lo que tarda el sonido en salir del móvil y volver a entrar. Loopin lo descuenta al '
      'grabar para que el loop caiga en el tiempo. Cambia según por dónde entra y sale el '
      'sonido (altavoz, cascos, interfaz), así que se guarda una para cada caso.';
  String route(String route) => 'Ahora: $route';
  String latencySourceName(bool measured, bool estimated) =>
      measured ? 'medida' : (estimated ? 'estimada por Android, sin medir' : 'sin medir');
  String compensation(String ms, String source) => 'Compensación: $ms ($source)';

  String get measureAlone => 'Medir sola';
  String measuringClick(int n) => 'Midiendo… clic $n/5';
  String get measureAloneLine => 'Con el altavoz, o una interfaz con un cable';
  String get measureAloneHelp =>
      'Loopin da 5 clics y mide cuánto tardan en volver. Altavoz: sin cascos, volumen '
      'alto y en silencio. Interfaz: une con un cable la salida de auriculares y la '
      'entrada.';
  String measured(String ms) => 'Medida: $ms · guardada';
  String get clicksNotHeard => 'No se oyeron los clics. Sube el volumen o revisa el cable.';

  String get measureTapping => 'Medir tocando al clic';
  String get measureTappingLine => 'Con cascos: tocas tú al ritmo';
  String get measureTappingHelp =>
      'Con cascos el clic no vuelve al micrófono: tocas tú al ritmo de unos clics y se '
      'mide cuánto tarda tu golpe en llegar.';

  String get byHand => 'A mano';
  String get byHandLine => 'Si el loop suena tarde, sube; si suena antes, baja.';
  String get byHandHelp =>
      'Para afinar a oído: graba un loop con el clic encendido dando golpes secos en los '
      'tiempos y mueve esto hasta que el loop y el clic suenen a la vez. Lo grabado se '
      'mueve contigo.';
  String get minus1ms => 'Restar 1 ms';
  String get plus1ms => 'Sumar 1 ms';
  String msValue(int ms) => '$ms ms';
  String msSemantics(int ms) => '$ms milisegundos';
  String get forgetLatency => 'Olvidar la latencia de esta ruta';
  String get finishRecordingFirst => 'Termina de grabar antes de medir.';

  String get technicalDetails => 'Detalles técnicos';
  String get sharedMode => 'compartido';
  String get exclusiveMode => 'exclusivo';
  String get lowLatency => 'baja latencia';
  String get noLowLatency => 'SIN baja latencia';
  String channels(int n) => n == 1 ? 'mono' : '$n canales';
  String detailsStream(String api, int rate, int burst) => '$api · $rate Hz · bloque $burst';
  String detailsOutput(String mode, String low, int buffer, String ms) =>
      'Salida: $mode · $low · buffer $buffer ($ms)';
  String detailsInput(String mode, String low, String ch, int burst, int buffer, int maxRead) =>
      'Entrada: $mode · $low · $ch · bloque $burst · buffer $buffer · máx. por callback $maxRead';
  String detailsEstimate(String out, String inp, String total) =>
      'Estimación de Android: salida $out + entrada $inp = $total';
  String detailsXruns(int n) => 'Cortes desde que arrancó el metrónomo: ${n < 0 ? '—' : n}';
  String engineLoad(String avg, String peak, String max) =>
      'Carga del motor: media $avg · pico $peak (máx. $max)';
  String get engineLoadHelp =>
      'Cuánto del tiempo de cada bloque de audio usa Loopin. Por encima del 100 % el '
      'sonido se corta.';

  // ---------------------------------------------------------------- medir tocando

  String get measureTappingTitle => 'Medir tocando';
  String get tapIntro => 'Para cuando usas cascos y el clic no vuelve al micrófono.';
  String get tapSteps =>
      '1. Ponte los cascos y coge la guitarra.\n'
      '2. Sonarán 16 clics. Escucha 4 y, en los 12 siguientes, da un golpe seco en cada '
      'clic (cuerdas apagadas o golpe en la caja).\n'
      '3. Toca como con un metrónomo: no hace falta ser perfecto.';
  String tapListen(int click) => 'Escucha\n$click';
  String tapCount(int n, int of) => '$n / $of';
  String tapHits(int n) => 'Golpes que cuentan: $n';
  String get tapGetReady => 'Prepárate…';
  String tapResult(int ms) => 'Latencia: $ms ms · guardada';
  String tapQuality(int spreadMs, int hitCount) {
    if (spreadMs <= 10) return 'Muy regular (±$spreadMs ms, ${hits(hitCount)}). Buena medida.';
    if (spreadMs <= 25) {
      return 'Regular (±$spreadMs ms, ${hits(hitCount)}). Vale; si quieres afinar, repite.';
    }
    return 'Bastante irregular (±$spreadMs ms). Repite con golpes más secos.';
  }

  String get tapFailed =>
      'No se oyeron bastantes golpes (hacen falta 6 de 12). Sube la ganancia o golpea más '
      'fuerte, y repite.';
  String get tapStart => 'Empezar';
  String get tapRepeat => 'Repetir';
  String get tapStop => 'Parar';
  String get tapWhat => '¿Qué se mide exactamente?';
  String get tapHelp =>
      'Se mide lo que tarda tu golpe en llegar respecto al clic que oyes: la latencia del '
      'móvil más tu forma de tocar. Por eso, con esta medida, lo que grabes cae justo en '
      'el tiempo.';

  // ---------------------------------------------------------------- informe («Copiar resultados»)

  String get reportTitle => 'Loopin · Etapa 3.5';
  ReportStrings get report => const ReportStrings();
  String loopStateName(LoopState st) => switch (st) {
    LoopState.empty => 'vacío',
    LoopState.armed => 'cuenta de entrada o esperando',
    LoopState.recording => 'grabando',
    LoopState.playing => 'sonando',
    LoopState.overdubbing => 'overdub',
    LoopState.stopped => 'parado',
  };
  String get none => 'ninguna';
}

/// Líneas del informe de «Copiar resultados».
class ReportStrings {
  const ReportStrings();

  String get measured => 'medida';
  String get estimated => 'estimada por Android';
  String get unmeasured => 'sin medir';
  String get normalLatency => 'latencia normal';

  String phone(String model, String android, String lowLatency, String proAudio) =>
      'Móvil: $model · Android $android · baja latencia: $lowLatency · pro audio: $proAudio';
  String route(String route) => 'Ruta: $route';
  String mic(String preset, bool fallback, String unprocessed, double gainDb) =>
      'Micrófono: $preset${fallback ? ' (el modo pedido falló)' : ''} · '
      'sin procesar admitido: $unprocessed · ganancia +${gainDb.toStringAsFixed(0)} dB';
  String stream(String api, int rate, int burst, int buffer, String bufferMs) =>
      'API: $api · $rate Hz · bloque $burst · buffer $buffer ($bufferMs)';
  String output(String mode, String low) => 'Salida: $mode · $low';
  String input(String mode, String low, int burst, int buffer, int maxRead, String channels) =>
      'Entrada: $mode · $low · bloque $burst · buffer $buffer · '
      'máx. leído por callback $maxRead · $channels';
  String estimate(String out, String inp) => 'Estimación de Oboe: salida $out + entrada $inp';
  String roundTrip(String ms, int frames) => 'Ida y vuelta medida: $ms ($frames muestras)';
  String compensation(String ms, String source) => 'Compensación al grabar: $ms ($source)';
  String metronomeRun(int bpm, double minutes, int xruns) =>
      'Metrónomo: $bpm BPM · ${minutes.toStringAsFixed(1)} min · cortes: $xruns';
  String xrunsSinceOpen(int n) => 'Cortes desde que se abrió el audio: $n';
  String metronome(String meter, String click, String onSound) =>
      'Metrónomo: $meter · clic: $click · empezar al tocar: $onSound';
  String recordDuck(String setting, bool speaker) =>
      'Al grabar con el altavoz: $setting${speaker ? ' (ruta con altavoz: se aplica)' : ' (ahora no se aplica)'}';
  String looper(String state, String mode, int? baseBars, String autoAdvance) =>
      'Looper: $state · $mode'
      '${baseBars != null ? ' · base de ${tr.bars(baseBars)}' : ''}'
      ' · avance automático: $autoAdvance';
  String track(int n, String state, int? bars, int layers, bool muted) =>
      'Pista $n: $state'
      '${bars != null ? ' · ${tr.bars(bars)} · ${tr.layers(layers)}' : ''}'
      '${muted ? ' · en silencio' : ''}';
  String controls(String volume, String headset, String learned) =>
      'Controles externos: volumen $volume · cascos $headset · teclas aprendidas: $learned';
}
