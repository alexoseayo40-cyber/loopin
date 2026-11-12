// Loopin — compases y el tiempo que suena
// SPDX-License-Identifier: GPL-3.0-or-later

/// Un compás: cómo se agrupan sus tiempos. En los de 8, el tiempo (y el BPM)
/// es la corchea.
class TimeSignature {
  const TimeSignature(this.label, this.groups);

  /// «7/8»
  final String label;

  /// Tiempos de cada grupo: [2, 2, 3] en 7/8. El primero de cada grupo lleva
  /// acento (el del compás, más fuerte).
  final List<int> groups;

  int get beats => groups.fold(0, (a, b) => a + b);

  /// Bit k = el tiempo k empieza un grupo (acento medio). El 0 no cuenta.
  int get accentMask {
    var mask = 0, beat = 0;
    for (final g in groups) {
      if (beat > 0) mask |= 1 << beat;
      beat += g;
    }
    return mask;
  }

  /// El tiempo k empieza un grupo (incluido el 0).
  bool startsGroup(int beat) => beat == 0 || (accentMask >> beat) & 1 == 1;

  /// «2+2+3» (vacío si es un solo grupo)
  String get grouping => groups.length > 1 ? groups.join('+') : '';

  /// En los compases de 8 el pulso es la corchea.
  bool get eighths => label.endsWith('/8');
}

/// Compases disponibles.
const List<TimeSignature> kTimeSignatures = [
  TimeSignature('4/4', [4]),
  TimeSignature('3/4', [3]),
  TimeSignature('2/4', [2]),
  TimeSignature('5/4', [3, 2]),
  TimeSignature('7/4', [4, 3]),
  TimeSignature('6/8', [3, 3]),
  TimeSignature('9/8', [3, 3, 3]),
  TimeSignature('12/8', [3, 3, 3, 3]),
  TimeSignature('5/8', [3, 2]),
  TimeSignature('7/8', [2, 2, 3]),
];

/// El tiempo que se está oyendo y cuánto lleva (de 0 a 1).
typedef BeatNow = ({int beat, double phase});

/// Compases que se pueden grabar en modo sincronizado.
const List<int> kSyncBarOptions = [1, 2, 4, 8];
