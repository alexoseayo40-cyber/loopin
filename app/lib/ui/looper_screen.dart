// Loopin — pantalla del looper: la cara de un pedal con 4 pistas
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../engine/engine_controller.dart';
import 'audio_settings_screen.dart';
import 'pedal_widgets.dart';
import 'settings_screen.dart';
import 'theme.dart';

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
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(controller: widget.controller)));
  }

  void _openLatency() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AudioSettingsScreen(controller: widget.controller)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final palette = LoopinPalette.of(context);
    final darkChassis = ThemeData.estimateBrightnessForColor(palette.chassis) == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Iconos de la barra de estado legibles sobre el color del chasis
      value: (darkChassis ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: palette.chassis,
      ),
      child: Scaffold(
        backgroundColor: palette.chassis,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, box) {
                  final view = _View(
                    controller: c,
                    s: c.status,
                    palette: palette,
                    onSettings: _openSettings,
                    onLatency: _openLatency,
                  );
                  // Apaisado (móvil tumbado o tablet): dos columnas
                  final wide = box.maxWidth >= 520 && box.maxWidth > box.maxHeight * 1.15;
                  // Con sitio de sobra (tablet) se ven los controles de las 4 pistas
                  final roomy = math.min(box.maxWidth, box.maxHeight) >= 560;
                  return wide
                      ? _WideLayout(view: view, box: box, mixer: roomy)
                      : _TallLayout(view: view, box: box, mixer: roomy);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Lo que necesitan todas las piezas de la pantalla.
class _View {
  const _View({
    required this.controller,
    required this.s,
    required this.palette,
    required this.onSettings,
    required this.onLatency,
  });

  final EngineController controller;
  final EngineStatus s;
  final LoopinPalette palette;
  final VoidCallback onSettings;
  final VoidCallback onLatency;
}

// ---------------------------------------------------------------------------
// Disposición

/// En vertical: todo en una columna, con el pulsador abajo, a mano.
class _TallLayout extends StatelessWidget {
  const _TallLayout({required this.view, required this.box, required this.mixer});

  final _View view;
  final BoxConstraints box;
  final bool mixer;

  @override
  Widget build(BuildContext context) {
    // En una tablet la columna no ocupa todo el ancho
    final width = math.min(box.maxWidth, 720.0);
    final compact = box.maxHeight < 760;
    final gap = compact ? 8.0 : 14.0;
    // Lo que ocupa todo menos el pulsador (medido), para darle el resto
    final fixed = (compact ? 492.0 : 585.0) + (mixer ? 3 * 52.0 : 0);
    final pedal = (math.min(
      width * 0.62,
      box.maxHeight - fixed,
    )).clamp(132.0, mixer ? 420.0 : 340.0);
    return Center(
      child: SizedBox(
        width: width,
        // Si no cabe todo (móvil pequeño o letra grande) se desplaza
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 4, 16, compact ? 8 : 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - (compact ? 12 : 16)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(view: view),
                    _TempoDisplay(view: view, compact: compact),
                    SizedBox(height: gap),
                    _TrackRings(view: view),
                    SizedBox(height: gap),
                    _TrackControls(view: view, mixer: mixer),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: gap),
                  child: _PedalArea(view: view, size: pedal),
                ),
                _BottomBar(view: view, showHint: !compact),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// En apaisado: a la izquierda el tempo y las pistas; a la derecha el pulsador.
class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.view, required this.box, required this.mixer});

  final _View view;
  final BoxConstraints box;
  final bool mixer;

  @override
  Widget build(BuildContext context) {
    final compact = box.maxHeight < 480;
    final gap = compact ? 6.0 : 14.0;
    final rightWidth = (box.maxWidth - 32 - 20) * 4 / 9;
    final pedal = (math.min(
      rightWidth * 0.78,
      box.maxHeight - (compact ? 190.0 : 250.0),
    )).clamp(110.0, 360.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(view: view),
                  _TempoDisplay(view: view, compact: compact),
                  SizedBox(height: gap),
                  _TrackRings(view: view, maxSize: compact ? 64 : 96),
                  SizedBox(height: gap),
                  _TrackControls(view: view, mixer: mixer),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 4,
            child: LayoutBuilder(
              builder: (context, right) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: right.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: gap),
                        child: _PedalArea(view: view, size: pedal),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: gap),
                        child: _BottomBar(view: view, showHint: !compact),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cabecera

class _TopBar extends StatelessWidget {
  const _TopBar({required this.view});

  final _View view;

  @override
  Widget build(BuildContext context) {
    final p = view.palette;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Text('LOOPIN', style: p.label(size: 20, spacing: 5)),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _LatencyChip(view: view),
            ),
          ),
          IconButton(
            tooltip: 'Ajustes',
            icon: Icon(Icons.tune, color: p.ink),
            onPressed: view.onSettings,
          ),
        ],
      ),
    );
  }
}

