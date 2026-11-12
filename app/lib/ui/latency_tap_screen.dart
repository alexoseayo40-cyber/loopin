// Loopin — medir la latencia tocando al clic (para cascos)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../engine/engine_controller.dart';
import '../l10n/strings.dart';
import 'help.dart';

class LatencyTapScreen extends StatefulWidget {
  const LatencyTapScreen({super.key, required this.controller});

  final EngineController controller;

  @override
  State<LatencyTapScreen> createState() => _LatencyTapScreenState();
}

class _LatencyTapScreenState extends State<LatencyTapScreen> with SingleTickerProviderStateMixin {
  // Destello en cada clic
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  int _lastClicks = 0;

  @override
  void initState() {
    super.initState();
    // Los clics cambian a cada momento: llegan por live
    widget.controller.live.addListener(_onChange);
  }

  void _onChange() {
    final clicks = widget.controller.status.tapClicks;
    final running = widget.controller.status.tapState == LatencyState.running;
    if (running && clicks > _lastClicks) _flash.forward(from: 0);
    _lastClicks = running ? clicks : 0;
  }

  @override
  void dispose() {
    widget.controller.live.removeListener(_onChange);
    // Si se sale a medias, se para
    if (widget.controller.status.tapState == LatencyState.running) {
      widget.controller.cancelTapCalibration();
    }
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr.measureTappingTitle)),
      body: ListenableBuilder(
        listenable: Listenable.merge([c, c.live]),
        builder: (context, _) {
          final s = c.status;
          final running = s.tapState == LatencyState.running;
          final ms = s.sampleRate > 0 ? 1000 / s.sampleRate : 0.0;
          final countIn = EngineStatus.tapCountInClicks;
          // Clic que acaba de sonar (1..16)
          final click = s.tapClicks;
          final counting = running && click > countIn;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(tr.tapIntro, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Text(tr.tapSteps),
                  const SizedBox(height: 24),
                  // El clic que suena, también a la vista; el botón, justo debajo para
                  // que no se mueva al aparecer el resultado
                  Center(
                    child: AnimatedBuilder(
                      animation: _flash,
                      builder: (context, _) {
                        final v = running ? 1 - _flash.value : 0.0;
                        final base = counting
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline;
                        return Container(
                          width: 140,
                          height: 140,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color.lerp(theme.colorScheme.surfaceContainerHighest, base, v),
                          ),
                          child: Text(
                            running
                                ? (click <= countIn
                                      ? tr.tapListen(click)
                                      : tr.tapCount(click - countIn, EngineStatus.tapCountedClicks))
                                : '',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: !s.running || c.recordingNow
                        ? null
                        : (running ? c.cancelTapCalibration : c.startTapCalibration),
                    icon: Icon(running ? Icons.stop : Icons.play_arrow),
                    label: Text(
                      running
                          ? tr.tapStop
                          : (s.tapState == LatencyState.idle ? tr.tapStart : tr.tapRepeat),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (running)
                    Text(
                      counting ? tr.tapHits(s.tapHits) : tr.tapGetReady,
                      textAlign: TextAlign.center,
                    ),
                  if (s.tapState == LatencyState.done) ...[
                    Text(
                      tr.tapResult((s.tapFrames * ms).round()),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr.tapQuality((s.tapSpread * ms).round(), s.tapHits),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (s.tapState == LatencyState.failed)
                    Text(
                      tr.tapFailed,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  if (c.recordingNow)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(tr.finishRecordingFirst, textAlign: TextAlign.center),
                    ),
                  const SizedBox(height: 16),
                  HelpLine(tr.tapWhat, help: tr.tapHelp),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
