// Loopin — afinador: la nota en grande y una aguja de luces, como en un pedal
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/engine_controller.dart';
import '../engine/tuner.dart';
import '../l10n/strings.dart';
import 'help.dart';
import 'theme.dart';

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key, required this.controller});

  final EngineController controller;

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  final TunerFilter _filter = TunerFilter();
  final Stopwatch _clock = Stopwatch()..start();
  TunerDisplay _shown = const TunerDisplay();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.controller.setTunerOpen(true);
    // Unas 30 lecturas por segundo, como la consulta del estado del motor
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) => _read());
  }

  void _read() {
    final c = widget.controller;
    _filter.a4 = c.tunerA4;
    final next = _filter.update(c.readTuner(), _clock.elapsed);
    if (next.note?.midi != _shown.note?.midi ||
        next.live != _shown.live ||
        (next.note?.cents ?? 0) != (_shown.note?.cents ?? 0) ||
        (next.levelDb - _shown.levelDb).abs() > 1) {
      setState(() => _shown = next);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.setTunerOpen(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final palette = LoopinPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr.tuner)),
      backgroundColor: palette.chassis,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _TunerDisplayPanel(shown: _shown, running: c.status.running),
                  const SizedBox(height: 12),
                  _LevelBar(levelDb: _shown.levelDb, palette: palette),
                  if (c.speakerRoute && c.status.playing) ...[
                    const SizedBox(height: 12),
                    _SpeakerWarning(controller: c, palette: palette),
                  ],
                  const SizedBox(height: 12),
                  _ReferenceNotes(controller: c, palette: palette),
                  const SizedBox(height: 12),
                  Material(
                    color: palette.panel,
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      children: [
                        OptionTile(
                          leading: const Icon(Icons.help_outline),
                          title: tr.tuner,
                          help: tr.tunerHelp,
                        ),
                        _A4Tile(controller: c),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La pantalla en ámbar: las 6 cuerdas, la nota, la aguja y los cents.
class _TunerDisplayPanel extends StatelessWidget {
  const _TunerDisplayPanel({required this.shown, required this.running});

  final TunerDisplay shown;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final note = shown.note;
    const amber = LoopinPalette.display;
    const dim = LoopinPalette.displayDim;
    final color = note == null
        ? dim
        : (!shown.live ? dim : (note.inTune ? LoopinPalette.play : amber));
    final label = LoopinPalette.of(context).label(size: 14, color: dim);
    return Semantics(
      liveRegion: true,
      label: note == null
          ? (running ? tr.tunerListening : tr.tunerNoAudio)
          : tr.tunerSemantics(tr.noteName(note.pitchClass), note.cents),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
        decoration: BoxDecoration(
          color: LoopinPalette.well,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: LoopinPalette.of(context).edge, width: 2),
        ),
        child: Column(
          children: [
            // Las 6 cuerdas de la afinación estándar (se enciende la que suena)
            Text(tr.tunerStandard.toUpperCase(), style: label.copyWith(fontSize: 11)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < kStandardStrings.length; i++)
                  _StringChip(
                    text: tr.noteName(kStandardStrings[i] % 12),
                    on: note?.standardString == i,
                    inTune: note?.inTune ?? false,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 128,
              child: FittedBox(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      note == null ? '—' : tr.noteName(note.pitchClass),
                      key: const ValueKey('tuner-note'),
                      style: TextStyle(
                        fontFamily: LoopinFonts.display,
                        fontSize: 110,
                        height: 1,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      note == null ? '' : tr.noteLetter(note.pitchClass, note.octave),
                      style: label.copyWith(fontSize: 24, color: color),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              width: double.infinity,
              child: CustomPaint(
                painter: _NeedlePainter(cents: note?.cents, live: shown.live && note != null),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    note == null
                        ? (running ? tr.tunerListening : tr.tunerNoAudio)
                        : (note.inTune
                              ? tr.tunerInTune
                              : (note.cents < 0 ? tr.tunerFlat : tr.tunerSharp)),
                    textAlign: TextAlign.center,
                    style: label.copyWith(
                      fontSize: 18,
                      color: note == null ? dim : color,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              note == null ? ' ' : '${tr.tunerCents(note.cents)} · ${tr.tunerHz(note.frequency)}',
              style: TextStyle(fontFamily: LoopinFonts.display, fontSize: 14, color: dim),
            ),
          ],
        ),
      ),
    );
  }
}

class _StringChip extends StatelessWidget {
  const _StringChip({required this.text, required this.on, required this.inTune});

  final String text;
  final bool on;
  final bool inTune;

  @override
  Widget build(BuildContext context) {
    final color = on ? (inTune ? LoopinPalette.play : LoopinPalette.display) : LoopinPalette.ledOff;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: LoopinPalette.of(context)
            .label(size: 13, color: on ? color : LoopinPalette.displayDim),
      ),
    );
  }
}

/// La aguja: una fila de luces de −50 a +50 cents, verde en el centro.
class _NeedlePainter extends CustomPainter {
  _NeedlePainter({required this.cents, required this.live});

  final double? cents;
  final bool live;

  static const int leds = 21; // cada 5 cents

  @override
  void paint(Canvas canvas, Size size) {
    final gap = 3.0;
    final w = (size.width - gap * (leds - 1)) / leds;
    final c = cents;
    final lit = c == null ? -1 : ((c.clamp(-50.0, 50.0) + 50) / 5).round();
    for (var i = 0; i < leds; i++) {
      final center = i == leds ~/ 2;
      final h = center ? size.height : size.height * (0.55 + 0.35 * (1 - (i - 10).abs() / 10));
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * (w + gap), (size.height - h) / 2, w, h),
        const Radius.circular(3),
      );
      Color color = LoopinPalette.ledOff;
      if (i == lit) {
        final inTune = c != null && c.abs() <= kInTuneCents;
        color = inTune ? LoopinPalette.play : LoopinPalette.display;
        if (!live) color = color.withValues(alpha: 0.35);
      } else if (center) {
        color = LoopinPalette.play.withValues(alpha: 0.25);
      }
      canvas.drawRRect(rect, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => old.cents != cents || old.live != live;
}

/// Nivel de la entrada: para ver que llega sonido.
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.levelDb, required this.palette});

  final double levelDb;
  final LoopinPalette palette;

  @override
  Widget build(BuildContext context) {
    final v = ((levelDb + 60) / 60).clamp(0.0, 1.0);
    return Row(
      children: [
        Icon(Icons.mic, size: 18, color: palette.dim),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: palette.edge,
              color: LoopinPalette.play,
              semanticsLabel: tr.inputLevel,
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeakerWarning extends StatelessWidget {
  const _SpeakerWarning({required this.controller, required this.palette});

  final EngineController controller;
  final LoopinPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LoopinPalette.dub),
      ),
      child: Row(
        children: [
          const Icon(Icons.speaker_phone, color: LoopinPalette.dub, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(tr.tunerSpeaker)),
          TextButton(
            key: const ValueKey('tuner-stop'),
            onPressed: controller.stopAll,
            child: Text(tr.tunerStopAll),
          ),
        ],
      ),
    );
  }
}

