// Loopin — cabecera del looper: nombre, aviso de latencia, afinador y ajustes
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../../engine/engine_controller.dart';
import '../../l10n/strings.dart';
import '../theme.dart';
import 'view.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.view});

  final LooperView view;

  @override
  Widget build(BuildContext context) {
    final p = view.palette;
    final latency = LatencyChip.shown(view);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          // El nombre lleva a las sesiones: debajo, la que está abierta
          Expanded(
            flex: 5,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: tr.sessionsOpenSemantics(view.controller.sessionName),
                excludeSemantics: true,
                child: InkWell(
                  key: const ValueKey('open-sessions'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: view.onSessions,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Si no cabe (letra grande), se encoge en vez de partirse
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            tr.appName.toUpperCase(),
                            maxLines: 1,
                            style: p.label(size: 18, spacing: 5),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                view.controller.sessionName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: p.label(size: 11, color: p.dim, spacing: 0.4),
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, size: 16, color: p.dim),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Solo si falta medirla (medida, la cifra está en «Audio y
          // latencia»); se encoge (con «…») si no cabe
          if (latency) ...[
            const SizedBox(width: 6),
            Flexible(
              flex: 6,
              child: Align(
                alignment: Alignment.centerRight,
                child: LatencyChip(view: view),
              ),
            ),
          ],
          IconButton(
            key: const ValueKey('open-tuner'),
            tooltip: tr.tunerOpen,
            icon: CustomPaint(size: const Size(24, 24), painter: TuningForkPainter(p.ink)),
            onPressed: view.onTuner,
          ),
          IconButton(
            tooltip: tr.settings,
            icon: Icon(Icons.tune, color: p.ink),
            onPressed: view.onSettings,
          ),
        ],
      ),
    );
  }
}

/// Aviso de que la latencia de esta entrada y salida está sin medir; lleva a
/// medirla. Medida, no se ve (la cifra está en «Audio y latencia»).
class LatencyChip extends StatelessWidget {
  const LatencyChip({super.key, required this.view});

  final LooperView view;

  static bool shown(LooperView view) =>
      view.s.running && view.controller.latencySource != LatencySource.measured;

  @override
  Widget build(BuildContext context) {
    final p = view.palette;
    if (!shown(view)) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: tr.latencyChipUnmeasuredSemantics,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('latency-chip'),
        borderRadius: BorderRadius.circular(20),
        onTap: view.onLatency,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: LoopinPalette.well,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: LoopinPalette.dub),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: LoopinPalette.dub),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  tr.latencyChipUnmeasured,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: p.label(size: 12, color: LoopinPalette.dub),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icono del afinador: un diapasón.
class TuningForkPainter extends CustomPainter {
  TuningForkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round;
    // Las dos púas y la curva de abajo
    final fork = Path()
      ..moveTo(w * 0.32, h * 0.1)
      ..lineTo(w * 0.32, h * 0.5)
      ..arcToPoint(Offset(w * 0.68, h * 0.5), radius: Radius.circular(w * 0.18), clockwise: false)
      ..lineTo(w * 0.68, h * 0.1);
    canvas.drawPath(fork, paint);
    // El mango
    canvas.drawLine(Offset(w * 0.5, h * 0.68), Offset(w * 0.5, h * 0.92), paint);
  }

  @override
  bool shouldRepaint(TuningForkPainter old) => old.color != color;
}
