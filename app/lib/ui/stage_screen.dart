// Loopin — modo escenario: toda la pantalla es el pulsador (Etapa 6)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Para tocar en directo con el móvil en el suelo o en un atril: se pisa (o se
// toca) en cualquier sitio. El estado se ve en grande y de lejos: el fondo
// toma el color del estado (rojo graba, verde suena…) y destella con el pulso.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine_controller.dart';
import '../l10n/strings.dart';
import 'looper/pedal_area.dart';
import 'looper/tempo_display.dart';
import 'looper/tracks.dart';
import 'looper/view.dart';
import 'pedal_widgets.dart';
import 'theme.dart';

class StageScreen extends StatefulWidget {
  const StageScreen({super.key, required this.controller});

  final EngineController controller;

  @override
  State<StageScreen> createState() => _StageScreenState();
}

class _StageScreenState extends State<StageScreen> {
  EngineController get c => widget.controller;

  /// El dedo (o el pie) que está pisando: los demás no cuentan.
  int? _pointer;

  @override
  void initState() {
    super.initState();
    // Sin barras del sistema: más sitio y nada que tocar sin querer
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    if (_pointer != null) c.pedalUp();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    c.pedalDown();
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    c.pedalUp();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LoopinPalette.of(context);
    final view = LooperView(
      controller: c,
      palette: palette,
      onSettings: () {},
      onLatency: () {},
      onTuner: () {},
    );
    return Scaffold(
      backgroundColor: LoopinPalette.well,
      body: ListenableBuilder(
        listenable: Listenable.merge([c, c.live]),
        builder: (context, _) {
          final s = c.status;
          final look = pedalLook(
            s,
            mode: c.loopMode,
            startOnSound: c.startOnSound,
            duck: c.speakerRoute ? c.recordDuck : RecordDuck.normal,
          );
          final color = look.color ?? LoopinPalette.ledOff;
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Arriba, fuera del pulsador: salir (manteniendo), tempo y pistas
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      _ExitButton(onExit: () => Navigator.of(context).maybePop()),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            tr.stageTempo(tr.bpmNumber(s.bpm), c.timeSignature.label),
                            style: palette.label(size: 20, color: LoopinPalette.display),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TrackRings(view: view, maxSize: 64),
                ),
                Expanded(
                  child: Listener(
                    key: const ValueKey('stage-pedal'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _down,
                    onPointerUp: _up,
                    onPointerCancel: _up,
                    child: BeatBuilder(
                      active: s.playing,
                      beatNow: c.beatNow,
                      builder: (context, now) {
                        final flash = now == null ? 0.0 : (1 - now.phase / 0.3).clamp(0.0, 1.0);
                        final pulse = now != null && now.beat == 0
                            ? LoopinPalette.rec
                            : LoopinPalette.display;
                        return Semantics(
                          button: true,
                          label: tr.pedalSemantics(look.title, look.subtitle),
                          child: Container(
                            margin: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Color.lerp(LoopinPalette.groove, color, 0.28),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Color.lerp(color, pulse, flash * 0.9)!,
                                width: 6 + 10 * flash,
                              ),
                            ),
                            padding: const EdgeInsets.all(16),
                            // Si no cabe (apaisado, móvil pequeño), todo se
                            // encoge a la vez
                            child: LayoutBuilder(
                              builder: (context, box) => FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SizedBox(
                                  width: box.maxWidth,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          look.text ?? look.title,
                                          maxLines: 1,
                                          key: const ValueKey('stage-title'),
                                          textAlign: TextAlign.center,
                                          style: palette.label(
                                            size: look.text != null ? 160 : 64,
                                            color: color == LoopinPalette.ledOff
                                                ? LoopinPalette.count
                                                : color,
                                            spacing: 3,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        look.subtitle,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          height: 1.25,
                                          color: Colors.white70,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      SizedBox(
                                        width: 320,
                                        child: BeatBar(
                                          signature: c.timeSignature,
                                          beats: s.beatsPerBar,
                                          now: now,
                                          height: 22,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Text(
                                        tr.stageGestures,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 14, color: Colors.white54),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Salir manteniendo pulsado (así no se sale sin querer al pisar cerca).
class _ExitButton extends StatefulWidget {
  const _ExitButton({required this.onExit});

  final VoidCallback onExit;

  @override
  State<_ExitButton> createState() => _ExitButtonState();
}

class _ExitButtonState extends State<_ExitButton> with SingleTickerProviderStateMixin {
  late final AnimationController _hold =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
        ..addStatusListener((st) {
          if (st == AnimationStatus.completed) widget.onExit();
        });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr.stageExit,
      onTap: widget.onExit,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('stage-exit'),
        onTapDown: (_) => _hold.forward(from: 0),
        onTapUp: (_) => _hold.reverse(),
        onTapCancel: () => _hold.reverse(),
        child: AnimatedBuilder(
          animation: _hold,
          builder: (context, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white38),
              gradient: LinearGradient(
                colors: [Colors.white30, Colors.white30, Colors.transparent, Colors.transparent],
                stops: [0, _hold.value, _hold.value, 1],
              ),
            ),
            child: Text(
              tr.stageExitHold,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}