/// De un vistazo: si la latencia de esta entrada y salida está medida.
class _LatencyChip extends StatelessWidget {
  const _LatencyChip({required this.view});

  final _View view;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final p = view.palette;
    if (!view.s.running) return const SizedBox.shrink();
    final measured = c.latencySource == LatencySource.measured;
    final text = measured ? 'LATENCIA ${c.compensationMs.round()} MS' : 'LATENCIA SIN MEDIR';
    return Semantics(
      button: true,
      label: measured
          ? 'Latencia medida: ${c.compensationMs.round()} milisegundos'
          : 'Latencia sin medir: el loop puede ir desfasado. Toca para medirla',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: view.onLatency,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: measured ? null : LoopinPalette.well,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: measured ? p.edge : LoopinPalette.dub),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                measured ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                size: 16,
                color: measured ? p.dim : LoopinPalette.dub,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: p.label(size: 12, color: measured ? p.dim : LoopinPalette.dub),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pantalla de tempo: números en ámbar sobre negro, como la de un pedal

class _TempoDisplay extends StatelessWidget {
  const _TempoDisplay({required this.view, required this.compact});

  final _View view;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final s = view.s;
    final locked = c.tempoLocked;
    final bpm = locked ? s.bpm : c.bpm;
    const amber = LoopinPalette.display;
    const dimAmber = LoopinPalette.displayDim;
    final small = view.palette.label(size: 12, color: dimAmber);
    // El modo solo cuenta al empezar a grabar
    final busy = s.loopState == LoopState.armed || s.loopState == LoopState.recording;
    final modeValue = c.loopMode == LoopMode.sync ? c.syncBars : 0;

