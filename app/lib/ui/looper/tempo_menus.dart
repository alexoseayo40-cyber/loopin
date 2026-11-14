// Loopin — fila de abajo de la pantalla de tempo: compás, modo, compases,
// «empezar al tocar» y clic (en el modo simple, solo compás y clic)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../../engine/engine_controller.dart';
import '../../engine/play_mode.dart';
import '../../l10n/strings.dart';
import '../theme.dart';
import 'view.dart';

/// Un valor de la pantalla de tempo que abre un menú al tocarlo.
class DisplayChip extends StatelessWidget {
  const DisplayChip({super.key, required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? LoopinPalette.display : LoopinPalette.displayDim;
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(fontFamily: LoopinFonts.display, fontSize: 14, color: color),
        ),
      ),
    );
  }
}

/// Compás (4/4, 7/8…; en simple, solo 4/4, 3/4 y 6/8).
class MeterMenu extends StatelessWidget {
  const MeterMenu({super.key, required this.view});

  final LooperView view;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final enabled = !c.tempoLocked;
    return PopupMenuButton<TimeSignature>(
      tooltip: tr.meter,
      enabled: enabled,
      initialValue: c.timeSignature,
      onSelected: c.setTimeSignature,
      itemBuilder: (_) => [
        for (final t in c.timeSignatures) PopupMenuItem(value: t, child: Text(tr.meterItem(t))),
      ],
      child: DisplayChip(label: tr.meterChip(c.timeSignature), enabled: enabled),
    );
  }
}

/// Modo de grabación: sincronizado, manual o libre.
class ModeMenu extends StatelessWidget {
  const ModeMenu({super.key, required this.view});

  final LooperView view;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final enabled = !modeLocked(view.s);
    return PopupMenuButton<LoopMode>(
      tooltip: tr.recordMode,
      enabled: enabled,
      initialValue: c.loopMode,
      onSelected: c.setLoopMode,
      itemBuilder: (_) => [
        // En simple, sin el libre
        for (final m in c.simple ? kSimpleLoopModes : LoopMode.values)
          PopupMenuItem(
            value: m,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr.loopModeName(m)),
              subtitle: Text(tr.loopModeLine(m)),
            ),
          ),
      ],
      child: DisplayChip(label: tr.loopModeShort(c.loopMode), enabled: enabled),
    );
  }
}

/// Compases que graba el modo sincronizado.
class BarsMenu extends StatelessWidget {
  const BarsMenu({super.key, required this.view});

  final LooperView view;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final enabled = !modeLocked(view.s);
    return PopupMenuButton<int>(
      tooltip: tr.syncBars,
      enabled: enabled,
      initialValue: c.syncBars,
      onSelected: c.setSyncBars,
      itemBuilder: (_) => [
        for (final b in kSyncBarOptions) PopupMenuItem(value: b, child: Text(tr.bars(b))),
      ],
      child: DisplayChip(label: tr.barsShort(c.syncBars), enabled: enabled),
    );
  }
}

/// «Empezar al tocar»: un toque lo enciende o lo apaga. Encendido, la pista 1
/// no tiene cuenta de entrada: arranca con la primera nota.
class OnSoundToggle extends StatelessWidget {
  const OnSoundToggle({super.key, required this.view});

  final LooperView view;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final on = c.startOnSound;
    final enabled = !modeLocked(view.s);
    final color = enabled ? LoopinPalette.display : LoopinPalette.displayDim;
    return Tooltip(
      message: tr.startOnSoundTooltip(on),
      child: Semantics(
        button: true,
        toggled: on,
        label: tr.startOnSound,
        excludeSemantics: true,
        child: InkWell(
          key: const ValueKey('on-sound-toggle'),
          borderRadius: BorderRadius.circular(6),
          onTap: enabled
              ? () {
                  c.setStartOnSound(!on);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        duration: const Duration(seconds: 3),
                        content: Text(!on ? tr.startOnSoundOn : tr.startOnSoundOff),
                      ),
                    );
                }
              : null,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: on ? color.withValues(alpha: 0.2) : null,
              border: Border.all(color: color.withValues(alpha: on ? 1 : 0.45)),
            ),
            child: Icon(on ? Icons.hearing : Icons.hearing_disabled, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

/// El clic (los dos modos): cada toque pasa al siguiente modo (siempre →
/// hasta grabar → apagado, solo las luces → siempre). En libre no suena.
class ClickToggle extends StatelessWidget {
  const ClickToggle({super.key, required this.view});

  final LooperView view;

  static IconData iconFor(ClickMode m) => switch (m) {
    ClickMode.always => Icons.volume_up,
    ClickMode.untilRecording => Icons.fiber_smart_record_outlined,
    _ => Icons.volume_off,
  };

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final free = c.loopMode == LoopMode.free;
    final mode = clickModeOf(c.clickMode);
    final on = mode != ClickMode.silent && !free;
    const color = LoopinPalette.display;
    final i = kClickModes.indexOf(mode);
    final next = kClickModes[(i + 1) % kClickModes.length];
    final label = free ? tr.clickFree : tr.clickLabel(mode);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        toggled: on,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: const ValueKey('click-toggle'),
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            // En libre el clic no suena nunca: solo se explica
            if (!free) c.setClickMode(next);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 3),
                  content: Text(free ? tr.clickFree : tr.clickSnack(next)),
                ),
              );
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: on ? color.withValues(alpha: 0.2) : null,
              border: Border.all(color: color.withValues(alpha: on ? 1 : 0.45)),
            ),
            child: Icon(free ? Icons.visibility_outlined : iconFor(mode), size: 20, color: color),
          ),
        ),
      ),
    );
  }
}
