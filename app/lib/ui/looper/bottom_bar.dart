// Loopin — barra de abajo: deshacer, parar, borrar todo, nivel y escucharme
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../../l10n/strings.dart';
import '../theme.dart';
import 'chassis_button.dart';
import 'view.dart';

class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.view, required this.showHint});

  final LooperView view;
  final bool showHint;

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.clearAllTitle),
        content: Text(tr.clearAllBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr.clearAllConfirm),
          ),
        ],
      ),
    );
    if (ok == true) view.controller.clearLoop();
  }

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final s = view.s;
    final p = view.palette;
    final on = s.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHint)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              tr.gestures,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: p.dim),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: ChassisButton(
                palette: p,
                icon: Icons.undo,
                label: tr.undo,
                onPressed: on && s.loopCanUndo ? c.undo : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChassisButton(
                palette: p,
                icon: s.playing ? Icons.stop : Icons.play_arrow,
                label: s.playing ? tr.stop : tr.start,
                onPressed: on ? c.toggleTransport : null,
              ),
            ),
            const SizedBox(width: 8),
            ChassisButton(
              palette: p,
              icon: Icons.delete_sweep_outlined,
              tooltip: tr.clearAll,
              onPressed: on && s.loopState != LoopState.empty ? () => _confirmClear(context) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.mic_none, size: 18, color: p.dim),
            const SizedBox(width: 8),
            Expanded(child: _InputLevel(view: view)),
            const SizedBox(width: 10),
            ChassisButton(
              palette: p,
              icon: c.monitorEnabled ? Icons.headphones : Icons.headset_off_outlined,
              label: tr.monitor,
              selected: c.monitorEnabled,
              isToggle: true,
              dense: true,
              onPressed: () => c.setMonitorEnabled(!c.monitorEnabled),
            ),
          ],
        ),
      ],
    );
  }
}

/// Nivel de entrada: cambia a cada momento, así que se redibuja solo.
class _InputLevel extends StatelessWidget {
  const _InputLevel({required this.view});

  final LooperView view;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: view.controller.live,
      builder: (context, _) {
        final peak = view.s.inputPeak.clamp(0.0, 1.0);
        return Semantics(
          label: tr.inputLevel,
          value: tr.percent(peak),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: peak,
              minHeight: 8,
              backgroundColor: LoopinPalette.groove,
              color: peak > 0.9
                  ? LoopinPalette.rec
                  : (peak > 0.6 ? LoopinPalette.dub : LoopinPalette.play),
            ),
          ),
        );
      },
    );
  }
}
