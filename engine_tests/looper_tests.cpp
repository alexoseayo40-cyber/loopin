// Loopin — tests del looper (PC)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Un simulador hace de músico y de móvil: el músico toca sobre lo que oye y su
// sonido llega a la entrada con la latencia de ida y vuelta L, en bloques de
// entrada distintos (y a trompicones) de los de salida. Así, lo que el músico
// toca «sobre» la muestra de salida n entra como la muestra de entrada n + L.
#include <algorithm>
#include <cmath>
#include <functional>
#include <vector>

#include "EngineCore.h"
#include "test_util.h"

using namespace loopin;
using T = Command::Type;
using St = Looper::State;

namespace {

constexpr int64_t kInf = Looper::kNever;

// Señal de prueba de una capa: valores múltiplos de 1/4096, así las sumas de
// varias capas son exactas en float y se pueden comparar con ==.
inline float sig(int seed, int64_t p) {
  return float(1 + (p * (2 * seed + 1) + seed * 13) % 61) / 4096.0f;
}

// Lo que toca el músico: tramos [from, to) en índices de salida, cada uno con
// su señal en función de la posición del loop.
struct Take {
  int64_t from, to;
  int seed;
};

struct Rig {
  EngineCore core;
  int32_t sr;
  int32_t L;
  std::mt19937 rng;
  int32_t inJitter = 300;  // la entrada va hasta 300 muestras por detrás
  std::function<float(int64_t)> player = [](int64_t) { return 0.0f; };
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
      for (int32_t k = 0; k < m; ++k) inBuf[k] = player(inPos + k - L);
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

int64_t wrapPos(int64_t a, int64_t m) {
  const int64_t r = a % m;
  return r < 0 ? r + m : r;
}

// -----------------------------------------------------------------------------
// «Listo cuando»: 4 compases en modo sincronizado con la latencia real del
// móvil de Alex (149 ms) y el loop cuadra con el metrónomo, muestra a muestra,
// durante 5 minutos.
void testSyncFourBarsNoDrift() {
  std::printf("Sincronizado: 4 compases con 149 ms de latencia cuadran 5 minutos\n");
  for (int32_t sr : {48000, 44100}) {
    const int32_t L = int32_t(std::lround(0.1491 * sr));
    Rig r(sr, L);
    r.keep = false;
    r.post(T::kSetBpm, 92);
    r.post(T::kSetLoopMode, 0);
    r.post(T::kSetSyncBars, 4);
    const int64_t spb = Transport::computeSamplesPerBeat(sr, 92);
    const int64_t bar = spb * 4;

    // El músico da un golpe en cada tiempo que oye, cada uno con su volumen
    const int64_t t0 = 1000;
    auto amp = [](int64_t k) { return 0.03f * float(1 + k % 16); };
    r.player = [&](int64_t n) {
      if (n < t0 || (n - t0) % spb != 0) return 0.0f;
      return amp((n - t0) / spb);
    };
    r.postAt(t0, T::kLoopPress);  // parado: 1 compás de cuenta y graba 4
    r.runTo(t0 + 1);
    CHECK(r.state() == St::kArmed);
    CHECK(r.core.status().playing);
    r.runTo(t0 + bar + 1);
    CHECK(r.state() == St::kRecording);
    CHECK_EQ(r.lp().targetFrames(), 4 * bar);
    r.runTo(t0 + 5 * bar - 1);
    CHECK(r.state() == St::kRecording);
    r.runTo(t0 + 5 * bar + 1);
    CHECK(r.state() == St::kPlaying);
    CHECK_EQ(r.lp().length(), 4 * bar);

    // A partir de aquí la salida es solo el loop (el clic está apagado): cada
    // golpe tiene que caer justo en un tiempo del metrónomo y con su volumen.
    int64_t hits = 0, wrong = 0;
    r.onOut = [&](int64_t n, float s) {
      const bool onBeat = (n - t0) % spb == 0;
      const float want = onBeat ? amp((n - t0) / spb) : 0.0f;
      if (s != want) {
        if (wrong < 3)
          std::printf("  muestra %lld: %g, esperado %g\n", (long long)n, s, want);
        ++wrong;
      }
      if (onBeat && s == want) ++hits;
    };
    const int64_t end = t0 + 5 * bar + int64_t(sr) * 300;
    r.runTo(end);
    CHECK_EQ(wrong, 0);
    CHECK(hits > 300 * 92 / 60 - 2);
    std::printf("  %d Hz: %lld golpes del loop, todos en su muestra\n", sr, (long long)hits);
  }
}

// -----------------------------------------------------------------------------
void testManualMode() {
  std::printf("Manual: cuenta de entrada al pulsar, cerrar tarde y cerrar pronto\n");
  const int32_t sr = 48000;
  Rig r(sr, 3000, 7);
  r.post(T::kSetBpm, 120);
  r.post(T::kSetLoopMode, 1);
  const int64_t bar = 4 * 24000;
  r.post(T::kPlay);  // metrónomo desde la muestra 0

  // Pulsa en cualquier momento con el metrónomo ya sonando: el metrónomo
  // vuelve a empezar ahí, cuenta 1 compás y entonces graba.
  const int64_t press0 = 2 * bar + 5000;
  int64_t recStart = press0 + bar;
  r.player = [&](int64_t n) { return n >= recStart ? sig(1, n - recStart) : 0.7f; };
  r.postAt(press0, T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kArmed);
  CHECK_EQ(r.core.status().framePosition, r.outPos - press0);  // clic reiniciado
  CHECK_EQ(r.lp().recordedFrames(r.outPos), r.outPos - recStart);
  r.runTo(recStart + 1);
  CHECK(r.state() == St::kRecording);
  CHECK_EQ(r.lp().targetFrames(), 0);

  // Cierra a los 3,3 compases: se recorta a 3 y suena ya, en su sitio
  const int64_t press = recStart + bar * 33 / 10;
  r.postAt(press, T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().length(), 3 * bar);
  r.runFor(3 * bar * 2);
  int64_t wrong = 0;
  for (int64_t n = press; n < r.outPos; ++n)
    if (r.hist[n] != sig(1, wrapPos(n - recStart, 3 * bar))) ++wrong;
  CHECK_EQ(wrong, 0);
  // Mientras grababa no sonaba nada del loop
  bool silent = true;
  for (int64_t n = recStart; n < press; ++n) silent = silent && r.hist[n] == 0.0f;
  CHECK(silent);

  // Borrar y otra vez, pulsando a mitad de compás: cuenta desde ahí
  r.post(T::kLoopClear);
  r.runFor(1);
  CHECK(r.state() == St::kEmpty);
  const int64_t press1 = (r.outPos / bar + 1) * bar + bar * 6 / 10;
  r.postAt(press1, T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kArmed);
  recStart = press1 + bar;
  CHECK_EQ(r.lp().recordedFrames(r.outPos), r.outPos - recStart);
  r.runTo(recStart + 1);
  CHECK(r.state() == St::kRecording);
  // Cierra a los 2,6 compases: sigue grabando hasta los 3
  r.postAt(recStart + bar * 26 / 10, T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kRecording);
  CHECK_EQ(r.lp().targetFrames(), 3 * bar);
  r.runTo(recStart + 3 * bar - 1);
  CHECK(r.state() == St::kRecording);
  r.runTo(recStart + 3 * bar + 1);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().length(), 3 * bar);
  r.runFor(3 * bar);
  wrong = 0;
  for (int64_t n = recStart + 3 * bar; n < r.outPos; ++n)
    if (r.hist[n] != sig(1, wrapPos(n - recStart, 3 * bar))) ++wrong;
  CHECK_EQ(wrong, 0);

