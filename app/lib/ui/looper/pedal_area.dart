// Loopin — el pulsador grande y lo que está pasando
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../../engine/engine_controller.dart';
import '../../l10n/strings.dart';
import '../pedal_widgets.dart';
import '../theme.dart';
import 'chassis_button.dart';
import 'view.dart';

/// Cómo se ve el pulsador y qué dice debajo.
class PedalLook {
  const PedalLook({
    required this.color,
    required this.title,
    required this.subtitle,
    this.progress = 0,
    this.glow = false,
    this.icon,
    this.text,
  });

  final Color? color;
  final String title;
  final String subtitle;
  final double progress;
  final bool glow;
  final IconData? icon;
  final String? text;
}

/// [duck]: lo que pasa con lo que ya suena mientras se graba (para decirlo
/// debajo; normal si no se aplica).
PedalLook pedalLook(
  EngineStatus s, {
  required LoopMode mode,
  required bool startOnSound,
  RecordDuck duck = RecordDuck.normal,
}) {
  final selected = s.tracks[s.selectedTrack];
  final sel = s.selectedTrack + 1;
  final active = s.activeTrack >= 0 ? s.activeTrack + 1 : sel;
  final bar = s.loopBarFrames;
  // Tiempos que faltan mientras espera (cuenta de entrada o siguiente compás)
  final beatsLeft = s.samplesPerBeat > 0 ? (-s.loopRecorded / s.samplesPerBeat).ceil() : 0;
  // Parando en el 1 o con fundido: el pulsador para ya
  if (s.stopping != 0 && s.playing) {
    return PedalLook(
      color: LoopinPalette.stopped,
      title: s.stopping == 1 ? tr.stoppingAtOne : tr.fadingOut,
      subtitle: tr.tapToStopNow,
      progress: selected.hasLoop ? selected.progress : 0,
      icon: Icons.stop,
    );
  }
  switch (s.loopState) {
    case LoopState.empty:
      return PedalLook(
        color: null,
        title: tr.ready,
        subtitle: startOnSound
            ? tr.readyOnSound(sel)
            : (mode == LoopMode.free ? tr.readyFree(sel) : tr.readyCountIn(sel)),
        icon: startOnSound ? Icons.hearing : Icons.fiber_manual_record,
      );
    case LoopState.armed:
      if (s.loopWaiting) {
        return PedalLook(
          color: LoopinPalette.count,
          title: tr.waiting,
          subtitle: tr.waitingLine,
          progress: 1,
          icon: Icons.hearing,
        );
      }
      return PedalLook(
        color: LoopinPalette.count,
        title: tr.getReady,
        subtitle: s.hasLoops ? tr.trackStartsNextBar(active) : tr.countIn,
        progress: recordProgress(s),
        text: '$beatsLeft',
      );
    case LoopState.recording:
      final barNow = bar > 0 ? s.loopRecorded ~/ bar + 1 : 1;
      final target = bar > 0 ? s.loopTarget ~/ bar : 0;
      return PedalLook(
        color: LoopinPalette.rec,
        title: tr.recordingTitle(active),
        subtitle: bar <= 0
            ? tr.recordingFree
            : tr.withDuck(
                target > 0 ? tr.barOf(barNow, target) : tr.barOpen(barNow),
                s.hasLoops ? duck : RecordDuck.normal,
              ),
        progress: recordProgress(s),
        icon: Icons.stop,
      );
    case LoopState.playing:
      return PedalLook(
        color: LoopinPalette.play,
        title: tr.playing,
        subtitle: selected.hasLoop ? tr.overdubOn(sel) : tr.recordOn(sel),
        progress: selected.hasLoop
            ? selected.progress
            : (s.baseLength > 0 ? s.basePosition / s.baseLength : 0),
        glow: true,
        icon: selected.hasLoop ? Icons.layers : Icons.fiber_manual_record,
      );
    case LoopState.overdubbing:
      final track = s.tracks[(active - 1).clamp(0, kTrackCount - 1)];
      if (s.loopRecorded < 0) {
        return PedalLook(
          color: LoopinPalette.count,
          title: tr.getReady,
          subtitle: tr.overdubNextBar(active),
          progress: recordProgress(s),
          text: '$beatsLeft',
        );
      }
      return PedalLook(
        color: LoopinPalette.dub,
        title: tr.overdubTitle(active),
        subtitle: tr.withDuck(tr.tapToFinish, duck),
        progress: track.progress,
        glow: true,
        icon: Icons.stop,
      );
    case LoopState.stopped:
      return PedalLook(
        color: LoopinPalette.stopped,
        title: tr.stopped,
        subtitle: tr.tapToStart,
        icon: Icons.play_arrow,
      );
  }
}

/// El pulsador con el estado debajo. Se redibuja con cada consulta al motor
/// (el anillo avanza, la cuenta baja) y en cada fotograma mientras suena (el
/// destello del pulso).
class PedalArea extends StatelessWidget {
  const PedalArea({super.key, required this.view, required this.size});

  final LooperView view;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    if (!view.s.running) return _AudioOff(view: view);
    return ListenableBuilder(
      listenable: c.live,
      builder: (context, _) {
        final p = view.palette;
        final look = pedalLook(
          view.s,
          mode: c.loopMode,
          startOnSound: c.startOnSound,
          duck: c.speakerRoute ? c.recordDuck : RecordDuck.normal,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // La arandela del pulsador se ilumina en cada tiempo (roja en el
            // primero): el tempo se ve sin tener que oír el clic
            BeatBuilder(
              active: view.s.playing,
              beatNow: c.beatNow,
              builder: (context, now) {
                final flash = now == null ? 0.0 : (1 - now.phase / 0.35).clamp(0.0, 1.0);
                return Footswitch(
                  size: size,
                  color: look.color,
                  progress: look.progress,
                  glow: look.glow,
                  icon: look.icon,
                  text: look.text,
                  pulse: flash,
                  pulseColor: now != null && now.beat == 0
                      ? LoopinPalette.rec
                      : LoopinPalette.display,
                  semanticLabel: tr.pedalSemantics(look.title, look.subtitle),
                  onDown: c.pedalDown,
                  onUp: c.pedalUp,
                );
              },
            ),
            const SizedBox(height: 10),
            // El estado, grande: se tiene que leer con el móvil en el suelo
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Led(color: look.color ?? LoopinPalette.ledOff, size: 12),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    look.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: p.label(size: 22, spacing: 2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // Si no se ha podido guardar (falta espacio), lo dice aquí cuando
            // no se graba; tocarlo lleva a Sesiones (con Exportar)
            if (c.sessionSaveFailed && !c.recordingNow)
              InkWell(
                key: const ValueKey('pedal-save-failed'),
                onTap: view.onSessions,
                child: Text(
                  '⚠ ${tr.saveFailedLine(c.sessionSaveNoSpace)}',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.25, color: LoopinPalette.dub),
                ),
              )
            else
              Text(
                look.subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, height: 1.25, color: p.dim),
              ),
          ],
        );
      },
    );
  }
}

class _AudioOff extends StatelessWidget {
  const _AudioOff({required this.view});

  final LooperView view;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final p = view.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              c.error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.ink, fontSize: 15, height: 1.3),
            ),
          ),
        ChassisButton(
          palette: p,
          icon: Icons.power_settings_new,
          label: tr.audioOn,
          onPressed: c.startAudio,
        ),
      ],
    );
  }
}
