// Loopin — entrenador de tempo: el botón junto al ▶ y su hoja de ajustes
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../../engine/engine_controller.dart';
import '../../l10n/strings.dart';
import '../help.dart';
import '../theme.dart';
import 'view.dart';

/// Botón del entrenador (solo en avanzado), junto a arrancar/parar. Se ve
/// encendido si el entrenador lo está; con loops, apagado (el tempo es suyo).
class TrainerButton extends StatelessWidget {
  const TrainerButton({super.key, required this.view});

  final LooperView view;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final on = c.trainerOn;
    final enabled = c.trainerAvailable;
    final color = enabled ? LoopinPalette.display : LoopinPalette.displayDim;
    return Semantics(
      button: true,
      toggled: on,
      label: tr.trainerTooltip(on),
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('trainer-button'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => showTrainerSheet(context, c),
        child: Container(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: on && enabled ? 1 : 0.5)),
            color: on && enabled ? LoopinPalette.display.withValues(alpha: 0.15) : null,
          ),
          child: Icon(Icons.trending_up, color: color, size: 22),
        ),
      ),
    );
  }
}

/// Hoja con el entrenador: encendido, cuánto sube, cada cuántos compases y
/// hasta dónde.
Future<void> showTrainerSheet(BuildContext context, EngineController c) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: c,
      builder: (context, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TrainerPanel(controller: c),
        ),
      ),
    ),
  );
}

class _TrainerPanel extends StatelessWidget {
  const _TrainerPanel({required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final can = c.trainerAvailable;
    final from = c.bpm.round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OptionTile.toggle(
          key: const ValueKey('trainer-switch'),
          leading: const Icon(Icons.trending_up),
          title: tr.trainer,
          subtitle: can ? tr.trainerLine : tr.trainerNeedsNoLoops,
          help: tr.trainerHelp,
          value: c.trainerOn,
          onChanged: can || c.trainerOn ? c.setTrainerOn : null,
        ),
        _Stepper(
          label: tr.trainerStep,
          value: '+${tr.trainerBpm(c.trainerStep)}',
          onDown: c.trainerStep > 1 ? () => c.setTrainerStep(c.trainerStep - 1) : null,
          onUp: c.trainerStep < 20 ? () => c.setTrainerStep(c.trainerStep + 1) : null,
          keyName: 'trainer-step',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              SizedBox(width: 64, child: Text(tr.trainerEvery, style: theme.textTheme.bodyLarge)),
              Expanded(
                child: SegmentedButton<int>(
                  key: const ValueKey('trainer-bars'),
                  segments: [
                    for (final b in kTrainerBarOptions)
                      ButtonSegment(value: b, label: Text(tr.trainerBarsShort(b))),
                  ],
                  showSelectedIcon: false,
                  selected: {c.trainerBars},
                  onSelectionChanged: (v) => c.setTrainerBars(v.first),
                ),
              ),
            ],
          ),
        ),
        _Stepper(
          label: tr.trainerTop,
          value: tr.trainerBpm(c.trainerTop),
          onDown: c.trainerTop > from + 1 ? () => c.setTrainerTop(c.trainerTop - 5) : null,
          onUp: c.trainerTop < 240 ? () => c.setTrainerTop(c.trainerTop + 5) : null,
          keyName: 'trainer-top',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            tr.trainerSummary(
              from,
              c.trainerTop.round(),
              c.trainerStep.round(),
              c.trainerBars,
              c.trainerSteps,
            ),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onDown,
    required this.onUp,
    required this.keyName,
  });

  final String label;
  final String value;
  final VoidCallback? onDown;
  final VoidCallback? onUp;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: theme.textTheme.bodyLarge)),
          IconButton(
            key: ValueKey('$keyName-down'),
            tooltip: tr.trainerDecrease,
            onPressed: onDown,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: LoopinFonts.display, fontSize: 22),
            ),
          ),
          IconButton(
            key: ValueKey('$keyName-up'),
            tooltip: tr.trainerIncrease,
            onPressed: onUp,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
