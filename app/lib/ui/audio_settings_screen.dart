// Loopin — ajustes de audio: entrada, micrófono, escucharte y latencia
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../engine/engine_controller.dart';
import '../l10n/strings.dart';
import 'help.dart';
import 'latency_tap_screen.dart';

class AudioSettingsScreen extends StatelessWidget {
  const AudioSettingsScreen({super.key, required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr.audioAndLatency),
        actions: [
          IconButton(
            tooltip: tr.copyResults,
            icon: const Icon(Icons.copy_all),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: controller.report()));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.resultsCopied)));
            },
          ),
        ],
      ),
      // Esta pantalla enseña cosas que cambian a cada momento (nivel, medidas,
      // carga): se redibuja con cada consulta al motor
      body: ListenableBuilder(
        listenable: Listenable.merge([controller, controller.live]),
        builder: (context, _) {
          final s = controller.status;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                children: [
                  _PowerCard(controller: controller),
                  _InputCard(controller: controller, s: s),
                  _LatencyCard(controller: controller, s: s),
                  // En simple: sin modos del micro, latencia a mano ni detalles
                  if (!controller.simple)
                    _DetailsCard(controller: controller, s: s)
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                      child: Text(tr.moreInAdvanced, style: Theme.of(context).textTheme.bodySmall),
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.help});

  final String title;
  final String? help;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(title, help: help, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _PowerCard extends StatelessWidget {
  const _PowerCard({required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final on = controller.wantRunning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: on ? controller.stopAudio : controller.startAudio,
            icon: Icon(on ? Icons.power_settings_new : Icons.play_circle),
            label: Text(on ? tr.turnAudioOff : tr.turnAudioOn),
          ),
          if (controller.error != null) ...[
            const SizedBox(height: 8),
            Text(controller.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entrada

class _InputCard extends StatelessWidget {
  const _InputCard({required this.controller, required this.s});

  final EngineController controller;
  final EngineStatus s;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final peak = s.inputPeak.clamp(0.0, 1.0);
    return _Section(
      title: tr.input,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: DropdownButtonFormField<int>(
            key: ValueKey('in-${c.inputDeviceId}-${c.inputDevices.length}'),
            initialValue: c.inputDeviceId < 0 ? 0 : c.inputDeviceId,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr.inputDevice),
            onTap: c.refreshDevices,
            items: [
              DropdownMenuItem(value: 0, child: Text(tr.inputAuto)),
              for (final d in c.inputDevices)
                DropdownMenuItem(
                  value: d.id,
                  child: Text(tr.deviceName(d), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) {
              if (id != null) c.setInputDevice(id);
            },
          ),
        ),
        if (!c.simple) ...[
          const SizedBox(height: 8),
          SectionTitle(tr.micMode, help: tr.micModeHelp, style: theme.textTheme.titleSmall),
          _MicModes(controller: c),
          if (s.running && s.presetFallback && s.inputPreset != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(
                tr.presetFallback(s.inputPreset!),
                style: small?.copyWith(color: theme.colorScheme.error),
              ),
            ),
        ],
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            children: [
              Text(tr.level),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  label: tr.inputLevel,
                  value: tr.percent(peak),
                  child: LinearProgressIndicator(
                    value: peak,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                    color: peak > 0.9 ? Colors.red : (peak > 0.6 ? Colors.orange : Colors.green),
                  ),
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            SizedBox(width: 104, child: Text(tr.gain(c.inputGainDb))),
            Expanded(
              child: Slider(
                max: 24,
                divisions: 24,
                value: c.inputGainDb,
                onChanged: c.setInputGainDb,
              ),
            ),
          ],
        ),
        Text(tr.gainLine, style: small),
        const SizedBox(height: 4),
        OptionTile.toggle(
          padding: EdgeInsets.zero,
          title: tr.monitorTitle,
          subtitle: tr.monitorLine,
          help: tr.monitorHelp,
          value: c.monitorEnabled,
          onChanged: c.setMonitorEnabled,
        ),
        Row(
          children: [
            const Icon(Icons.volume_up, size: 20),
            Expanded(
              child: Slider(
                max: 2,
                value: c.monitorVolume,
                onChanged: c.setMonitorVolume,
                semanticFormatterCallback: (v) => '${tr.monitorVolume}: ${tr.percent(v / 2)}',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Los modos del micrófono, una línea cada uno. Se ve el que conviene en este
/// móvil (RECOMENDADO) y los demás van plegados en «Otros modos» (abiertos si
/// el elegido es uno de ellos).
class _MicModes extends StatefulWidget {
  const _MicModes({required this.controller});

  final EngineController controller;

  @override
  State<_MicModes> createState() => _MicModesState();
}

class _MicModesState extends State<_MicModes> {
  late bool _others = widget.controller.inputPreset != widget.controller.recommendedPreset;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    final recommended = c.recommendedPreset;
    final others = [
      for (final p in InputPreset.values)
        if (p != recommended) p,
    ];

    Widget tile(InputPreset p) => RadioListTile<InputPreset>(
      key: ValueKey('preset-${p.name}'),
      value: p,
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      title: Row(
        children: [
          Flexible(child: Text(tr.presetName(p))),
          if (p == recommended) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tr.recommended,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        p == InputPreset.unprocessed && c.unprocessedSupported == false
            ? tr.unprocessedUnsupported
            : tr.presetLine(p),
      ),
    );

    return RadioGroup<InputPreset>(
      groupValue: c.inputPreset,
      onChanged: (p) {
        if (p != null) c.setInputPreset(p);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile(recommended),
          // Pulsar otra vez no lo pliega si el elegido está dentro
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('preset-others'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => setState(() => _others = !_others || c.inputPreset != recommended),
              icon: Icon(_others ? Icons.expand_less : Icons.expand_more),
              label: Text(tr.micOtherModes(others.length)),
            ),
          ),
          if (_others) ...[for (final p in others) tile(p)],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Latencia

class _LatencyCard extends StatelessWidget {
  const _LatencyCard({required this.controller, required this.s});

  final EngineController controller;
  final EngineStatus s;

  @override
  Widget build(BuildContext context) {
    final measuring = s.latencyState == LatencyState.running;
    final c = controller;
    final canMeasure = s.running && !c.recordingNow;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final current = c.compensationTargetMs.clamp(0.0, 500.0);
    final measured = c.latencySource == LatencySource.measured;
    return _Section(
      title: tr.latency,
      help: tr.latencyHelp,
      children: [
        if (s.running) ...[
          Text(tr.route(c.routeLabel), style: small),
          const SizedBox(height: 2),
          Text(
            tr.compensation(
              tr.ms(c.compensationMs),
              tr.latencySourceName(measured, c.latencySource == LatencySource.estimated),
            ),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: measured ? null : theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (c.recordingNow)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(tr.finishRecordingFirst, style: small),
          ),
        // 1. Con el altavoz o una interfaz (sola)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton.tonalIcon(
            // No mientras se graba: los pulsos acabarían dentro del loop
            onPressed: canMeasure && !measuring ? c.measureLatency : null,
            icon: measuring
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed),
            label: Text(measuring ? tr.measuringClick(s.latencyProgress) : tr.measureAlone),
          ),
        ),
        switch (s.latencyState) {
          LatencyState.done => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr.measured(tr.ms(s.latencyMs)), style: theme.textTheme.titleMedium),
          ),
          LatencyState.failed => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr.clicksNotHeard, style: TextStyle(color: theme.colorScheme.error)),
          ),
          _ => const SizedBox.shrink(),
        },
        HelpLine(tr.measureAloneLine, help: tr.measureAloneHelp),
        const SizedBox(height: 8),
        // 2. Tocando al clic (cascos)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton.tonalIcon(
            onPressed: canMeasure
                ? () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => LatencyTapScreen(controller: c)))
                : null,
            icon: const Icon(Icons.touch_app),
            label: Text(tr.measureTapping),
          ),
        ),
        HelpLine(tr.measureTappingLine, help: tr.measureTappingHelp),
        // 3. A mano (solo en el avanzado)
        if (!c.simple) ..._byHand(context, current, canMeasure, measured),
      ],
    );
  }

  List<Widget> _byHand(BuildContext context, double current, bool canMeasure, bool measured) {
    final c = controller;
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 8),
      Text(tr.byHand, style: theme.textTheme.titleSmall),
      Row(
        children: [
          IconButton(
            tooltip: tr.minus1ms,
            onPressed: canMeasure ? () => c.setLatencyManually(current - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Slider(
              max: 500,
              divisions: 500,
              value: current,
              label: tr.msValue(current.round()),
              onChanged: canMeasure ? (v) => c.setLatencyManually(v.roundToDouble()) : null,
              semanticFormatterCallback: (v) => tr.msSemantics(v.round()),
            ),
          ),
          IconButton(
            tooltip: tr.plus1ms,
            onPressed: canMeasure ? () => c.setLatencyManually(current + 1) : null,
            icon: const Icon(Icons.add),
          ),
          SizedBox(width: 60, child: Text(tr.msValue(current.round()), textAlign: TextAlign.end)),
        ],
      ),
      HelpLine(tr.byHandLine, help: tr.byHandHelp),
      if (measured)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: c.forgetLatency, child: Text(tr.forgetLatency)),
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Detalles técnicos (plegados)

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.controller, required this.s});

  final EngineController controller;
  final EngineStatus s;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final api = switch (s.audioApi) {
      AudioApi.aaudio => 'AAudio',
      AudioApi.openSles => 'OpenSL ES',
      AudioApi.unknown => '—',
    };
    final estimate = (s.outputLatencyMs >= 0 && s.inputLatencyMs >= 0)
        ? s.outputLatencyMs + s.inputLatencyMs
        : -1.0;
    String mode(bool exclusive) => exclusive ? tr.exclusiveMode : tr.sharedMode;
    String low(bool on) => on ? tr.lowLatency : tr.noLowLatency;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        title: Text(tr.technicalDetails),
        shape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.running) ...[
            Text(
              [
                tr.detailsStream(api, s.sampleRate, s.framesPerBurst),
                tr.detailsOutput(
                  mode(s.exclusive),
                  low(s.lowLatency),
                  s.bufferSizeFrames,
                  tr.ms(s.bufferMs),
                ),
                tr.detailsInput(
                  mode(s.inputExclusive),
                  low(s.inputLowLatency),
                  tr.channels(s.inputChannels),
                  s.inputFramesPerBurst,
                  s.inputBufferFrames,
                  s.inputMaxRead,
                ),
                tr.detailsEstimate(
                  tr.ms(s.outputLatencyMs),
                  tr.ms(s.inputLatencyMs),
                  tr.ms(estimate),
                ),
                if (s.playing) tr.detailsXruns(controller.xrunsSincePlay),
              ].join('\n'),
              style: small,
            ),
            HelpLine(
              tr.engineLoad(
                tr.percent(s.cpuLoad),
                tr.percent(s.cpuLoadPeak),
                tr.percent(s.cpuLoadMax),
              ),
              help: tr.engineLoadHelp,
            ),
          ] else
            Text('—', style: small),
        ],
      ),
    );
  }
}