  // En modo sincronizado, igual: cuenta de entrada desde la pulsación
  r.post(T::kLoopClear);
  r.post(T::kSetLoopMode, 0);
  r.post(T::kSetSyncBars, 1);
  const int64_t press2 = r.outPos + 12345;
  r.postAt(press2, T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kArmed);
  CHECK_EQ(r.lp().recordedFrames(r.outPos), r.outPos - (press2 + bar));
  r.runTo(press2 + 2 * bar + 1);
  CHECK(r.state() == St::kPlaying);
}

// -----------------------------------------------------------------------------
// Capas: overdub, deshacer y la suma en segundo plano, comprobando que lo que
// suena es siempre la suma exacta de las capas que deben sonar.
void testOverdubUndoLayers() {
  std::printf("Overdub, deshacer y consolidar capas\n");
  const int32_t sr = 48000;
  Rig r(sr, 7158, 3);
  r.post(T::kSetBpm, 100);
  r.post(T::kSetLoopMode, 0);
  r.post(T::kSetSyncBars, 2);
  const int64_t bar = 4 * int64_t(Transport::computeSamplesPerBeat(sr, 100));
  const int64_t len = 2 * bar;

  std::vector<Take> takes;
  int64_t origin = 0;
  r.player = [&](int64_t n) {
    float s = 0.0f;
    for (const Take& t : takes)
      if (n >= t.from && n < t.to) s += sig(t.seed, wrapPos(n - origin, len));
    return s;
  };
  // Lo que debería sonar: la suma de las capas vivas en cada posición
  struct Layer { int64_t from, to; int seed; };
  std::vector<Layer> live;
  auto expected = [&](int64_t n) {
    const int64_t p = wrapPos(n - origin, len);
    float s = 0.0f;
    for (const Layer& l : live) {
      // ¿la capa cubrió la posición p? (si dura un loop o más, todas)
      const bool all = l.to - l.from >= len;
      const int64_t a = wrapPos(l.from - origin, len);
      const int64_t d = wrapPos(p - a, len);
      if (all || d < l.to - l.from) s += sig(l.seed, p);
    }
    return s;
  };
  auto checkRange = [&](int64_t from, int64_t to, const char* what) {
    int64_t wrong = 0;
    for (int64_t n = from; n < to; ++n) {
      if (r.hist[n] != expected(n)) {
        if (wrong == 0)
          std::printf("  %s: muestra %lld = %g, esperado %g\n", what, (long long)n, r.hist[n],
                      expected(n));
        ++wrong;
      }
    }
    if (wrong) std::printf("  %s: %lld muestras mal\n", what, (long long)wrong);
    CHECK_EQ(wrong, 0);
  };

  // Base: 2 compases tras la cuenta de entrada
  r.postAt(500, T::kLoopPress);
  origin = 500 + bar;
  takes.push_back({origin, origin + len, 1});
  r.runTo(origin + len + 1);
  CHECK(r.state() == St::kPlaying);
  live.push_back({origin, origin + len, 1});
  r.runFor(len);
  checkRange(origin + len, r.outPos, "base");
  CHECK_EQ(r.lp().layerCount(), 1);
  CHECK(!r.lp().canUndo());

  // Overdub B: un loop entero empezando a media vuelta
  int64_t a = r.outPos + len / 3;
  r.postAt(a, T::kLoopPress);
  takes.push_back({a, a + len, 2});
  r.postAt(a + len, T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().layerCount(), 2);
  live.push_back({a, a + len, 2});
  r.runFor(len + r.L);  // la cola de la grabación llega con la latencia
  checkRange(a + len + r.L, r.outPos, "base+B");

  // Deshacer B
  r.post(T::kLoopUndo);
  r.runFor(1);
  live.pop_back();
  int64_t from = r.outPos;
  r.runFor(len);
  checkRange(from, r.outPos, "deshacer B");
  CHECK_EQ(r.lp().layerCount(), 1);

  // C (medio loop) y, pegado, D (un loop y medio, se oye a sí mismo al
  // dar la vuelta). Al acabar D, C se consolida en segundo plano: no debe
  // notarse nada.
  a = r.outPos + 1234;
  r.postAt(a, T::kLoopPress);
  takes.push_back({a, a + len / 2, 3});
  r.postAt(a + len / 2, T::kLoopPress);  // fin de C
  r.post(T::kLoopPress);                 // empieza D en la misma muestra
  takes.push_back({a + len / 2, a + len / 2 + len * 3 / 2, 4});
  live.push_back({a, a + len / 2, 3});
  r.runFor(1);
  CHECK(r.state() == St::kOverdubbing);
  r.postAt(a + len / 2 + len * 3 / 2, T::kLoopPress);  // fin de D
  // D ha pasado dos veces por la primera mitad de su recorrido
  r.runFor(1);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().layerCount(), 3);
  live.push_back({a + len / 2, a + len / 2 + len, 4});  // cubre todo el loop
  from = r.outPos + r.L;
  r.runFor(r.L + 2 * len);
  // La parte que D grabó dos veces suena doble
  {
    int64_t wrong = 0;
    const int64_t dStart = a + len / 2;
    for (int64_t n = from; n < r.outPos; ++n) {
      const int64_t p = wrapPos(n - origin, len);
      const int64_t dd = wrapPos(p - wrapPos(dStart - origin, len), len);
      float want = expected(n);
      if (dd < len / 2) want += sig(4, p);  // segunda pasada de D
      if (r.hist[n] != want) ++wrong;
    }
    CHECK_EQ(wrong, 0);
  }

