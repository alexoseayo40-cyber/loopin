// Loopin — leer y escribir WAV (las pistas de las sesiones)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

/// WAV mono en float de 32 bits: guarda las pistas tal cual (sin perder nada,
/// aunque las capas sumadas pasen de 1).
Uint8List encodeWavFloat(Float32List samples, int sampleRate) {
  final data = samples.length * 4;
  final out = Uint8List(44 + data);
  final b = ByteData.sublistView(out);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      out[at + i] = s.codeUnitAt(i);
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + data, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 3, Endian.little); // float
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 4, Endian.little);
  b.setUint16(32, 4, Endian.little);
  b.setUint16(34, 32, Endian.little);
  tag(36, 'data');
  b.setUint32(40, data, Endian.little);
  final view = Float32List.sublistView(out, 44);
  view.setAll(0, samples);
  return out;
}

/// Un WAV leído: frecuencia y muestras (el primer canal).
class WavData {
  const WavData(this.sampleRate, this.samples);
  final int sampleRate;
  final Float32List samples;
}

/// Lee un WAV de 16 bits o float de 32 (el primer canal). null si no lo es.
WavData? decodeWav(Uint8List bytes) {
  if (bytes.length < 12) return null;
  String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  final b = ByteData.sublistView(bytes);
  var format = 0, channels = 0, rate = 0, bits = 0;
  var at = 12;
  while (at + 8 <= bytes.length) {
    final id = tag(at);
    final size = b.getUint32(at + 4, Endian.little);
    final body = at + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      format = b.getUint16(body, Endian.little);
      channels = b.getUint16(body + 2, Endian.little);
      rate = b.getUint32(body + 4, Endian.little);
      bits = b.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (channels <= 0 || rate <= 0) return null;
      final end = (body + size).clamp(body, bytes.length);
      final frameBytes = channels * bits ~/ 8;
      if (frameBytes <= 0) return null;
      final frames = (end - body) ~/ frameBytes;
      final out = Float32List(frames);
      if (format == 3 && bits == 32) {
        for (var i = 0; i < frames; i++) {
          out[i] = b.getFloat32(body + i * frameBytes, Endian.little);
        }
      } else if (format == 1 && bits == 16) {
        for (var i = 0; i < frames; i++) {
          out[i] = b.getInt16(body + i * frameBytes, Endian.little) / 32768;
        }
      } else {
        return null;
      }
      return WavData(rate, out);
    }
    at = body + size + (size.isOdd ? 1 : 0);
  }
  return null;
}
