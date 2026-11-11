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
  CHECK(r.lp().canUndo());  // deshacer quitaría la pista recién grabada

  // El overdub empieza en el primer tiempo del compás siguiente a la pulsación
  auto nb = [&](int64_t x) { return origin + (x - origin + bar - 1) / bar * bar; };

  // Pulsar y volver a pulsar antes de que empiece: no pasa nada
  r.postAt(nb(r.outPos) + bar / 4, T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kOverdubbing);
  CHECK_EQ(r.lp().recordedFrames(r.outPos), r.outPos - nb(r.outPos));
  r.runFor(bar / 4);
  r.post(T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().layerCount(), 1);

  // Overdub B: se pulsa a media vuelta, graba un loop entero desde el compás
  int64_t press = r.outPos + len / 3;
  int64_t a = nb(press);
  r.postAt(press, T::kLoopPress);
  takes.push_back({a, a + len, 2});
  r.runTo(a - 1);
  CHECK(r.lp().recordedFrames(r.outPos) < 0);
  r.runTo(a + 1);
  CHECK_EQ(r.lp().recordedFrames(r.outPos), 0);
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
  press = r.outPos + 1234;
  a = nb(press);
  r.postAt(press, T::kLoopPress);
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
  press = r.outPos + 100;
  a = nb(press);
  r.postAt(press, T::kLoopPress);
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
  // Reproduciendo + toque (empieza overdub) + mantener → fuera el overdub y
  // lo último que se hizo, que era grabar la pista: queda vacío
  r.post(T::kLoopPress);
  r.runFor(1000);
  CHECK(r.state() == St::kOverdubbing);
  r.post(T::kLoopHold);
  r.runFor(100);
  CHECK(r.state() == St::kEmpty);
  CHECK_EQ(r.lp().layerCount(), 0);
  // Otra vez 1 compás
  r.post(T::kLoopPress);
  r.runFor(2 * bar + 10);
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
  r.runFor(bar);
  r.post(T::kLoopPress);
  r.runFor(50);
  r.post(T::kLoopHold);
  r.runFor(100);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().layerCount(), 1);
  // Otra capa; toque (empieza overdub) + doble toque → sin overdub y parado
  r.post(T::kLoopPress);
  r.runFor(bar);
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
  r.runFor(bar);
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
  r.runTo(3 * bar);
  r.post(T::kLoopPress);  // overdub a medias (justo en el primer tiempo)
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
    if (p < bar / 3) want += sig(2, p);
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


// -----------------------------------------------------------------------------
// Cuatro pistas con avance automático. Un modelo sencillo dice qué tiene que
// sonar en cada muestra: la suma de lo grabado en cada pista, cada una con su
// origen, su longitud (1, 2 o 4 veces la base) y su volumen.
struct TrackModel {
  bool on = false;
  int64_t origin = 0, len = 0, recorded = 0, since = 0;
  int seed = 0;
  float gain = 1.0f;
};
struct LayerModel {
  int track;
  int64_t from, span, since;  // tramo grabado, en índices de salida
  int seed;
};

