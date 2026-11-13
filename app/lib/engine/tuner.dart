// Loopin — afinador: de la frecuencia a la nota, con un filtro para que la
// aguja no baile (el análisis lo hace el motor: ver Tuner.cpp)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'package:loopin_engine/loopin_engine.dart';

/// Cuerdas al aire de la afinación estándar (números MIDI): Mi La Re Sol Si Mi.
const List<int> kStandardStrings = [40, 45, 50, 55, 59, 64];

/// Una nota y lo que se desvía.
class TunerNote {
  const TunerNote({required this.midi, required this.cents, required this.frequency});

  /// Número MIDI (69 = La 440).
  final int midi;

  /// De −50 a +50: negativo, baja; positivo, alta.
  final double cents;
  final double frequency;

  /// 0 = Do … 11 = Si.
  int get pitchClass => midi % 12;

  /// Octava científica (La 440 = La4; la 6.ª cuerda, Mi2).
  int get octave => midi ~/ 12 - 1;

  /// Dentro de ±[kInTuneCents].
  bool get inTune => cents.abs() <= kInTuneCents;

  /// La cuerda al aire de la afinación estándar que es (o null).
  int? get standardString {
    final i = kStandardStrings.indexOf(midi);
    return i < 0 ? null : i;
  }
}

/// Margen para dar una nota por afinada (cents).
const double kInTuneCents = 3;

/// La nota más cercana a [frequency] con el La de referencia [a4].
TunerNote? noteFor(double frequency, {double a4 = 440}) {
  if (frequency <= 0 || a4 <= 0) return null;
  final m = 69 + 12 * math.log(frequency / a4) / math.ln2;
  final midi = m.round();
  return TunerNote(midi: midi, cents: (m - midi) * 100, frequency: frequency);
}

/// Lo que enseña la pantalla.
class TunerDisplay {
  const TunerDisplay({this.note, this.live = false, this.levelDb = -120});

  /// La nota (la última que se oyó, durante un momento, aunque ya no suene).
  final TunerNote? note;

  /// Se está oyendo ahora (si no, la pantalla la enseña apagada).
  final bool live;

  /// Nivel de la entrada (dBFS).
  final double levelDb;

  bool get hasNote => note != null;
}

/// Suaviza lo que llega del motor (30 veces por segundo): quita lecturas
/// sueltas (la mediana de las 3 últimas), no cambia de nota por una sola
/// lectura, suaviza los cents y mantiene la última nota 1,5 s cuando deja de
/// sonar.
class TunerFilter {
  TunerFilter({this.a4 = 440});

  double a4;

  /// Claridad mínima para fiarse de una lectura.
  static const double minClarity = 0.85;

  /// Tiempo que se mantiene la última nota cuando ya no suena.
  static const Duration hold = Duration(milliseconds: 1500);

  final List<double> _recent = [];
  TunerNote? _note;
  double _cents = 0;
  int? _candidate;
  Duration _lastHeard = Duration.zero;

  TunerDisplay update(TunerReading? r, Duration now) {
    final level = r?.levelDb ?? -120;
    final good = r != null && r.frequency > 0 && r.clarity >= minClarity;
    if (!good) {
      _recent.clear();
      _candidate = null;
      final held = _note != null && now - _lastHeard < hold;
      if (!held) _note = null;
      return TunerDisplay(note: held ? _shown : null, levelDb: level);
    }
    _recent.add(r.frequency);
    if (_recent.length > 3) _recent.removeAt(0);
    final sorted = [..._recent]..sort();
    final freq = sorted[sorted.length ~/ 2];
    final n = noteFor(freq, a4: a4)!;
    _lastHeard = now;
    final current = _note;
    if (current == null || n.midi == current.midi) {
      // Misma nota: los cents se suavizan
      _cents = current == null ? n.cents : _cents + (n.cents - _cents) * 0.35;
      _note = n;
      _candidate = null;
    } else if (_candidate == n.midi) {
      // Otra nota por segunda vez seguida: se cambia
      _note = n;
      _cents = n.cents;
      _candidate = null;
    } else {
      _candidate = n.midi;
    }
    return TunerDisplay(note: _shown, live: true, levelDb: level);
  }

  TunerNote? get _shown {
    final n = _note;
    return n == null ? null : TunerNote(midi: n.midi, cents: _cents, frequency: n.frequency);
  }

  void reset() {
    _recent.clear();
    _note = null;
    _candidate = null;
  }
}
