// Loopin — pasar del modo simple al avanzado y al revés
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Parte de engine_controller.dart (comparte sus campos privados). Qué tiene
// cada modo: play_mode.dart.
part of 'engine_controller.dart';

extension PlayModeControl on EngineController {
  /// Mientras se graba no se cambia (el modo de grabación y «empezar al
  /// tocar» cuentan al empezar).
  bool get canChangePlayMode => !recordingNow;

  void setPlayMode(PlayMode mode) {
    if (mode == playMode || !canChangePlayMode) return;
    playMode = mode;
    _prefs.set(Prefs.playMode, mode.name);
    if (simple) {
      _enterSimple();
    } else {
      _leaveSimple();
    }
    notifyListeners();
  }

  /// Lo que no se ve en simple vuelve a sus valores; el que tenía se apunta.
  void _enterSimple() {
    final f = _forced;
    if (loopMode != kSimpleLoopMode) {
      f.remember(SimpleForced.loopMode, loopMode.name);
      setLoopMode(kSimpleLoopMode);
    }
    if (startOnSound) {
      f.remember(SimpleForced.startOnSound, '1');
      setStartOnSound(false);
    }
    // Con loops el compás es el suyo: se queda (y se ve en la pantalla)
    if (!kSimpleMeters.contains(timeSignature.label) && !tempoLocked) {
      f.remember(SimpleForced.meter, timeSignature.label);
      setTimeSignature(kTimeSignatures.firstWhere((t) => t.label == kSimpleMeter));
    }
    if (!kSimpleClickModes.contains(clickMode)) {
      f.remember(SimpleForced.clickMode, clickMode.name);
      setClickMode(ClickMode.always);
    }
    // Sin batería ni canción (no se ven): se apagan, sin parar nada
    if (drumsOn) {
      f.remember(SimpleForced.drumsOn, '1');
      setDrumsOn(false);
    }
    if (backingOn) {
      f.remember(SimpleForced.backingOn, '1');
      setBackingOn(false);
    }
    if (recordDuck != RecordDuck.silent) {
      f.remember(SimpleForced.recordDuck, recordDuck.name);
      setRecordDuck(RecordDuck.silent);
    }
    _applyPreset(); // el micrófono, el recomendado
    _saveForced();
  }

  /// Vuelve lo que el simple cambió, si mientras tanto no se ha tocado.
  void _leaveSimple() {
    final f = _forced;
    _forced = SimpleForced();
    _saveForced();
    T? parse<T extends Enum>(List<T> values, String key) {
      final name = f[key];
      for (final v in values) {
        if (v.name == name) return v;
      }
      return null;
    }

    final loop = parse(LoopMode.values, SimpleForced.loopMode);
    if (loop != null && loopMode == kSimpleLoopMode) setLoopMode(loop);
    if (f[SimpleForced.startOnSound] == '1' && !startOnSound) setStartOnSound(true);
    final meter = kTimeSignatures.where((t) => t.label == f[SimpleForced.meter]);
    if (meter.isNotEmpty && timeSignature.label == kSimpleMeter && !tempoLocked) {
      setTimeSignature(meter.first);
    }
    final click = parse(ClickMode.values, SimpleForced.clickMode);
    if (click != null && clickMode == ClickMode.always) setClickMode(click);
    // La batería y la canción vuelven encendidas, pero no arrancan nada:
    // suenan al darle a ▶ o al grabar, como siempre
    if (f[SimpleForced.drumsOn] == '1' && !drumsOn) {
      drumsOn = true;
      _engine.setDrumsEnabled(true);
      _prefs.setBool(Prefs.drumsOn, true);
    }
    if (f[SimpleForced.backingOn] == '1' && !backingOn) _backing.setOn(true);
    final duck = parse(RecordDuck.values, SimpleForced.recordDuck);
    if (duck != null && recordDuck == RecordDuck.silent) setRecordDuck(duck);
    _applyPreset(); // el micrófono, el que eligió
  }

  void _saveForced() => _prefs.set(Prefs.simpleForced, _forced.encode());
}