    return Container(
      padding: EdgeInsets.fromLTRB(4, compact ? 4 : 8, 4, compact ? 6 : 10),
      decoration: BoxDecoration(
        color: LoopinPalette.well,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: view.palette.edge, width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Bajar el tempo',
                onPressed: locked ? null : () => c.setBpm(c.bpm - 1),
                icon: const Icon(Icons.remove),
                color: amber,
                disabledColor: dimAmber.withValues(alpha: 0.5),
              ),
              Expanded(
                child: Semantics(
                  button: !locked,
                  label:
                      '${bpm.round()} pulsos por minuto. '
                      '${locked ? 'Fijo mientras haya loop' : 'Toca varias veces para marcar el tempo'}',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: locked ? null : c.tapTempo,
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              if (locked)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.lock, size: 16, color: dimAmber),
                                ),
                              Text(
                                bpm.toStringAsFixed(0),
                                style: TextStyle(
                                  fontFamily: LoopinFonts.display,
                                  fontSize: compact ? 36 : 46,
                                  height: 1,
                                  color: amber,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('BPM', style: small.copyWith(fontSize: 14)),
                            ],
                          ),
                        ),
                        Text(
                          locked ? 'FIJO MIENTRAS HAYA LOOP' : 'TOCA AQUÍ PARA MARCAR EL TEMPO',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Subir el tempo',
                onPressed: locked ? null : () => c.setBpm(c.bpm + 1),
                icon: const Icon(Icons.add),
                color: amber,
                disabledColor: dimAmber.withValues(alpha: 0.5),
              ),
            ],
          ),
          SizedBox(height: compact ? 2 : 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                // LEDs de los tiempos del compás
                for (var i = 0; i < s.beatsPerBar; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Led(
                      size: 11,
                      color: s.playing && s.beat == i
                          ? (i == 0 ? LoopinPalette.rec : amber)
                          : LoopinPalette.ledOff,
                    ),
                  ),
                const SizedBox(width: 4),
                // Si no caben (letra grande, 6/8…), se encogen
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DisplayMenu<int>(
                          tooltip: 'Compás',
                          enabled: !locked,
                          value: c.beatsPerBar,
                          label: kTimeSignatures[c.beatsPerBar] ?? '${c.beatsPerBar}',
                          items: {for (final e in kTimeSignatures.entries) e.key: e.value},
                          onSelected: c.setBeatsPerBar,
                        ),
                        const SizedBox(width: 6),
                        _DisplayMenu<int>(
                          tooltip: 'Modo de grabación',
                          enabled: !busy,
                          value: modeValue,
                          label: c.loopMode == LoopMode.sync ? 'SYNC · ${c.syncBars} C' : 'MANUAL',
                          items: {
                            for (final b in kSyncBarOptions)
                              b: 'Sincronizado · $b ${b == 1 ? 'compás' : 'compases'}',
                            0: 'Manual · se cierra al pulsar',
                          },
                          onSelected: (v) {
                            if (v == 0) {
                              c.setLoopMode(LoopMode.manual);
                            } else {
                              c.setLoopMode(LoopMode.sync);
                              c.setSyncBars(v);
                            }
                          },
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: c.clickEnabled ? 'Clic encendido' : 'Clic apagado',
                          onPressed: () => c.setClickEnabled(!c.clickEnabled),
                          icon: Icon(c.clickEnabled ? Icons.volume_up : Icons.volume_off, size: 20),
                          color: c.clickEnabled ? amber : dimAmber,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Un valor de la pantalla de tempo que abre un menú al tocarlo.
class _DisplayMenu<T> extends StatelessWidget {
  const _DisplayMenu({
    required this.tooltip,
    required this.enabled,
    required this.value,
    required this.label,
    required this.items,
    required this.onSelected,
  });

  final String tooltip;
  final bool enabled;
  final T value;
  final String label;
  final Map<T, String> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? LoopinPalette.display : LoopinPalette.displayDim;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      enabled: enabled,
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final e in items.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(
          label,
          style: TextStyle(fontFamily: LoopinFonts.display, fontSize: 14, color: color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pistas

/// Cuánto lleva la grabación en curso, de 0 a 1 (para los anillos).
double _recordProgress(EngineStatus s) {
  if (s.loopRecorded < 0) {
    // Esperando: lo que falta del compás
    return s.loopBarFrames > 0 ? (1 + s.loopRecorded / s.loopBarFrames).clamp(0.0, 1.0) : 0;
  }
  if (s.loopTarget > 0) return (s.loopRecorded / s.loopTarget).clamp(0.0, 1.0);
  // Sin final fijado: una vuelta por cada vuelta de la base (o por compás)
  final lap = s.baseLength > 0 ? s.baseLength : s.loopBarFrames;
  return lap > 0 ? (s.loopRecorded % lap) / lap : 0;
}

/// Color del anillo según el estado (null = apagado).
Color? _stateColor(LoopState st, {bool waiting = false, bool muted = false}) => switch (st) {
  LoopState.empty => null,
  LoopState.armed => LoopinPalette.count,
  LoopState.recording => LoopinPalette.rec,
  LoopState.playing => muted ? LoopinPalette.stopped : LoopinPalette.play,
  LoopState.overdubbing => waiting ? LoopinPalette.count : LoopinPalette.dub,
  LoopState.stopped => LoopinPalette.stopped,
};

String _bars(int n) => '$n ${n == 1 ? 'compás' : 'compases'}';

/// Los cuatro anillos: uno por pista. Tocar uno elige la pista.
class _TrackRings extends StatelessWidget {
  const _TrackRings({required this.view, this.maxSize = 96});

  final _View view;
  final double maxSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = ((box.maxWidth - 3 * 10) / kTrackCount).clamp(48.0, maxSize);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var i = 0; i < kTrackCount; i++) _TrackRing(view: view, index: i, size: size),
          ],
        );
      },
    );
  }
}

