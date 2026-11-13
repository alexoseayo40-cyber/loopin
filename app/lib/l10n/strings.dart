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
import '../engine/song_backing.dart' show BackingPhase;
import '../engine/songs.dart' show ImportError;
import '../engine/meter.dart';
import '../engine/pedal_keys.dart';
import '../engine/play_mode.dart';
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
  String get ok => 'Entendido';
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
    ClickMode.untilRecording => 'Hasta grabar',
  };

  String clickModeLine(ClickMode m) => switch (m) {
    ClickMode.always => 'Suena todo el rato',
    ClickMode.untilRecording => 'Con el metrónomo solo y en la cuenta; al grabar, se calla',
    ClickMode.countIn => 'Solo el compás antes de grabar la pista 1',
    ClickMode.silent => 'No suena nunca: solo las luces',
  };

  /// «Clic: siempre»
  String click(ClickMode m) => 'Clic: ${clickModeName(m).toLowerCase()}';

  /// En el modo simple, un toque pasa de un modo del clic al siguiente.
  String simpleClick(ClickMode m) => m == ClickMode.silent ? 'Clic: apagado' : click(m);
  String simpleClickSnack(ClickMode m) => switch (m) {
    ClickMode.always => 'Clic: siempre',
    ClickMode.untilRecording =>
      'Clic hasta grabar: suena con el metrónomo y en la cuenta; al grabar se calla',
    _ => 'Clic apagado: el tempo se ve en las luces y en el pulsador',
  };

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

  // Etapa 5: reverse y media velocidad
  String get reverseShort => 'REV';
  String get halfShort => '½';
  String reverseTrack(int n, bool on) =>
      on ? 'Pista $n al revés: quitar' : 'Poner la pista $n al revés';
  String halfTrack(int n, bool on) =>
      on ? 'Pista $n a media velocidad: quitar' : 'Poner la pista $n a media velocidad';

  /// Para lectores de pantalla, cuando el cambio espera al siguiente 1
  String get atNextOne => 'en el siguiente 1';

  /// Debajo del anillo, si la pista va al revés o a media velocidad: «2 C · REV ½»
  String trackRingFx(String label, {required bool reverse, required bool half}) =>
      '$label${reverse || half ? ' ·' : ''}${reverse ? ' REV' : ''}${half ? ' ½' : ''}';

  // ---------------------------------------------------------------- entrenador de tempo

  String get trainer => 'Entrenador de tempo';
  String trainerTooltip(bool on) => 'Entrenador de tempo: ${on ? 'encendido' : 'apagado'}';
  String get trainerLine => 'Sube el tempo poco a poco mientras tocas';
  String get trainerHelp =>
      'Para practicar algo cada vez más rápido. Al darle a ▶ empieza en tu tempo y, cada '
      'pocos compases, sube lo que digas, justo en el 1, hasta el tempo de arriba; ahí se '
      'queda. Al parar vuelve a tu tempo. Funciona sin loops (con un loop el tempo es el '
      'suyo). La batería lo sigue; una canción se calla un momento en cada subida, '
      'mientras se vuelve a preparar.';
  String get trainerStep => 'Sube';
  String get trainerEvery => 'Cada';
  String get trainerTop => 'Hasta';
  String trainerBpm(num v) => '${v.round()} BPM';
  String trainerBarsShort(int n) => '$n C';
  String trainerSummary(int from, int to, int step, int bars, int steps) => steps <= 0
      ? 'Ya estás en $to BPM o más: sube el tempo de arriba'
      : 'De $from a $to BPM: +$step cada ${this.bars(bars)} '
            '(${steps == 1 ? '1 subida' : '$steps subidas'})';

  /// En la pantalla de tempo, en lugar del TAP: «ENTRENADOR +5 / 4 C · HASTA 132»
  String trainerPill(int step, int bars, int top) => 'ENTRENADOR +$step / $bars C · HASTA $top';
  String get trainerNeedsNoLoops => 'Solo sin loops: con un loop el tempo es el suyo';
  String get trainerDecrease => 'Menos';
  String get trainerIncrease => 'Más';

  // ---------------------------------------------------------------- afinador

  String get tuner => 'Afinador';
  String get tunerHelp =>
      'Toca una cuerda al aire, sola y dejándola sonar. Arriba sale la nota que oye y la '
      'aguja dice cuánto le falta: a la izquierda, baja (aprieta la clavija); a la '
      'derecha, alta (afloja). En el centro, verde, está afinada. Usa la entrada que '
      'tengas: el micrófono del móvil o la interfaz. Con el micrófono, mejor cerca de la '
      'guitarra y en silencio. Mientras está abierto, lo demás sigue sonando.';
  // Con «#» y no «♯»: las tipografías de la app no tienen ese signo
  static const _noteNames = [
    'DO',
    'DO#',
    'RE',
    'RE#',
    'MI',
    'FA',
    'FA#',
    'SOL',
    'SOL#',
    'LA',
    'LA#',
    'SI',
  ];
  static const _noteLetters = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  /// Nombre de la nota (0 = Do … 11 = Si)
  String noteName(int pitchClass) => _noteNames[pitchClass % 12];

  /// En letras, con la octava: «E2»
  String noteLetter(int pitchClass, int octave) => '${_noteLetters[pitchClass % 12]}$octave';
  String get tunerListening => 'Toca una cuerda al aire';
  String get tunerNoAudio => 'El audio está apagado';
  String get tunerInTune => 'AFINADA';
  String get tunerFlat => 'BAJA · aprieta';
  String get tunerSharp => 'ALTA · afloja';
  String tunerCents(double c) => '${c >= 0 ? '+' : '−'}${c.abs().round()} cents';
  String tunerHz(double f) => '${f.toStringAsFixed(1).replaceAll('.', ',')} Hz';
  String get tunerStandard => 'Afinación estándar';
  String tunerSemantics(String note, double cents) =>
      'Nota $note, ${cents.abs() <= 3 ? 'afinada' : (cents < 0 ? 'baja' : 'alta')}, '
      '${tunerCents(cents)}';
  String get tunerA4 => 'La de referencia';
  String tunerA4Value(double hz) => 'La = ${hz.round()} Hz';
  String get tunerA4Help =>
      'La frecuencia del La de la 5.ª cuerda, una octava más arriba. Lo normal es 440 Hz; '
      'cámbialo solo para tocar con algo afinado de otra forma (un piano, una grabación).';
  String get tunerSpeaker => 'Lo que suena por el altavoz también llega al afinador';
  String get tunerStopAll => 'Parar';
  String get tunerOpen => 'Afinador';
  String get referenceNotes => 'Oír una nota';
  String get referenceNotesLine =>
      'Para afinar de oído: toca una para que suene, otra vez para callarla';
  String get referenceStop => 'Callar';

  /// El botón del La de referencia: «LA 440»
  String referenceA4(double hz) => 'LA ${hz.round()}';
  String referenceNoteSemantics(String note, double hz, bool on) =>
      '${on ? 'Callar' : 'Oír'} $note, ${tunerHz(hz)}';

  // ---------------------------------------------------------------- looper: batería

  String get drums => 'BATERÍA';
  String drumStyleName(DrumStyle st) => switch (st) {
    DrumStyle.basic => 'Básico',
    DrumStyle.rock => 'Rock',
    DrumStyle.pop => 'Pop',
    DrumStyle.shuffle => 'Blues shuffle',
    DrumStyle.funk => 'Funk',
    DrumStyle.ballad => 'Balada',
    DrumStyle.reggae => 'Reggae',
    DrumStyle.waltz => 'Vals',
    DrumStyle.sixEight => 'Balada 6/8',
    DrumStyle.slowBlues => 'Blues lento',
  };
  String drumStyleChip(DrumStyle st) => switch (st) {
    DrumStyle.shuffle => 'SHUFFLE',
    DrumStyle.sixEight => 'BALADA',
    DrumStyle.slowBlues => 'BLUES',
    _ => drumStyleName(st).toUpperCase(),
  };

  /// En el menú: «Rock · 4/4», «Básico · cualquier compás»
  String drumStyleItem(DrumStyle st, String? meter) =>
      '${drumStyleName(st)} · ${meter ?? 'cualquier compás'}';
  String get drumStyleMenu => 'Estilo de la batería';
  String get drumsTurnOn => 'Encender la batería';
  String get drumsTurnOff => 'Apagar la batería';
  String drumVolume(double v) => 'Volumen de la batería: ${(v * 100).round()} %';
  String drumsSemantics(String style, bool on, bool playing) =>
      'Batería, $style, ${!on ? 'apagada' : (playing ? 'sonando' : 'encendida, entra en el próximo 1')}';
  String get drumsBleed => 'Con el altavoz, el micro graba la batería';
  String get drumsBleedHelp =>
      'Con el altavoz y el micrófono del móvil, la batería se cuela en lo que grabas (no se '
      'calla al grabar: la necesitas para tocar a tempo). Si luego la apagas, seguirá en los '
      'loops. Para que no pase, usa cascos o una interfaz.';

  // ---------------------------------------------------------------- looper: acompañamiento

  /// El selector de la fila de abajo: batería o canción
  String get accDrums => 'BATERÍA';
  String get accSong => 'CANCIÓN';
  String accShow(String what) => 'Enseñar: ${what.toLowerCase()}';

  // ---------------------------------------------------------------- canción (audio importado)

  /// «97,3», «120», «97,34»: con los decimales que tenga (coma decimal)
  String bpmNumber(double v) {
    var t = v.toStringAsFixed(2);
    while (t.contains('.') && (t.endsWith('0') || t.endsWith('.'))) {
      t = t.substring(0, t.length - 1);
    }
    return t.replaceAll('.', ',');
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
    return '$m:${rest.toStringAsFixed(1).padLeft(4, '0').replaceAll('.', ',')}';
  }

  // En la fila
  String get songChoose => 'ELEGIR';
  String get songSetup => 'PREPARAR';
  String get songTooFar => 'LEJOS';
  String get songFailedChip => 'ERROR';
  String songChip(String name) => name.toUpperCase();
  String songSpeed(double v) => '${(v * 100).round()} %';
  String get songMenu => 'Canciones';
  String get songTurnOn => 'Encender la canción';
  String get songTurnOff => 'Apagar la canción';
  String songVolume(double v) => 'Volumen de la canción: ${(v * 100).round()} %';
  String songSemantics(String? name, bool on, bool playing) =>
      'Canción, ${name ?? 'ninguna'}, '
      '${!on ? 'apagada' : (playing ? 'sonando' : 'encendida, entra en el próximo 1')}';
  String get songBleed => 'Con el altavoz, el micro graba la canción';
  String get songBleedHelp =>
      'Con el altavoz y el micrófono del móvil, la canción se cuela en lo que grabas (no se '
      'calla al grabar: la necesitas para tocar encima). Para que no pase, usa cascos o una '
      'interfaz.';

  /// En qué está la elegida (en la lista de canciones)
  String backingPhase(BackingPhase p, {required String bpm, double progress = 0}) => switch (p) {
    BackingPhase.noSong => 'Ninguna elegida.',
    BackingPhase.needsSetup => 'Sin preparar: marca su tempo y dónde cae el 1.',
    BackingPhase.preparing =>
      'Preparándola a $bpm BPM… ${progress > 0 ? percent(progress) : ''}'.trim(),
    BackingPhase.ready => 'Lista a $bpm BPM.',
    BackingPhase.tooFar => 'A $bpm BPM está demasiado lejos de su tempo: va de la mitad al doble.',
    BackingPhase.failed => 'No se ha podido preparar.',
  };

  // Lista de canciones
  String get songsTitle => 'Canciones';
  String get songsHow => 'Cómo funciona';
  String get songsImport => 'Importar audio';
  String get songsEmpty => 'Aún no hay ninguna';
  String get songsEmptyLine => 'Importa un audio tuyo (WAV, MP3 o FLAC) para tocar encima.';
  String get songsHelp =>
      'Loopin estira la canción al tempo del metrónomo sin cambiar el tono, así puedes '
      'tocarla más despacio para practicar. Para que cuadre con los loops necesita su tempo y '
      'dónde cae un 1: se marcan una vez, al prepararla.\n'
      'Al elegirla, el metrónomo se pone a su tempo y su compás (si no hay loops; elegirla otra '
      'vez vuelve a su tempo). Con loops grabados se estira al tempo del loop.\n'
      'Entra siempre en un 1 (con cuenta de entrada, al empezar a grabar) y, al acabar, vuelve '
      'a empezar. Suena en mono y puede durar hasta 10 minutos (también estirada).';
  String get songsCurrent => 'Elegida';
  String songRestoreTempo(String bpm) => 'Volver a su tempo ($bpm BPM)';
  String get songsNone => 'Sin canción';
  String songSubtitle(String bpm, String meter, double seconds) =>
      '$bpm BPM · $meter${seconds > 0 ? ' · ${duration(seconds)}' : ''}';
  String get songNotReady => 'Sin preparar: tócala para marcar su tempo y el 1';
  String get songPrepare => 'Preparar (tempo y 1)';
  String get songDelete => 'Borrar';
  String get songOptions => 'Opciones de la canción';
  String songDeleteTitle(String name) => '¿Borrar «$name»?';
  String get songDeleteBody => 'Se borra la copia de Loopin. El archivo original no se toca.';
  String get importing => 'Copiando el audio…';
  String importError(ImportError e) => switch (e) {
    ImportError.tooBig => 'El archivo es demasiado grande.',
    ImportError.copy => 'No se ha podido copiar el archivo.',
    ImportError.noStorage => 'No hay dónde guardar el archivo.',
  };
  String songError(SongError e) => switch (e) {
    SongError.none => '',
    SongError.open => 'No se puede abrir: tiene que ser WAV, MP3 o FLAC.',
    SongError.tooLong => 'Dura demasiado: hasta 10 minutos (también estirada).',
    SongError.memory => 'No hay memoria para abrirla.',
    SongError.empty => 'No suena nada.',
    SongError.tempo => 'Demasiado lejos de su tempo: va de la mitad al doble.',
  };

  // Preparar una canción
  String get editorTitle => 'Preparar canción';
  String editorOpening(double p) => 'Abriendo… ${p > 0 ? percent(p) : ''}'.trim();
  String get editorName => 'Nombre';
  String get editorPlay => 'Escuchar';
  String get editorPause => 'Parar';
  String get editorFromMark => 'Desde un compás antes del 1';
  String get editorClick => 'CLIC';
  String get editorClickTip => 'Clic en su tempo, desde el 1';
  String get editorWaveTip => 'Toca para escuchar desde ahí';
  String get editorMarkOne => 'MARCAR EL 1';
  String get editorMarkLine => 'Mientras suena, justo en el primer tiempo de un compás.';
  String get editorMarkHelp =>
      'Toca el botón cuando oigas un 1 (el primer tiempo de un compás; vale cualquiera, no '
      'hace falta el primero). Loopin lo pone en el golpe más claro de ahí cerca. Luego '
      'afínalo en la vista de cerca (arrastra) o con los botones, y compruébalo con el clic '
      'encendido: el clic fuerte tiene que caer en los unos.';
  String get editorZoom => 'El 1, de cerca (arrastra para moverlo)';
  String editorNudge(int ms) => 'Mover el 1 ${ms > 0 ? '+' : ''}$ms ms';
  String get editorTempo => 'Tempo';
  String editorBpm(String bpm) => '$bpm BPM';
  String get editorTap => 'TAP';
  String get editorTapTip => 'Toca al ritmo de la canción';
  String editorGuess(String bpm) => 'Sugerido: $bpm';
  String get editorTempoMinus => 'Bajar 0,1 BPM';
  String get editorTempoPlus => 'Subir 0,1 BPM';
  String get editorTempoHelp =>
      'Escríbelo, márcalo con TAP mientras suena o, lo más exacto, marca otro 1 más '
      'adelante: Loopin cuenta los compases que hay entre los dos y saca el tempo con '
      'decimales. Con el clic encendido, escúchala cerca del final: si el clic se va '
      'adelantando o retrasando, el tempo aún no es exacto.\n'
      'Si la canción no lleva un tempo fijo (grabada sin metrónomo), no cuadrará del todo.';
  String get editorBpmDialog => 'Tempo de la canción';
  String get editorMeter => 'Compás';
  String get editorSecond => 'MARCAR OTRO 1 MÁS ADELANTE';
  String get editorSecondLine => 'Para sacar el tempo exacto (cuanto más lejos, mejor).';
  String editorBarsBetween(int bars) => 'Entre los dos unos: ${this.bars(bars)}';
  String get editorFewerBars => 'Un compás menos';
  String get editorMoreBars => 'Un compás más';
  String get editorClearSecond => 'Quitar el otro 1';
  String get editorSave => 'GUARDAR Y USAR';

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

  // Parar en el 1 o con fundido
  String get stoppingAtOne => 'PARA EN EL 1';
  String get fadingOut => 'BAJANDO…';
  String get tapToStopNow => 'Toca para parar ya';

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

  String get playModeTitle => 'Modo';
  String playModeName(PlayMode m) => switch (m) {
    PlayMode.simple => 'Simple',
    PlayMode.advanced => 'Avanzado',
  };
  String playModeLine(PlayMode m) => switch (m) {
    PlayMode.simple => 'Lo justo para grabar, tocar y practicar',
    PlayMode.advanced => 'Todos los controles',
  };
  String get playModeHelp =>
      'Simple: el pulsador más grande, 3 compases (4/4, 3/4 y 6/8), grabar sincronizado o '
      'manual, empezar al tocar, el clic (siempre, hasta grabar o apagado), el '
      'entrenador de tempo, el afinador y cómo parar. Avanzado: además, la batería y tus '
      'canciones, el modo libre, todos los compases, el clic solo en la cuenta, REV y ½ '
      'en las pistas, los modos del micrófono, qué suena al grabar con el altavoz y la '
      'latencia a mano. Al volver al avanzado recupera lo que tenías.';
  String get playModeBusy => 'Acaba de grabar para cambiarlo';

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

  String get stopModeTitle => 'Al parar';
  String get stopModeLine => 'El botón de parar y el doble toque';
  String get stopModeHelp =>
      'Al momento: se corta todo en cuanto pulsas. En el 1: sigue sonando hasta el final '
      'del compás y para justo en el siguiente 1, para acabar a tiempo. Fundido: todo baja '
      'poco a poco durante 4 segundos y luego para. Mientras espera o baja, pulsar otra vez '
      '(o tocar el pulsador) para ya. Si estás grabando una pista nueva, para siempre al '
      'momento; un overdub se cierra al pedir parar.';
  String stopModeName(StopMode m) => switch (m) {
    StopMode.now => 'Al momento',
    StopMode.bar => 'En el 1',
    StopMode.fade => 'Fundido',
  };

  String get quantizeTitle => 'Cambios de pista en el 1';
  String get quantizeLine => 'Silenciar, REV y ½ esperan al siguiente 1';
  String get quantizeLineSimple => 'Silenciar una pista espera al siguiente 1';
  String get quantizeHelp =>
      'Encendido, cuando silencias una pista (o le pones o quitas el reverse o la media '
      'velocidad), el cambio espera al siguiente 1: así entra y sale a tiempo aunque '
      'pulses un poco antes. Mientras espera, el botón lleva un punto. Apagado, cambia en '
      'cuanto pulsas.';

  String get recordDuckTitle => 'Al grabar con el altavoz';
  String get recordDuckLine => 'Lo que ya suena, mientras grabas';
  String get recordDuckHelp =>
      'Con el altavoz y el micrófono del móvil, el micrófono recoge lo que suena y lo graba '
      'otra vez en la pista nueva (o en el overdub): se duplica y se acumula. Mientras '
      'grabas, lo que ya suena puede seguir normal, sonar más bajo o callarse; vuelve al '
      'acabar de grabar. El tempo lo sigues viendo en las luces y en el pulsador. Con '
      'cascos o una interfaz suena siempre normal. El clic en «siempre» también se graba: '
      'mejor «solo la cuenta». La batería no se calla (hace falta para tocar a tempo), así '
      'que también se graba.';
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
  String get moreInAdvanced =>
      'Modos del micrófono, latencia a mano y detalles técnicos: en el modo avanzado '
      '(Ajustes › Modo).';
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

  String get reportTitle => 'Loopin · Etapa 5';
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
  String drums(String style, bool on, bool playing, int volume, int loaded) =>
      'Batería: $style · ${on ? (playing ? 'sonando' : 'encendida') : 'apagada'} · '
      'volumen $volume % · sonidos cargados: $loaded de ${DrumSound.values.length}';
  String song(String? name, String phase, bool on, bool playing, int volume, int count) =>
      'Canción: ${name ?? 'ninguna'} · $phase · '
      '${on ? (playing ? 'sonando' : 'encendida') : 'apagada'} · volumen $volume % · '
      'en la lista: $count';
  String recordDuck(String setting, bool speaker) =>
      'Al grabar con el altavoz: $setting${speaker ? ' (ruta con altavoz: se aplica)' : ' (ahora no se aplica)'}';
  String playMode(String mode) => 'Modo de la app: $mode';
  String looper(String state, String mode, int? baseBars, String autoAdvance) =>
      'Looper: $state · $mode'
      '${baseBars != null ? ' · base de ${tr.bars(baseBars)}' : ''}'
      ' · avance automático: $autoAdvance';
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
      '${bars != null ? ' · ${tr.bars(bars)} · ${tr.layers(layers)}' : ''}'
      '${muted ? ' · en silencio' : ''}'
      '${reverse ? ' · al revés' : ''}'
      '${half ? ' · a media velocidad' : ''}';
  String live(String stop, bool quantize, String? trainer, double a4) =>
      'Al parar: $stop · cambios de pista en el 1: ${quantize ? 'sí' : 'no'} · '
      'entrenador: ${trainer ?? 'apagado'} · afinador: La = ${a4.round()} Hz';
  String trainerSetting(int step, int bars, int top) => '+$step BPM cada $bars C hasta $top';
  String controls(String volume, String headset, String learned) =>
      'Controles externos: volumen $volume · cascos $headset · teclas aprendidas: $learned';
}
