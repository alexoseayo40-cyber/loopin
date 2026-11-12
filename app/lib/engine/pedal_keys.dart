// Loopin — controles externos: botones de volumen, de los cascos y pedales
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/services.dart';

import 'prefs.dart';

/// Lo que puede hacer un botón externo (botones de volumen, botón de los
/// cascos, pedal Bluetooth…).
enum PedalAction {
  /// Como el botón grande: toque, mantener y doble toque.
  main,

  /// Toque: siguiente pista. Mantener: deshacer.
  secondary,
}

/// Una tecla aprendida (de un pedal Bluetooth, un teclado…).
class LearnedKey {
  const LearnedKey({required this.code, required this.name, required this.action});

  /// Código de tecla de Android (KeyEvent.KEYCODE_*).
  final int code;

  /// Nombre de Android («KEYCODE_PAGE_DOWN»); puede venir vacío.
  final String name;
  final PedalAction action;

  /// Nombre corto para mostrar: «PAGE_DOWN» en vez de «KEYCODE_PAGE_DOWN».
  String get label => shortKeyName(name);
}

/// «PAGE_DOWN» en vez de «KEYCODE_PAGE_DOWN».
String shortKeyName(String name) => name.startsWith('KEYCODE_') ? name.substring(8) : name;

/// Las teclas externas y qué hace cada una.
///
/// Android entrega las teclas a MainActivity, que nos pasa solo las que nos
/// interesan (y se las queda, para que los botones de volumen no cambien el
/// volumen mientras hacen de pedal).
class PedalKeys {
  PedalKeys({required this.onAction, required this.onChanged, this.prefs = const Prefs()}) {
    _channel.setMethodCallHandler(_onCall);
  }

  /// Una tecla con acción se ha pulsado ([down]) o soltado.
  final void Function(PedalAction action, {required bool down}) onAction;

  /// Ha cambiado algo que se ve en Ajustes.
  final void Function() onChanged;
  final Prefs prefs;

  static const _channel = MethodChannel('loopin/keys');

  /// Subir volumen = botón principal; bajar volumen = botón secundario.
  bool volumeKeys = false;

  /// El botón central de los cascos (o de un mando multimedia) = principal.
  bool headsetKey = true;

  /// Teclas aprendidas (pedal Bluetooth, teclado…).
  List<LearnedKey> learned = const [];

  /// Si no es null, la próxima tecla que se pulse se asigna a esta acción.
  PedalAction? learning;

  /// La última tecla recibida, para comprobar que el pedal funciona (código,
  /// nombre de Android —puede venir vacío— y acción).
  int? lastKeyCode;
  String lastKeyName = '';
  PedalAction? lastKeyAction;

  static const _keyVolumeUp = 24, _keyVolumeDown = 25;
  static const _keyHeadsetHook = 79, _keyPlayPause = 85, _keyPlay = 126, _keyPause = 127;
  static const _keyMediaNext = 87;

  PedalAction? actionFor(int code) {
    for (final k in learned) {
      if (k.code == code) return k.action;
    }
    if (volumeKeys) {
      if (code == _keyVolumeUp) return PedalAction.main;
      if (code == _keyVolumeDown) return PedalAction.secondary;
    }
    if (headsetKey) {
      if (code == _keyHeadsetHook ||
          code == _keyPlayPause ||
          code == _keyPlay ||
          code == _keyPause) {
        return PedalAction.main;
      }
      if (code == _keyMediaNext) return PedalAction.secondary;
    }
    return null;
  }

  /// Dice a Android qué teclas tiene que pasarnos.
  Future<void> syncCapture() async {
    final codes = <int>{
      for (final k in learned) k.code,
      if (volumeKeys) ...[_keyVolumeUp, _keyVolumeDown],
      if (headsetKey) ...[_keyHeadsetHook, _keyPlayPause, _keyPlay, _keyPause, _keyMediaNext],
    };
    try {
      await _channel.invokeMethod<void>('setCapture', {
        'codes': codes.toList(),
        'learning': learning != null,
      });
    } on Object {
      // sin Android (tests): no hay teclas que capturar
    }
  }

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'key') return null;
    final args = call.arguments as Map<Object?, Object?>;
    handle(
      (args['code'] as num).toInt(),
      down: args['down'] == true,
      repeat: (args['repeat'] as num?)?.toInt() ?? 0,
      name: (args['name'] as String?) ?? '',
    );
    return null;
  }

  /// Una tecla externa se ha pulsado o soltado.
  void handle(int code, {required bool down, int repeat = 0, String name = ''}) {
    final toLearn = learning;
    if (toLearn != null) {
      if (!down || repeat > 0) return;
      learned = [
        for (final k in learned)
          if (k.code != code) k,
        LearnedKey(code: code, name: name, action: toLearn),
      ];
      learning = null;
      _changedKeys();
      return;
    }
    final action = actionFor(code);
    if (action == null || repeat > 0) return;
    if (down) {
      lastKeyCode = code;
      lastKeyName = name;
      lastKeyAction = action;
    }
    onAction(action, down: down);
  }

  void setVolumeKeys(bool on) {
    volumeKeys = on;
    prefs.setBool(Prefs.volumeKeys, on);
    syncCapture();
    onChanged();
  }

  void setHeadsetKey(bool on) {
    headsetKey = on;
    prefs.setBool(Prefs.headsetKey, on);
    syncCapture();
    onChanged();
  }

  void startLearning(PedalAction action) {
    learning = action;
    syncCapture();
    onChanged();
  }

  void cancelLearning() {
    learning = null;
    syncCapture();
    onChanged();
  }

  void forget(int code) {
    learned = [
      for (final k in learned)
        if (k.code != code) k,
    ];
    _changedKeys();
  }

  void _changedKeys() {
    prefs.set(
      Prefs.learnedKeys,
      jsonEncode([
        for (final k in learned) {'code': k.code, 'name': k.name, 'action': k.action.name},
      ]),
    );
    syncCapture();
    onChanged();
  }

  Future<void> load() async {
    volumeKeys = await prefs.getBool(Prefs.volumeKeys) ?? volumeKeys;
    headsetKey = await prefs.getBool(Prefs.headsetKey) ?? headsetKey;
    try {
      final raw = await prefs.get(Prefs.learnedKeys);
      if (raw != null) {
        learned = [
          for (final e in jsonDecode(raw) as List)
            LearnedKey(
              code: ((e as Map<String, dynamic>)['code'] as num).toInt(),
              name: (e['name'] as String?) ?? '',
              action: PedalAction.values.firstWhere(
                (a) => a.name == e['action'],
                orElse: () => PedalAction.main,
              ),
            ),
        ];
      }
    } on Object {
      learned = const [];
    }
    await syncCapture();
  }

  void dispose() => _channel.setMethodCallHandler(null);
}
