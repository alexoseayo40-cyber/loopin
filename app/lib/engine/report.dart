// Loopin — «Copiar resultados»: resumen para pegar en una incidencia o en el plan
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:loopin_engine/loopin_engine.dart';

import '../l10n/language.dart';
import 'engine_controller.dart';

extension EngineReport on EngineController {
  /// Resumen del móvil, la ruta de audio, la latencia, la carga y el looper.
  String report() {
    final s = status;
    // En español si la app está en español; si no, en inglés (ver report_strings.dart)
    final tr = reportStrings;
    final r = tr.report;
    String ms(double v) => tr.ms(v);
    final api = switch (s.audioApi) {
      AudioApi.aaudio => 'AAudio',
      AudioApi.openSles => 'OpenSL ES',
      AudioApi.unknown => '—',
    };
    final source = switch (latencySource) {
      LatencySource.measured => r.measured,
      LatencySource.estimated => r.estimated,
      LatencySource.none => r.unmeasured,
    };
    String mode(bool exclusive) => exclusive ? tr.exclusiveMode : tr.sharedMode;
    String low(bool on) => on ? tr.lowLatency : r.normalLatency;
    return [
      tr.reportTitle(appVersion),
      r.phone(
        '${deviceInfo['model'] ?? '—'}',
        '${deviceInfo['android'] ?? '—'}',
        tr.yesNo(deviceInfo['lowLatency']),
        tr.yesNo(deviceInfo['proAudio']),
      ),
      r.route(routeLabel),
      r.mic(
        s.inputPreset == null ? '—' : tr.presetName(s.inputPreset!),
        s.presetFallback,
        tr.yesNo(deviceInfo['unprocessed']),
        inputGainDb,
      ),
      r.stream(api, s.sampleRate, s.framesPerBurst, s.bufferSizeFrames, ms(s.bufferMs)),
      r.output(mode(s.exclusive), low(s.lowLatency)),
      r.input(
        mode(s.inputExclusive),
        low(s.inputLowLatency),
        s.inputFramesPerBurst,
        s.inputBufferFrames,
        s.inputMaxRead,
        tr.channels(s.inputChannels),
      ),
      r.estimate(ms(s.outputLatencyMs), ms(s.inputLatencyMs)),
      if (s.latencyState == LatencyState.done) r.roundTrip(ms(s.latencyMs), s.latencyFrames),
      r.compensation(ms(compensationMs), source),
      tr.engineLoad(tr.percent(s.cpuLoad), tr.percent(s.cpuLoadPeak), tr.percent(s.cpuLoadMax)),
      if (s.playing || s.framePosition > 0)
        r.metronomeRun(s.bpm.round(), s.playSeconds / 60, xrunsSincePlay),
      // Cortes desde que se abrió el audio (el buffer sube si los hay)
      if (s.xrunCount >= 0) r.xrunsSinceOpen(s.xrunCount),
      r.metronome(
        tr.meterChip(timeSignature),
        tr.clickModeName(clickMode).toLowerCase(),
        tr.yesNo(startOnSound),
      ),
      r.playMode(tr.playModeName(playMode).toLowerCase()),
      r.looper(
        r.loopStateName(s.loopState),
        tr.loopModeName(loopMode),
        s.hasLoops ? s.baseBars : null,
        tr.yesNo(autoAdvance),
      ),
      r.drums(
        tr.drumStyleName(drumStyleNow),
        drumsOn,
        s.drumsPlaying,
        (drumVolume * 100).round(),
        drumSoundsLoaded,
      ),
      r.song(
        currentSong?.name,
        tr
            .backingPhase(backingPhase, bpm: tr.bpmNumber(s.bpm), progress: backingProgress)
            .replaceAll('.', '')
            .toLowerCase(),
        backingOn,
        s.backingPlaying,
        (backingVolume * 100).round(),
        songs.length,
      ),
      r.recordDuck(tr.recordDuckName(recordDuck).toLowerCase(), speakerRoute),
      for (var i = 0; i < s.tracks.length; i++)
        if (s.tracks[i].state != LoopState.empty)
          r.track(
            i + 1,
            r.loopStateName(s.tracks[i].state),
            s.tracks[i].hasLoop && s.loopBarFrames > 0
                ? (s.tracks[i].length / s.loopBarFrames).round()
                : null,
            s.tracks[i].layers,
            s.tracks[i].muted,
            reverse: s.tracks[i].reverse,
            half: s.tracks[i].half,
          ),
      r.live(
        tr.stopModeName(stopMode).toLowerCase(),
        quantize,
        trainerOn ? r.trainerSetting(trainerStep.round(), trainerBars, trainerTop.round()) : null,
        tunerA4,
      ),
      r.controls(
        tr.yesNo(volumeKeys),
        tr.yesNo(headsetKey),
        learnedKeys.isEmpty
            ? r.none
            : learnedKeys.map((k) => tr.keyName(k.code, k.name)).join(', '),
      ),
    ].join('\n');
  }
}
