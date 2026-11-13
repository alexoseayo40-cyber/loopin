// Loopin — exportar la sesión abierta a WAV y compartirla (Etapa 6)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../engine/engine_controller.dart';
import '../l10n/strings.dart';
import 'help.dart';

Future<void> showExportSheet(BuildContext context, EngineController c) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ExportSheet(controller: c),
  );
}

class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key, required this.controller});

  final EngineController controller;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  EngineController get c => widget.controller;

  bool _mix = true;
  bool _stems = false;
  // De serie, lo que suena ahora (se puede quitar)
  late bool _drums = c.exportCanDrums;
  late bool _song = c.exportCanSong;
  late int _loops = c.exportLoopOptions.contains(2) ? 2 : 1;

  /// Ya se ha pedido exportar (se enseña el progreso o el resultado).
  bool _started = false;
  String? _problem;

  Future<void> _start() async {
    setState(() => _problem = null);
    final code = await c.startExport(
      mix: _mix,
      stems: _stems,
      withDrums: _drums,
      withSong: _song,
      loops: _loops,
    );
    if (!mounted) return;
    setState(() {
      _started = code == 0;
      _problem = code == 0 ? null : tr.exportStartError(code);
    });
  }

  Future<void> _save() async {
    final n = await c.saveExport();
    if (!mounted || n == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(n < 0 ? tr.exportSaveFailed : tr.exportSaved(n))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ListenableBuilder(
          listenable: Listenable.merge([c, c.live]),
          builder: (context, _) {
            final state = c.exportState;
            final running = _started && state == JobState.running;
            final done = _started && state == JobState.done;
            final failed = _started && state == JobState.failed;
            final cycle = c.cycleSeconds;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr.exportTitle(c.sessionName), style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  SectionTitle(
                    tr.exportWhat,
                    help: tr.exportHelp,
                    padding: const EdgeInsets.only(top: 4),
                  ),
                  SwitchListTile(
                    key: const ValueKey('export-mix'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.exportMix),
                    value: _mix,
                    onChanged: running ? null : (v) => setState(() => _mix = v),
                  ),
                  SwitchListTile(
                    key: const ValueKey('export-stems'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.exportStems),
                    value: _stems,
                    onChanged: running ? null : (v) => setState(() => _stems = v),
                  ),
                  if (c.exportCanDrums)
                    CheckboxListTile(
                      key: const ValueKey('export-drums'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr.exportWithDrums),
                      value: _drums,
                      onChanged: running ? null : (v) => setState(() => _drums = v ?? false),
                    ),
                  if (c.exportCanSong)
                    CheckboxListTile(
                      key: const ValueKey('export-song'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr.exportWithSong),
                      value: _song,
                      onChanged: running ? null : (v) => setState(() => _song = v ?? false),
                    ),
                  const SizedBox(height: 8),
                  Text(tr.exportLoops, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  SegmentedButton<int>(
                    segments: [
                      for (final n in c.exportLoopOptions)
                        ButtonSegment(value: n, label: Text('$n')),
                    ],
                    selected: {_loops},
                    onSelectionChanged: running ? null : (v) => setState(() => _loops = v.first),
                  ),
                  const SizedBox(height: 4),
                  Text(tr.exportLength(_loops, cycle * _loops), style: theme.textTheme.bodySmall),
                  const SizedBox(height: 16),
                  if (running) ...[
                    LinearProgressIndicator(value: c.exportProgress),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: Text(tr.exporting(c.exportProgress))),
                        TextButton(onPressed: c.cancelExport, child: Text(tr.cancel)),
                      ],
                    ),
                  ] else if (done) ...[
                    Text(tr.exportDone(c.exportedFiles.length), style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('export-share'),
                          onPressed: c.shareExport,
                          icon: const Icon(Icons.share),
                          label: Text(tr.exportShare),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('export-save'),
                          onPressed: _save,
                          icon: const Icon(Icons.folder_outlined),
                          label: Text(tr.exportSave),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _started = false),
                          child: Text(tr.exportAgain),
                        ),
                      ],
                    ),
                  ] else ...[
                    if (failed || _problem != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _problem ?? tr.exportError(c.status.exportError),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    FilledButton.icon(
                      key: const ValueKey('export-start'),
                      onPressed: (_mix || _stems) && c.canExport ? _start : null,
                      icon: const Icon(Icons.file_download_outlined),
                      label: Text(tr.exportStart),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
