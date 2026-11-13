// Loopin — controles de la batería (en la fila de acompañamiento): estilo,
// volumen y encendido
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../../engine/drums.dart';
import '../../l10n/strings.dart';
import '../theme.dart';
import 'accompaniment_row.dart';
import 'view.dart';

/// Color de la luz de la batería: verde cuando suena, ámbar si está
/// encendida pero espera al siguiente 1 (o todo está parado) y apagada si no.
Color drumLed(LooperView view) {
  final on = view.controller.drumsOn;
  if (!on) return LoopinPalette.ledOff;
  return view.s.drumsPlaying ? LoopinPalette.play : LoopinPalette.dub;
}

/// La parte de la batería de la fila de abajo.
class DrumControls extends StatelessWidget {
  const DrumControls({super.key, required this.view});

  final LooperView view;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final on = c.drumsOn;
    final playing = on && view.s.drumsPlaying;
    final style = c.drumStyleNow;
    return Semantics(
      container: true,
      label: tr.drumsSemantics(tr.drumStyleName(style), on, playing),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            _StyleMenu(
              view: view,
              style: style,
              maxWidth: chipRoom(box.maxWidth, c.drumsBleed ? 2 : 1),
            ),
            Expanded(
              child: RowSlider(
                view: view,
                max: 1.5,
                value: c.drumVolume,
                onChanged: c.setDrumVolume,
                onChangeEnd: (_) => c.saveDrumVolume(),
                semantics: tr.drumVolume,
              ),
            ),
            if (c.drumsBleed) BleedButton(tooltip: tr.drumsBleed, help: tr.drumsBleedHelp),
            PowerButton(
              view: view,
              on: on,
              tooltip: on ? tr.drumsTurnOff : tr.drumsTurnOn,
              onPressed: c.toggleDrums,
            ),
          ],
        ),
      ),
    );
  }
}

/// El estilo: abre un menú con todos. Los de otro compás cambian el compás
/// (con un loop grabado no se puede y salen desactivados).
class _StyleMenu extends StatelessWidget {
  const _StyleMenu({required this.view, required this.style, required this.maxWidth});

  final LooperView view;
  final DrumStyle style;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
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
      child: RowChip(view: view, label: tr.drumStyleChip(style), arrow: true, maxWidth: maxWidth),
    );
  }
}
