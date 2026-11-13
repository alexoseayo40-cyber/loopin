// Loopin — qué cambios del motor obligan a redibujar la pantalla entera
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:loopin_engine/loopin_engine.dart';

/// El estado del motor se consulta 30 veces por segundo, pero casi todo lo que
/// llega cambia solo de vez en cuando (el estado del looper, el tempo, la
/// pista elegida…). Lo que cambia a cada momento (por dónde va cada pista, lo
/// grabado, el nivel de entrada, el tiempo que suena, la carga…) no cuenta
/// aquí: lo dibujan solas las piezas que se mueven, que escuchan a
/// `EngineController.live`.
bool layoutChanged(EngineStatus a, EngineStatus b) {
  if (a.running != b.running ||
      a.disconnected != b.disconnected ||
      a.sampleRate != b.sampleRate ||
      a.framesPerBurst != b.framesPerBurst ||
      a.bufferSizeFrames != b.bufferSizeFrames ||
      a.audioApi != b.audioApi ||
      a.exclusive != b.exclusive ||
      a.lowLatency != b.lowLatency ||
      a.inputChannels != b.inputChannels ||
      a.inputPreset != b.inputPreset ||
      a.presetFallback != b.presetFallback ||
      a.inputDeviceId != b.inputDeviceId ||
      a.outputDeviceId != b.outputDeviceId ||
      // Transporte
      a.playing != b.playing ||
      a.bpm != b.bpm ||
      a.beatsPerBar != b.beatsPerBar ||
      a.samplesPerBeat != b.samplesPerBeat ||
      a.accentMask != b.accentMask ||
      a.clickMode != b.clickMode ||
      a.startOnSound != b.startOnSound ||
      // Batería (entra en un 1: cambia lo que se ve)
      a.drumsEnabled != b.drumsEnabled ||
      a.drumStyle != b.drumStyle ||
      a.drumsPlaying != b.drumsPlaying ||
      // Audio importado (entra en un 1, se prepara, se abre…)
      a.backingEnabled != b.backingEnabled ||
      a.backingPlaying != b.backingPlaying ||
      a.backingId != b.backingId ||
      a.backingSamplesPerBeat != b.backingSamplesPerBeat ||
      a.backingBeatsPerBar != b.backingBeatsPerBar ||
      a.songPrepState != b.songPrepState ||
      a.songOpenState != b.songOpenState ||
      a.previewId != b.previewId ||
      a.previewPlaying != b.previewPlaying ||
      a.previewClick != b.previewClick ||
      // Medidas de latencia
      a.latencyState != b.latencyState ||
      a.latencyFrames != b.latencyFrames ||
      a.tapState != b.tapState ||
      a.tapFrames != b.tapFrames ||
      a.tapSpread != b.tapSpread ||
      // Looper
      a.loopState != b.loopState ||
      a.loopMode != b.loopMode ||
      a.loopSyncBars != b.loopSyncBars ||
      a.loopLayers != b.loopLayers ||
      a.loopCanUndo != b.loopCanUndo ||
      a.loopLatencyFrames != b.loopLatencyFrames ||
      a.loopLength != b.loopLength ||
      a.loopTarget != b.loopTarget ||
      a.loopBarFrames != b.loopBarFrames ||
      a.loopWaiting != b.loopWaiting ||
      // Esperando al compás (negativo) o ya grabando
      (a.loopRecorded < 0) != (b.loopRecorded < 0) ||
      a.selectedTrack != b.selectedTrack ||
      a.activeTrack != b.activeTrack ||
      a.autoAdvance != b.autoAdvance ||
      a.baseLength != b.baseLength ||
      // Directo y práctica
      a.quantize != b.quantize ||
      a.stopMode != b.stopMode ||
      a.stopping != b.stopping ||
      a.trainerBars != b.trainerBars ||
      a.trainerStep != b.trainerStep ||
      a.trainerTop != b.trainerTop ||
      a.tracks.length != b.tracks.length) {
    return true;
  }
  for (var i = 0; i < a.tracks.length; i++) {
    final x = a.tracks[i], y = b.tracks[i];
    if (x.state != y.state ||
        x.layers != y.layers ||
        x.muted != y.muted ||
        x.volume != y.volume ||
        x.length != y.length ||
        x.reverse != y.reverse ||
        x.half != y.half ||
        x.pending != y.pending) {
      return true;
    }
  }
  return false;
}