/// Oír una nota para afinar de oído: las 6 cuerdas y el La de referencia.
/// Tocar una la hace sonar; otra vez, la calla.
class _ReferenceNotes extends StatelessWidget {
  const _ReferenceNotes({required this.controller, required this.palette});

  final EngineController controller;
  final LoopinPalette palette;

  /// El La de referencia (La4)
  static const _a4 = 69;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    Widget note(int midi, String label, String key) {
      final on = c.toneMidi == midi;
      return Semantics(
        button: true,
        toggled: on,
        label: tr.referenceNoteSemantics(label, c.noteHz(midi), on),
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(8),
          onTap: () => c.toggleTone(midi),
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: on ? LoopinPalette.display : null,
              border: Border.all(color: on ? LoopinPalette.display : palette.edge, width: 1.5),
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                label,
                style: palette.label(size: 15, color: on ? LoopinPalette.well : palette.ink),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: palette.panel, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.volume_up, size: 18, color: palette.dim),
              const SizedBox(width: 8),
              Expanded(child: Text(tr.referenceNotes, style: theme.textTheme.titleSmall)),
              if (c.toneMidi != null)
                TextButton(onPressed: c.stopTone, child: Text(tr.referenceStop)),
            ],
          ),
          Text(
            tr.referenceNotesLine,
            style: theme.textTheme.bodySmall?.copyWith(color: palette.dim),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < kStandardStrings.length; i++)
                note(
                  kStandardStrings[i],
                  tr.noteName(kStandardStrings[i] % 12),
                  'tone-${kStandardStrings[i]}',
                ),
              note(_a4, tr.referenceA4(c.tunerA4), 'tone-$_a4'),
            ],
          ),
        ],
      ),
    );
  }
}

/// La de referencia: − 440 Hz +
class _A4Tile extends StatelessWidget {
  const _A4Tile({required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final a4 = c.tunerA4;
    return OptionTile(
      leading: const Icon(Icons.tune),
      title: tr.tunerA4,
      subtitle: Text(tr.tunerA4Value(a4)),
      help: tr.tunerA4Help,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: tr.trainerDecrease,
            onPressed: a4 > LiveSettings.minA4 ? () => c.setTunerA4(a4 - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            tooltip: tr.trainerIncrease,
            onPressed: a4 < LiveSettings.maxA4 ? () => c.setTunerA4(a4 + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