void testFourTracks() {
  std::printf("4 pistas: avance automático, longitudes 1x/2x/4x, volumen y borrar\n");
  const int32_t sr = 48000;
  Rig r(sr, 4113, 17);
  r.post(T::kSetBpm, 120);
  r.post(T::kSetLoopMode, 1);
  r.post(T::kSetAutoAdvance, 1);
  const int64_t bar = 96000;

  struct Play { int64_t from, to; int seed; int64_t ref; };  // suena sig(seed, n - ref)
  std::vector<Play> plays;
  r.player = [&](int64_t n) {
    float s = 0.0f;
    for (const Play& p : plays)
      if (n >= p.from && n < p.to) s += sig(p.seed, n - p.ref);
    return s;
  };
  TrackModel m[4];
  std::vector<LayerModel> layers;
  auto expected = [&](int64_t n) {
    float s = 0.0f;
    for (int i = 0; i < 4; ++i) {
      const TrackModel& t = m[i];
      if (!t.on || n < t.since) continue;
      const int64_t p = wrapPos(n - t.origin, t.len);
      float x = p < t.recorded ? sig(t.seed, p) : 0.0f;
      for (const LayerModel& l : layers) {
        if (l.track != i || n < l.since) continue;
        const int64_t d = wrapPos(p - wrapPos(l.from - t.origin, t.len), t.len);
        if (d < l.span) x += sig(l.seed, p);
      }
      s += x * t.gain;
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

  // Pista 1: cuenta de entrada y 2 compases → la base
  const int64_t t0 = 1000;
  int64_t base0 = t0 + bar;  // origen del ciclo base
  r.postAt(t0, T::kLoopPress);
  plays.push_back({base0, base0 + 3 * bar, 1, base0});
  r.postAt(base0 + 2 * bar, T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().baseLength(), 2 * bar);
  CHECK_EQ(r.lp().trackLength(0), 2 * bar);
  CHECK_EQ(r.lp().selected(), 1);  // avance automático
  CHECK(r.lp().trackState(0) == St::kPlaying);
  CHECK(r.lp().trackState(1) == St::kEmpty);
  CHECK_EQ(r.lp().active(), -1);
  m[0] = {true, base0, 2 * bar, 2 * bar, base0 + 2 * bar, 1, 1.0f};

  // Pista 2: se pulsa a mitad de compás, empieza en el siguiente; se cierra a
  // los 1,6 compases → dura la base (2) y el resto es silencio
  const int64_t o1 = base0 + 3 * bar;
  r.postAt(base0 + 2 * bar + bar * 3 / 10, T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kArmed);
  CHECK_EQ(r.lp().active(), 1);
  CHECK(r.lp().trackState(1) == St::kArmed);
  CHECK(r.lp().trackState(0) == St::kPlaying);
  CHECK_EQ(r.lp().recordedFrames(r.outPos), r.outPos - o1);
  CHECK(r.core.status().playing);
  plays.push_back({o1, o1 + 2 * bar, 2, o1});  // sigue tocando tras pulsar
  r.runTo(o1 + 1);
  CHECK(r.state() == St::kRecording);
  r.postAt(o1 + bar * 16 / 10, T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().trackLength(1), 2 * bar);
  CHECK_EQ(r.lp().selected(), 2);
  m[1] = {true, o1, 2 * bar, bar * 16 / 10, o1 + bar * 16 / 10, 2, 1.0f};

  // Pista 3: 2,9 compases → 3 compases no caben en la base → dura el doble (4)
  const int64_t o2 = base0 + 5 * bar;
  r.postAt(o1 + bar * 16 / 10 + 1000, T::kLoopPress);
  plays.push_back({o2, o2 + 3 * bar, 3, o2});  // toca hasta que empieza la pista 4
  r.postAt(o2 + bar * 29 / 10, T::kLoopPress);
  r.runFor(1);
  CHECK_EQ(r.lp().trackLength(2), 4 * bar);
  CHECK_EQ(r.lp().selected(), 3);
  m[2] = {true, o2, 4 * bar, bar * 29 / 10, o2 + bar * 29 / 10, 3, 1.0f};

  // Pista 4: se pulsa justo en un primer tiempo (empieza ya) y se cierra tarde,
  // a los 2,2 compases → dura 2 y lo que sobra no se graba
  const int64_t o3 = o2 + 3 * bar;
  r.postAt(o3, T::kLoopPress);
  plays.push_back({o3, o3 + 3 * bar, 4, o3});
  r.runFor(1);
  CHECK(r.state() == St::kRecording);
  r.postAt(o3 + bar * 22 / 10, T::kLoopPress);
  r.runFor(1);
  CHECK_EQ(r.lp().trackLength(3), 2 * bar);
  CHECK_EQ(r.lp().selected(), 3);  // no queda ninguna vacía: se queda en la 4
  m[3] = {true, o3, 2 * bar, 2 * bar, o3 + bar * 22 / 10, 4, 1.0f};
  r.runFor(8 * bar);
  // Todo lo que ha sonado desde que se cerró la primera pista
  checkRange(base0 + 2 * bar, r.outPos, "4 pistas");

  // Silenciar la pista 2 y bajar la 3 a la mitad (el cambio tarda unos ms)
  r.postTrack(T::kSetTrackMuted, 1, 1);
  r.postTrack(T::kSetTrackVolume, 2, 0.5);
  r.runFor(sr / 5);
  m[1].gain = 0.0f;
  m[2].gain = 0.5f;
  CHECK(r.core.status().trackMuted[1] == 1);
  int64_t from = r.outPos;
  r.runFor(4 * bar);
  checkRange(from, r.outPos, "silencio y volumen");
  r.postTrack(T::kSetTrackMuted, 1, 0);
  r.postTrack(T::kSetTrackVolume, 2, 1.0);
  r.runFor(sr / 5);
  m[1].gain = 1.0f;
  m[2].gain = 1.0f;

  // Con las 4 llenas, el toque hace overdub en la seleccionada (la 4)
  auto nb = [&](int64_t x) { return base0 + (x - base0 + bar - 1) / bar * bar; };
  int64_t press = r.outPos + 500;
  int64_t a = nb(press);
  r.postAt(press, T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kOverdubbing);
  CHECK_EQ(r.lp().active(), 3);
  CHECK(r.lp().trackState(3) == St::kOverdubbing);
  // El músico toca sobre la pista 4: la señal depende de la posición en ella
  plays.push_back({a, a + bar, 5, m[3].origin});
  r.postAt(a + bar, T::kLoopPress);
  r.runFor(1);
  CHECK_EQ(r.lp().trackLayers(3), 2);
  // Lo grabado es sig(5, n - origen) en el tramo [a, a + bar)
  from = r.outPos + r.L;
  r.runFor(r.L + 4 * bar);
  {
    int64_t wrong = 0;
    for (int64_t n = from; n < r.outPos; ++n) {
      float want = expected(n);
      const int64_t p = wrapPos(n - m[3].origin, m[3].len);
      const int64_t pa = wrapPos(a - m[3].origin, m[3].len);
      const int64_t d = wrapPos(p - pa, m[3].len);
      if (d < bar) want += sig(5, a - m[3].origin + d);
      if (r.hist[n] != want) ++wrong;
    }
    CHECK_EQ(wrong, 0);
  }
  // Deshacer quita esa capa (y solo esa)
  CHECK(r.lp().canUndo());
  r.post(T::kLoopUndo);
  r.runFor(1);
  CHECK_EQ(r.lp().trackLayers(3), 1);
  CHECK(!r.lp().canUndo());
  from = r.outPos;
  r.runFor(4 * bar);
  checkRange(from, r.outPos, "deshacer overdub de la pista 4");

  // Borrar la pista 2 y volver a grabarla, más corta: no queda nada de la vieja
  r.postTrack(T::kClearTrack, 1);
  r.runFor(1);
  m[1].on = false;
  CHECK(r.lp().trackState(1) == St::kEmpty);
  CHECK(r.state() == St::kPlaying);
  from = r.outPos;
  r.runFor(2 * bar);
  checkRange(from, r.outPos, "borrar pista 2");
  r.postTrack(T::kSelectTrack, 1);
  press = r.outPos + 100;
  a = nb(press);
  r.postAt(press, T::kLoopPress);
  plays.push_back({a, a + bar, 6, a});
  r.postAt(a + bar / 2, T::kLoopPress);
  r.runFor(1);
  CHECK_EQ(r.lp().trackLength(1), 2 * bar);
  CHECK_EQ(r.lp().selected(), 1);
  m[1] = {true, a, 2 * bar, bar / 2, a + bar / 2, 6, 1.0f};
  r.runFor(4 * bar);
  checkRange(a + bar / 2, r.outPos, "pista 2 nueva");
  // Deshacer quita la pista recién grabada y la deja elegida
  CHECK(r.lp().canUndo());
  r.post(T::kLoopUndo);
  r.runFor(1);
  m[1].on = false;
  CHECK(r.lp().trackState(1) == St::kEmpty);
  CHECK_EQ(r.lp().selected(), 1);
  CHECK(!r.lp().canUndo());
  from = r.outPos;
  r.runFor(2 * bar);
  checkRange(from, r.outPos, "deshacer pista 2");

  // Parar y arrancar: el ciclo base empieza con el compás 1 y cada pista
  // conserva su posición respecto a las demás
  r.postAt(r.outPos + 12345, T::kPause);
  r.runFor(1);
  CHECK(r.state() == St::kStopped);
  CHECK(r.lp().trackState(2) == St::kStopped);
  from = r.outPos;
  r.runFor(50000);
  bool silent = true;
  for (int64_t n = from; n < r.outPos; ++n) silent = silent && r.hist[n] == 0.0f;
  CHECK(silent);
  const int64_t start = r.outPos + 777;
  r.postAt(start, T::kPlay);
  r.runFor(1);
  CHECK(r.state() == St::kPlaying);
  const int64_t shift = start - base0;
  base0 = start;
  for (TrackModel& t : m) t.origin += shift;
  r.runFor(8 * bar);
  checkRange(start, r.outPos, "parar y arrancar");
  CHECK_EQ(r.core.status().framePosition, r.outPos - start);

  // Borrar la pista que marcó la base: las demás siguen y la base no cambia
  r.postTrack(T::kClearTrack, 0);
  r.runFor(1);
  m[0].on = false;
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().baseLength(), 2 * bar);
  r.post(T::kSetBpm, 90);
  from = r.outPos;
  r.runFor(4 * bar);
  checkRange(from, r.outPos, "sin la pista 1");
  CHECK(std::fabs(r.core.status().bpm - 120) < 1e-9);  // el tempo sigue fijo
  r.postTrack(T::kSelectTrack, 0);
  press = r.outPos + 4321;
  a = nb(press);
  r.postAt(press, T::kLoopPress);
  plays.push_back({a, a + 2 * bar, 7, a});
  r.postAt(a + bar, T::kLoopPress);
  r.runFor(1);
  CHECK_EQ(r.lp().trackLength(0), 2 * bar);
  m[0] = {true, a, 2 * bar, bar, a + bar, 7, 1.0f};
  r.runFor(4 * bar);
  checkRange(a + bar, r.outPos, "pista 1 nueva");

  // Borrar todo
  r.post(T::kLoopClear);
  r.runFor(1);
  CHECK(r.state() == St::kEmpty);
  CHECK_EQ(r.lp().baseLength(), 0);
  for (int i = 0; i < 4; ++i) CHECK(r.lp().trackState(i) == St::kEmpty);
  from = r.outPos;
  r.runFor(bar);
  silent = true;
  for (int64_t n = from; n < r.outPos; ++n) silent = silent && r.hist[n] == 0.0f;
  CHECK(silent);
}

// -----------------------------------------------------------------------------
// Modo sincronizado con varias pistas: cada una graba los compases elegidos y
// se cierra sola.
void testSyncTracks() {
  std::printf("Sincronizado con varias pistas: se cierran solas\n");
  const int32_t sr = 48000;
  Rig r(sr, 6123, 23);
  r.post(T::kSetBpm, 120);
  r.post(T::kSetLoopMode, 0);
  r.post(T::kSetSyncBars, 2);
  r.post(T::kSetAutoAdvance, 1);
  const int64_t bar = 96000;
  struct Play { int64_t from, to; int seed; };
  std::vector<Play> plays;
  r.player = [&](int64_t n) {
    float s = 0.0f;
    for (const Play& p : plays)
      if (n >= p.from && n < p.to) s += sig(p.seed, n - p.from);
    return s;
  };
  TrackModel m[4];
  auto expected = [&](int64_t n) {
    float s = 0.0f;
    for (const TrackModel& t : m) {
      if (!t.on || n < t.since) continue;
      const int64_t p = wrapPos(n - t.origin, t.len);
      if (p < t.recorded) s += sig(t.seed, p);
    }
    return s;
  };

  const int64_t base0 = 500 + bar;
  r.postAt(500, T::kLoopPress);
  plays.push_back({base0, base0 + 3 * bar, 1});
  r.runTo(base0 + 2 * bar + 1);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().selected(), 1);
  m[0] = {true, base0, 2 * bar, 2 * bar, base0 + 2 * bar, 1, 1.0f};

  // Pista 2: 2 compases desde el siguiente compás
  const int64_t o1 = base0 + 3 * bar;
  r.postAt(base0 + 2 * bar + bar / 2, T::kLoopPress);
  r.runFor(1);
  CHECK(r.state() == St::kArmed);
  CHECK_EQ(r.lp().targetFrames(), 2 * bar);
  plays.push_back({o1, o1 + 3 * bar, 2});
  r.runTo(o1 + 2 * bar - 1);
  CHECK(r.state() == St::kRecording);
  r.runTo(o1 + 2 * bar + 1);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().trackLength(1), 2 * bar);
  CHECK_EQ(r.lp().selected(), 2);
  m[1] = {true, o1, 2 * bar, 2 * bar, o1 + 2 * bar, 2, 1.0f};

  // Pista 3: 4 compases → el doble de la base
  r.post(T::kSetSyncBars, 4);
  const int64_t o2 = o1 + 3 * bar;
  r.postAt(o1 + 2 * bar + 100, T::kLoopPress);
  plays.push_back({o2, o2 + 5 * bar, 3});
  r.runTo(o2 + 4 * bar + 1);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().trackLength(2), 4 * bar);
  m[2] = {true, o2, 4 * bar, 4 * bar, o2 + 4 * bar, 3, 1.0f};

  // Pista 4: 1 compás → dura la base y medio loop es silencio
  r.post(T::kSetSyncBars, 1);
  const int64_t o3 = o2 + 5 * bar;
  r.postAt(o2 + 4 * bar + 100, T::kLoopPress);
  plays.push_back({o3, o3 + 2 * bar, 4});
  r.runTo(o3 + bar + 1);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().trackLength(3), 2 * bar);
  m[3] = {true, o3, 2 * bar, bar, o3 + bar, 4, 1.0f};

  r.runFor(8 * bar);
  int64_t wrong = 0;
  for (int64_t n = base0 + 2 * bar; n < r.outPos; ++n)
    if (r.hist[n] != expected(n)) ++wrong;
  CHECK_EQ(wrong, 0);
}

