// Loopin — simulador de músico y móvil para los tests del motor
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Un simulador hace de músico y de móvil: el músico toca sobre lo que oye y su
// sonido llega a la entrada con la latencia de ida y vuelta L, en bloques de
// entrada distintos (y a trompicones) de los de salida. Así, lo que el músico
// toca «sobre» la muestra de salida n entra como la muestra de entrada n + L.
#pragma once

#include <algorithm>
#include <functional>
#include <random>
#include <vector>

#include "EngineCore.h"
#include "test_util.h"

namespace loopin_test {

using namespace loopin;
using T = Command::Type;
using St = Looper::State;

constexpr int64_t kInf = Looper::kNever;

// Señal de prueba de una capa: valores múltiplos de 1/4096, así las sumas de
// varias capas son exactas en float y se pueden comparar con ==.
inline float sig(int seed, int64_t p) {
  return float(1 + (p * (2 * seed + 1) + seed * 13) % 61) / 4096.0f;
}

struct Rig {
  EngineCore core;
  int32_t sr;
  int32_t L;
  std::mt19937 rng;
  int32_t inJitter = 300;  // la entrada va hasta 300 muestras por detrás
  std::function<float(int64_t)> player = [](int64_t) { return 0.0f; };
  // Lo que suena por el altavoz y vuelve a entrar por el micrófono (0 = cascos)
  float bleed = 0.0f;
  std::function<void(int64_t, float)> onOut;
  bool keep = true;
  std::vector<float> hist;  // toda la salida (canal izquierdo), hist[n]
  int64_t outPos = 0, inPos = 0;
  std::vector<float> inBuf, outBuf;

  Rig(int32_t sampleRate, int32_t latency, uint32_t seed = 1)
      : sr(sampleRate), L(latency), rng(seed) {
    core.prepare(sr);
    inBuf.assign(EngineCore::kMaxBlockFrames, 0.0f);
    outBuf.assign(EngineCore::kMaxBlockFrames * 2, 0.0f);
    post(T::kSetLatencyFrames, L);
    post(T::kSetClickEnabled, 0);
  }
  void post(T t, double v = 0) { core.post({t, v}); }
  void postTrack(T t, int32_t track, double v = 0) {
    Command c;
    c.type = t;
    c.value = v;
    c.arg = track;
    core.post(c);
  }
  const Looper& lp() const { return core.looper(); }
  St state() const { return lp().state(); }

  // Procesa hasta que la próxima muestra de salida sea target. Las órdenes
  // enviadas antes se aplican justo en outPos.
  void runTo(int64_t target) {
    while (outPos < target) {
      const int32_t n = int32_t(std::min<int64_t>(randomBlock(rng), target - outPos));
      const int64_t avail = outPos + n - (inJitter > 0 ? int64_t(rng() % inJitter) : 0);
      const int32_t m =
          int32_t(std::clamp<int64_t>(avail - inPos, 0, EngineCore::kMaxBlockFrames));
      for (int32_t k = 0; k < m; ++k) {
        const int64_t o = inPos + k - L;  // la salida que suena en el aire ahora
        inBuf[k] = player(o);
        if (bleed != 0.0f && o >= 0 && o < int64_t(hist.size())) inBuf[k] += bleed * hist[o];
      }
      inPos += m;
      core.process(inBuf.data(), m, 1, outBuf.data(), n, 2);
      for (int32_t i = 0; i < n; ++i) {
        const float s = outBuf[i * 2];
        if (onOut) onOut(outPos + i, s);
        if (keep) hist.push_back(s);
      }
      outPos += n;
    }
  }
  void runFor(int64_t frames) { runTo(outPos + frames); }
  // Envía una orden que se aplicará en la muestra at
  void postAt(int64_t at, T t, double v = 0) {
    runTo(at);
    post(t, v);
  }
};

inline int64_t wrapPos(int64_t a, int64_t m) {
  const int64_t r = a % m;
  return r < 0 ? r + m : r;
}

}  // namespace loopin_test
