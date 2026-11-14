// Loopin — pantalla de tempo: números en ámbar sobre negro, como la de un pedal
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../../engine/engine_controller.dart';
import '../../l10n/strings.dart';
import '../pedal_widgets.dart';
import '../theme.dart';
import 'tempo_menus.dart';
import 'trainer_sheet.dart';
import 'view.dart';

/// Tres filas: el tempo (con − / + y TAP), arrancar/parar y el entrenador con
/// las luces de los tiempos, y compás, modo, compases, «empezar al tocar» y
/// clic (en simple, con menos opciones).
class TempoDisplay extends StatelessWidget {
  const TempoDisplay({super.key, required this.view, required this.compact});

  final LooperView view;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final s = view.s;
    return Container(
      padding: EdgeInsets.fromLTRB(4, compact ? 4 : 8, 4, compact ? 6 : 10),
      decoration: BoxDecoration(
        color: LoopinPalette.well,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: view.palette.edge, width: 2),
      ),
      child: Column(
        children: [
          _TempoRow(view: view, compact: compact),
          SizedBox(height: compact ? 4 : 8),
          // Arrancar o parar y los tiempos del compás, bien grandes
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                _MetronomeButton(view: view),
                const SizedBox(width: 6),
                TrainerButton(view: view),
                const SizedBox(width: 10),
                Expanded(
                  child: BeatBuilder(
                    active: s.playing,
                    beatNow: c.beatNow,
                    builder: (context, now) => BeatBar(
                      signature: c.timeSignature,
                      beats: s.playing ? s.beatsPerBar : c.beatsPerBar,
                      now: now,
                      height: compact ? 14 : 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...[
            SizedBox(height: compact ? 4 : 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Expanded(flex: 4, child: MeterMenu(view: view)),
                  const SizedBox(width: 6),
                  Expanded(flex: 4, child: ModeMenu(view: view)),
                  // Los compases solo cuentan en sincronizado
                  if (c.loopMode == LoopMode.sync) ...[
                    const SizedBox(width: 6),
                    Expanded(flex: 3, child: BarsMenu(view: view)),
                  ],
                  const SizedBox(width: 6),
                  OnSoundToggle(view: view),
                  const SizedBox(width: 6),
                  // Un toque pasa de un modo del clic al siguiente
                  ClickToggle(view: view),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// − / BPM / + y, debajo, el botón de TAP (o por qué no se puede cambiar).
class _TempoRow extends StatelessWidget {
  const _TempoRow({required this.view, required this.compact});

  final LooperView view;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final s = view.s;
    final locked = c.tempoLocked;
    final free = c.loopMode == LoopMode.free;
    // En libre, mientras no haya loop no hay tempo
    final noTempo = free && !s.hasLoops;
    // Con loop, o con el entrenador subiéndolo, el tempo es el del motor
    final bpm = c.shownBpm;
    final trainer = c.trainerOn && !locked;
    const amber = LoopinPalette.display;
    const dimAmber = LoopinPalette.displayDim;
    final small = view.palette.label(size: 12, color: dimAmber);
    final canEdit = !locked && !free;

    return Row(
      children: [
        IconButton(
          tooltip: tr.tempoDown,
          onPressed: canEdit ? () => c.setBpm(c.bpm - 1) : null,
          icon: const Icon(Icons.remove),
          color: amber,
          disabledColor: dimAmber.withValues(alpha: 0.5),
        ),
        Expanded(
          child: Semantics(
            button: canEdit,
            label: noTempo
                ? tr.tempoFromLoopSemantics
                : tr.bpmSemantics(bpm.round(), locked: locked),
            excludeSemantics: true,
            child: InkWell(
              key: const ValueKey('tap-tempo'),
              onTap: canEdit ? c.tapTempo : null,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (locked)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.lock, size: 16, color: dimAmber),
                          ),
                        Text(
                          noTempo ? tr.noTempoYet : bpm.toStringAsFixed(0),
                          style: TextStyle(
                            fontFamily: LoopinFonts.display,
                            fontSize: compact ? 36 : 46,
                            height: 1,
                            color: amber,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          c.timeSignature.eighths ? tr.bpmUnitEighths : tr.bpmUnit,
                          style: small.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (trainer)
                    // En lugar del TAP: lo que hará el entrenador (tocar lo abre)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: InkWell(
                        key: const ValueKey('trainer-pill'),
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => showTrainerSheet(context, c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: amber.withValues(alpha: 0.15),
                            border: Border.all(color: amber),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.trending_up, size: 14, color: amber),
                              const SizedBox(width: 4),
                              Text(
                                tr.trainerPill(
                                  c.trainerStep.round(),
                                  c.trainerBars,
                                  c.trainerTop.round(),
                                ),
                                style: small.copyWith(color: amber),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (canEdit)
                    // Que se vea que se puede marcar el tempo tocando
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: amber.withValues(alpha: 0.6)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.touch_app, size: 14, color: amber),
                            const SizedBox(width: 4),
                            Text(tr.tapTempo, style: small.copyWith(color: amber)),
                          ],
                        ),
                      ),
                    )
                  else
                    Text(
                      noTempo ? tr.tempoFromLoop : (locked ? tr.tempoLocked : ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small.copyWith(fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: tr.tempoUp,
          onPressed: canEdit ? () => c.setBpm(c.bpm + 1) : null,
          icon: const Icon(Icons.add),
          color: amber,
          disabledColor: dimAmber.withValues(alpha: 0.5),
        ),
      ],
    );
  }
}

/// Arranca o para el metrónomo (y los loops, si los hay).
class _MetronomeButton extends StatelessWidget {
  const _MetronomeButton({required this.view});

  final LooperView view;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final s = view.s;
    final playing = s.playing;
    // En libre, sin loop no hay tempo que arrancar
    final enabled = s.running && !(c.loopMode == LoopMode.free && !s.hasLoops);
    final color = enabled ? LoopinPalette.display : LoopinPalette.displayDim;
    // Parando (en el 1 o con fundido): pulsar otra vez para ya
    final stopping = c.stoppingNow;
    return Semantics(
      button: true,
      label: stopping
          ? tr.tapToStopNow
          : playing
          ? (s.hasLoops ? tr.stopAll : tr.stopMetronome)
          : (s.hasLoops ? tr.startAll : tr.startMetronome),
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('metronome-toggle'),
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? c.togglePlay : null,
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: playing ? 1 : 0.5)),
            color: playing ? LoopinPalette.display.withValues(alpha: 0.15) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                stopping ? Icons.hourglass_bottom : (playing ? Icons.stop : Icons.play_arrow),
                color: color,
                size: 22,
              ),
              const SizedBox(width: 2),
              Icon(Icons.av_timer, color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los tiempos del compás como una fila de luces: se enciende el que suena
/// (rojo el primero, ámbar fuerte el que empieza cada grupo) y se apaga poco a
/// poco hasta el siguiente. Los grupos (2+2+3…) van separados.
class BeatBar extends StatelessWidget {
  const BeatBar({
    super.key,
    required this.signature,
    required this.beats,
    required this.now,
    required this.height,
  });

  final TimeSignature signature;
  final int beats;
  final BeatNow? now;
  final double height;

  @override
  Widget build(BuildContext context) {
    final n = beats.clamp(1, 16);
    final children = <Widget>[];
    for (var i = 0; i < n; i++) {
      if (i > 0) children.add(SizedBox(width: signature.startsGroup(i) ? 10 : 4));
      final on = now != null && now!.beat == i;
      final strong = signature.startsGroup(i);
      final base = i == 0
          ? LoopinPalette.rec
          : (strong ? LoopinPalette.display : LoopinPalette.display.withValues(alpha: 0.75));
      // Destello al empezar el tiempo que se va apagando
      final glow = on ? 1.0 - 0.6 * now!.phase.clamp(0.0, 1.0) : 0.0;
      children.add(
        Expanded(
          child: Container(
            height: strong ? height : height * 0.72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: on ? Color.lerp(LoopinPalette.ledOff, base, glow) : LoopinPalette.ledOff,
            ),
          ),
        ),
      );
    }
    return Semantics(
      label: now == null ? tr.metronomeStopped : tr.beatOf(now!.beat + 1, n),
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
      ),
    );
  }
}
