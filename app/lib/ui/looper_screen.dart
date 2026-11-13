// Loopin — pantalla del looper: la cara de un pedal con 4 pistas
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Aquí solo va la disposición (vertical y apaisado). Las piezas están en
// ui/looper/: cabecera, pantalla de tempo, pistas, pulsador y barra de abajo.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine_controller.dart';
import 'audio_settings_screen.dart';
import 'looper/bottom_bar.dart';
import 'looper/drum_row.dart';
import 'looper/pedal_area.dart';
import 'looper/tempo_display.dart';
import 'looper/top_bar.dart';
import 'looper/tracks.dart';
import 'looper/view.dart';
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
                  final view = LooperView(
                    controller: c,
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

// ---------------------------------------------------------------------------
// Disposición

/// En vertical: todo en una columna, con el pulsador abajo, a mano.
class _TallLayout extends StatelessWidget {
  const _TallLayout({required this.view, required this.box, required this.mixer});

  final LooperView view;
  final BoxConstraints box;
  final bool mixer;

  @override
  Widget build(BuildContext context) {
    // En una tablet la columna no ocupa todo el ancho
    final width = math.min(box.maxWidth, 720.0);
    // Pantallas bajas: todo más apretado; en las muy bajas, más aún (y el
    // pulsador puede bajar hasta 100)
    final compact = box.maxHeight < 820;
    final tight = box.maxHeight < 700;
    final gap = tight ? 4.0 : (compact ? 8.0 : 14.0);
    final rings = tight ? 48.0 : (compact ? 60.0 : 96.0);
    // Lo que ocupa todo menos el pulsador (medido, con la fila de la batería),
    // para darle el resto
    final fixed = (tight ? 543.0 : (compact ? 568.0 : 694.0)) + (mixer ? 3 * 52.0 : 0);
    final pedal = (math.min(
      width * 0.62,
      box.maxHeight - fixed,
    )).clamp(tight ? 100.0 : 132.0, mixer ? 420.0 : 340.0);
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
                    TopBar(view: view),
                    TempoDisplay(view: view, compact: compact),
                    SizedBox(height: gap),
                    TrackRings(view: view, maxSize: rings),
                    SizedBox(height: gap),
                    TrackControls(view: view, mixer: mixer),
                    const SizedBox(height: 6),
                    DrumRow(view: view, dense: compact),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: gap),
                  child: PedalArea(view: view, size: pedal),
                ),
                BottomBar(view: view, showHint: !compact),
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

  final LooperView view;
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
                  TopBar(view: view),
                  TempoDisplay(view: view, compact: compact),
                  SizedBox(height: gap),
                  TrackRings(view: view, maxSize: compact ? 64 : 96),
                  SizedBox(height: gap),
                  TrackControls(view: view, mixer: mixer),
                  const SizedBox(height: 6),
                  DrumRow(view: view, dense: compact),
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
                        child: PedalArea(view: view, size: pedal),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: gap),
                        child: BottomBar(view: view, showHint: !compact),
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
