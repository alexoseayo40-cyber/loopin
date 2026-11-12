// Loopin — latencia guardada por ruta (entrada, salida y modo del micro)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';

import 'prefs.dart';

/// De dónde sale la compensación de latencia que se está usando.
enum LatencySource {
  /// Medida (con el altavoz o tocando) o ajustada a mano para esta ruta.
  measured,

  /// Sin medir: estimación de Android (puede fallar bastante).
  estimated,

  /// Sin medir y sin estimación.
  none,
}

/// La latencia de ida y vuelta depende de por dónde entra y sale el sonido
/// (altavoz + micro, cascos USB + micro, interfaz…). Se guarda una medida por
/// cada combinación y se aplica sola al cambiar de ruta.
class LatencyRoutes {
  LatencyRoutes({required this.apply, this.prefs = const Prefs()});

  /// Pide al motor una compensación (muestras).
  final void Function(int frames) apply;
  final Prefs prefs;

  /// Medidas guardadas: clave de ruta → muestras (a la frecuencia de la ruta).
  Map<String, int> _saved = {};

  /// Ruta en uso (null = aún sin elegir).
  String? key;
  LatencySource source = LatencySource.none;

  /// Compensación pedida al motor (-1 = ninguna aún).
  int applied = -1;

  /// El audio se ha reabierto: se vuelve a elegir en cuanto se sepa la ruta.
  void reset() {
    key = null;
    applied = -1;
  }

  void _use(int frames, LatencySource from) {
    source = from;
    if (frames != applied) {
      applied = frames;
      apply(frames);
    }
  }

  /// Elige la compensación de la ruta [routeKey]: la guardada o, si no hay,
  /// la estimación de Android ([estimateFrames], ≤ 0 si no la hay).
  void update(String routeKey, {required int estimateFrames}) {
    // Con la misma ruta solo se vuelve a mirar si aún no había ningún valor
    // (la estimación de Android tarda un poco en estar disponible).
    if (routeKey == key && source != LatencySource.none) return;
    if (routeKey != key) applied = -1;
    key = routeKey;
    final saved = _saved[routeKey];
    if (saved != null) {
      _use(saved, LatencySource.measured);
    } else if (estimateFrames > 0) {
      _use(estimateFrames, LatencySource.estimated);
    } else {
      _use(0, LatencySource.none);
    }
  }

  /// Una medida nueva para la ruta en uso (o [fallbackKey]).
  void saveMeasured(String fallbackKey, int frames) {
    final k = key ?? fallbackKey;
    _saved[k] = frames;
    _use(frames, LatencySource.measured);
    _store();
  }

  /// Ajuste a mano: se guarda sin pedírselo al motor (lo hace quien llama,
  /// moviendo también lo grabado).
  void setManually(String fallbackKey, int frames) {
    final k = key ?? fallbackKey;
    key = k;
    _saved[k] = frames;
    source = LatencySource.measured;
    applied = frames;
    _store();
  }

  /// Olvida la medida de la ruta en uso (vuelve a la estimación).
  bool forget() {
    final k = key;
    if (k == null) return false;
    _saved.remove(k);
    key = null;
    _store();
    return true;
  }

  Future<void> load() async {
    try {
      final raw = await prefs.get(Prefs.latencies);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _saved = {for (final e in m.entries) e.key: (e.value as num).toInt()};
        key = null; // volver a elegir con lo cargado
      }
    } on Object {
      // ajustes ilegibles: se vuelve a medir
    }
  }

  void _store() => prefs.set(Prefs.latencies, jsonEncode(_saved));
}
