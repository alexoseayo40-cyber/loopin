// Loopin — ajustes de audio: entrada, monitor y latencia
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../engine/engine_controller.dart';
import 'latency_tap_screen.dart';

/// Qué hace cada modo del micrófono, en palabras sencillas.
String micModeHelp(InputPreset p) => switch (p) {
  InputPreset.unprocessed =>
    'El sonido tal cual llega al micrófono, sin ningún arreglo. Es el ideal para un '
        'instrumento. Si el móvil no lo admite, Android usa el modo Normal.',
  InputPreset.voicePerformance =>
    'Pensado para cantar o tocar en directo con poco retardo. No todos los móviles lo tienen.',
  InputPreset.voiceRecognition =>
    'El del dictado por voz. Android le obliga a no subir ni bajar el volumen solo, así '
        'que suena natural, pero en algunos móviles tiene más retardo.',
  InputPreset.camcorder => 'El que usa la cámara al grabar vídeo. Puede llevar filtros.',
  InputPreset.generic =>
    'El de una grabación cualquiera. Puede subir y bajar el volumen solo, lo que '
        'estropea los loops.',
};

class AudioSettingsScreen extends StatelessWidget {
  const AudioSettingsScreen({super.key, required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.status;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Audio y latencia'),
            actions: [
              IconButton(
                tooltip: 'Copiar resultados',
                icon: const Icon(Icons.copy_all),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: controller.report()));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Resultados copiados')));
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              _AudioCard(controller: controller, s: s),
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
          Text(controller.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (s.running) ...[
          const SizedBox(height: 8),
          Text('$api · ${s.sampleRate} Hz · bloque ${s.framesPerBurst} muestras'),
          Text(
            '${s.exclusive ? 'Exclusivo' : 'Compartido'} · '
            '${s.lowLatency ? 'baja latencia' : 'SIN baja latencia'} · '
            'entrada ${s.inputChannels == 1 ? 'mono' : '${s.inputChannels} canales'}',
          ),
          if (s.playing)
            Text(
              'Cortes desde que arrancó el metrónomo: '
              '${controller.xrunsSincePlay < 0 ? 'no disponible' : controller.xrunsSincePlay}',
            ),
        ],
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
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Modo del micrófono',
            helperText: 'Cuánto «arregla» Android el sonido antes de que llegue a Loopin',
          ),
          items: [
            for (final p in InputPreset.values)
              DropdownMenuItem(
                value: p,
                child: Text(p.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (p) {
            if (p != null) c.setInputPreset(p);
          },
        ),
        const SizedBox(height: 6),
        Text(micModeHelp(c.inputPreset), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          'Si suenan igual, quédate con el que dé menos latencia (lo mides abajo). Solo se nota '
          'al escucharte en directo: los loops cuadran con cualquiera porque la latencia se compensa.',
          style: Theme.of(context).textTheme.bodySmall,
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
              child: Slider(max: 2, value: c.monitorVolume, onChanged: c.setMonitorVolume),
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
    final c = controller;
    final recordingNow = c.recordingNow;
    final estimate = (s.outputLatencyMs >= 0 && s.inputLatencyMs >= 0)
        ? s.outputLatencyMs + s.inputLatencyMs
        : -1.0;
    final source = switch (c.latencySource) {
      LatencySource.measured => 'medida',
      LatencySource.estimated => 'estimada por Android, sin medir',
      LatencySource.none => 'sin medir',
    };
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final current = c.compensationTargetMs.clamp(0.0, 500.0);
    return _Section(
      title: 'Latencia',
      children: [
        Text(
          'Lo que tarda el sonido en salir del móvil y volver a entrar. Loopin lo descuenta al '
          'grabar para que el loop caiga en el tiempo. Cambia según por dónde entra y sale el '
          'sonido (altavoz, cascos, interfaz), así que se guarda una para cada caso.',
          style: small,
        ),
        const SizedBox(height: 10),
        if (s.running) ...[
          Text('Ahora: ${c.routeLabel}', style: small),
          const SizedBox(height: 2),
          Text(
            'Compensación: ${_ms(c.compensationMs)} ($source)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: c.latencySource == LatencySource.measured ? null : theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 12),
        ],
        // 1. Con el altavoz (automática)
        Text('Con el altavoz o una interfaz', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        FilledButton.tonalIcon(
          // No mientras se graba: los pulsos acabarían dentro del loop
          onPressed: s.running && !measuring && !recordingNow ? controller.measureLatency : null,
          icon: measuring
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.speed),
          label: Text(measuring ? 'Midiendo… clic ${s.latencyProgress}/5' : 'Medir sola'),
        ),
        const SizedBox(height: 4),
        switch (s.latencyState) {
          LatencyState.done => Text(
            'Medida: ${_ms(s.latencyMs)} · guardada',
            style: theme.textTheme.titleMedium,
          ),
          LatencyState.failed => Text(
            'No se oyeron los clics. Sube el volumen o revisa el cable.',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          _ => const SizedBox.shrink(),
        },
        Text(
          'Altavoz: sin cascos, volumen alto y en silencio. Interfaz: une con un cable la salida '
          'de auriculares y la entrada.',
          style: small,
        ),
        const SizedBox(height: 14),
        // 2. Tocando (cascos)
        Text('Con cascos', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        FilledButton.tonalIcon(
          onPressed: s.running && !recordingNow
              ? () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => LatencyTapScreen(controller: c)))
              : null,
          icon: const Icon(Icons.touch_app),
          label: const Text('Medir tocando al clic'),
        ),
        const SizedBox(height: 4),
        Text(
          'Con cascos el clic no vuelve al micrófono: tocas tú al ritmo de unos clics y se '
          'mide cuánto tarda tu golpe en llegar.',
          style: small,
        ),
        const SizedBox(height: 14),
        // 3. A mano
        Text('A mano', style: theme.textTheme.titleSmall),
        Row(
          children: [
            IconButton(
              tooltip: 'Restar 1 ms',
              onPressed: s.running && !recordingNow
                  ? () => c.setLatencyManually(current - 1)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Slider(
                max: 500,
                divisions: 500,
                value: current,
                label: '${current.round()} ms',
                onChanged: s.running && !recordingNow
                    ? (v) => c.setLatencyManually(v.roundToDouble())
                    : null,
                semanticFormatterCallback: (v) => '${v.round()} milisegundos',
              ),
            ),
            IconButton(
              tooltip: 'Sumar 1 ms',
              onPressed: s.running && !recordingNow
                  ? () => c.setLatencyManually(current + 1)
                  : null,
              icon: const Icon(Icons.add),
            ),
            SizedBox(width: 64, child: Text('${current.round()} ms', textAlign: TextAlign.end)),
          ],
        ),
        Text(
          'Para afinar a oído: graba un loop con el clic encendido dando golpes secos en los '
          'tiempos y mueve esto hasta que el loop y el clic suenen a la vez. Lo grabado se '
          'mueve contigo. Si el loop suena tarde, sube; si suena antes, baja.',
          style: small,
        ),
        if (c.latencySource == LatencySource.measured)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: c.forgetLatency,
              child: const Text('Olvidar la latencia de esta ruta'),
            ),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Detalles'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Estimación de Android: salida ${_ms(s.outputLatencyMs)} + entrada '
                '${_ms(s.inputLatencyMs)} = ${_ms(estimate)}\n'
                'Buffer de salida: ${s.bufferSizeFrames} muestras (${_ms(s.bufferMs)})\n'
                '${s.running ? 'Entrada: ${s.inputExclusive ? 'exclusivo' : 'compartido'} · '
                          '${s.inputLowLatency ? 'baja latencia' : 'SIN baja latencia'} · '
                          'bloque ${s.inputFramesPerBurst} · buffer ${s.inputBufferFrames} · '
                          'máx. por callback ${s.inputMaxRead}' : ''}',
                style: small,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
