// Loopin — fila de acompañamiento: la batería o la canción, con un selector
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../pedal_widgets.dart';
import '../theme.dart';
import 'drum_row.dart';
import 'song_controls.dart';
import 'view.dart';

/// Entre los controles de la pista y el pulsador. A la izquierda, un
/// selector de dos posiciones (batería y canción), cada una con su luz: así se
/// ve si suenan aunque se esté enseñando la otra. A la derecha, los controles
/// de la elegida. Las dos pueden sonar a la vez.
class AccompanimentRow extends StatelessWidget {
  const AccompanimentRow({super.key, required this.view, this.dense = false});

  final LooperView view;

  /// En pantallas bajas: más estrecha.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = view.palette;
    final song = view.controller.showSong;
    return Container(
      height: dense ? 40 : 46,
      padding: const EdgeInsets.only(left: 4, right: 4),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.edge),
      ),
      child: Row(
        children: [
          _SourceSelector(view: view, dense: dense),
          const SizedBox(width: 6),
          Expanded(
            child: song ? SongControls(view: view) : DrumControls(view: view),
          ),
        ],
      ),
    );
  }
}

class _SourceSelector extends StatelessWidget {
  const _SourceSelector({required this.view, required this.dense});

  final LooperView view;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    Widget option(String label, Color led, bool selected, VoidCallback onTap) {
      final p = view.palette;
      return Semantics(
        button: true,
        selected: selected,
        label: tr.accShow(label),
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: Container(
            height: dense ? 16 : 19,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: selected ? p.ink : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Led(color: led, size: dense ? 7 : 8),
                const SizedBox(width: 5),
                // Con letra grande se encoge en vez de salirse
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: p.label(
                        size: dense ? 10.5 : 11.5,
                        color: selected ? p.chassis : p.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 74,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          option(tr.accDrums, drumLed(view), !c.showSong, () => c.setShowSong(false)),
          const SizedBox(height: 2),
          option(tr.accSong, songLed(view), c.showSong, () => c.setShowSong(true)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas que comparten la batería y la canción

/// Ancho máximo del botón de estilo o canción, para que al volumen le queden
/// al menos 90 puntos (buttons: botones redondos que van a la derecha).
double chipRoom(double width, int buttons) => (width - 90 - 40.0 * buttons).clamp(56.0, 120.0);

/// Un botón con borde (estilo, canción…).
class RowChip extends StatelessWidget {
  const RowChip({
    super.key,
    required this.view,
    required this.label,
    this.trailing,
    this.arrow = false,
    this.maxWidth = 120,
  });

  final LooperView view;
  final String label;
  final String? trailing;
  final bool arrow;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final p = view.palette;
    return Container(
      constraints: BoxConstraints(minHeight: 32, minWidth: 48, maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.edge),
      ),
      // Del ancho de lo que lleva (hasta maxWidth), centrado
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: p.label(size: 13),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 5),
              Text(trailing!, style: p.label(size: 11, color: LoopinPalette.dub)),
            ],
            // Sin sitio para todo: el aviso (porcentaje…) antes que la flecha
            if (arrow && trailing == null) Icon(Icons.arrow_drop_down, size: 18, color: p.ink),
          ],
        ),
      ),
    );
  }
}

class RowSlider extends StatelessWidget {
  const RowSlider({
    super.key,
    required this.view,
    required this.max,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    required this.semantics,
  });

  final LooperView view;
  final double max;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final String Function(double) semantics;

  @override
  Widget build(BuildContext context) {
    final p = view.palette;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: p.ink,
        inactiveTrackColor: p.edge,
        thumbColor: p.ink,
        overlayColor: p.ink.withValues(alpha: 0.12),
        // Menos margen a los lados que el de serie: en la fila cada punto cuenta
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Slider(
        max: max,
        value: value.clamp(0.0, max),
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
        semanticFormatterCallback: semantics,
      ),
    );
  }
}

/// Encender o apagar. Encendido, como un botón del chasis pulsado.
class PowerButton extends StatelessWidget {
  const PowerButton({
    super.key,
    required this.view,
    required this.on,
    required this.tooltip,
    required this.onPressed,
  });

  final LooperView view;
  final bool on;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = view.palette;
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      isSelected: on,
      onPressed: view.s.running ? onPressed : null,
      icon: const Icon(Icons.power_settings_new, size: 22),
      style: IconButton.styleFrom(
        backgroundColor: on ? p.ink : null,
        foregroundColor: on ? p.chassis : p.ink,
        disabledForegroundColor: p.dim.withValues(alpha: 0.4),
      ),
    );
  }
}

/// Unos cascos en ámbar: con el altavoz, el micro graba lo que suena.
class BleedButton extends StatelessWidget {
  const BleedButton({super.key, required this.tooltip, required this.help});

  final String tooltip;
  final String help;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.headphones),
          title: Text(tooltip),
          content: Text(help),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr.ok))],
        ),
      ),
      icon: const Icon(Icons.headphones, size: 20),
      color: LoopinPalette.dub,
    );
  }
}