  // Deshacer quita D (C ya está consolidada y no se puede deshacer)
  r.post(T::kLoopUndo);
  r.runFor(1);
  live.pop_back();
  CHECK(!r.lp().canUndo());
  from = r.outPos;
  r.runFor(len);
  checkRange(from, r.outPos, "deshacer D");
  r.post(T::kLoopUndo);  // no hay nada más que deshacer: no cambia nada
  r.runFor(1);
  from = r.outPos;
  r.runFor(len);
  checkRange(from, r.outPos, "deshacer de más");
  CHECK_EQ(r.lp().layerCount(), 2);

  // Deshacer un overdub a medias
  a = r.outPos + 100;
  r.postAt(a, T::kLoopPress);
  takes.push_back({a, kInf, 5});
  r.runFor(len / 2);
  r.post(T::kLoopUndo);
  r.runFor(1);
  takes.back().to = r.outPos;
  CHECK(r.state() == St::kPlaying);
  from = r.outPos;
  r.runFor(len);
  checkRange(from, r.outPos, "deshacer a medias");

  // Borrar: silencio, y el tempo vuelve a poder cambiarse
  r.post(T::kSetBpm, 150);
  r.runFor(1);
  CHECK(std::fabs(r.core.status().bpm - 100) < 1e-9);  // bloqueado con loop
  r.post(T::kLoopClear);
  r.runFor(1);
  live.clear();
  CHECK(r.state() == St::kEmpty);
  CHECK_EQ(r.lp().layerCount(), 0);
  from = r.outPos;
  r.runFor(len);
  bool silent = true;
  for (int64_t n = from; n < r.outPos; ++n) silent = silent && r.hist[n] == 0.0f;
  CHECK(silent);
  r.post(T::kSetBpm, 150);
  r.runFor(int64_t(sr) * 3);  // se aplica al empezar el siguiente tiempo
  CHECK(std::fabs(r.core.status().bpm - 150) < 1e-9);
}

