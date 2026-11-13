// Loopin — fila de la batería: estilo, volumen y encendido
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../../engine/drums.dart';
import '../../l10n/strings.dart';
import '../pedal_widgets.dart';
import '../theme.dart';
import 'view.dart';

/// Entre los controles de la pista y el pulsador. La luz va verde cuando
/// suena, ámbar si está encendida pero espera al siguiente 1 (o todo está
/// parado) y apagada si no.
class DrumRow extends StatelessWidget {
  const DrumRow({super.key, required this.view, this.dense = false});

  final LooperView view;

  /// En pantallas bajas: más estrecha.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final p = view.palette;
    final on = c.drumsOn;
    final playing = on && view.s.drumsPlaying;
    final style = c.drumStyleNow;
    final led = !on ? LoopinPalette.ledOff : (playing ? LoopinPalette.play : LoopinPalette.dub);
    return Semantics(
      container: true,
      label: tr.drumsSemantics(tr.drumStyleName(style), on, playing),
      child: Container(
        height: dense ? 40 : 46,
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.edge),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            // En móviles estrechos no cabe la palabra «BATERÍA»
            final showLabel = box.maxWidth >= 330;
            return Row(
              children: [
                Led(color: led),
                const SizedBox(width: 8),
                if (showLabel) ...[
                  ExcludeSemantics(child: Text(tr.drums, style: p.label(size: 14))),
                  const SizedBox(width: 8),
                ],
                _StyleMenu(view: view, style: style),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: p.ink,
                      inactiveTrackColor: p.edge,
                      thumbColor: p.ink,
                      overlayColor: p.ink.withValues(alpha: 0.12),
                    ),
                    child: Slider(
                      max: 1.5,
                      value: c.drumVolume.clamp(0.0, 1.5),
                      onChanged: c.setDrumVolume,
                      onChangeEnd: (_) => c.saveDrumVolume(),
                      semanticFormatterCallback: tr.drumVolume,
                    ),
                  ),
                ),
                if (c.drumsBleed)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: tr.drumsBleed,
                    onPressed: () => _showBleed(context),
                    icon: const Icon(Icons.headphones, size: 20),
                    color: LoopinPalette.dub,
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: on ? tr.drumsTurnOff : tr.drumsTurnOn,
                  isSelected: on,
                  onPressed: view.s.running ? c.toggleDrums : null,
                  icon: const Icon(Icons.power_settings_new, size: 22),
                  // Encendida, como un botón del chasis pulsado
                  style: IconButton.styleFrom(
                    backgroundColor: on ? p.ink : null,
                    foregroundColor: on ? p.chassis : p.ink,
                    disabledForegroundColor: p.dim.withValues(alpha: 0.4),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showBleed(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.headphones),
        title: Text(tr.drumsBleed),
        content: Text(tr.drumsBleedHelp),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr.ok))],
      ),
    );
  }
}

/// El estilo: abre un menú con todos. Los de otro compás cambian el compás
/// (con un loop grabado no se puede y salen desactivados).
class _StyleMenu extends StatelessWidget {
  const _StyleMenu({required this.view, required this.style});

  final LooperView view;
  final DrumStyle style;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final p = view.palette;
    return PopupMenuButton<DrumStyle>(
      tooltip: tr.drumStyleMenu,
      initialValue: style,
      onSelected: c.setDrumStyle,
      itemBuilder: (_) => [
        for (final s in DrumStyle.values)
          PopupMenuItem(
            value: s,
            enabled: c.drumStyleAvailable(s),
            child: Text(tr.drumStyleItem(s, drumStyleMeter(s))),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 32, minWidth: 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.edge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr.drumStyleChip(style), style: p.label(size: 13)),
            Icon(Icons.arrow_drop_down, size: 18, color: p.ink),
          ],
        ),
      ),
    );
  }
}
