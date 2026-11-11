// Loopin — pantalla del looper (Etapa 2: una pista)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../engine/engine_controller.dart';
import 'audio_settings_screen.dart';

class LooperScreen extends StatefulWidget {
  const LooperScreen({super.key, required this.controller});

  final EngineController controller;

  @override
  State<LooperScreen> createState() => _LooperScreenState();
}

class _LooperScreenState extends State<LooperScreen> {
  @override
  void initState() {
    super.initState();
    // El audio se enciende al abrir la app (pide el permiso del micro)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.controller.wantRunning) widget.controller.startAudio();
    });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AudioSettingsScreen(controller: widget.controller)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.status;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Loopin'),
            actions: [
              IconButton(
                tooltip: 'Copiar resultados',
                icon: const Icon(Icons.copy_all),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: c.report()));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Resultados copiados')));
                },
              ),
              IconButton(
                tooltip: 'Audio y latencia',
                icon: const Icon(Icons.tune),
                onPressed: _openSettings,
              ),
            ],
          ),
          body: SafeArea(
            // Si no cabe todo (móvil pequeño o letra grande) se desplaza
            child: LayoutBuilder(
              builder: (context, box) {
                final pedal = math.max(
                  170.0,
                  math.min(280.0, math.min(box.maxWidth * 0.8, box.maxHeight * 0.42)),
                );
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight - 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _TempoBar(controller: c, s: s),
                            const SizedBox(height: 10),
                            _BeatDots(s: s),
                            const SizedBox(height: 12),
                            _ModeRow(controller: c, s: s),
                            if (s.running && c.latencySource != LatencySource.measured)
                              _LatencyWarning(controller: c, onMeasure: _openSettings),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: s.running
                                ? _PedalButton(controller: c, s: s, size: pedal)
                                : _AudioOff(controller: c),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Toca: grabar / overdub · Mantén: deshacer · Doble toque: parar',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            _BottomBar(controller: c, s: s),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _TempoBar extends StatelessWidget {
  const _TempoBar({required this.controller, required this.s});
  final EngineController controller;
  final EngineStatus s;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final locked = c.tempoLocked;
    final bpm = locked ? s.bpm : c.bpm;
    return Row(
      children: [
        IconButton(
          onPressed: locked ? null : () => c.setBpm(c.bpm - 1),
          icon: const Icon(Icons.remove),
        ),
        Expanded(
          child: GestureDetector(
            onTap: locked ? null : c.tapTempo,
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (locked) const Icon(Icons.lock, size: 16),
                      if (locked) const SizedBox(width: 4),
                      Text(
                        '${bpm.toStringAsFixed(0)} BPM',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  locked ? 'fijo mientras haya loop' : 'toca aquí para marcar el tempo',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: locked ? null : () => c.setBpm(c.bpm + 1),
          icon: const Icon(Icons.add),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<int>(
          enabled: !locked,
          initialValue: c.beatsPerBar,
          onSelected: c.setBeatsPerBar,
          itemBuilder: (_) => [
            for (final e in kTimeSignatures.entries)
              PopupMenuItem(value: e.key, child: Text(e.value)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              kTimeSignatures[c.beatsPerBar] ?? '${c.beatsPerBar}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        IconButton(
          tooltip: c.clickEnabled ? 'Clic encendido' : 'Clic apagado',
          onPressed: () => c.setClickEnabled(!c.clickEnabled),
          icon: Icon(c.clickEnabled ? Icons.notifications_active : Icons.notifications_off),
        ),
      ],
    );
  }
}

class _BeatDots extends StatelessWidget {
  const _BeatDots({required this.s});
  final EngineStatus s;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < s.beatsPerBar; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: s.playing && s.beat == i
                  ? (i == 0 ? cs.primary : cs.secondary)
                  : cs.surfaceContainerHighest,
            ),
          ),
      ],
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.controller, required this.s});
  final EngineController controller;
  final EngineStatus s;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    // El modo solo cuenta al empezar a grabar
    final busy = s.loopState == LoopState.armed || s.loopState == LoopState.recording;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<LoopMode>(
          segments: [
            for (final m in LoopMode.values) ButtonSegment(value: m, label: Text(m.label)),
          ],
          selected: {c.loopMode},
          onSelectionChanged: busy ? null : (v) => c.setLoopMode(v.first),
        ),
        const SizedBox(height: 8),
        if (c.loopMode == LoopMode.sync)
          Row(
            children: [
              const Text('Compases'),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final b in kSyncBarOptions) ButtonSegment(value: b, label: Text('$b')),
                  ],
                  selected: {c.syncBars},
                  onSelectionChanged: busy ? null : (v) => c.setSyncBars(v.first),
                ),
              ),
            ],
          )
        else
          Text(
            'Graba y vuelve a tocar para cerrar: el loop se ajusta al compás más cercano.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _LatencyWarning extends StatelessWidget {
  const _LatencyWarning({required this.controller, required this.onMeasure});
  final EngineController controller;
  final VoidCallback onMeasure;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Latencia sin medir para esta salida: el loop puede ir desfasado.',
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
              TextButton(onPressed: onMeasure, child: const Text('Medir')),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioOff extends StatelessWidget {
  const _AudioOff({required this.controller});
  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              controller.error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton.icon(
          onPressed: controller.startAudio,
          icon: const Icon(Icons.power_settings_new),
          label: const Text('Encender audio'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// El botón grande: hace de pedal. Actúa al pulsar, no al soltar.

class _PedalButton extends StatelessWidget {
  const _PedalButton({required this.controller, required this.s, required this.size});
  final EngineController controller;
  final EngineStatus s;
  final double size;

  ({Color color, String title, String subtitle, double? progress}) _look(ColorScheme cs) {
    final bar = s.loopBarFrames;
    switch (s.loopState) {
      case LoopState.empty:
        return (
          color: cs.surfaceContainerHighest,
          title: 'Grabar',
          subtitle: 'con 1 compás de cuenta',
          progress: 0,
        );
      case LoopState.armed:
        final left = -s.loopRecorded;
        final beats = s.samplesPerBeat > 0 ? (left / s.samplesPerBeat).ceil() : 0;
        return (
          color: Colors.orange.shade800,
          title: '$beats',
          subtitle: 'prepárate…',
          progress: bar > 0 ? 1 - left / bar : null,
        );
      case LoopState.recording:
        final barNow = bar > 0 ? s.loopRecorded ~/ bar + 1 : 1;
        final target = bar > 0 ? s.loopTarget ~/ bar : 0;
        return (
          color: Colors.red.shade700,
          title: 'Grabando',
          subtitle: target > 0 ? 'compás $barNow de $target' : 'compás $barNow · toca para cerrar',
          progress: s.loopTarget > 0
              ? s.loopRecorded / s.loopTarget
              : (bar > 0 ? (s.loopRecorded % bar) / bar : null),
        );
      case LoopState.playing:
        return (
          color: Colors.green.shade700,
          title: 'Sonando',
          subtitle: 'toca para grabar encima',
          progress: s.loopLength > 0 ? s.loopPosition / s.loopLength : 0,
        );
      case LoopState.overdubbing:
        return (
          color: Colors.amber.shade700,
          title: 'Overdub',
          subtitle: 'toca para terminar',
          progress: s.loopLength > 0 ? s.loopPosition / s.loopLength : 0,
        );
      case LoopState.stopped:
        return (
          color: Colors.blueGrey.shade600,
          title: 'Parado',
          subtitle: 'toca para arrancar',
          progress: 0,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final look = _look(cs);
    final onColor = look.color.computeLuminance() > 0.4 ? Colors.black : Colors.white;
    return Listener(
      onPointerDown: (_) => controller.pedalDown(),
      onPointerUp: (_) => controller.pedalUp(),
      onPointerCancel: (_) => controller.pedalUp(),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: look.progress?.clamp(0.0, 1.0),
              strokeWidth: 8,
              backgroundColor: cs.surfaceContainerHigh,
              color: look.color,
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(shape: BoxShape.circle, color: look.color),
                padding: EdgeInsets.all(size * 0.12),
                // Si no cabe (pantalla pequeña, letra grande) se encoge
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: size * 0.66,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          look.title,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(color: onColor, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          look.subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: onColor.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller, required this.s});
  final EngineController controller;
  final EngineStatus s;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final peak = s.inputPeak.clamp(0.0, 1.0);
    final info = s.loopState.hasLoop
        ? '${s.loopBars.round()} compases · ${s.loopLayers} '
              '${s.loopLayers == 1 ? 'capa' : 'capas'}'
        : 'Sin loop';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(info, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: s.loopCanUndo ? c.undo : null,
                icon: const Icon(Icons.undo),
                label: const Text('Deshacer'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: s.loopState == LoopState.empty ? null : c.clearLoop,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Borrar'),
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.graphic_eq, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: LinearProgressIndicator(
                value: peak,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                color: peak > 0.9 ? Colors.red : (peak > 0.6 ? Colors.orange : Colors.green),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Escucharme'),
              selected: c.monitorEnabled,
              onSelected: c.setMonitorEnabled,
            ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.loop, size: 20),
            Expanded(
              child: Slider(max: 1.5, value: c.loopVolume, onChanged: c.setLoopVolume),
            ),
          ],
        ),
      ],
    );
  }
}