// -----------------------------------------------------------------------------
// Parar y arrancar: el loop vuelve a empezar con el compás 1 del metrónomo.
void testStopStartRealign() {
  std::printf("Parar y arrancar: el loop vuelve a cuadrar con el compás 1\n");
  const int32_t sr = 48000;
  Rig r(sr, 2000, 11);
  r.post(T::kSetBpm, 120);
  r.post(T::kSetSyncBars, 1);
  const int64_t spb = 24000, bar = 4 * spb;
  r.player = [&](int64_t n) { return (n % spb) == 0 ? 0.25f : 0.0f; };
  r.postAt(0, T::kLoopPress);
  r.runTo(2 * bar + 10);
  CHECK(r.state() == St::kPlaying);
  r.postAt(2 * bar + 30000, T::kPause);
  r.runFor(1);
  CHECK(r.state() == St::kStopped);
  CHECK(!r.core.status().playing);
  r.runFor(50000);
  const int64_t start = r.outPos + 777;
  r.postAt(start, T::kPlay);
  r.runFor(1);
  CHECK(r.state() == St::kPlaying);
  r.runFor(3 * bar);
  int64_t wrong = 0;
  for (int64_t n = 2 * bar + 30000; n < r.outPos; ++n) {
    const float want = (n >= start && (n - start) % spb == 0) ? 0.25f : 0.0f;
    if (r.hist[n] != want) ++wrong;
  }
  CHECK_EQ(wrong, 0);
  // El metrónomo también empezó ahí
  CHECK_EQ(r.core.status().framePosition, r.outPos - start);
}

