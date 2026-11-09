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
import 'ui/prototype_screen.dart';

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
    return MaterialApp(
      title: 'Loopin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
      ),
      home: PrototypeScreen(controller: _controller),
    );
  }
}
