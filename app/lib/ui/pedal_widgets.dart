// Loopin — piezas del pedal: anillos de luz, pulsador y LEDs
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

import '../engine/engine_controller.dart' show BeatNow, EngineController;
import '../l10n/strings.dart';
import 'theme.dart';

/// Redibuja lo que hay dentro en cada fotograma mientras [active] (el
/// metrónomo suena), con el tiempo que se está oyendo. Así el pulso se ve
/// suave aunque el estado del motor llegue solo 30 veces por segundo, y solo
/// se redibuja esta pieza, no la pantalla entera.
class BeatBuilder extends StatefulWidget {
  const BeatBuilder({
    super.key,
    required this.active,
    required this.beatNow,
    required this.builder,
  });

  final bool active;
  final BeatNow? Function() beatNow;
  final Widget Function(BuildContext context, BeatNow? now) builder;

  @override
  State<BeatBuilder> createState() => _BeatBuilderState();
}

class _BeatBuilderState extends State<BeatBuilder> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    if (widget.active) _ticker.start();
  }

  @override
  void didUpdateWidget(BeatBuilder old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ticker.isActive) _ticker.start();
    if (!widget.active && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.active ? widget.beatNow() : null);
}

/// Un LED pequeño.
class Led extends StatelessWidget {
  const Led({super.key, required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: LoopinPalette.groove, width: size * 0.12),
      ),
    );
  }
}

/// Anillo de luz: un surco negro con un arco encendido que avanza desde
/// arriba en el sentido de las agujas del reloj.
class RingPainter extends CustomPainter {
  const RingPainter({
    required this.color,
    required this.progress,
    required this.stroke,
    this.glow = false,
    this.outline,
  });

  /// Color del arco (null = apagado).
  final Color? color;

  /// De 0 a 1.
  final double progress;
  final double stroke;

  /// Todo el anillo encendido muy flojo por debajo del arco.
  final bool glow;

  /// Si no es null, un aro fino por fuera (pista elegida).
  final Color? outline;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = math.min(size.width, size.height) / 2;
    var radius = outer - stroke / 2;
    if (outline != null) {
      canvas.drawCircle(
        center,
        outer - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = outline!,
      );
    }
    // Siempre se deja el hueco del aro, para que el anillo no cambie de tamaño
    radius -= math.max(4.0, stroke * 0.5);

    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = LoopinPalette.groove;
    canvas.drawCircle(center, radius, groove);

    final c = color;
    if (c == null) return;
    final inner = stroke * 0.62;
    if (glow) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = inner
          ..color = c.withValues(alpha: 0.22),
      );
    }
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = inner
      ..strokeCap = StrokeCap.round
      ..color = c;
    if (p >= 0.999) {
      canvas.drawCircle(center, radius, arc);
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * p,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.color != color ||
      old.progress != progress ||
      old.stroke != stroke ||
      old.glow != glow ||
      old.outline != outline;
}

/// Lo que dice y hace el pulsador con TalkBack, que no da toques sueltos:
/// tocar dos veces = un toque del pulsador; mantener (tocar dos veces y
/// mantener) = deshacer; y en las acciones, «Parar o arrancar» = doble toque.
/// Cada una hace lo mismo que con el dedo (pulsar y soltar).
class PedalSemantics extends StatelessWidget {
  const PedalSemantics({
    super.key,
    required this.label,
    required this.onDown,
    required this.onUp,
    required this.child,
  });

  final String label;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final Widget child;

  void _tap() {
    onDown();
    onUp();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: _tap,
      onTapHint: tr.pedalTapHint,
      onLongPress: () {
        onDown();
        // Se suelta cuando el controlador ya lo ha contado como «mantener»
        Timer(EngineController.holdDelay + const Duration(milliseconds: 50), onUp);
      },
      onLongPressHint: tr.pedalHoldHint,
      customSemanticsActions: {
        CustomSemanticsAction(label: tr.pedalDoubleAction): () {
          _tap();
          _tap();
        },
      },
      child: child,
    );
  }
}

/// El pulsador grande con su anillo de luz. Actúa al pulsar, no al soltar.
class Footswitch extends StatefulWidget {
  const Footswitch({
    super.key,
    required this.size,
    required this.color,
    required this.progress,
    required this.onDown,
    required this.onUp,
    this.glow = false,
    this.icon,
    this.text,
    this.pulse = 0,
    this.pulseColor = LoopinPalette.display,
    required this.semanticLabel,
  });

  final double size;
  final Color? color;
  final double progress;
  final bool glow;

  /// Destello del pulso del metrónomo en la arandela (de 0 a 1).
  final double pulse;
  final Color pulseColor;

  /// Lo que hará el siguiente toque.
  final IconData? icon;

  /// Si no es null, sustituye al icono (la cuenta de entrada).
  final String? text;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final String semanticLabel;

  @override
  State<Footswitch> createState() => _FootswitchState();
}

class _FootswitchState extends State<Footswitch> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final palette = LoopinPalette.of(context);
    final size = widget.size;
    return PedalSemantics(
      label: widget.semanticLabel,
      onDown: widget.onDown,
      onUp: widget.onUp,
      child: Listener(
        onPointerDown: (_) {
          _set(true);
          widget.onDown();
        },
        onPointerUp: (_) {
          _set(false);
          widget.onUp();
        },
        onPointerCancel: (_) {
          _set(false);
          widget.onUp();
        },
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _FootswitchPainter(
              ring: RingPainter(
                color: widget.color,
                progress: widget.progress,
                stroke: size * 0.075,
                glow: widget.glow,
              ),
              pressed: _pressed,
              washer: Color.lerp(
                palette.edge,
                widget.pulseColor,
                0.85 * widget.pulse.clamp(0.0, 1.0),
              )!,
            ),
            child: Center(
              child: widget.text != null
                  ? Text(
                      widget.text!,
                      style: TextStyle(
                        fontFamily: LoopinFonts.display,
                        fontSize: size * 0.26,
                        height: 1,
                        color: LoopinPalette.metalInk,
                      ),
                    )
                  : (widget.icon != null
                        ? Icon(widget.icon, size: size * 0.2, color: LoopinPalette.metalInk)
                        : null),
            ),
          ),
        ),
      ),
    );
  }
}

/// El anillo de luz y, dentro, la tapa metálica del pulsador con su arandela.
class _FootswitchPainter extends CustomPainter {
  const _FootswitchPainter({required this.ring, required this.pressed, required this.washer});

  final RingPainter ring;
  final bool pressed;
  final Color washer;

  @override
  void paint(Canvas canvas, Size size) {
    ring.paint(canvas, size);
    final center = size.center(Offset.zero);
    final s = math.min(size.width, size.height);
    final scale = pressed ? 0.97 : 1.0;
    canvas.drawCircle(center, s * 0.345, Paint()..color = washer);
    canvas.drawCircle(center, s * 0.305 * scale, Paint()..color = LoopinPalette.metalEdge);
    canvas.drawCircle(
      center,
      s * 0.285 * scale,
      Paint()..color = pressed ? LoopinPalette.metalPressed : LoopinPalette.metal,
    );
    canvas.drawCircle(
      center,
      s * 0.19 * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.008
        ..color = LoopinPalette.metalEdge.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_FootswitchPainter old) =>
      old.pressed != pressed || old.washer != washer || old.ring.shouldRepaint(ring);
}