// -----------------------------------------------------------------------------
// Toque, mantener y doble toque, en cada situación
void testPedalGestures() {
  std::printf("Pedal: mantener = deshacer, doble toque = parar\n");
  const int32_t sr = 48000;
  Rig r(sr, 1000, 5);
  r.post(T::kSetBpm, 120);
  r.post(T::kSetSyncBars, 1);
  const int64_t bar = 96000;
  r.player = [](int64_t n) { return sig(1, n); };

  // Vacío + toque (cuenta de entrada) + mantener → cancela
  r.post(T::kLoopPress);
  r.runFor(100);
  CHECK(r.state() == St::kArmed);
  r.post(T::kLoopHold);
  r.runFor(100);
  CHECK(r.state() == St::kEmpty);
  // Vacío + toque + doble toque → cancela y para el metrónomo
  r.post(T::kLoopPress);
  r.runFor(100);
  r.post(T::kLoopDoubleTap);
  r.runFor(100);
  CHECK(r.state() == St::kEmpty);
  CHECK(!r.core.status().playing);

  // Grabar 1 compás
  r.post(T::kLoopPress);
  r.runFor(2 * bar + 10);
  CHECK(r.state() == St::kPlaying);
  // Reproduciendo + toque (empieza overdub) + mantener → nada de overdub
  r.post(T::kLoopPress);
  r.runFor(1000);
  CHECK(r.state() == St::kOverdubbing);
  r.post(T::kLoopHold);
  r.runFor(100);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().layerCount(), 1);
  // Una capa: toque, toque
  r.post(T::kLoopPress);
  r.runFor(bar);
  r.post(T::kLoopPress);
  r.runFor(100);
  CHECK_EQ(r.lp().layerCount(), 2);
  // Overdub + mantener al poco → fuera el overdub y también la capa anterior
  r.post(T::kLoopPress);
  r.runFor(5000);
  r.post(T::kLoopHold);
  r.runFor(100);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().layerCount(), 1);
  CHECK(!r.lp().canUndo());
  // Otra capa y luego: toque (acaba) + mantener → se deshace esa capa
  r.post(T::kLoopPress);
  r.runFor(bar / 2);
  r.post(T::kLoopPress);
  r.runFor(50);
  r.post(T::kLoopHold);
  r.runFor(100);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().layerCount(), 1);
  // Otra capa; toque (empieza overdub) + doble toque → sin overdub y parado
  r.post(T::kLoopPress);
  r.runFor(bar / 2);
  r.post(T::kLoopPress);
  r.runFor(100);
  r.post(T::kLoopPress);
  r.runFor(100);
  r.post(T::kLoopDoubleTap);
  r.runFor(100);
  CHECK(r.state() == St::kStopped);
  CHECK(!r.core.status().playing);
  CHECK_EQ(r.lp().layerCount(), 2);
  // Parado + toque → arranca; + doble toque → sigue arrancado
  r.post(T::kLoopPress);
  r.runFor(100);
  r.post(T::kLoopDoubleTap);
  r.runFor(100);
  CHECK(r.state() == St::kPlaying);
  CHECK(r.core.status().playing);
  // Overdub; toque (acaba) + doble toque → parado y con la capa
  r.post(T::kLoopPress);
  r.runFor(bar / 2);
  r.post(T::kLoopPress);
  r.runFor(100);
  r.post(T::kLoopDoubleTap);
  r.runFor(100);
  CHECK(r.state() == St::kStopped);
  CHECK_EQ(r.lp().layerCount(), 3);
  // Parado + toque (arranca) + mantener → deshace la última capa y sigue parado
  r.post(T::kLoopPress);
  r.runFor(100);
  r.post(T::kLoopHold);
  r.runFor(100);
  CHECK(r.state() == St::kStopped);
  CHECK_EQ(r.lp().layerCount(), 2);
  // Mantener sin toque antes no hace nada
  r.post(T::kLoopHold);
  r.runFor(100);
  CHECK_EQ(r.lp().layerCount(), 2);

  // Grabando (manual) + toque (cierra) + mantener → se borra el loop
  r.post(T::kLoopClear);
  r.post(T::kSetLoopMode, 1);
  r.post(T::kLoopPress);  // parado: cuenta de entrada
  r.runFor(bar + 2 * bar + 1000);
  CHECK(r.state() == St::kRecording);
  r.post(T::kLoopPress);
  r.runFor(100);
  CHECK(r.state() == St::kPlaying);
  r.post(T::kLoopHold);
  r.runFor(100);
  CHECK(r.state() == St::kEmpty);

  // Grabando + doble toque → se cierra (compás más cercano) y queda parado
  r.post(T::kLoopPress);  // el metrónomo sigue en marcha
  r.runFor(1);
  CHECK(r.state() == St::kRecording || r.state() == St::kArmed);
  const int64_t recStart = r.outPos - r.lp().recordedFrames(r.outPos);
  r.runTo(recStart + bar * 17 / 10);  // 1,7 compases → cierra en 2, en el futuro
  r.post(T::kLoopPress);
  r.runFor(100);
  r.post(T::kLoopDoubleTap);
  r.runFor(100);
  CHECK(r.state() == St::kRecording);  // termina de grabar el compás
  CHECK(!r.core.status().playing);
  r.runTo(recStart + 2 * bar + 10);
  CHECK(r.state() == St::kStopped);
  CHECK_EQ(r.lp().length(), 2 * bar);
}

