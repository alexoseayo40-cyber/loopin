// Loopin — las 4 pistas: anillos y controles (volumen, silencio, borrar)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../../engine/engine_controller.dart';
import '../../l10n/strings.dart';
import '../pedal_widgets.dart';
import '../theme.dart';
import 'view.dart';

/// Los cuatro anillos: uno por pista. Tocar uno elige la pista.
class TrackRings extends StatelessWidget {
  const TrackRings({super.key, required this.view, this.maxSize = 96});

  final LooperView view;
  final double maxSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = ((box.maxWidth - 3 * 10) / kTrackCount).clamp(48.0, maxSize);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var i = 0; i < kTrackCount; i++)
              // El arco avanza con la pista: se redibuja con cada consulta
              ListenableBuilder(
                listenable: view.controller.live,
                builder: (context, _) => _TrackRing(view: view, index: i, size: size),
              ),
          ],
        );
      },
    );
  }
}

class _TrackRing extends StatelessWidget {
  const _TrackRing({required this.view, required this.index, required this.size});

  final LooperView view;
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
    return Semantics(
      button: true,
      selected: selected,
      label: tr.trackSemantics(
        index + 1,
        tr.trackStateName(t.state, muted: t.muted),
        bars: t.hasLoop ? bars : null,
        layers: t.layers,
      ),
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
                    color: stateColor(t.state, waiting: waiting, muted: t.muted),
                    progress: recording || waiting ? recordProgress(s) : t.progress,
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
                  t.hasLoop
                      ? tr.trackRingFx(
                          tr.trackRingLabel(bars, t.layers),
                          reverse: t.reverse,
                          half: t.half,
                        )
                      : tr.trackRingEmpty,
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
class TrackControls extends StatelessWidget {
  const TrackControls({super.key, required this.view, required this.mixer});

  final LooperView view;
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

  final LooperView view;
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
                Led(color: stateColor(t.state, muted: t.muted) ?? LoopinPalette.ledOff),
                const SizedBox(width: 8),
                // «PISTA 1» cabe; en otros idiomas («TRACCIA 1») se encoge
                // antes que quitarle sitio al volumen
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.textScalerOf(context).scale(52)),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(tr.trackLabel(n), style: p.label(size: 14)),
                  ),
                ),
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
                semanticFormatterCallback: (v) => tr.trackVolume(n, v),
              ),
            ),
          ),
          // Reverse y media velocidad (avanzado, con «Efectos de pista»)
          if (c.trackFxShown) ...[
            _FxToggle(
              key: ValueKey('reverse-$index'),
              text: tr.reverseShort,
              on: t.reverse,
              pending: t.pendingReverse,
              enabled: c.trackFxAvailable(index),
              tooltip: tr.reverseTrack(n, t.reverse),
              palette: p,
              onTap: () => c.toggleTrackReverse(index),
            ),
            const SizedBox(width: 4),
            _FxToggle(
              key: ValueKey('half-$index'),
              text: tr.halfShort,
              on: t.half,
              pending: t.pendingHalf,
              enabled: c.trackFxAvailable(index),
              tooltip: tr.halfTrack(n, t.half),
              palette: p,
              onTap: () => c.toggleTrackHalf(index),
            ),
          ],
          _PendingDot(
            pending: t.pendingMute,
            palette: p,
            child: IconButton(
              key: ValueKey('mute-$index'),
              visualDensity: VisualDensity.compact,
              tooltip:
                  '${t.muted ? tr.unmuteTrack(n) : tr.muteTrack(n)}'
                  '${t.pendingMute ? ', ${tr.atNextOne}' : ''}',
              onPressed: () => c.toggleTrackMuted(index),
              icon: Icon(t.muted ? Icons.volume_off : Icons.volume_up, size: 22),
              color: t.muted ? LoopinPalette.dub : p.ink,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: tr.clearTrack(n),
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

/// REV o ½: encendido, relleno; si el cambio espera al siguiente 1, con un
/// punto.
class _FxToggle extends StatelessWidget {
  const _FxToggle({
    super.key,
    required this.text,
    required this.on,
    required this.pending,
    required this.enabled,
    required this.tooltip,
    required this.palette,
    required this.onTap,
  });

  final String text;
  final bool on;
  final bool pending;
  final bool enabled;
  final String tooltip;
  final LoopinPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final ink = enabled ? p.ink : p.dim.withValues(alpha: 0.4);
    return Semantics(
      button: true,
      toggled: on,
      enabled: enabled,
      label: pending ? '$tooltip, ${tr.atNextOne}' : tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: _PendingDot(
          pending: pending,
          palette: p,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: enabled ? onTap : null,
            child: Container(
              width: 34,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? ink : null,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: on ? ink : p.edge, width: 1.5),
              ),
              child: Text(text, style: p.label(size: 13, color: on ? p.panel : ink)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un punto en la esquina: el cambio espera al siguiente 1.
class _PendingDot extends StatelessWidget {
  const _PendingDot({required this.pending, required this.palette, required this.child});

  final bool pending;
  final LoopinPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!pending) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: 1,
          top: 1,
          child: Container(
            key: const ValueKey('pending-dot'),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: LoopinPalette.dub,
              shape: BoxShape.circle,
              border: Border.all(color: palette.panel, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
