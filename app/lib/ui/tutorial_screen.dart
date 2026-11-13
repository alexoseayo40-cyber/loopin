// Loopin — guía de la primera vez: modo, pulsador, tempo, latencia y
// sesiones (Etapa 6)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Sale sola la primera vez que se abre la app (instalaciones nuevas) y desde
// Ajustes › «Ver la guía».
import 'package:flutter/material.dart';

import '../engine/engine_controller.dart';
import '../l10n/strings.dart';
import 'pedal_widgets.dart';
import 'theme.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.controller, this.onMeasure});

  final EngineController controller;

  /// «Medir ahora» en la página de la latencia (abre «Audio y latencia»).
  final VoidCallback? onMeasure;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final PageController _pages = PageController();
  int _page = 0;
  static const _count = 5;

  EngineController get c => widget.controller;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _finish({bool measure = false}) {
    c.setTutorialDone();
    Navigator.of(context).pop();
    if (measure) widget.onMeasure?.call();
  }

  void _next() {
    if (_page >= _count - 1) {
      _finish();
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = LoopinPalette.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey('tutorial-skip'),
                  onPressed: _finish,
                  child: Text(tr.tutorialSkip),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (p) => setState(() => _page = p),
                  children: [
                    _Page(
                      title: tr.tutorialWelcome,
                      body: tr.tutorialWelcomeBody,
                      child: Column(
                        children: [
                          for (final m in PlayMode.values)
                            Card(
                              key: ValueKey('tutorial-mode-${m.name}'),
                              color: c.playMode == m ? theme.colorScheme.primaryContainer : null,
                              child: ListTile(
                                leading: Icon(
                                  c.playMode == m
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                ),
                                title: Text(tr.playModeName(m)),
                                subtitle: Text(tr.tutorialModeLine(m)),
                                onTap: () => c.setPlayMode(m),
                              ),
                            ),
                          Text(tr.tutorialModeLater, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    _Page(
                      title: tr.tutorialPedal,
                      body: tr.tutorialPedalBody,
                      child: Column(
                        children: [
                          IgnorePointer(
                            child: Footswitch(
                              size: 120,
                              color: LoopinPalette.rec,
                              progress: 0.7,
                              icon: Icons.stop,
                              onDown: () {},
                              onUp: () {},
                              semanticLabel: '',
                            ),
                          ),
                          const SizedBox(height: 16),
                          _Gesture(Icons.touch_app, tr.tutorialTap),
                          _Gesture(Icons.back_hand_outlined, tr.tutorialHold),
                          _Gesture(Icons.ads_click, tr.tutorialDouble),
                        ],
                      ),
                    ),
                    _Page(
                      title: tr.tutorialTempo,
                      body: tr.tutorialTempoBody,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: LoopinPalette.well,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '−  92 BPM  +',
                              style: TextStyle(
                                fontFamily: LoopinFonts.display,
                                fontSize: 30,
                                color: LoopinPalette.display,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(tr.tapTempo, style: palette.label(size: 14)),
                          const SizedBox(height: 16),
                          _Gesture(Icons.timer_outlined, tr.tutorialCount),
                          _Gesture(Icons.light_mode_outlined, tr.tutorialLights),
                        ],
                      ),
                    ),
                    _Page(
                      title: tr.tutorialLatency,
                      body: tr.tutorialLatencyBody,
                      child: Column(
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('tutorial-measure'),
                            onPressed: widget.onMeasure == null
                                ? null
                                : () => _finish(measure: true),
                            icon: const Icon(Icons.speed),
                            label: Text(tr.tutorialMeasureNow),
                          ),
                          const SizedBox(height: 8),
                          Text(tr.tutorialMeasureLater, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    _Page(
                      title: tr.tutorialSaved,
                      body: tr.tutorialSavedBody,
                      child: Column(
                        children: [
                          _Gesture(Icons.library_music_outlined, tr.tutorialSessions),
                          _Gesture(Icons.ios_share, tr.tutorialExport),
                          _Gesture(Icons.fullscreen, tr.tutorialStage),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    for (var i = 0; i < _count; i++)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _page
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                    const Spacer(),
                    FilledButton(
                      key: const ValueKey('tutorial-next'),
                      onPressed: _next,
                      child: Text(_page == _count - 1 ? tr.tutorialStart : tr.tutorialNext),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.body, required this.child});

  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(body, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _Gesture extends StatelessWidget {
  const _Gesture(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
