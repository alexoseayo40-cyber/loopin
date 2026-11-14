// Loopin — sesiones: la abierta, las guardadas y exportar (Etapa 6)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../engine/engine_controller.dart';
import '../l10n/strings.dart';
import 'export_sheet.dart';
import 'help.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key, required this.controller});

  final EngineController controller;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  EngineController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.refreshSessions();
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _rename(Session s) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: s.name),
    );
    if (name != null) await c.renameSession(s, name);
  }

  Future<void> _delete(Session s, {required bool open}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.sessionDeleteTitle(s.name)),
        content: Text(open ? tr.sessionDeleteOpenBody : tr.sessionDeleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr.cancel)),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr.sessionDelete),
          ),
        ],
      ),
    );
    if (ok == true) await c.deleteSession(s);
  }

  Future<void> _duplicate(Session s) async {
    final copy = await c.duplicateSession(s);
    if (!mounted) return;
    _say(copy == null ? tr.sessionDuplicateEmpty : tr.sessionDuplicated(copy.name));
  }

  Future<void> _open(Session s) async {
    if (!c.canSwitchSession) {
      _say(tr.sessionBusy);
      return;
    }
    final ok = await c.openSession(s);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      _say(tr.sessionOpenFailed);
    }
  }

  Future<void> _new() async {
    if (!c.canSwitchSession) {
      _say(tr.sessionBusy);
      return;
    }
    await c.newSession();
    if (mounted) Navigator.of(context).pop();
  }

  void _export() => showExportSheet(context, c);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr.sessionsTitle),
        actions: [
          IconButton(
            key: const ValueKey('new-session'),
            tooltip: tr.sessionNew,
            onPressed: _new,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final open = c.session;
          final others = [
            for (final s in c.savedSessions)
              if (s.id != open?.id) s,
          ];
          final theme = Theme.of(context);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (c.sessionLoading) const LinearProgressIndicator(),
                  if (c.sessionSaveFailed)
                    Card(
                      key: const ValueKey('save-failed'),
                      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tr.saveFailedLine(c.sessionSaveNoSpace),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: theme.colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr.saveFailedBody(c.sessionSaveNoSpace),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SectionTitle(
                    tr.sessionsHow,
                    help: tr.sessionsHelp,
                    padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
                  ),
                  if (open != null)
                    Card(
                      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr.sessionOpenNow, style: theme.textTheme.labelMedium),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    open.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey('rename-open'),
                                  tooltip: tr.sessionRename,
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _rename(open),
                                ),
                                _Menu(
                                  onDuplicate: c.status.hasLoops ? () => _duplicate(open) : null,
                                  onDelete: () => _delete(open, open: true),
                                ),
                              ],
                            ),
                            Text(
                              c.status.hasLoops ? tr.sessionSummary(_live(c)) : tr.sessionEmptyNow,
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  key: const ValueKey('export'),
                                  onPressed: c.canExport ? _export : null,
                                  icon: const Icon(Icons.ios_share),
                                  label: Text(tr.exportButton),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _new,
                                  icon: const Icon(Icons.add),
                                  label: Text(tr.sessionNew),
                                ),
                              ],
                            ),
                            if (c.recordingNow)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(tr.sessionBusy, style: theme.textTheme.bodySmall),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(tr.sessionsSaved, style: theme.textTheme.titleSmall),
                  ),
                  if (others.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text(tr.sessionsEmpty, style: theme.textTheme.bodyMedium),
                    ),
                  for (final s in others)
                    ListTile(
                      leading: const Icon(Icons.album_outlined),
                      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${tr.sessionSummary(_saved(s))} · ${tr.sessionWhen(s.updated, DateTime.now())}',
                      ),
                      onTap: () => _open(s),
                      trailing: _Menu(
                        onOpen: () => _open(s),
                        onRename: () => _rename(s),
                        onDuplicate: () => _duplicate(s),
                        onDelete: () => _delete(s, open: false),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Lo que se cuenta de una sesión: tempo, compás, pistas y compases.
typedef SessionFacts = ({String bpm, String meter, int tracks, int bars});

SessionFacts _saved(Session s) =>
    (bpm: tr.bpmNumber(s.bpm), meter: s.meter, tracks: s.trackCount, bars: s.cycleBars);

SessionFacts _live(EngineController c) {
  final s = c.status;
  final longest = s.tracks.fold<int>(0, (m, t) => t.length > m ? t.length : m);
  return (
    bpm: tr.bpmNumber(s.bpm),
    meter: c.timeSignature.label,
    tracks: s.tracks.where((t) => t.hasLoop).length,
    bars: s.loopBarFrames > 0 ? (longest / s.loopBarFrames).round() : 0,
  );
}

class _Menu extends StatelessWidget {
  const _Menu({this.onOpen, this.onRename, this.onDuplicate, required this.onDelete});

  final VoidCallback? onOpen;
  final VoidCallback? onRename;
  final VoidCallback? onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: tr.sessionOptions,
      onSelected: (f) => f(),
      itemBuilder: (_) => [
        if (onOpen != null) PopupMenuItem(value: onOpen, child: Text(tr.sessionOpen)),
        if (onRename != null) PopupMenuItem(value: onRename, child: Text(tr.sessionRename)),
        if (onDuplicate != null)
          PopupMenuItem(value: onDuplicate, child: Text(tr.sessionDuplicate)),
        PopupMenuItem(value: onDelete, child: Text(tr.sessionDelete)),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr.sessionRename),
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: tr.sessionNameLabel),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr.cancel)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: Text(tr.sessionRenameSave),
        ),
      ],
    );
  }
}
