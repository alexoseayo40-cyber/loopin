// Loopin — pantalla de prueba de la Etapa 1
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../engine/engine_controller.dart';

class PrototypeScreen extends StatelessWidget {
  const PrototypeScreen({super.key, required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.status;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Loopin · prueba de audio'),
            actions: [
              IconButton(
                tooltip: 'Copiar resultados',
                icon: const Icon(Icons.copy_all),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: controller.report()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Resultados copiados')),
                  );
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              _AudioCard(controller: controller, s: s),
              _MetronomeCard(controller: controller, s: s),
              _MonitorCard(controller: controller, s: s),
              _LatencyCard(controller: controller, s: s),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _AudioCard extends StatelessWidget {
  const _AudioCard({required this.controller, required this.s});
  final EngineController controller;
  final EngineStatus s;

  @override
  Widget build(BuildContext context) {
    final on = controller.wantRunning;
    final api = switch (s.audioApi) {
      AudioApi.aaudio => 'AAudio',
      AudioApi.openSles => 'OpenSL ES',
      AudioApi.unknown => '—',
    };
    return _Section(
      title: 'Audio',
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: on ? controller.stopAudio : controller.startAudio,
          icon: Icon(on ? Icons.power_settings_new : Icons.play_circle),
          label: Text(on ? 'Apagar audio' : 'Encender audio'),
        ),
        if (controller.error != null) ...[
          const SizedBox(height: 8),
          Text(controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (s.running) ...[
          const SizedBox(height: 8),
          Text('$api · ${s.sampleRate} Hz · bloque ${s.framesPerBurst} muestras'),
          Text('${s.exclusive ? 'Exclusivo' : 'Compartido'} · '
              '${s.lowLatency ? 'baja latencia' : 'SIN baja latencia'} · '
              'entrada ${s.inputChannels == 1 ? 'mono' : '${s.inputChannels} canales'}'),
        ],
      ],
    );
  }
}

class _MetronomeCard extends StatelessWidget {
  const _MetronomeCard({required this.controller, required this.s});
  final EngineController controller;
  final EngineStatus s;

  String _mmss(double seconds) {
    final t = seconds.floor();
    return '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bpm = controller.bpm;
    final xruns = controller.xrunsSincePlay;
    final stable = s.playSeconds >= 300 && xruns == 0;
    return _Section(
      title: 'Metrónomo',
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: () => controller.setBpm(bpm - 1),
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 140,
              child: Text(
                '${bpm.toStringAsFixed(0)} BPM',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton.filledTonal(
              onPressed: () => controller.setBpm(bpm + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        Slider(
          min: 40,
          max: 240,
          value: bpm,
          onChanged: controller.setBpm,
        ),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<int>(
                segments: [
                  for (final e in kTimeSignatures.entries)
                    ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {controller.beatsPerBar},
                onSelectionChanged: (v) => controller.setBeatsPerBar(v.first),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: controller.tapTempo,
              child: const Text('Tap'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Tiempos del compás
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < s.beatsPerBar; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.playing && s.beat == i
                      ? (i == 0 ? cs.primary : cs.secondary)
                      : cs.surfaceContainerHighest,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: s.running ? controller.togglePlay : null,
          icon: Icon(s.playing ? Icons.stop : Icons.play_arrow),
          label: Text(s.playing ? 'Parar' : 'Arrancar metrónomo'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Clic'),
          value: controller.clickEnabled,
          onChanged: controller.setClickEnabled,
        ),
        Row(
          children: [
            const Icon(Icons.volume_up, size: 20),
            Expanded(
              child: Slider(value: controller.clickVolume, onChanged: controller.setClickVolume),
            ),
          ],
        ),
        if (s.playing)
          Row(
            children: [
              Icon(stable ? Icons.check_circle : Icons.timer_outlined,
                  color: stable ? Colors.green : null, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sonando ${_mmss(s.playSeconds)} · compás ${s.bar + 1} · '
                  'cortes: ${xruns < 0 ? 'no disponible' : xruns}',
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _MonitorCard extends StatelessWidget {
  const _MonitorCard({required this.controller, required this.s});
  final EngineController controller;
  final EngineStatus s;

  @override
  Widget build(BuildContext context) {
    final peak = s.inputPeak.clamp(0.0, 1.0);
    final c = controller;
    final unprocessed = c.deviceInfo['unprocessed'];
    return _Section(
      title: 'Guitarra (entrada)',
      children: [
        DropdownButtonFormField<int>(
          key: ValueKey('in-${c.inputDeviceId}-${c.inputDevices.length}'),
          initialValue: c.inputDeviceId < 0 ? 0 : c.inputDeviceId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Entrada'),
          onTap: c.refreshDevices,
          items: [
            const DropdownMenuItem(value: 0, child: Text('Automática (la elige Android)')),
            for (final d in c.inputDevices)
              DropdownMenuItem(
                value: d.id,
                child: Text(d.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            if (id != null) c.setInputDevice(id);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<InputPreset>(
          initialValue: c.inputPreset,
          decoration: const InputDecoration(labelText: 'Modo del micrófono'),
          items: [
            for (final p in InputPreset.values)
              DropdownMenuItem(value: p, child: Text(p.label)),
          ],
          onChanged: (p) {
            if (p != null) c.setInputPreset(p);
          },
        ),
        const SizedBox(height: 6),
        if (s.running)
          Text(
            'Entra por: ${c.deviceLabel(s.inputDeviceId, input: true)}\n'
            'Sale por: ${c.deviceLabel(s.outputDeviceId, input: false)}\n'
            'Modo: ${s.inputPreset?.label ?? '—'}'
            '${s.presetFallback ? ' (el modo elegido no funciona en este móvil)' : ''}'
            '${unprocessed == null ? '' : ' · sin procesar admitido: ${unprocessed == true ? 'sí' : 'no'}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Nivel'),
            const SizedBox(width: 12),
            Expanded(
              child: LinearProgressIndicator(
                value: peak,
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
                color: peak > 0.9 ? Colors.red : (peak > 0.6 ? Colors.orange : Colors.green),
              ),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(width: 90, child: Text('Ganancia +${c.inputGainDb.toStringAsFixed(0)} dB')),
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
        Text(
          'Toca fuerte: el nivel debe llegar a naranja sin ponerse rojo.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Escucharme en directo'),
          subtitle: const Text('Con auriculares de cable. Por el altavoz se acopla.'),
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
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LatencyCard extends StatelessWidget {
  const _LatencyCard({required this.controller, required this.s});
  final EngineController controller;
  final EngineStatus s;

  String _ms(double v) => v < 0 ? '—' : '${v.toStringAsFixed(1)} ms';

  @override
  Widget build(BuildContext context) {
    final measuring = s.latencyState == LatencyState.running;
    final estimate = (s.outputLatencyMs >= 0 && s.inputLatencyMs >= 0)
        ? s.outputLatencyMs + s.inputLatencyMs
        : -1.0;
    return _Section(
      title: 'Latencia',
      children: [
        Text('Estimación de Android: salida ${_ms(s.outputLatencyMs)} + '
            'entrada ${_ms(s.inputLatencyMs)} = ${_ms(estimate)}'),
        Text('Buffer de salida: ${s.bufferSizeFrames} muestras (${_ms(s.bufferMs)})'),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: s.running && !measuring ? controller.measureLatency : null,
          icon: measuring
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.speed),
          label: Text(measuring
              ? 'Midiendo… clic ${s.latencyProgress}/5'
              : 'Medir latencia de ida y vuelta'),
        ),
        const SizedBox(height: 8),
        switch (s.latencyState) {
          LatencyState.done => Text(
              'Ida y vuelta: ${_ms(s.latencyMs)} (${s.latencyFrames} muestras)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          LatencyState.failed => Text(
              'No se oyeron los clics. Sube el volumen o revisa el cable.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          _ => const SizedBox.shrink(),
        },
        const SizedBox(height: 8),
        Text(
          'Altavoz y micro: sin cascos, volumen alto y en silencio.\n'
          'Cascos y micro: pon un auricular pegado al micro de abajo del móvil.\n'
          'Interfaz USB: une con un cable la salida de auriculares y la entrada.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
