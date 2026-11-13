// Loopin — controles de la canción (en la fila de acompañamiento)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../../engine/engine_controller.dart';
import '../../l10n/strings.dart';
import '../songs_screen.dart';
import '../theme.dart';
import 'accompaniment_row.dart';
import 'view.dart';

/// Color de la luz de la canción: verde cuando suena, ámbar si está
/// encendida pero espera (al siguiente 1, a que se prepare, a que se elija) y
/// apagada si no.
Color songLed(LooperView view) {
  final c = view.controller;
  if (!c.backingOn) return LoopinPalette.ledOff;
  return view.s.backingPlaying ? LoopinPalette.play : LoopinPalette.dub;
}

/// La parte de la canción de la fila de abajo: cuál (abre la lista), volumen
/// y encendido.
class SongControls extends StatelessWidget {
  const SongControls({super.key, required this.view});

  final LooperView view;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final song = c.currentSong;
    final phase = c.backingPhase;
    final speed = c.songSpeed;
    final label = switch (phase) {
      BackingPhase.noSong => tr.songChoose,
      BackingPhase.needsSetup => tr.songSetup,
      _ => tr.songChip(song?.name ?? ''),
    };
    final trailing = switch (phase) {
      BackingPhase.preparing => tr.percent(c.backingProgress),
      BackingPhase.tooFar => tr.songTooFar,
      BackingPhase.failed => tr.songFailedChip,
      // A su tempo no hace falta decirlo
      BackingPhase.ready when speed != null && (speed - 1).abs() >= 0.005 => tr.songSpeed(speed),
      _ => null,
    };
    return Semantics(
      container: true,
      label: tr.songSemantics(song?.name, c.backingOn, view.s.backingPlaying),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            Tooltip(
              message: tr.songMenu,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => SongsScreen(controller: c))),
                child: RowChip(
                  view: view,
                  label: label,
                  trailing: trailing,
                  arrow: true,
                  maxWidth: chipRoom(box.maxWidth, c.songBleed ? 2 : 1),
                ),
              ),
            ),
            Expanded(
              child: RowSlider(
                view: view,
                max: 1.5,
                value: c.backingVolume,
                onChanged: c.setBackingVolume,
                onChangeEnd: (_) => c.saveBackingVolume(),
                semantics: tr.songVolume,
              ),
            ),
            if (c.songBleed) BleedButton(tooltip: tr.songBleed, help: tr.songBleedHelp),
            PowerButton(
              view: view,
              on: c.backingOn,
              tooltip: c.backingOn ? tr.songTurnOff : tr.songTurnOn,
              onPressed: c.toggleBacking,
            ),
          ],
        ),
      ),
    );
  }
}
