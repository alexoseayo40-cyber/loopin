// Loopin — forma de onda de una canción (vista entera y de cerca)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Una raya vertical sobre la onda (el 1, el cursor…), en fracción del ancho.
class WaveMark {
  const WaveMark(this.at, this.color, {this.width = 2});
  final double at;
  final Color color;
  final double width;
}

/// La onda: un pico por columna, centrado. Encima, rayas finas de la rejilla
/// (los compases) y las marcas.
class Waveform extends StatelessWidget {
  const Waveform({
    super.key,
    required this.peaks,
    this.marks = const [],
    this.grid = const [],
    this.height = 72,
    this.onTap,
    this.onDrag,
    this.semanticLabel,
  });

  final Float32List peaks;
  final List<WaveMark> marks;
  final List<double> grid;
  final double height;

  /// Toque, en fracción del ancho (0–1).
  final ValueChanged<double>? onTap;

  /// Arrastre, en fracción del ancho (lo que se ha movido).
  final ValueChanged<double>? onDrag;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return Semantics(
          label: semanticLabel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: onTap == null ? null : (d) => onTap!((d.localPosition.dx / w).clamp(0, 1)),
            onHorizontalDragUpdate: onDrag == null ? null : (d) => onDrag!(d.delta.dx / w),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: CustomPaint(
                size: Size(w, height),
                painter: _WavePainter(
                  peaks: peaks,
                  marks: marks,
                  grid: grid,
                  wave: scheme.onSurfaceVariant,
                  gridColor: scheme.outlineVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.peaks,
    required this.marks,
    required this.grid,
    required this.wave,
    required this.gridColor,
  });

  final Float32List peaks;
  final List<WaveMark> marks;
  final List<double> grid;
  final Color wave;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final mid = h / 2;
    final g = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final x in grid) {
      if (x < 0 || x > 1) continue;
      canvas.drawLine(Offset(x * size.width, 4), Offset(x * size.width, h - 4), g);
    }
    if (peaks.isNotEmpty) {
      final p = Paint()
        ..color = wave
        ..strokeWidth = (size.width / peaks.length).clamp(1.0, 3.0);
      for (var i = 0; i < peaks.length; i++) {
        final x = (i + 0.5) * size.width / peaks.length;
        final a = peaks[i].clamp(0.0, 1.0) * (mid - 3);
        canvas.drawLine(Offset(x, mid - a - 0.5), Offset(x, mid + a + 0.5), p);
      }
    }
    for (final m in marks) {
      if (m.at < 0 || m.at > 1) continue;
      final paint = Paint()
        ..color = m.color
        ..strokeWidth = m.width;
      canvas.drawLine(Offset(m.at * size.width, 0), Offset(m.at * size.width, h), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.peaks != peaks ||
      old.wave != wave ||
      old.gridColor != gridColor ||
      !_sameMarks(old.marks, marks) ||
      !_sameList(old.grid, grid);

  static bool _sameMarks(List<WaveMark> a, List<WaveMark> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].at != b[i].at || a[i].color != b[i].color || a[i].width != b[i].width) {
        return false;
      }
    }
    return true;
  }

  static bool _sameList(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
