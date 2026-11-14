// Loopin — modo simple y modo avanzado
// SPDX-License-Identifier: GPL-3.0-or-later
//
// El simple es para quien empieza con los loopers y para tocar sin mirar
// tanto: menos controles y sin batería ni canción, pero con lo que hace más
// cómodo tocar y practicar (sincronizado, empezar al tocar, entrenador, cómo
// parar, afinador). Lo que es solo para avanzados (libre, 10 compases, REV y
// ½, micro, latencia a mano…) no está. No solo esconde: al pasar a simple, lo que no se ve
// vuelve a sus valores (para que no quede, por ejemplo, el modo libre puesto
// sin que se vea). Lo que se cambió se apunta y se devuelve al volver al
// avanzado, si mientras tanto no se ha tocado.
import 'package:loopin_engine/loopin_engine.dart';

enum PlayMode { simple, advanced }

/// Compases del modo simple (por su etiqueta).
const List<String> kSimpleMeters = ['4/4', '3/4', '6/8'];

/// El compás al que vuelve el simple si el de ahora no es suyo.
const String kSimpleMeter = '4/4';

/// Los modos del clic de la app (los dos modos), en el orden en que pasa con
/// cada toque: siempre, hasta grabar y apagado (solo las luces). El motor
/// también sabe «solo la cuenta», pero desde la 1.0 la app ya no lo usa:
/// «hasta grabar» hace casi lo mismo.
const List<ClickMode> kClickModes = [ClickMode.always, ClickMode.untilRecording, ClickMode.silent];

/// A qué pasa un modo del clic que la app ya no tiene («solo la cuenta»).
ClickMode clickModeOf(ClickMode m) => kClickModes.contains(m) ? m : ClickMode.untilRecording;

/// Modos de grabación del simple (sin el libre).
const List<LoopMode> kSimpleLoopModes = [LoopMode.sync, LoopMode.manual];

/// Al que pasa el simple si estaba en libre.
const LoopMode kSimpleLoopMode = LoopMode.manual;

/// Lo que el modo simple cambió al entrar: el valor que tenía en el avanzado,
/// por clave. Se guarda como texto: «loopMode=sync;meter=7/8».
class SimpleForced {
  SimpleForced([Map<String, String>? values]) : values = values ?? {};

  final Map<String, String> values;

  static const loopMode = 'loopMode';
  static const startOnSound = 'startOnSound';
  static const meter = 'meter';

  /// (de versiones de antes: el clic ya es igual en los dos modos)
  static const clickMode = 'clickMode';
  static const drumsOn = 'drumsOn';
  static const backingOn = 'backingOn';
  static const recordDuck = 'recordDuck';

  bool get isEmpty => values.isEmpty;

  /// Apunta el valor del avanzado (si ya estaba apuntado, se queda el primero).
  void remember(String key, String value) => values.putIfAbsent(key, () => value);

  String? operator [](String key) => values[key];

  String encode() => [for (final e in values.entries) '${e.key}=${e.value}'].join(';');

  static SimpleForced decode(String? text) {
    final out = SimpleForced();
    if (text == null || text.isEmpty) return out;
    for (final part in text.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) out.values[part.substring(0, i)] = part.substring(i + 1);
    }
    return out;
  }
}
