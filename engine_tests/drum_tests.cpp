// Loopin — tests de la batería (PC)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Casi todos miran la lista de golpes que apunta la batería (en qué muestra de
// salida suena cada uno) y la comparan con la que sale a mano de la partitura.
// testDrumAudio comprueba además que cada golpe suena justo en esa muestra.
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <set>
#include <utility>
#include <vector>

#include "Drums.h"
#include "EngineCore.h"
#include "rig.h"
#include "test_util.h"

using namespace loopin;
using namespace loopin_test;
using DS = DrumSound;
using Hit = Drums::LoggedHit;

namespace {

void postArg(Rig& r, T t, double v, int32_t arg) { r.core.post({t, v, arg}); }

// Muestras de prueba: un impulso de 1 muestra (o lo que se diga) por sonido.
// Hay que llamarla antes de r.core.prepare().
void impulses(EngineCore& core, std::initializer_list<DS> sounds, float value = 1.0f) {
  for (int i = 0; i < int(DS::kCount); ++i) core.setDrumSample(DS(i), nullptr, 0, 0);
  static float one[1];
  one[0] = value;
  for (DS s : sounds) core.setDrumSample(s, one, 1, 48000);
}

// Prepara el motor con las muestras de prueba y apunta los golpes en log
void setup(Rig& r, std::vector<Hit>& log, std::initializer_list<DS> sounds = {}) {
  impulses(r.core, sounds);
  r.core.prepare(r.sr);
  log.clear();
  log.reserve(1 << 16);
  r.core.drumsForTest().setTestLog(&log);
}

using Ev = std::pair<int64_t, DS>;

std::vector<Ev> events(const std::vector<Hit>& log, int64_t from = 0, int64_t to = Looper::kNever) {
  std::vector<Ev> v;
  for (const Hit& h : log)
    if (h.frame >= from && h.frame < to) v.push_back({h.frame, h.sound});
  std::sort(v.begin(), v.end());
  return v;
}

std::vector<int64_t> framesOf(const std::vector<Hit>& log, DS s) {
  std::vector<int64_t> v;
  for (const Hit& h : log)
    if (h.sound == s) v.push_back(h.frame);
  return v;
}

int64_t firstFrame(const std::vector<Hit>& log) {
  int64_t f = Looper::kNever;
  for (const Hit& h : log) f = std::min(f, h.frame);
  return f;
}

struct MeterCase {
  const char* name;
  int beats;
  uint32_t mask;
  bool eighths;
  std::vector<int> kick, snare;  // tiempos con bombo y con caja (básico)
};

const std::vector<MeterCase>& meters() {
  // Los 10 compases de la app, con el patrón básico escrito a mano
  static const std::vector<MeterCase> m = {
      {"4/4", 4, 0, false, {0, 2}, {1, 3}},
      {"3/4", 3, 0, false, {0}, {1, 2}},
      {"2/4", 2, 0, false, {0}, {1}},
      {"5/4 (3+2)", 5, 1u << 3, false, {0}, {3}},
      {"7/4 (4+3)", 7, 1u << 4, false, {0}, {4}},
      {"6/8", 6, 1u << 3, true, {0}, {3}},
      {"9/8", 9, (1u << 3) | (1u << 6), true, {0, 6}, {3}},
      {"12/8", 12, (1u << 3) | (1u << 6) | (1u << 9), true, {0, 6}, {3, 9}},
      {"5/8 (3+2)", 5, 1u << 3, true, {0}, {3}},
      {"7/8 (2+2+3)", 7, (1u << 2) | (1u << 4), true, {0, 4}, {2}},
  };
  return m;
}

// «Listo cuando»: la batería sigue el BPM y el compás en todos los compases.
// Básico en los 10, a 3 tempos y a 48 y 44,1 kHz, con bloques de tamaños
// variables: cada golpe cae en su muestra, compás tras compás.
void testDrumsAllMeters() {
  std::printf("Batería: el básico sigue el tempo y el compás en los 10 compases\n");
  int runs = 0, wrong = 0;
  for (int32_t sr : {48000, 44100}) {
    for (const MeterCase& mc : meters()) {
      for (double bpm : {61.0, 128.0, 233.0}) {
        Rig r(sr, 0, uint32_t(runs + 7));
        r.keep = false;
        std::vector<Hit> log;
        setup(r, log);
        postArg(r, T::kSetMeter, mc.beats, int32_t(mc.mask));
        r.post(T::kSetBpm, bpm);
        postArg(r, T::kSetDrumStyle, 0, mc.eighths ? 1 : 0);
        r.post(T::kSetDrumsEnabled, 1);
        r.post(T::kPlay);
        const int64_t spb = Transport::computeSamplesPerBeat(sr, bpm);
        const int64_t bar = spb * mc.beats;
        const int bars = 9;
        r.runTo(bars * bar);
        std::vector<Ev> want;
        for (int k = 0; k < bars; ++k) {
          const int64_t b0 = k * bar;
          if (k == 0) want.push_back({0, DS::kCrash});  // entra con un crash
          for (int b = 0; b < mc.beats; ++b) {
            const int64_t t = b0 + b * spb;
            want.push_back({t, DS::kHat});
            if (!mc.eighths) want.push_back({t + spb / 2, DS::kHatSoft});
            if (std::count(mc.kick.begin(), mc.kick.end(), b)) want.push_back({t, DS::kKick});
            if (std::count(mc.snare.begin(), mc.snare.end(), b)) want.push_back({t, DS::kSnare});
          }
        }
        std::sort(want.begin(), want.end());
        const std::vector<Ev> got = events(log);
        if (got != want) {
          ++wrong;
          std::printf("  %s a %.0f BPM y %d Hz: %zu golpes, esperados %zu\n", mc.name, bpm, sr,
                      got.size(), want.size());
        }
        CHECK(r.core.status().drumsPlaying == 1);
        ++runs;
      }
    }
  }
  CHECK_EQ(wrong, 0);
  std::printf("  %d combinaciones, todos los golpes en su muestra\n", runs);
}

// Los estilos hechos a mano: rock (semicorcheas, 2 compases) y shuffle
// (tresillos). El desfase de cada paso se redondea a la muestra.
void testDrumsStyles() {
  std::printf("Batería: rock, shuffle y 12/8 tocan su partitura\n");
  const int32_t sr = 44100;
  const double bpm = 92;
  const int64_t spb = Transport::computeSamplesPerBeat(sr, bpm);  // 28761
  const int64_t bar = 4 * spb;
  auto step = [&](int64_t sub, int64_t steps) { return (sub * spb + steps / 2) / steps; };
  {
    Rig r(sr, 0, 3);
    std::vector<Hit> log;
    setup(r, log);
    r.post(T::kSetBpm, bpm);
    postArg(r, T::kSetDrumStyle, 1, 0);  // rock
    r.post(T::kSetDrumsEnabled, 1);
    r.post(T::kPlay);
    r.runTo(4 * bar);
    std::vector<int64_t> kick;
    for (int k = 0; k < 4; ++k) {
      const int64_t b0 = k * bar;
      kick.push_back(b0);                      // 1
      kick.push_back(b0 + 2 * spb);            // 3
      kick.push_back(b0 + 2 * spb + step(2, 4));  // 3 y
      if (k % 2 == 1) kick.push_back(b0 + 3 * spb + step(2, 4));  // 4 y (2.º compás)
    }
    CHECK(framesOf(log, DS::kKick) == kick);
    std::vector<int64_t> snare, hat;
    for (int k = 0; k < 4; ++k)
      for (int b = 0; b < 4; ++b) {
        if (b % 2 == 1) snare.push_back(k * bar + b * spb);
        hat.push_back(k * bar + b * spb);
        hat.push_back(k * bar + b * spb + step(2, 4));
      }
    CHECK(framesOf(log, DS::kSnare) == snare);
    CHECK(framesOf(log, DS::kHat) == hat);
    CHECK(r.core.drums().effectiveStyle() == DrumStyle::kRock);
  }
  {
    Rig r(sr, 0, 4);
    std::vector<Hit> log;
    setup(r, log);
    r.post(T::kSetBpm, bpm);
    postArg(r, T::kSetDrumStyle, 3, 0);  // shuffle
    r.post(T::kSetDrumsEnabled, 1);
    r.post(T::kPlay);
    r.runTo(2 * bar);
    std::vector<int64_t> hat, soft;
    for (int k = 0; k < 2; ++k)
      for (int b = 0; b < 4; ++b) {
        hat.push_back(k * bar + b * spb);
        soft.push_back(k * bar + b * spb + step(2, 3));  // 3.ª corchea del tresillo
      }
    CHECK(framesOf(log, DS::kHat) == hat);
    CHECK(framesOf(log, DS::kHatSoft) == soft);
    CHECK(framesOf(log, DS::kSnare) ==
          (std::vector<int64_t>{spb, 3 * spb, bar + spb, bar + 3 * spb}));
  }
  {
    // 12/8: ride en cada corchea, bombo en 1 y 7 (y 6 de recogida), caja en 4 y 10
    Rig r(sr, 0, 5);
    std::vector<Hit> log;
    setup(r, log);
    r.post(T::kSetBpm, bpm);
    postArg(r, T::kSetMeter, 12, (1 << 3) | (1 << 6) | (1 << 9));
    postArg(r, T::kSetDrumStyle, 9, 1);
    r.post(T::kSetDrumsEnabled, 1);
    r.post(T::kPlay);
    const int64_t bar12 = 12 * spb;
    r.runTo(bar12);
    CHECK(framesOf(log, DS::kRide).size() == 12);
    CHECK(framesOf(log, DS::kKick) == (std::vector<int64_t>{0, 5 * spb, 6 * spb}));
    CHECK(framesOf(log, DS::kSnare) == (std::vector<int64_t>{3 * spb, 9 * spb}));
  }
}

// Lo que suena sale justo en la muestra del golpe, con su fuerza y el volumen
// de la batería. El charles cerrado corta el abierto en 5 ms.
void testDrumAudio() {
  std::printf("Batería: cada golpe suena en su muestra; el charles cerrado corta el abierto\n");
  const int32_t sr = 48000;
  {
    Rig r(sr, 0, 9);
    std::vector<Hit> log;
    setup(r, log, {DS::kKick, DS::kSnare, DS::kHat, DS::kHatSoft, DS::kCrash});
    postArg(r, T::kSetDrumStyle, 4, 0);  // funk: muchos golpes juntos
    r.post(T::kSetDrumsEnabled, 1);
    r.post(T::kSetDrumVolume, 0.3);  // sin pasar de 1 (la salida se recorta)
    r.post(T::kPlay);
    r.runTo(4 * 115200);  // 4 compases a 100 BPM
    // Lo que debería sonar: la suma de los golpes de cada muestra × volumen
    std::vector<double> want(r.hist.size(), 0.0);
    for (const Hit& h : log)
      if (h.sound != DS::kCrossStick && h.sound != DS::kHatOpen && h.sound != DS::kSnareSoft)
        want[size_t(h.frame)] += h.gain;
    int64_t bad = 0;
    for (size_t n = 0; n < r.hist.size(); ++n)
      if (std::fabs(r.hist[n] - 0.3 * want[n]) > 1e-5) {
        if (bad == 0) std::printf("  muestra %zu: %f, esperado %f\n", n, r.hist[n], 0.3 * want[n]);
        ++bad;
      }
    CHECK_EQ(bad, 0);
    CHECK_EQ(log.size(), 97);  // 24 golpes por compás y el crash
  }
  {
    // Pop: charles abierto en el «4 y» del 2.º compás, cerrado en el 1 siguiente
    Rig r(sr, 0, 10);
    std::vector<Hit> log;
    setup(r, log, {DS::kHat});
    static std::vector<float> open(48000, 0.5f);
    r.core.setDrumSample(DS::kHatOpen, open.data(), int32_t(open.size()), sr);
    r.core.prepare(sr);
    r.core.drumsForTest().setTestLog(&log);
    r.post(T::kSetBpm, 120);
    postArg(r, T::kSetDrumStyle, 2, 0);
    r.post(T::kSetDrumsEnabled, 1);
    r.post(T::kSetDrumVolume, 1.0);
    r.post(T::kPlay);
    r.runTo(3 * 96000);
    const std::vector<int64_t> opens = framesOf(log, DS::kHatOpen);
    CHECK(opens == (std::vector<int64_t>{96000 + 3 * 24000 + 12000}));
    const int64_t closed = 2 * 96000;  // el siguiente cerrado
    CHECK(std::fabs(r.hist[size_t(closed - 1)] - 0.375f) < 1e-5);  // abierto: 0,5 × 0,75
    // A los 5 ms del cerrado ya no queda nada del abierto
    bool gone = true;
    for (int64_t n = closed + sr / 200 + 1; n < closed + 2000; ++n)
      if (r.hist[size_t(n)] != 0.0f) gone = false;
    CHECK(gone);
  }
}

// Cuenta de entrada con baquetas en vez del clic; luego entra la batería en
// el primer tiempo de la grabación y el clic se calla mientras toca.
void testDrumsCountIn() {
  std::printf("Batería: cuenta con baquetas y el clic se calla mientras toca\n");
  const int32_t sr = 48000;
  const int64_t bar = 96000, spb = 24000;
  for (int clickMode : {2, 1, 0}) {
    Rig r(sr, 3000, 11);
    std::vector<Hit> log;
    setup(r, log, {DS::kSticks});  // solo suenan las baquetas (y el clic)
    r.post(T::kSetBpm, 120);
    r.post(T::kSetSyncBars, 1);
    r.post(T::kSetClickMode, clickMode);
    r.post(T::kSetDrumsEnabled, 1);
    r.post(T::kLoopPress);
    r.runTo(3 * bar);
    // Cuenta: baquetas en los 4 tiempos (salvo con el clic en «nunca»)
    const std::vector<int64_t> sticks = framesOf(log, DS::kSticks);
    if (clickMode == 0) {
      CHECK(sticks.empty());
    } else {
      CHECK(sticks == (std::vector<int64_t>{0, spb, 2 * spb, 3 * spb}));
    }
    // Lo único que suena son las baquetas: nada de clic, ni en la cuenta ni luego
    int64_t extra = 0;
    for (int64_t n = 0; n < 3 * bar; ++n) {
      const bool stick = std::count(sticks.begin(), sticks.end(), n) > 0;
      if (!stick && r.hist[size_t(n)] != 0.0f) ++extra;
    }
    CHECK_EQ(extra, 0);
    // El 1, fuerte (volumen 0,7)
    CHECK(std::fabs(r.hist[0] - (clickMode == 0 ? 0.0f : 0.7f)) < 1e-5);
    // La batería entra con la grabación, en el compás 2, con un crash
    CHECK_EQ(firstFrame(log), clickMode == 0 ? bar : 0);
    const std::vector<int64_t> kicks = framesOf(log, DS::kKick);
    CHECK(!kicks.empty() && kicks.front() == bar);
    CHECK(framesOf(log, DS::kCrash) == (std::vector<int64_t>{bar}));
    CHECK(r.state() == St::kPlaying);
  }
  {
    // Sin batería, la cuenta sigue siendo con el clic
    Rig r(sr, 3000, 12);
    std::vector<Hit> log;
    setup(r, log, {DS::kSticks});
    r.post(T::kSetBpm, 120);
    r.post(T::kSetClickMode, 1);
    r.post(T::kLoopPress);
    r.runTo(bar);
    CHECK(log.empty());
    CHECK(r.hist[10] != 0.0f);  // clic
  }
}

// Empezar al tocar: la batería espera al primer 1 después de que arranque el
// tempo (el ataque se detecta tarde) y cae justo en la rejilla del loop.
void testDrumsStartOnSound() {
  std::printf("Batería: con «empezar al tocar» entra en el siguiente 1\n");
  const int32_t sr = 48000;
  const int32_t L = 6123;
  Rig r(sr, L, 47);
  std::vector<Hit> log;
  setup(r, log);
  r.post(T::kSetBpm, 120);
  r.post(T::kSetLoopMode, 0);
  r.post(T::kSetSyncBars, 2);
  r.post(T::kSetStartOnSound, 1);
  r.post(T::kSetDrumsEnabled, 1);
  const int64_t bar = 96000;
  const int64_t T0 = 60000;
  r.player = [&](int64_t n) { return n >= T0 ? 0.25f + sig(1, n - T0) : 0.0f; };
  r.post(T::kLoopPress);
  r.runTo(T0 + 4 * bar);
  const int64_t start = T0 - sr / 500;  // el compás 1 empieza 2 ms antes del ataque
  CHECK_EQ(r.lp().baseLength(), 2 * bar);
  CHECK_EQ(firstFrame(log), start + bar);
  std::vector<int64_t> want;
  for (int64_t k = 1; start + k * bar < r.outPos; ++k) {
    want.push_back(start + k * bar);
    if (start + k * bar + 2 * 24000 < r.outPos) want.push_back(start + k * bar + 2 * 24000);
  }
  CHECK(framesOf(log, DS::kKick) == want);
}

// Libre: no hay tempo hasta cerrar el primer loop. Al cerrarlo, la batería
// entra en ese mismo 1 (aunque el loop se recorte unas muestras) y sigue los
// compases del loop.
void testDrumsFreeMode() {
  std::printf("Batería: en libre entra al cerrar el primer loop, a su compás\n");
  const int32_t sr = 48000;
  for (int64_t len : {205000LL, 205003LL}) {  // con y sin recorte
    Rig r(sr, 4113, 53);
    std::vector<Hit> log;
    setup(r, log);
    r.post(T::kSetLoopMode, 2);
    r.post(T::kSetBeatsPerBar, 4);
    r.post(T::kSetDrumsEnabled, 1);
    r.player = [](int64_t n) { return 0.2f + sig(2, n); };
    const int64_t rec = 1000;
    r.postAt(rec, T::kLoopPress);
    r.postAt(rec + len, T::kLoopPress);
    r.runFor(5 * 102500);
    CHECK(r.state() == St::kPlaying);
    const int64_t barF = r.lp().barFrames();
    CHECK_EQ(barF, 102500);  // 2 compases a 112,4 BPM
    CHECK(firstFrame(log) == rec + len);  // entra al cerrar, sin esperar otro compás
    const std::vector<int64_t> kicks = framesOf(log, DS::kKick);
    CHECK(!kicks.empty());
    // Desde el segundo 1, cada compás en su sitio exacto respecto al loop
    bool aligned = kicks.size() >= 6;
    for (size_t k = 1; k < kicks.size(); ++k)
      if (wrapPos(kicks[k] - rec, barF / 2) != 0) aligned = false;
    CHECK(aligned);
    CHECK_EQ(kicks[1], rec + 2 * barF + barF / 2);
  }
}

// Cambios con la batería sonando: el tempo, en el siguiente tiempo; el estilo,
// en el siguiente compás; si el estilo no es del compás, suena el básico.
void testDrumsChanges() {
  std::printf("Batería: cambios de tempo, estilo y compás\n");
  const int32_t sr = 48000;
  {
    Rig r(sr, 0, 21);
    std::vector<Hit> log;
    setup(r, log);
    r.post(T::kSetBpm, 100);  // 28800
    r.post(T::kSetDrumsEnabled, 1);
    r.post(T::kPlay);
    r.postAt(5 * 28800 + 1000, T::kSetBpm, 150);  // 19200, desde el tiempo 6
    r.runTo(6 * 28800 + 10 * 19200);
    std::vector<int64_t> want;
    for (int k = 0; k < 6; ++k) want.push_back(k * 28800);
    for (int k = 0; k < 10; ++k) want.push_back(6 * 28800 + k * 19200);
    CHECK(framesOf(log, DS::kHat) == want);
  }
  {
    Rig r(sr, 0, 22);
    std::vector<Hit> log;
    setup(r, log);
    r.post(T::kSetBpm, 120);
    r.post(T::kSetDrumsEnabled, 1);
    r.post(T::kPlay);
    r.postAt(30000, T::kSetDrumStyle, 1);  // rock a mitad del compás 1
    r.runTo(96000);
    auto soundAt = [&](int64_t f) {
      for (const Hit& h : log)
        if (h.frame == f && (h.sound == DS::kHat || h.sound == DS::kHatSoft)) return h.sound;
      return DS::kCount;
    };
    CHECK(soundAt(36000) == DS::kHatSoft);  // aún el básico
    r.runTo(2 * 96000);
    CHECK(soundAt(96000 + 36000) == DS::kHat);  // ya el rock
    CHECK(r.core.drums().effectiveStyle() == DrumStyle::kRock);
    // 3/4 con el rock pedido: no es su compás, suena el básico de 3/4
    postArg(r, T::kSetMeter, 3, 0);
    const int64_t b3 = 3 * 96000;  // el compás que ya va en 3/4
    r.runTo(b3 + 72000);
    CHECK(r.core.drums().effectiveStyle() == DrumStyle::kBasic);
    CHECK_EQ(r.core.status().drumStyle, 1);
    CHECK(framesOf(log, DS::kSnare).back() == b3 + 2 * 24000);
    // Vals en 3/4
    r.post(T::kSetDrumStyle, 7);
    r.runTo(b3 + 3 * 72000);
    CHECK(r.core.drums().effectiveStyle() == DrumStyle::kWaltz);
    const std::vector<Ev> last = events(log, b3 + 2 * 72000, b3 + 3 * 72000);
    const int64_t w = b3 + 2 * 72000;
    CHECK(last == (std::vector<Ev>{{w, DS::kKick},
                                   {w, DS::kHat},
                                   {w + 24000, DS::kSnare},
                                   {w + 24000, DS::kHat},
                                   {w + 48000, DS::kSnare},
                                   {w + 48000, DS::kHat}}));
  }
}

// Encenderla con todo sonando: espera al siguiente 1 y entra con un crash.
// Apagarla: no suena nada más. Parar y arrancar: vuelve a entrar en el 1.
void testDrumsOnOff() {
  std::printf("Batería: encender a mitad de compás, apagar, parar y arrancar\n");
  const int32_t sr = 48000;
  Rig r(sr, 0, 31);
  std::vector<Hit> log;
  setup(r, log);
  r.post(T::kSetBpm, 120);
  r.post(T::kPlay);
  r.postAt(30000, T::kSetDrumsEnabled, 1);
  r.runTo(96000 + 10);
  CHECK_EQ(firstFrame(log), 96000);
  CHECK(framesOf(log, DS::kCrash) == (std::vector<int64_t>{96000}));
  r.postAt(200000, T::kSetDrumsEnabled, 0);
  const size_t n = log.size();
  r.runTo(400000);
  CHECK_EQ(log.size(), n);
  CHECK(r.core.status().drumsPlaying == 0);
  r.post(T::kSetDrumsEnabled, 1);
  r.postAt(420000, T::kPause);
  r.runTo(500000);
  CHECK(r.core.status().drumsPlaying == 0);
  r.post(T::kPlay);
  r.runTo(500000 + 10);
  // Arranca en el compás 1: crash y bombo en esa muestra
  const std::vector<Ev> got = events(log, 500000, 500001);
  CHECK(std::count(got.begin(), got.end(), Ev{500000, DS::kCrash}) == 1);
  CHECK(std::count(got.begin(), got.end(), Ev{500000, DS::kKick}) == 1);
  CHECK(events(log, 400000, 500000).empty());
}

// Las muestras se pasan a la frecuencia del móvil
void testDrumResample() {
  std::printf("Batería: muestras a 44,1 kHz desde 48 kHz\n");
  Drums d;
  std::vector<float> s(480, 0.25f);
  d.setSample(DS::kKick, s.data(), int32_t(s.size()), 48000);
  d.setSample(DS::kSnare, s.data(), int32_t(s.size()), 44100);
  d.prepare(44100);
  CHECK_EQ(d.sampleFrames(DS::kKick), 441);
  CHECK_EQ(d.sampleFrames(DS::kSnare), 480);
  CHECK(!d.hasSample(DS::kHat));
}

// Cuánto cuesta: un minuto de funk con muestras de verdad (por longitud)
void testDrumCost() {
  std::printf("Batería: coste\n");
  EngineCore core;
  std::vector<float> s(48000 * 2);
  for (size_t i = 0; i < s.size(); ++i) s[i] = 0.3f * std::sin(0.01f * float(i));
  for (int i = 0; i < int(DS::kCount); ++i) core.setDrumSample(DS(i), s.data(), int32_t(s.size()), 48000);
  core.prepare(48000);
  core.post({T::kSetBpm, 180});
  core.post({T::kSetDrumStyle, 4});
  core.post({T::kSetDrumsEnabled, 1});
  core.post({T::kPlay});
  std::vector<float> in(256, 0.0f), out(512, 0.0f);
  auto run = [&](bool drums) {
    core.post({T::kSetDrumsEnabled, drums ? 1.0 : 0.0});
    const auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < 48000 * 60 / 256; ++i) core.process(in.data(), 256, 1, out.data(), 256, 2);
    return std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  };
  const double without = run(false);
  const double with = run(true);
  std::printf("  1 min de audio: %.0f ms sin batería, %.0f ms con ella (%.2f %% de tiempo real)\n",
              without * 1000, with * 1000, with / 60 * 100);
  CHECK(with < 6.0);  // muy holgado: en el PC son unas decenas de ms
}

}  // namespace

void runDrumTests() {
  testDrumsAllMeters();
  testDrumsStyles();
  testDrumAudio();
  testDrumsCountIn();
  testDrumsStartOnSound();
  testDrumsFreeMode();
  testDrumsChanges();
  testDrumsOnOff();
  testDrumResample();
  testDrumCost();
}