class _TrackRing extends StatelessWidget {
  const _TrackRing({required this.view, required this.index, required this.size});

  final _View view;
  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = view.s;
    final p = view.palette;
    final t = s.tracks[index];
    final selected = s.selectedTrack == index;
    final active = s.activeTrack == index;
    final waiting = active && s.loopRecorded < 0;
    final recording = active && (t.state == LoopState.armed || t.state == LoopState.recording);
    final bars = s.loopBarFrames > 0 ? (t.length / s.loopBarFrames).round() : 0;
    final stateText = switch (t.state) {
      LoopState.empty => 'vacía',
      LoopState.armed => 'a punto de grabar',
      LoopState.recording => 'grabando',
      LoopState.playing => t.muted ? 'en silencio' : 'sonando',
      LoopState.overdubbing => 'grabando encima',
      LoopState.stopped => 'parada',
    };
    return Semantics(
      button: true,
      selected: selected,
      label: 'Pista ${index + 1}, $stateText${t.hasLoop ? ', ${_bars(bars)}' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('track-ring-$index'),
        behavior: HitTestBehavior.opaque,
        onTap: () => view.controller.selectTrack(index),
        child: SizedBox(
          width: size,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CustomPaint(
                  painter: RingPainter(
                    color: _stateColor(t.state, waiting: waiting, muted: t.muted),
                    progress: recording || waiting ? _recordProgress(s) : t.progress,
                    stroke: size * 0.13,
                    glow: t.hasLoop,
                    outline: selected ? p.ink : null,
                  ),
                  child: Center(
                    child: t.muted
                        ? Icon(Icons.volume_off, size: size * 0.3, color: p.dim)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontFamily: LoopinFonts.display,
                              fontSize: size * 0.32,
                              height: 1,
                              color: t.state == LoopState.empty && !selected ? p.dim : p.ink,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Compases y, si hay más de una, capas
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  t.hasLoop ? '$bars C${t.layers > 1 ? ' · ${t.layers}' : ''}' : '—',
                  style: p.label(size: 12, color: p.dim),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Volumen, silencio y borrar: de la pista elegida o, si hay sitio, de las 4.
class _TrackControls extends StatelessWidget {
  const _TrackControls({required this.view, required this.mixer});

  final _View view;
  final bool mixer;

  @override
  Widget build(BuildContext context) {
    if (!mixer) return _TrackStrip(view: view, index: view.s.selectedTrack, highlighted: false);
    return Column(
      children: [
        for (var i = 0; i < kTrackCount; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
            child: _TrackStrip(view: view, index: i, highlighted: view.s.selectedTrack == i),
          ),
      ],
    );
  }
}

class _TrackStrip extends StatelessWidget {
  const _TrackStrip({required this.view, required this.index, required this.highlighted});

  final _View view;
  final int index;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final p = view.palette;
    final t = view.s.tracks[index];
    final n = index + 1;
    return Container(
      height: 46,
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: highlighted ? p.ink : p.edge, width: highlighted ? 1.5 : 1),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => c.selectTrack(index),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Led(color: _stateColor(t.state, muted: t.muted) ?? LoopinPalette.ledOff),
                const SizedBox(width: 8),
                Text('PISTA $n', style: p.label(size: 14)),
              ],
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: p.ink,
                inactiveTrackColor: p.edge,
                thumbColor: p.ink,
                overlayColor: p.ink.withValues(alpha: 0.12),
              ),
              child: Slider(
                max: 1.5,
                value: c.trackVolumes[index].clamp(0.0, 1.5),
                onChanged: (v) => c.setTrackVolume(index, v),
                semanticFormatterCallback: (v) => 'Volumen de la pista $n: ${(v * 100).round()} %',
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: t.muted ? 'Volver a oír la pista $n' : 'Silenciar la pista $n',
            onPressed: () => c.toggleTrackMuted(index),
            icon: Icon(t.muted ? Icons.volume_off : Icons.volume_up, size: 22),
            color: t.muted ? LoopinPalette.dub : p.ink,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Borrar la pista $n',
            onPressed: t.state == LoopState.empty ? null : () => c.clearTrack(index),
            icon: const Icon(Icons.delete_outline, size: 22),
            color: p.ink,
            disabledColor: p.dim.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// El pulsador y lo que está pasando

class _PedalLook {
  const _PedalLook({
    required this.color,
    required this.title,
    required this.subtitle,
    this.progress = 0,
    this.glow = false,
    this.icon,
    this.text,
  });

  final Color? color;
  final String title;
  final String subtitle;
  final double progress;
  final bool glow;
  final IconData? icon;
  final String? text;
}

_PedalLook _pedalLook(EngineStatus s) {
  final selected = s.tracks[s.selectedTrack];
  final sel = s.selectedTrack + 1;
  final active = s.activeTrack >= 0 ? s.activeTrack + 1 : sel;
  final bar = s.loopBarFrames;
  // Tiempos que faltan mientras espera (cuenta de entrada o siguiente compás)
  final beatsLeft = s.samplesPerBeat > 0 ? (-s.loopRecorded / s.samplesPerBeat).ceil() : 0;
  switch (s.loopState) {
    case LoopState.empty:
      return _PedalLook(
        color: null,
        title: 'LISTO',
        subtitle: 'Toca para grabar la pista $sel, con 1 compás de cuenta',
        icon: Icons.fiber_manual_record,
      );
    case LoopState.armed:
      return _PedalLook(
        color: LoopinPalette.count,
        title: 'PREPÁRATE',
        subtitle: s.hasLoops
            ? 'La pista $active empieza en el próximo compás'
            : 'Cuenta de entrada',
        progress: _recordProgress(s),
        text: '$beatsLeft',
      );
    case LoopState.recording:
      final barNow = bar > 0 ? s.loopRecorded ~/ bar + 1 : 1;
      final target = bar > 0 ? s.loopTarget ~/ bar : 0;
      return _PedalLook(
        color: LoopinPalette.rec,
        title: 'GRABANDO · PISTA $active',
        subtitle: target > 0 ? 'Compás $barNow de $target' : 'Compás $barNow · toca para cerrar',
        progress: _recordProgress(s),
        icon: Icons.stop,
      );
    case LoopState.playing:
      return _PedalLook(
        color: LoopinPalette.play,
        title: 'SONANDO',
        subtitle: selected.hasLoop
            ? 'Toca para grabar encima de la pista $sel'
            : 'Toca para grabar la pista $sel',
        progress: selected.hasLoop
            ? selected.progress
            : (s.baseLength > 0 ? s.basePosition / s.baseLength : 0),
        glow: true,
        icon: selected.hasLoop ? Icons.layers : Icons.fiber_manual_record,
      );
    case LoopState.overdubbing:
      final track = s.tracks[(active - 1).clamp(0, kTrackCount - 1)];
      if (s.loopRecorded < 0) {
        return _PedalLook(
          color: LoopinPalette.count,
          title: 'PREPÁRATE',
          subtitle: 'Overdub de la pista $active en el próximo compás',
          progress: _recordProgress(s),
          text: '$beatsLeft',
        );
      }
      return _PedalLook(
        color: LoopinPalette.dub,
        title: 'OVERDUB · PISTA $active',
        subtitle: 'Toca para terminar',
        progress: track.progress,
        glow: true,
        icon: Icons.stop,
      );
    case LoopState.stopped:
      return const _PedalLook(
        color: LoopinPalette.stopped,
        title: 'PARADO',
        subtitle: 'Toca para arrancar',
        icon: Icons.play_arrow,
      );
  }
}

class _PedalArea extends StatelessWidget {
  const _PedalArea({required this.view, required this.size});

  final _View view;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final p = view.palette;
    if (!view.s.running) return _AudioOff(view: view);
    final look = _pedalLook(view.s);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Footswitch(
          size: size,
          color: look.color,
          progress: look.progress,
          glow: look.glow,
          icon: look.icon,
          text: look.text,
          semanticLabel: 'Botón principal. ${look.title}. ${look.subtitle}',
          onDown: c.pedalDown,
          onUp: c.pedalUp,
        ),
        const SizedBox(height: 10),
        // El estado, grande: se tiene que leer con el móvil en el suelo
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Led(color: look.color ?? LoopinPalette.ledOff, size: 12),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                look.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: p.label(size: 22, spacing: 2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          look.subtitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, height: 1.25, color: p.dim),
        ),
      ],
    );
  }
}

class _AudioOff extends StatelessWidget {
  const _AudioOff({required this.view});

