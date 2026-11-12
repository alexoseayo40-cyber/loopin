// Loopin — cabecera del looper: nombre, latencia y ajustes
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
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Text(tr.appName.toUpperCase(), style: p.label(size: 20, spacing: 5)),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: LatencyChip(view: view),
            ),
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

/// De un vistazo: si la latencia de esta entrada y salida está medida.
class LatencyChip extends StatelessWidget {
  const LatencyChip({super.key, required this.view});

  final LooperView view;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final p = view.palette;
    if (!view.s.running) return const SizedBox.shrink();
    final measured = c.latencySource == LatencySource.measured;
    final ms = c.compensationMs.round();
    return Semantics(
      button: true,
      label: measured ? tr.latencyChipSemantics(ms) : tr.latencyChipUnmeasuredSemantics,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: view.onLatency,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: measured ? null : LoopinPalette.well,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: measured ? p.edge : LoopinPalette.dub),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                measured ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                size: 16,
                color: measured ? p.dim : LoopinPalette.dub,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  measured ? tr.latencyChip(ms) : tr.latencyChipUnmeasured,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: p.label(size: 12, color: measured ? p.dim : LoopinPalette.dub),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