// -----------------------------------------------------------------------------
// Gestos del pedal con avance automático, cambio de pista y límite del buffer
void testTrackGestures() {
  std::printf("Pistas: gestos con avance automático y límite de 60 s\n");
  const int32_t sr = 48000;
  Rig r(sr, 1000, 29);
  r.keep = false;
  r.post(T::kSetBpm, 120);
  r.post(T::kSetSyncBars, 1);
  r.post(T::kSetAutoAdvance, 1);
  const int64_t bar = 96000;
  r.player = [](int64_t n) { return sig(1, n); };

  // Pista 1 (1 compás). La selección pasa a la 2
  r.post(T::kLoopPress);
  r.runFor(2 * bar + 10);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().selected(), 1);
  // Toque (prepara la pista 2) + mantener → se anula y se deshace la pista 1
  r.post(T::kLoopPress);
  r.runFor(100);
  CHECK(r.state() == St::kArmed || r.state() == St::kRecording);
  r.post(T::kLoopHold);
  r.runFor(100);
  CHECK(r.state() == St::kEmpty);
  CHECK_EQ(r.lp().selected(), 0);
  CHECK(r.lp().trackState(1) == St::kEmpty);

  // Otra vez la pista 1; toque + doble toque → nada en la 2 y todo parado
  r.post(T::kLoopPress);
  r.runFor(2 * bar + 10);
  CHECK_EQ(r.lp().selected(), 1);
  r.post(T::kLoopPress);
  r.runFor(100);
  r.post(T::kLoopDoubleTap);
  r.runFor(100);
  CHECK(r.state() == St::kStopped);
  CHECK(r.lp().trackState(0) == St::kStopped);
  CHECK(r.lp().trackState(1) == St::kEmpty);
  CHECK(!r.core.status().playing);
  // Toque → arranca
  r.post(T::kLoopPress);
  r.runFor(100);
  CHECK(r.state() == St::kPlaying);

  // Pista 2; al cerrarla, mantener → se quita la 2 y vuelve a quedar elegida
  r.post(T::kLoopPress);
  r.runFor(2 * bar + 200);
  CHECK(r.state() == St::kPlaying);
  CHECK(r.lp().trackState(1) == St::kPlaying);
  CHECK_EQ(r.lp().selected(), 2);
  r.post(T::kLoopUndo);
  r.runFor(100);
  CHECK(r.lp().trackState(1) == St::kEmpty);
  CHECK(r.lp().trackState(0) == St::kPlaying);
  CHECK_EQ(r.lp().selected(), 1);

  // Cambiar de pista: «siguiente» da la vuelta; mientras se graba no cambia
  r.post(T::kSelectNextTrack);
  r.runFor(10);
  CHECK_EQ(r.lp().selected(), 2);
  r.post(T::kSelectNextTrack);
  r.post(T::kSelectNextTrack);
  r.runFor(10);
  CHECK_EQ(r.lp().selected(), 0);
  r.post(T::kLoopPress);  // overdub en la pista 1
  r.runFor(100);
  CHECK(r.state() == St::kOverdubbing);
  r.post(T::kSelectNextTrack);
  r.runFor(10);
  CHECK_EQ(r.lp().selected(), 0);
  r.post(T::kLoopPress);
  r.runFor(10);
  CHECK(r.state() == St::kPlaying);

  // Sin avance automático la selección no se mueve
  r.post(T::kSetAutoAdvance, 0);
  r.postTrack(T::kSelectTrack, 3);
  r.post(T::kLoopPress);
  r.runFor(2 * bar + 200);
  CHECK(r.lp().trackState(3) == St::kPlaying);
  CHECK_EQ(r.lp().selected(), 3);

  // Borrar la única pista con loop mientras se graba otra → todo vacío
  r.post(T::kLoopClear);
  r.runFor(10);
  CHECK(r.state() == St::kEmpty);
  r.post(T::kSetAutoAdvance, 1);
  r.postTrack(T::kSelectTrack, 0);
  r.post(T::kLoopPress);
  r.runFor(2 * bar + 10);
  r.post(T::kLoopPress);  // pista 2
  r.runFor(bar + 5000);
  CHECK(r.state() == St::kRecording);
  r.postTrack(T::kClearTrack, 0);
  r.runFor(10);
  CHECK(r.state() == St::kEmpty);
  CHECK_EQ(r.lp().baseLength(), 0);

  // Base de 24 s: una pista nueva puede durar como mucho el doble (48 s); si
  // no se cierra, se cierra sola ahí
  r.post(T::kSetLoopMode, 1);
  r.post(T::kLoopPress);
  r.runFor(1);
  const int64_t rec0 = r.outPos - r.lp().recordedFrames(r.outPos);
  r.postAt(rec0 + 12 * bar, T::kLoopPress);
  r.runFor(10);
  CHECK_EQ(r.lp().baseLength(), 12 * bar);
  const int32_t first = r.lp().selected() == 0 ? 3 : r.lp().selected() - 1;
  CHECK_EQ(r.lp().trackLength(first), 12 * bar);
  const int32_t second = r.lp().selected();
  r.post(T::kLoopPress);
  r.runFor(1);
  const int64_t rec1 = r.outPos - r.lp().recordedFrames(r.outPos);
  CHECK_EQ(r.lp().targetFrames(), 0);  // manual: abierta
  r.runTo(rec1 + 24 * bar - 100);
  CHECK(r.state() == St::kRecording);
  r.runFor(200);
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().trackLength(second), 24 * bar);
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
  testFourTracks();
  testSyncTracks();
  testTrackGestures();
}
