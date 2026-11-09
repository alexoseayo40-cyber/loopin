// Loopin — medidor de latencia
// SPDX-License-Identifier: GPL-3.0-or-later
#include "LatencyMeter.h"

#include <algorithm>
#include <cmath>

namespace loopin {

namespace {
constexpr double kPi = 3.14159265358979323846;
constexpr double kPulseFreq = 2000.0;  // 3 ciclos a 2 kHz: corto y nítido
constexpr int kPulseCycles = 3;
constexpr float kMinThreshold = 0.02f;
}  // namespace

void LatencyMeter::start() {
  state_ = State::kRunning;
  justStarted_ = true;
  round_ = 0;
  successes_ = 0;
  failures_ = 0;
  resultFrames_ = 0;
  phase_ = Phase::kListen;
  noisePeak_ = 0.0f;
  pulseIndex_ = -1;
}

void LatencyMeter::nextRound() {
  ++round_;
  if (round_ >= kRounds) {
    finish();
    return;
  }
  phase_ = Phase::kListen;
  phaseEndOut_ = outFrames_ + sampleRate_ / 5;  // 0,2 s
  noisePeak_ = 0.0f;
}

void LatencyMeter::finish() {
  if (successes_ >= 3) {
    std::sort(results_.begin(), results_.begin() + successes_);
    resultFrames_ = results_[successes_ / 2];
    state_ = State::kDone;
  } else {
    state_ = State::kFailed;
  }
}

void LatencyMeter::process(const float* inMono, int32_t inFrames, int64_t inStart,
                           float* outMono, int32_t outFrames, int64_t outStart) {
  if (state_ != State::kRunning) return;
  inFrames_ = inStart;
  outFrames_ = outStart;
  if (justStarted_) {
    justStarted_ = false;
    phaseEndOut_ = outStart + sampleRate_ / 2;  // 0,5 s escuchando el ruido de fondo
  }

  const int32_t pulseLength =
      static_cast<int32_t>(sampleRate_ * kPulseCycles / kPulseFreq);

  // --- Entrada ---
  for (int32_t i = 0; i < inFrames; ++i) {
    const int64_t idx = inFrames_ + i;
    const float a = std::fabs(inMono[i]);
    if (phase_ == Phase::kListen) {
      noisePeak_ = std::max(noisePeak_, a);
    } else if ((phase_ == Phase::kDetect || phase_ == Phase::kEmit) && pulseIndex_ >= 0 &&
               idx >= emitAt_ && a > threshold_) {
      // Pulso detectado
      results_[successes_++] = static_cast<int32_t>(idx - emitAt_);
      phase_ = Phase::kCooldown;
      phaseEndOut_ = outFrames_ + sampleRate_ * 4 / 10;  // 0,4 s para que se apague
      pulseIndex_ = -1;
      break;
    }
  }
  inFrames_ += inFrames;

  // --- Salida ---
  for (int32_t i = 0; i < outFrames; ++i) {
    const int64_t idx = outFrames_ + i;
    switch (phase_) {
      case Phase::kListen:
        if (idx >= phaseEndOut_) {
          threshold_ = std::max(kMinThreshold, noisePeak_ * 3.0f);
          phase_ = Phase::kEmit;
          emitAt_ = idx;
          pulseIndex_ = 0;
        }
        break;
      case Phase::kCooldown:
        if (idx >= phaseEndOut_) {
          nextRound();
          if (state_ != State::kRunning) {
            outFrames_ += outFrames;
            return;
          }
        }
        break;
      default:
        break;
    }
    if (phase_ == Phase::kEmit && pulseIndex_ >= 0 && idx >= emitAt_) {
      const int64_t k = idx - emitAt_;
      if (k < pulseLength) {
        outMono[i] += 0.95f * static_cast<float>(
            std::sin(2.0 * kPi * kPulseFreq * double(k) / sampleRate_));
      } else {
        phase_ = Phase::kDetect;
        phaseEndOut_ = emitAt_ + sampleRate_;  // 1 s como máximo para volver
      }
    }
    if (phase_ == Phase::kDetect && idx >= phaseEndOut_) {
      // No ha llegado: ronda fallida
      ++failures_;
      pulseIndex_ = -1;
      if (failures_ > kRounds - 3) {
        finish();
        outFrames_ += outFrames;
        return;
      }
      nextRound();
    }
  }
  outFrames_ += outFrames;
}

}  // namespace loopin
