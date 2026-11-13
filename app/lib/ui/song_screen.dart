// Loopin — preparar una canción: escucharla, marcar el 1, su tempo y su compás
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/engine_controller.dart';
import '../engine/song_editor.dart';
import '../l10n/strings.dart';
import 'help.dart';
import 'song/waveform.dart';
import 'theme.dart';

class SongScreen extends StatefulWidget {
  const SongScreen({super.key, required this.controller, required this.song});

  final EngineController controller;
  final Song song;

  @override
  State<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends State<SongScreen> {
  late final SongEditor e = SongEditor(controller: widget.controller, song: widget.song);
  late final TextEditingController _name = TextEditingController(text: widget.song.name);

  @override
  void initState() {
    super.initState();
    e.start();
  }

  @override
  void dispose() {
    e.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    e.setName(_name.text);
    await e.save();
    if (!mounted) return;
    // Lista para tocar: de vuelta al looper
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr.editorTitle),
        actions: [
          ListenableBuilder(
            listenable: Listenable.merge([c, e]),
            builder: (context, _) =>
                TextButton(onPressed: e.ready ? _save : null, child: Text(tr.editorSave)),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([c, e]),
        builder: (context, _) {
          if (!e.ready) return _Opening(editor: e);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(labelText: tr.editorName, isDense: true),
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: e.setName,
                  ),
                  const SizedBox(height: 16),
                  _Overview(editor: e),
                  _Transport(editor: e),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: e.markOne,
                    icon: const Icon(Icons.flag),
                    label: Text(tr.editorMarkOne),
                  ),
                  HelpLine(tr.editorMarkLine, help: tr.editorMarkHelp),
                  const SizedBox(height: 8),
                  Text(tr.editorZoom, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  _Zoom(editor: e),
                  _Nudge(editor: e),
                  const Divider(height: 32),
                  _Tempo(editor: e),
                  const SizedBox(height: 8),
                  _Meter(editor: e),
                  const SizedBox(height: 8),
                  _Second(editor: e),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _save, child: Text(tr.editorSave)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Opening extends StatelessWidget {
  const _Opening({required this.editor});

  final SongEditor editor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: editor.failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
                  const SizedBox(height: 12),
                  Text(tr.songError(editor.error), textAlign: TextAlign.center),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 220,
                    child: LinearProgressIndicator(
                      value: editor.progress > 0 ? editor.progress : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(tr.editorOpening(editor.progress)),
                ],
              ),
      ),
    );
  }
}

/// Rayas finas en cada compás de la rejilla (desde el 1, hacia atrás y hacia
/// adelante), en fracción de [from]–[to]. Si salen demasiadas, cada pocas.
List<double> _barLines(SongEditor e, int from, int to, {int maxLines = 200}) {
  final bar = e.beatFrames * e.meter.beats;
  if (bar <= 0 || to <= from) return const [];
  final span = (to - from).toDouble();
  var step = 1;
  while (span / (bar * step) > maxLines) {
    step *= 2;
  }
  final first = ((from - e.markFrame) / (bar * step)).ceil();
  final lines = <double>[];
  for (var k = first; ; k++) {
    final f = e.markFrame + k * bar * step;
    if (f > to) break;
    lines.add((f - from) / span);
  }
  return lines;
}

class _Overview extends StatelessWidget {
  const _Overview({required this.editor});

  final SongEditor editor;

  @override
  Widget build(BuildContext context) {
    final e = editor;
    final frames = math.max(1, e.frames);
    final grid = _barLines(e, 0, frames);
    return ListenableBuilder(
      listenable: e.controller.live,
      builder: (context, _) {
        final heard = e.playing ? e.controller.previewHeardFrame() : e.cursor;
        return Waveform(
          peaks: e.overview,
          grid: grid,
          height: 72,
          semanticLabel: tr.editorWaveTip,
          onTap: (x) => e.seek((x * frames).round()),
          marks: [
            WaveMark(e.markFrame / frames, LoopinPalette.rec),
            if (e.mark2Frame != null) WaveMark(e.mark2Frame! / frames, LoopinPalette.dub),
            WaveMark(heard / frames, Theme.of(context).colorScheme.primary, width: 1.5),
          ],
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.editor});

  final SongEditor editor;

  @override
  Widget build(BuildContext context) {
    final e = editor;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: e.controller.live,
            builder: (context, _) {
              final heard = e.playing ? e.controller.previewHeardFrame() : e.cursor;
              return Text(
                '${tr.clock(heard / e.rate)} / ${tr.clock(e.frames / e.rate)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: LoopinFonts.display,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              );
            },
          ),
        ),
        IconButton(
          tooltip: tr.editorFromMark,
          onPressed: e.playFromMark,
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton.filled(
          tooltip: e.playing ? tr.editorPause : tr.editorPlay,
          onPressed: e.togglePlay,
          iconSize: 32,
          icon: Icon(e.playing ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: tr.editorClickTip,
          child: FilterChip(label: Text(tr.editorClick), selected: e.click, onSelected: e.setClick),
        ),
      ],
    );
  }
}

class _Zoom extends StatelessWidget {
  const _Zoom({required this.editor});

