// Loopin — canciones importadas: elegir, importar, preparar y borrar
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../engine/engine_controller.dart';
import '../l10n/strings.dart';
import 'help.dart';
import 'song_screen.dart';

class SongsScreen extends StatefulWidget {
  const SongsScreen({super.key, required this.controller});

  final EngineController controller;

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> {
  bool _importing = false;

  EngineController get c => widget.controller;

  Future<void> _import() async {
    setState(() => _importing = true);
    Song? song;
    String? problem;
    try {
      song = await c.importSong();
    } on ImportException catch (e) {
      problem = tr.importError(e.error);
    }
    if (!mounted) return;
    setState(() => _importing = false);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    // Recién importada: a prepararla (tempo y 1)
    if (song != null) _prepare(song);
  }

  void _prepare(Song song) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SongScreen(controller: c, song: song),
      ),
    );
  }

  /// Tocar una preparada la elige (y vuelve al looper); una sin preparar, a
  /// prepararla.
  void _choose(Song song) {
    if (!song.ready) {
      _prepare(song);
      return;
    }
    c.selectSong(song);
    Navigator.of(context).pop();
  }

  Future<void> _delete(Song song) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.songDeleteTitle(song.name)),
        content: Text(tr.songDeleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr.songDelete)),
        ],
      ),
    );
    if (ok == true) await c.deleteSong(song);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr.songsTitle),
        actions: [
          IconButton(
            tooltip: tr.songsImport,
            onPressed: _importing ? null : _import,
            icon: const Icon(Icons.library_add),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final songs = c.songs;
          final current = c.currentSong;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (_importing) ...[
                    const LinearProgressIndicator(),
                    Padding(padding: const EdgeInsets.all(16), child: Text(tr.importing)),
                  ],
                  SectionTitle(
                    tr.songsHow,
                    help: tr.songsHelp,
                    padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
                  ),
                  if (current != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        tr.backingPhase(
                          c.backingPhase,
                          bpm: tr.bpmNumber(c.status.bpm),
                          progress: c.backingProgress,
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (c.canRestoreSongTempo)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          c.restoreSongTempo();
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.restore),
                        label: Text(tr.songRestoreTempo(tr.bpmNumber(current!.bpm))),
                      ),
                    ),
                  if (songs.isEmpty) _Empty(onImport: _importing ? null : _import),
                  for (final s in songs)
                    _SongTile(
                      song: s,
                      selected: current?.id == s.id,
                      onTap: () => _choose(s),
                      onPrepare: () => _prepare(s),
                      onDelete: () => _delete(s),
                    ),
                  if (songs.isNotEmpty && current != null)
                    ListTile(
                      leading: const Icon(Icons.music_off),
                      title: Text(tr.songsNone),
                      onTap: () {
                        c.selectSong(null);
                        Navigator.of(context).pop();
                      },
                    ),
                  if (songs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        onPressed: _importing ? null : _import,
                        icon: const Icon(Icons.library_add),
                        label: Text(tr.songsImport),
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

class _Empty extends StatelessWidget {
  const _Empty({required this.onImport});

  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        children: [
          Icon(Icons.queue_music, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(tr.songsEmpty, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(tr.songsEmptyLine, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.library_add),
            label: Text(tr.songsImport),
          ),
        ],
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.selected,
    required this.onTap,
    required this.onPrepare,
    required this.onDelete,
  });

  final Song song;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPrepare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
      title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        song.ready
            ? tr.songSubtitle(tr.bpmNumber(song.bpm), song.meter, song.seconds)
            : tr.songNotReady,
      ),
      onTap: onTap,
      trailing: PopupMenuButton<int>(
        tooltip: tr.songOptions,
        onSelected: (v) => v == 0 ? onPrepare() : onDelete(),
        itemBuilder: (_) => [
          PopupMenuItem(value: 0, child: Text(tr.songPrepare)),
          PopupMenuItem(value: 1, child: Text(tr.songDelete)),
        ],
      ),
    );
  }
}