  final _View view;

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final p = view.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              c.error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.ink, fontSize: 15, height: 1.3),
            ),
          ),
        _ChassisButton(
          palette: p,
          icon: Icons.power_settings_new,
          label: 'ENCENDER AUDIO',
          onPressed: c.startAudio,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Barra de abajo

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.view, required this.showHint});

  final _View view;
  final bool showHint;

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar las 4 pistas?'),
        content: const Text('Se pierde todo lo grabado. No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar todo'),
          ),
        ],
      ),
    );
    if (ok == true) view.controller.clearLoop();
  }

  @override
  Widget build(BuildContext context) {
    final c = view.controller;
    final s = view.s;
    final p = view.palette;
    final peak = s.inputPeak.clamp(0.0, 1.0);
    final on = s.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHint)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Toca: grabar · Mantén: deshacer · Doble toque: parar',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: p.dim),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _ChassisButton(
                palette: p,
                icon: Icons.undo,
                label: 'DESHACER',
                onPressed: on && s.loopCanUndo ? c.undo : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ChassisButton(
                palette: p,
                icon: s.playing ? Icons.stop : Icons.play_arrow,
                label: s.playing ? 'PARAR' : 'ARRANCAR',
                onPressed: on ? c.toggleTransport : null,
              ),
            ),
            const SizedBox(width: 8),
            _ChassisButton(
              palette: p,
              icon: Icons.delete_sweep_outlined,
              tooltip: 'Borrar todas las pistas',
              onPressed: on && s.loopState != LoopState.empty ? () => _confirmClear(context) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.mic_none, size: 18, color: p.dim),
            const SizedBox(width: 8),
            // Nivel de entrada
            Expanded(
              child: Semantics(
                label: 'Nivel de entrada',
                value: '${(peak * 100).round()} %',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: peak,
                    minHeight: 8,
                    backgroundColor: LoopinPalette.groove,
                    color: peak > 0.9
                        ? LoopinPalette.rec
                        : (peak > 0.6 ? LoopinPalette.dub : LoopinPalette.play),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _ChassisButton(
              palette: p,
              icon: c.monitorEnabled ? Icons.headphones : Icons.headset_off_outlined,
              label: 'ESCUCHARME',
              selected: c.monitorEnabled,
              isToggle: true,
              dense: true,
              onPressed: () => c.setMonitorEnabled(!c.monitorEnabled),
            ),
          ],
        ),
      ],
    );
  }
}

/// Botón con el aspecto del chasis: borde fino y etiqueta en mayúsculas.
class _ChassisButton extends StatelessWidget {
  const _ChassisButton({
    required this.palette,
    required this.icon,
    required this.onPressed,
    this.label,
    this.tooltip,
    this.selected = false,
    this.isToggle = false,
    this.dense = false,
  });

  final LoopinPalette palette;
  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  /// Es un interruptor (encendido o apagado), no una acción.
  final bool isToggle;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final enabled = onPressed != null;
    final fg = !enabled ? p.dim.withValues(alpha: 0.45) : (selected ? p.chassis : p.ink);
    final button = Material(
      color: selected ? p.ink : p.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? p.ink : p.edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          constraints: BoxConstraints(minHeight: dense ? 40 : 48, minWidth: 48),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              if (label != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: p.label(size: 14, color: fg),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: isToggle ? selected : null,
      label: tooltip,
      child: tooltip != null ? Tooltip(message: tooltip, child: button) : button,
    );
  }
}
