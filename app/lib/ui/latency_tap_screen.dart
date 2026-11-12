// Loopin — medir la latencia tocando al clic (para cascos)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../engine/engine_controller.dart';

class LatencyTapScreen extends StatefulWidget {
  const LatencyTapScreen({super.key, required this.controller});

  final EngineController controller;

  @override
  State<LatencyTapScreen> createState() => _LatencyTapScreenState();
}

class _LatencyTapScreenState extends State<LatencyTapScreen> with SingleTickerProviderStateMixin {
  // Destello en cada clic
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  int _lastClicks = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  void _onChange() {
    final clicks = widget.controller.status.tapClicks;
    final running = widget.controller.status.tapState == LatencyState.running;
    if (running && clicks > _lastClicks) _flash.forward(from: 0);
    _lastClicks = running ? clicks : 0;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    // Si se sale a medias, se para
    if (widget.controller.status.tapState == LatencyState.running) {
      widget.controller.cancelTapCalibration();
    }
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Medir tocando')),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final s = c.status;
          final running = s.tapState == LatencyState.running;
          final ms = s.sampleRate > 0 ? 1000 / s.sampleRate : 0.0;
          final countIn = EngineStatus.tapCountInClicks;
          // Clic que acaba de sonar (1..16)
          final click = s.tapClicks;
          final counting = running && click > countIn;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Para cuando usas cascos y el clic no puede volver solo al micrófono.',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '1. Ponte los cascos y coge la guitarra.\n'
                    '2. Sonarán 16 clics. Escucha los 4 primeros y, con los 12 siguientes, '
                    'da un golpe seco en cada clic: un rasgueo con las cuerdas apagadas con la '
                    'otra mano, o un golpe en la caja.\n'
                    '3. Toca como lo harías con un metrónomo: no hace falta ser perfecto.',
                  ),
                  const SizedBox(height: 24),
                  // El clic que suena, también a la vista
                  Center(
                    child: AnimatedBuilder(
                      animation: _flash,
                      builder: (context, _) {
                        final v = running ? 1 - _flash.value : 0.0;
                        final base = counting
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline;
                        return Container(
                          width: 140,
                          height: 140,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color.lerp(theme.colorScheme.surfaceContainerHighest, base, v),
                          ),
                          child: Text(
                            running
                                ? (click <= countIn ? 'Escucha\n$click' : '${click - countIn} / 12')
                                : '',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (running)
                    Text(
                      counting ? 'Golpes que cuentan: ${s.tapHits}' : 'Prepárate…',
                      textAlign: TextAlign.center,
                    ),
                  if (s.tapState == LatencyState.done) ...[
                    Text(
                      'Latencia: ${(s.tapFrames * ms).round()} ms · guardada',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(_quality(s.tapSpread * ms, s.tapHits), textAlign: TextAlign.center),
                  ],
                  if (s.tapState == LatencyState.failed)
                    Text(
                      'No se oyeron bastantes golpes (hacen falta 6 de 12). Sube la ganancia de '
                      'entrada o golpea más fuerte, y repite.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: !s.running || c.recordingNow
                        ? null
                        : (running ? c.cancelTapCalibration : c.startTapCalibration),
                    icon: Icon(running ? Icons.stop : Icons.play_arrow),
                    label: Text(
                      running ? 'Parar' : (s.tapState == LatencyState.idle ? 'Empezar' : 'Repetir'),
                    ),
                  ),
                  if (c.recordingNow)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Termina de grabar antes de medir.', textAlign: TextAlign.center),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Lo que se mide es lo que tarda tu golpe en llegar respecto al clic que oyes: '
                    'la latencia del móvil más tu forma de tocar. Por eso, con esta medida, lo '
                    'que grabes cae justo en el tiempo.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _quality(double spreadMs, int hits) {
    final spread = spreadMs.round();
    if (spread <= 10) {
      return 'Muy regular (±$spread ms, $hits golpes). Buena medida.';
    }
    if (spread <= 25) {
      return 'Regular (±$spread ms, $hits golpes). Vale; si quieres afinar, repite.';
    }
    return 'Bastante irregular (±$spread ms). Repite con golpes más secos.';
  }
}
