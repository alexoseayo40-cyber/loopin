// Loopin — ajustes: apariencia, looper y controles externos
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../engine/engine_controller.dart';
import 'audio_settings_screen.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return PopScope(
      // Al salir se deja de esperar la tecla de un pedal
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && c.learning != null) c.cancelLearning();
      },
      child: _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListenableBuilder(
        listenable: Listenable.merge([c, c.appearance]),
        builder: (context, _) {
          return Center(
            child: ConstrainedBox(
              // En tablet o apaisado no se estira de lado a lado
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  const _Header('Apariencia'),
                  _AppearanceSection(controller: c),
                  const _Header('Looper'),
                  SwitchListTile(
                    title: const Text('Avance automático'),
                    subtitle: const Text(
                      'Al cerrar una pista se elige sola la siguiente vacía, así cada '
                      'toque graba una pista nueva. Apagado, todo va a la misma pista, '
                      'como en un pedal clásico.',
                    ),
                    value: c.autoAdvance,
                    onChanged: c.setAutoAdvance,
                  ),
                  const _Header('Controles externos'),
                  _ControlsSection(controller: c),
                  const _Header('Audio'),
                  ListTile(
                    leading: const Icon(Icons.graphic_eq),
                    title: const Text('Audio y latencia'),
                    subtitle: const Text('Entrada, micrófono, escucharte y medir la latencia'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => AudioSettingsScreen(controller: c)),
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

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final look = controller.appearance.value;
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('Sistema'),
                icon: Icon(Icons.brightness_auto),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Claro'),
                icon: Icon(Icons.light_mode),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Oscuro'),
                icon: Icon(Icons.dark_mode),
              ),
            ],
            showSelectedIcon: false,
            selected: {look.mode},
            onSelectionChanged: (v) => controller.setThemeMode(v.first),
          ),
          const SizedBox(height: 16),
          Text('Color del pedal', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final chassis in Chassis.values)
                _ChassisSwatch(
                  chassis: chassis,
                  palette: LoopinPalette.forChassis(chassis, brightness),
                  selected: look.chassis == chassis,
                  onTap: () => controller.setChassis(chassis),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Una muestra del chasis: un pedal en miniatura con su anillo.
class _ChassisSwatch extends StatelessWidget {
  const _ChassisSwatch({
    required this.chassis,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final Chassis chassis;
  final LoopinPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Color ${chassis.label}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 72,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2),
          ),
          child: Column(
            children: [
              Container(
                height: 72,
                decoration: BoxDecoration(
                  color: palette.chassis,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.edge),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: LoopinPalette.metal,
                    border: Border.all(color: LoopinPalette.groove, width: 5),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(chassis.label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ControlsSection extends StatelessWidget {
  const _ControlsSection({required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Para tocar sin manos. El botón principal hace lo mismo que el pulsador grande '
            '(toque, mantener y doble toque). El secundario cambia de pista con un toque y '
            'deshace si lo mantienes.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.volume_up),
          title: const Text('Botones de volumen'),
          subtitle: const Text(
            'Subir = principal, bajar = secundario. Valen los del móvil y los del cable de '
            'los cascos. Mientras esté activado no cambian el volumen dentro de Loopin.',
          ),
          value: c.volumeKeys,
          onChanged: c.setVolumeKeys,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.headset_mic),
          title: const Text('Botón de los cascos'),
          subtitle: const Text(
            'El botón central de los cascos hace de botón principal. Mejor solo con toques: '
            'en muchos cascos, mantenerlo abre el asistente de voz.',
          ),
          value: c.headsetKey,
          onChanged: c.setHeadsetKey,
        ),
        for (final action in PedalAction.values) _LearnTile(controller: c, action: action),
        if (c.lastKeyName != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Última tecla recibida: ${_short(c.lastKeyName!)} → '
              '${c.lastKeyAction?.label.toLowerCase() ?? '—'}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  static String _short(String name) => name.startsWith('KEYCODE_') ? name.substring(8) : name;
}

/// Teclas de un pedal Bluetooth (o de un teclado) asignadas a una acción.
class _LearnTile extends StatelessWidget {
  const _LearnTile({required this.controller, required this.action});

  final EngineController controller;
  final PedalAction action;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final keys = [
      for (final k in c.learnedKeys)
        if (k.action == action) k,
    ];
    final learning = c.learning == action;
    return ListTile(
      leading: Icon(action == PedalAction.main ? Icons.radio_button_checked : Icons.skip_next),
      title: Text('Pedal Bluetooth: ${action.label.toLowerCase()}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            learning
                ? 'Pulsa ahora el botón del pedal…'
                : (keys.isEmpty
                      ? 'Sin asignar. Toca «Aprender» y pulsa el botón del pedal.'
                      : 'Teclas asignadas:'),
          ),
          if (keys.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final k in keys)
                    InputChip(
                      label: Text(k.label),
                      deleteButtonTooltipMessage: 'Quitar ${k.label}',
                      onDeleted: () => c.forgetKey(k.code),
                    ),
                ],
              ),
            ),
        ],
      ),
      trailing: learning
          ? TextButton(onPressed: c.cancelLearning, child: const Text('Cancelar'))
          : FilledButton.tonal(
              key: ValueKey('learn-${action.name}'),
              onPressed: () => c.startLearning(action),
              child: const Text('Aprender'),
            ),
    );
  }
}
