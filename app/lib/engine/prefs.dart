// Loopin — ajustes guardados en el móvil
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/services.dart';

/// Ajustes guardados entre sesiones (SharedPreferences, desde MainActivity).
/// Todo se guarda como texto.
class Prefs {
  const Prefs();

  static const _channel = MethodChannel('loopin/permissions');

  // Claves
  static const latencies = 'latencies';
  static const inputPreset = 'inputPreset';
  static const autoAdvance = 'autoAdvance';
  static const themeMode = 'themeMode';
  static const chassis = 'chassis';
  static const volumeKeys = 'volumeKeys';
  static const headsetKey = 'headsetKey';
  static const learnedKeys = 'learnedKeys';
  static const bpm = 'bpm';
  static const meter = 'meter';
  static const clickMode = 'clickMode';
  static const loopMode = 'loopMode';
  static const syncBars = 'syncBars';
  static const startOnSound = 'startOnSound';
  static const recordDuck = 'recordDuck';
  static const drumsOn = 'drumsOn';
  static const drumStyle = 'drumStyle';
  static const drumVolume = 'drumVolume';
  static const songId = 'songId';
  static const backingOn = 'backingOn';
  static const backingVolume = 'backingVolume';
  static const accompaniment = 'accompaniment';
  static const playMode = 'playMode';
  static const simpleForced = 'simpleForced';

  Future<String?> get(String key) async {
    try {
      return await _channel.invokeMethod<String>('prefsGet', {'key': key});
    } on Object {
      return null; // sin ajustes guardados (o en un test sin Android)
    }
  }

  Future<void> set(String key, String value) async {
    try {
      await _channel.invokeMethod<void>('prefsSet', {'key': key, 'value': value});
    } on Object {
      // no se pudo guardar: vale solo para esta sesión
    }
  }

  Future<bool?> getBool(String key) async {
    final v = await get(key);
    return v == null ? null : v == '1';
  }

  Future<void> setBool(String key, bool value) => set(key, value ? '1' : '0');
}
