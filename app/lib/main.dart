// Loopin — looper de guitarra libre
// Copyright (C) 2026 Alex
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file.
//
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import 'engine/engine_controller.dart';
import 'ui/looper_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const LoopinApp());
}

class LoopinApp extends StatefulWidget {
  const LoopinApp({super.key});

  @override
  State<LoopinApp> createState() => _LoopinAppState();
}

class _LoopinAppState extends State<LoopinApp> {
  final EngineController _controller = EngineController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // El tema (claro, oscuro o el del sistema) y el color del chasis se eligen
    // en Ajustes
    return ValueListenableBuilder<Appearance>(
      valueListenable: _controller.appearance,
      builder: (context, look, _) => MaterialApp(
        title: 'Loopin',
        debugShowCheckedModeBanner: false,
        theme: buildLoopinTheme(look.chassis, Brightness.light),
        darkTheme: buildLoopinTheme(look.chassis, Brightness.dark),
        themeMode: look.mode,
        home: LooperScreen(controller: _controller, tutorial: true),
      ),
    );
  }
}
