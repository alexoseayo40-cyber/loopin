// Loopin — batería: estilos, compases y muestras
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:loopin_engine/loopin_engine.dart';

import 'meter.dart';

/// Compás de cada estilo (null = vale para todos). Si el compás de ahora no
/// es el suyo, el motor toca el básico.
String? drumStyleMeter(DrumStyle s) => switch (s) {
  DrumStyle.basic => null,
  DrumStyle.waltz => '3/4',
  DrumStyle.sixEight => '6/8',
  DrumStyle.slowBlues => '12/8',
  _ => '4/4',
};

/// El estilo vale con este compás.
bool drumStyleFits(DrumStyle s, TimeSignature ts) {
  final m = drumStyleMeter(s);
  return m == null || m == ts.label;
}

/// Lo que suena de verdad con el compás de ahora.
DrumStyle effectiveDrumStyle(DrumStyle s, TimeSignature ts) =>
    drumStyleFits(s, ts) ? s : DrumStyle.basic;

/// Archivo de cada sonido en assets/drums (WAV mono de 16 bits, CC0; ver
/// assets/drums/LICENSE.md).
String drumAsset(DrumSound s) =>
    'assets/drums/${switch (s) {
      DrumSound.kick => 'kick',
      DrumSound.snare => 'snare',
      DrumSound.snareSoft => 'snare_soft',
      DrumSound.crossStick => 'xstick',
      DrumSound.hat => 'hat',
      DrumSound.hatSoft => 'hat_soft',
      DrumSound.hatOpen => 'hat_open',
      DrumSound.ride => 'ride',
      DrumSound.crash => 'crash',
      DrumSound.sticks => 'sticks',
    }}.wav';

/// Un WAV PCM de 16 bits (mono o el primer canal) en float. null si no se
/// entiende.
({Float32List samples, int sampleRate})? decodeWav16(ByteData b) {
  if (b.lengthInBytes < 44) return null;
  String tag(int at) => String.fromCharCodes(b.buffer.asUint8List(b.offsetInBytes + at, 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  var channels = 0, rate = 0, bits = 0;
  var p = 12;
  while (p + 8 <= b.lengthInBytes) {
    final id = tag(p);
    final len = b.getUint32(p + 4, Endian.little);
    if (id == 'fmt ') {
      if (b.getUint16(p + 8, Endian.little) != 1) return null; // solo PCM
      channels = b.getUint16(p + 10, Endian.little);
      rate = b.getUint32(p + 12, Endian.little);
      bits = b.getUint16(p + 22, Endian.little);
    } else if (id == 'data') {
      if (channels < 1 || bits != 16 || rate <= 0) return null;
      final end = (p + 8 + len).clamp(0, b.lengthInBytes);
      final frames = (end - p - 8) ~/ (2 * channels);
      final out = Float32List(frames);
      for (var i = 0; i < frames; i++) {
        out[i] = b.getInt16(p + 8 + i * 2 * channels, Endian.little) / 32768.0;
      }
      return (samples: out, sampleRate: rate);
    }
    p += 8 + len + (len & 1);
  }
  return null;
}

/// Carga el kit de assets/drums en el motor (antes de abrir el audio).
/// Devuelve cuántos sonidos se han cargado.
Future<int> loadDrumKit(LoopinEngine engine, {AssetBundle? bundle}) async {
  final b = bundle ?? rootBundle;
  var loaded = 0;
  for (final s in DrumSound.values) {
    try {
      final wav = decodeWav16(await b.load(drumAsset(s)));
      if (wav == null) continue;
      engine.setDrumSample(s, wav.samples, wav.sampleRate);
      loaded++;
    } on Object {
      // sin ese sonido: no suena, pero lo demás sí
    }
  }
  return loaded;
}
