// Loopin — ajustes: modo, apariencia, looper y controles externos
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:loopin_engine/loopin_engine.dart' show StopMode;

import '../engine/engine_controller.dart';
import '../l10n/strings.dart';
import 'audio_settings_screen.dart';
import 'help.dart';
import 'tutorial_screen.dart';
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
      child: Scaffold(
        appBar: AppBar(title: Text(tr.settings)),
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
                    _Header(tr.playModeTitle, help: tr.playModeHelp),
                    _PlayModeSection(controller: c),
                    _Header(tr.appearance),
                    _AppearanceSection(controller: c),
                    _Header(tr.looper),
                    OptionTile.toggle(
                      title: tr.autoAdvance,
                      subtitle: tr.autoAdvanceLine,
                      help: tr.autoAdvanceHelp,
                      value: c.autoAdvance,
                      onChanged: c.setAutoAdvance,
                    ),
                    if (!c.simple) _RecordDuckSection(controller: c),
                    _StopModeSection(controller: c),
                    OptionTile.toggle(
                      key: const ValueKey('quantize'),
                      leading: const Icon(Icons.timer_outlined),
                      title: tr.quantizeTitle,
                      subtitle: c.simple ? tr.quantizeLineSimple : tr.quantizeLine,
                      help: tr.quantizeHelp,
                      value: c.quantize,
                      onChanged: c.setQuantize,
                    ),
                    _Header(tr.externalControls, help: tr.externalControlsHelp),
                    _ControlsSection(controller: c),
                    _Header(tr.audio),
                    ListTile(
                      leading: const Icon(Icons.graphic_eq),
                      title: Text(tr.audioAndLatency),
                      subtitle: Text(tr.audioAndLatencyLine),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => AudioSettingsScreen(controller: c)),
                      ),
                    ),
                    _Header(tr.helpSection),
                    ListTile(
                      key: const ValueKey('open-tutorial'),
                      leading: const Icon(Icons.school_outlined),
                      title: Text(tr.tutorialOpen),
                      subtitle: Text(tr.tutorialOpenLine),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TutorialScreen(
                            controller: c,
                            onMeasure: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AudioSettingsScreen(controller: c),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.help});

  final String text;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionTitle(
      text,
      help: help,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
    );
  }
}

// ---------------------------------------------------------------------------

/// Simple o avanzado: una línea con los dos y debajo qué tiene el elegido.
class _PlayModeSection extends StatelessWidget {
  const _PlayModeSection({required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final can = c.canChangePlayMode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<PlayMode>(
            key: const ValueKey('play-mode'),
            segments: [
              ButtonSegment(
                value: PlayMode.simple,
                label: Text(tr.playModeName(PlayMode.simple)),
                icon: const Icon(Icons.radio_button_checked),
              ),
              ButtonSegment(
                value: PlayMode.advanced,
                label: Text(tr.playModeName(PlayMode.advanced)),
                icon: const Icon(Icons.tune),
              ),
            ],
            showSelectedIcon: false,
            selected: {c.playMode},
            onSelectionChanged: can ? (v) => c.setPlayMode(v.first) : null,
          ),
          const SizedBox(height: 6),
          Text(
            can ? tr.playModeLine(c.playMode) : tr.playModeBusy,
            style: theme.textTheme.bodySmall,
          ),
        ],
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
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text(tr.themeSystem),
                icon: const Icon(Icons.brightness_auto),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text(tr.themeLight),
                icon: const Icon(Icons.light_mode),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text(tr.themeDark),
                icon: const Icon(Icons.dark_mode),
              ),
            ],
            showSelectedIcon: false,
            selected: {look.mode},
            onSelectionChanged: (v) => controller.setThemeMode(v.first),
          ),
          const SizedBox(height: 16),
          Text(tr.pedalColor, style: Theme.of(context).textTheme.bodyMedium),
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
      label: tr.chassisSemantics(chassis),
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
              Text(tr.chassisName(chassis), style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Qué hace lo que ya suena mientras se graba con el altavoz.
class _RecordDuckSection extends StatelessWidget {
  const _RecordDuckSection({required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OptionTile(
          leading: const Icon(Icons.speaker_phone),
          title: tr.recordDuckTitle,
          subtitle: Text(tr.recordDuckLine),
          help: tr.recordDuckHelp,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<RecordDuck>(
            segments: [
              for (final d in RecordDuck.values)
                ButtonSegment(value: d, label: Text(tr.recordDuckName(d))),
            ],
            showSelectedIcon: false,
            selected: {c.recordDuck},
            onSelectionChanged: (v) => c.setRecordDuck(v.first),
          ),
        ),
      ],
    );
  }
}

/// Al parar: al momento, en el 1 o con fundido.
class _StopModeSection extends StatelessWidget {
  const _StopModeSection({required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OptionTile(
          leading: const Icon(Icons.stop_circle_outlined),
          title: tr.stopModeTitle,
          subtitle: Text(tr.stopModeLine),
          help: tr.stopModeHelp,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<StopMode>(
            key: const ValueKey('stop-mode'),
            segments: [
              for (final m in StopMode.values)
                ButtonSegment(value: m, label: Text(tr.stopModeName(m))),
            ],
            showSelectedIcon: false,
            selected: {c.stopMode},
            onSelectionChanged: (v) => c.setStopMode(v.first),
          ),
        ),
      ],
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
    final lastCode = c.lastKeyCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OptionTile.toggle(
          leading: const Icon(Icons.volume_up),
          title: tr.volumeKeys,
          subtitle: tr.volumeKeysLine,
          help: tr.volumeKeysHelp,
          value: c.volumeKeys,
          onChanged: c.setVolumeKeys,
        ),
        OptionTile.toggle(
          leading: const Icon(Icons.headset_mic),
          title: tr.headsetKey,
          subtitle: tr.headsetKeyLine,
          help: tr.headsetKeyHelp,
          value: c.headsetKey,
          onChanged: c.setHeadsetKey,
        ),
        for (final action in PedalAction.values) _LearnTile(controller: c, action: action),
        if (lastCode != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              tr.lastKey(tr.keyName(lastCode, c.lastKeyName), c.lastKeyAction),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
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
    return OptionTile(
      leading: Icon(action == PedalAction.main ? Icons.radio_button_checked : Icons.skip_next),
      title: tr.bluetoothPedal(action),
      help: tr.learnHelp,
      subtitle: learning
          ? Text(tr.pressPedalNow)
          : (keys.isEmpty
                ? Text(tr.notAssigned)
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final k in keys)
                          InputChip(
                            label: Text(tr.keyName(k.code, k.name)),
                            deleteButtonTooltipMessage: tr.removeKey(tr.keyName(k.code, k.name)),
                            onDeleted: () => c.forgetKey(k.code),
                          ),
                      ],
                    ),
                  )),
      trailing: learning
          ? TextButton(onPressed: c.cancelLearning, child: Text(tr.cancel))
          : FilledButton.tonal(
              key: ValueKey('learn-${action.name}'),
              onPressed: () => c.startLearning(action),
              child: Text(tr.learn),
            ),
    );
  }
}
