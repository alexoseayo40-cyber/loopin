// Loopin — modo simple y modo avanzado
// SPDX-License-Identifier: GPL-3.0-or-later
//
// El simple es para quien empieza con los loopers y para tocar sin mirar
// tanto: menos controles, sin batería ni canción, y la grabación siempre
// igual (1 compás de cuenta y se cierra al pulsar). No solo esconde: al pasar a simple, lo que no se ve
// vuelve a sus valores (para que no quede, por ejemplo, el modo libre puesto
// sin que se vea). Lo que se cambió se apunta y se devuelve al volver al
// avanzado, si mientras tanto no se ha tocado.
import 'package:loopin_engine/loopin_engine.dart';

enum PlayMode { simple, advanced }

/// Compases del modo simple (por su etiqueta).
const List<String> kSimpleMeters = ['4/4', '3/4', '6/8'];

/// El compás al que vuelve el simple si el de ahora no es suyo.
const String kSimpleMeter = '4/4';

/// Clic del modo simple: siempre o apagado (solo las luces).
const List<ClickMode> kSimpleClickModes = [ClickMode.always, ClickMode.silent];

/// Modo de grabación del simple: se cierra al pulsar, con 1 compás de cuenta.
const LoopMode kSimpleLoopMode = LoopMode.manual;

/// Lo que el modo simple cambió al entrar: el valor que tenía en el avanzado,
/// por clave. Se guarda como texto: «loopMode=sync;meter=7/8».
class SimpleForced {
  SimpleForced([Map<String, String>? values]) : values = values ?? {};

  final Map<String, String> values;

  static const loopMode = 'loopMode';
  static const startOnSound = 'startOnSound';
  static const meter = 'meter';
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
