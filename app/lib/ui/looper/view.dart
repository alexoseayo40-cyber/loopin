// Loopin — lo que comparten las piezas de la pantalla del looper
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:loopin_engine/loopin_engine.dart';

import '../../engine/engine_controller.dart';
import '../theme.dart';

/// Lo que necesitan todas las piezas de la pantalla.
///
/// Redibujado: la pantalla entera escucha al controlador, que solo avisa
/// cuando cambia algo (el estado del looper, el tempo…). Lo que se mueve a
/// cada momento (anillos, pulsador, nivel de entrada) escucha además
/// [EngineController.live], que avisa 30 veces por segundo; las luces de los
/// tiempos se redibujan en cada fotograma con [BeatBuilder].
class LooperView {
  const LooperView({
    required this.controller,
    required this.palette,
    required this.onSettings,
    required this.onLatency,
    required this.onTuner,
    this.onSessions,
    this.onStage,
  });

  final EngineController controller;
  final LoopinPalette palette;
  final VoidCallback onSettings;
  final VoidCallback onLatency;
  final VoidCallback onTuner;

  /// Sesiones (el nombre de arriba) y modo escenario.
  final VoidCallback? onSessions;
  final VoidCallback? onStage;

  /// El último estado del motor.
  EngineStatus get s => controller.status;
}

/// Cuánto lleva la grabación en curso, de 0 a 1 (para los anillos).
double recordProgress(EngineStatus s) {
  if (s.loopRecorded < 0) {
    // Esperando: lo que falta del compás
    return s.loopBarFrames > 0 ? (1 + s.loopRecorded / s.loopBarFrames).clamp(0.0, 1.0) : 0;
  }
  if (s.loopTarget > 0) return (s.loopRecorded / s.loopTarget).clamp(0.0, 1.0);
  // Sin final fijado: una vuelta por cada vuelta de la base, por compás o
  // (en libre, sin compás aún) cada 4 segundos
  final lap = s.baseLength > 0
      ? s.baseLength
      : (s.loopBarFrames > 0 ? s.loopBarFrames : s.sampleRate * 4);
  return lap > 0 ? (s.loopRecorded % lap) / lap : 0;
}

/// Color del anillo según el estado (null = apagado).
Color? stateColor(LoopState st, {bool waiting = false, bool muted = false}) => switch (st) {
  LoopState.empty => null,
  LoopState.armed => LoopinPalette.count,
  LoopState.recording => LoopinPalette.rec,
  LoopState.playing => muted ? LoopinPalette.stopped : LoopinPalette.play,
  LoopState.overdubbing => waiting ? LoopinPalette.count : LoopinPalette.dub,
  LoopState.stopped => LoopinPalette.stopped,
};

/// El modo de grabación solo cuenta al empezar a grabar: mientras tanto no se
/// cambia.
bool modeLocked(EngineStatus s) =>
    s.loopState == LoopState.armed || s.loopState == LoopState.recording;