// -----------------------------------------------------------------------------
// Al reabrir el audio (cambio de entrada, de modo de micro…) el loop se conserva
void testRestartKeepsLoop() {
  std::printf("Reabrir el audio conserva el loop\n");
  const int32_t sr = 48000;
  Rig r(sr, 500, 9);
  r.post(T::kSetBpm, 120);
  r.post(T::kSetSyncBars, 1);
  const int64_t bar = 96000;
  int64_t origin = bar;
  r.player = [&](int64_t n) { return sig(2, wrapPos(n - origin, bar)); };
  r.post(T::kLoopPress);
  r.runTo(2 * bar + 1);
  r.post(T::kLoopPress);  // overdub a medias
  r.runFor(bar / 3);
  CHECK(r.state() == St::kOverdubbing);

  r.core.prepare(sr);  // como al reabrir los streams
  CHECK(r.state() == St::kStopped);
  CHECK_EQ(r.lp().length(), bar);
  CHECK_EQ(r.lp().layerCount(), 2);
  CHECK(r.lp().canUndo());
  // Los contadores vuelven a 0, como en un stream nuevo
  r.outPos = 0;
  r.inPos = 0;
  r.hist.clear();
  r.player = [](int64_t) { return 0.0f; };
  r.post(T::kSetLatencyFrames, 500);
  r.post(T::kPlay);
  r.runFor(bar);
  // Suena la base completa y el tercio del overdub (que empezó en la
  // posición 1; su final exacto depende de cuánta entrada había llegado)
  int64_t wrong = 0;
  for (int64_t p = 0; p < bar; ++p) {
    if (p >= bar / 3 - 1500 && p < bar / 3 + 500) continue;
    float want = sig(2, p);
    if (p >= 1 && p < bar / 3) want += sig(2, p);
    if (r.hist[p] != want) ++wrong;
  }
  CHECK_EQ(wrong, 0);
  // Con otra frecuencia de muestreo, el loop se pierde
  r.core.prepare(44100);
  CHECK(r.state() == St::kEmpty);
}

// -----------------------------------------------------------------------------
void testMaxLength() {
  std::printf("Grabación manual sin cerrar: se corta a los 60 s\n");
  const int32_t sr = 48000;
  Rig r(sr, 0, 13);
  r.keep = false;
  r.post(T::kSetBpm, 120);  // compás de 2 s → caben 30
  r.post(T::kSetLoopMode, 1);
  r.post(T::kLoopPress);
  r.runFor(int64_t(sr) * 62);
  CHECK(r.state() == St::kRecording);
  r.runFor(int64_t(sr) * 2);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().length(), int64_t(sr) * 60);
}

// -----------------------------------------------------------------------------
// Monitor: con la entrada a trompicones no se acumula retraso
void testMonitorNoBacklog() {
  std::printf("Monitor: la entrada a trompicones no acumula retraso\n");
  Rig r(48000, 0, 21);
  r.post(T::kSetMonitorEnabled, 1);
  r.post(T::kSetMonitorVolume, 1);
  r.inJitter = 1000;
  // Impulso cada 10000 muestras de entrada
  r.player = [](int64_t n) { return n % 10000 == 0 ? 0.5f : 0.0f; };
  r.runFor(48000 * 20);
  // El retraso del monitor (salida − entrada) se queda acotado
  int64_t maxDelay = 0, count = 0;
  for (int64_t n = 48000; n < r.outPos; ++n) {
    if (r.hist[n] == 0.5f) {
      const int64_t d = n - (n / 10000) * 10000;
      maxDelay = std::max(maxDelay, d);
      ++count;
    }
  }
  CHECK(count >= 90);  // no se pierde ningún golpe (hay 91 tras el primer segundo)
  CHECK(maxDelay < 1000 + 2 * 1024);
  std::printf("  %lld golpes, retraso máximo del monitor: %lld muestras\n", (long long)count,
              (long long)maxDelay);
}

}  // namespace

void runLooperTests() {
  testSyncFourBarsNoDrift();
  testManualMode();
  testOverdubUndoLayers();
  testStopStartRealign();
  testPedalGestures();
  testRestartKeepsLoop();
  testMaxLength();
  testMonitorNoBacklog();
}