  final SongEditor editor;

  @override
  Widget build(BuildContext context) {
    final e = editor;
    final r = (SongEditor.zoomRadius * e.rate).round();
    final from = e.markFrame - r, to = e.markFrame + r;
    return ListenableBuilder(
      listenable: e.controller.live,
      builder: (context, _) {
        final heard = e.playing ? e.controller.previewHeardFrame() : e.cursor;
        return Waveform(
          peaks: e.zoom,
          height: 96,
          semanticLabel: tr.editorZoom,
          // Se arrastra la onda: el 1 se queda en medio
          onDrag: (dx) => e.setMarkFrame((e.markFrame - dx * 2 * r).round()),
          marks: [
            const WaveMark(0.5, LoopinPalette.rec),
            if (heard >= from && heard <= to)
              WaveMark(
                (heard - from) / (to - from),
                Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
          ],
        );
      },
    );
  }
}

class _Nudge extends StatelessWidget {
  const _Nudge({required this.editor});

  final SongEditor editor;

  @override
  Widget build(BuildContext context) {
    Widget b(int ms) => Expanded(
      child: Tooltip(
        message: tr.editorNudge(ms),
        child: TextButton(
          onPressed: () => editor.nudgeMark(ms.toDouble()),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text('${ms > 0 ? '+' : ''}$ms ms')),
        ),
      ),
    );
    return Row(children: [b(-10), b(-1), b(1), b(10)]);
  }
}

class _Tempo extends StatelessWidget {
  const _Tempo({required this.editor});

  final SongEditor editor;

  Future<void> _type(BuildContext context) async {
    final text = TextEditingController(text: tr.bpmNumber(editor.draft.bpm));
    final v = await showDialog<double>(
      context: context,
      builder: (context) {
        double? parse() => double.tryParse(text.text.replaceAll(',', '.').trim());
        return AlertDialog(
          title: Text(tr.editorBpmDialog),
          content: TextField(
            controller: text,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(suffixText: 'BPM'),
            onSubmitted: (_) => Navigator.of(context).pop(parse()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr.cancel)),
            TextButton(onPressed: () => Navigator.of(context).pop(parse()), child: Text(tr.ok)),
          ],
        );
      },
    );
    text.dispose();
    if (v != null && v > 0) editor.setBpm(v);
  }

  @override
  Widget build(BuildContext context) {
    final e = editor;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(tr.editorTempo, help: tr.editorTempoHelp),
        Row(
          children: [
            IconButton(
              tooltip: tr.editorTempoMinus,
              onPressed: () => e.setBpm(e.draft.bpm - 0.1),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => _type(context),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    tr.editorBpm(tr.bpmNumber(e.draft.bpm)),
                    style: theme.textTheme.headlineSmall?.copyWith(fontFamily: LoopinFonts.display),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: tr.editorTempoPlus,
              onPressed: () => e.setBpm(e.draft.bpm + 0.1),
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: tr.editorTapTip,
              child: OutlinedButton(onPressed: e.tap, child: Text(tr.editorTap)),
            ),
          ],
        ),
        if (e.bpmGuess > 0)
          Text(
            tr.editorGuess(tr.bpmNumber((e.bpmGuess * 10).round() / 10)),
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.editor});

  final SongEditor editor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(tr.editorMeter, style: Theme.of(context).textTheme.bodyLarge)),
        DropdownButton<TimeSignature>(
          value: editor.meter,
          onChanged: (ts) {
            if (ts != null) editor.setMeter(ts);
          },
          items: [
            for (final ts in kTimeSignatures)
              DropdownMenuItem(value: ts, child: Text(tr.meterChip(ts))),
          ],
        ),
      ],
    );
  }
}

class _Second extends StatelessWidget {
  const _Second({required this.editor});

  final SongEditor editor;

  @override
  Widget build(BuildContext context) {
    final e = editor;
    final bars = e.barsBetween;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: e.markSecond,
          icon: const Icon(Icons.outlined_flag),
          label: Text(tr.editorSecond),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr.editorSecondLine, style: Theme.of(context).textTheme.bodySmall),
        ),
        if (bars != null)
          Row(
            children: [
              Expanded(child: Text(tr.editorBarsBetween(bars))),
              IconButton(
                tooltip: tr.editorFewerBars,
                onPressed: bars > 1 ? () => e.setBarsBetween(bars - 1) : null,
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                tooltip: tr.editorMoreBars,
                onPressed: () => e.setBarsBetween(bars + 1),
                icon: const Icon(Icons.add),
              ),
              IconButton(
                tooltip: tr.editorClearSecond,
                onPressed: e.clearSecond,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
      ],
    );
  }
}
