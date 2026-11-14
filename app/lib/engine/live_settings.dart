// Loopin — ajustes de directo y práctica (Etapa 5)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:loopin_engine/loopin_engine.dart';

import 'prefs.dart';

/// Compases que se pueden elegir para el entrenador de tempo.
const List<int> kTrainerBarOptions = [1, 2, 4, 8];

/// Directo y práctica: lo que eligió el usuario (vale en los dos modos).
class LiveSettings {
  /// Silenciar, reverse y media velocidad esperan al siguiente 1.
  bool quantize = true;

  /// Los botones REV y ½ de cada pista se ven (avanzado). Apagado de serie:
  /// son efectos para jugar con el sonido, no para tocar (Alex, 14/11).
  bool trackFx = false;

  /// Cómo paran el botón de parar y el doble toque.
  StopMode stopMode = StopMode.now;

  /// Lo que dura el fundido al parar.
  static const double fadeSeconds = 4;

  /// Entrenador de tempo: encendido (no se guarda: cada práctica se enciende
  /// a propósito), cuánto sube, cada cuántos compases y hasta dónde.
  bool trainerOn = false;
  double trainerStep = 5;
  int trainerBars = 4;
  double trainerTop = 140;

  /// El La de referencia del afinador (Hz).
  double tunerA4 = 440;
  static const double minA4 = 430;
  static const double maxA4 = 450;

  Future<void> load(Prefs prefs) async {
    quantize = await prefs.getBool(Prefs.quantize) ?? quantize;
    trackFx = await prefs.getBool(Prefs.trackFx) ?? trackFx;
    final stop = await prefs.get(Prefs.stopMode);
    stopMode = StopMode.values.firstWhere((m) => m.name == stop, orElse: () => stopMode);
    final step = double.tryParse(await prefs.get(Prefs.trainerStep) ?? '');
    if (step != null) trainerStep = step.clamp(1, 20);
    final bars = int.tryParse(await prefs.get(Prefs.trainerBars) ?? '');
    if (bars != null && kTrainerBarOptions.contains(bars)) trainerBars = bars;
    final top = double.tryParse(await prefs.get(Prefs.trainerTop) ?? '');
    if (top != null) trainerTop = top.clamp(41, 240);
    final a4 = double.tryParse(await prefs.get(Prefs.tunerA4) ?? '');
    if (a4 != null) tunerA4 = a4.clamp(minA4, maxA4);
  }
}
