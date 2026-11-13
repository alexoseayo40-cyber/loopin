// Loopin — tests del motor de la Etapa 5: reverse, media velocidad, cambios
// al compás, modos de parar, entrenador de tempo y afinador
// SPDX-License-Identifier: GPL-3.0-or-later
#include <chrono>
#include <cmath>
#include <cstdio>
#include <vector>

#include "Tuner.h"
#include "rig.h"

using namespace loopin_test;

namespace {

constexpr int32_t kSr = 48000;
constexpr int64_t kBar = 96000;  // 4/4 a 120 BPM y 48 kHz
constexpr int32_t kX = kSr / 200;  // fundido cruzado y rampa de volumen: 5 ms

// Graba la pista 1: 2 compases de sig(1, posición), con cuenta de entrada.
// Devuelve el origen (la muestra de salida de la posición 0).
int64_t recordBase(Rig& r) {
  r.post(T::kSetBpm, 120);
  r.post(T::kSetSyncBars, 2);
  const int64_t t0 = 1000;
  const int64_t base0 = t0 + kBar;
  r.player = [base0](int64_t n) {
    return n >= base0 && n < base0 + 2 * kBar ? sig(1, n - base0) : 0.0f;
  };
  r.postAt(t0, T::kLoopPress);
  r.runTo(base0 + 2 * kBar + r.L + 2000);
  r.player = [](int64_t) { return 0.0f; };
  CHECK(r.state() == St::kPlaying);
  CHECK_EQ(r.lp().trackLength(0), 2 * kBar);
  return base0;
}

float d1(int64_t p) { return p >= 0 && p < 2 * kBar ? sig(1, p) : 0.0f; }

// Lo que suena en q (medias muestras) de un buffer con contenido f
template <class F>
float valueAt(F f, int64_t q, int64_t len) {
  const int64_t p = q >> 1;
  if ((q & 1) == 0) return f(p);
  return 0.5f * (f(p) + f(p + 1 >= len ? 0 : p + 1));
}

// Compara la salida con lo esperado en [from, to)
template <class F>
void expectRange(Rig& r, int64_t from, int64_t to, F want, const char* what) {
  int64_t wrong = 0;
  for (int64_t n = from; n < to; ++n) {
    const float w = want(n);
    if (std::fabs(r.hist[size_t(n)] - w) > 1e-6f) {
      if (wrong == 0)
        std::printf("  %s: muestra %lld = %g, esperado %g\n", what, (long long)n,
                    r.hist[size_t(n)], w);
      ++wrong;
    }
  }
  if (wrong) std::printf("  %s: %lld muestras mal\n", what, (long long)wrong);
  CHECK_EQ(wrong, 0);
}

void testReverseAndHalf() {
  std::printf("Reverse y media velocidad: siguen desde donde suena y vuelven a su sitio\n");
  Rig r(kSr, 3001, 5);
  const int64_t base0 = recordBase(r);
  const int64_t len = 2 * kBar;
  auto grid = [&](int64_t n) { return d1(wrapPos(n - base0, len)); };
  expectRange(r, base0 + 2 * kBar, r.outPos, grid, "normal");

  // Reverse a mitad de compás (sin esperar al 1): desde donde suena, hacia atrás
  const int64_t n0 = r.outPos + 12345;
  r.runTo(n0);
  r.postTrack(T::kSetTrackReverse, 0, 1);
  r.runFor(kBar);
  const int64_t p0 = wrapPos(n0 - base0, len);
  auto rev = [&](int64_t n) { return d1(wrapPos(p0 - (n - n0), len)); };
  expectRange(r, n0 + kX, r.outPos, rev, "reverse");
  CHECK_EQ(r.core.status().trackReverse[0], 1);
  CHECK_EQ(r.core.status().trackPending[0], 0);
  CHECK_EQ(r.lp().trackStep(0), -2);
  // Durante el fundido cruzado, entre lo de antes y lo de ahora
  {
    const int64_t n = n0 + kX / 2;
    const float w = 0.5f;
    const float want = rev(n) * (1 - w) + grid(n) * w;
    CHECK(std::fabs(r.hist[size_t(n)] - want) < 2e-3f);
  }
  // La posición publicada va hacia atrás
  const int64_t pa = r.lp().trackPosition(0);
  r.runFor(1000);
  CHECK_EQ(wrapPos(pa - r.lp().trackPosition(0), len), 1000);

  // + media velocidad: sigue desde donde suena, al revés y a la mitad
  const int64_t n1 = r.outPos + 777;
  r.runTo(n1);
  const int64_t q1 = 2 * wrapPos(p0 - (n1 - n0), len);
  r.postTrack(T::kSetTrackHalf, 0, 1);
  r.runFor(kBar);
  auto revHalf = [&](int64_t n) { return valueAt(d1, wrapPos(q1 - (n - n1), 2 * len), len); };
  expectRange(r, n1 + kX, r.outPos, revHalf, "reverse + media velocidad");
  CHECK_EQ(r.lp().trackStep(0), -1);

  // Solo media velocidad: hacia delante, a la mitad
  const int64_t n2 = r.outPos + 50;
  r.runTo(n2);
  const int64_t q2 = wrapPos(q1 - (n2 - n1), 2 * len);
  r.postTrack(T::kSetTrackReverse, 0, 0);
  r.runFor(kBar);
  auto half = [&](int64_t n) { return valueAt(d1, wrapPos(q2 + (n - n2), 2 * len), len); };
  expectRange(r, n2 + kX, r.outPos, half, "media velocidad");

  // Sin efectos: vuelve a su sitio en la rejilla (al compás de las demás)
  const int64_t n3 = r.outPos + 999;
  r.runTo(n3);
  r.postTrack(T::kSetTrackHalf, 0, 0);
  r.runFor(2 * kBar);
  expectRange(r, n3 + kX, r.outPos, grid, "otra vez normal");
  CHECK_EQ(r.lp().trackStep(0), 2);

  // Con efecto, parar y arrancar: desde su sitio en la rejilla y en su sentido
  r.postTrack(T::kSetTrackReverse, 0, 1);
  r.runFor(kBar);
  r.post(T::kPause);
  r.runFor(1000);
  const int64_t s0 = r.outPos;
  r.post(T::kPlay);
  r.runFor(kBar);
  // Al arrancar, el ciclo empieza en el 1: la posición 0 suena en s0 y va
  // hacia atrás
  auto restart = [&](int64_t n) { return d1(wrapPos(-(n - s0), len)); };
  expectRange(r, s0, r.outPos, restart, "reverse tras parar y arrancar");

  // Borrar la pista quita los efectos
  r.postTrack(T::kClearTrack, 0);
  r.runFor(10);
  CHECK_EQ(r.core.status().trackReverse[0], 0);
  // Y en una pista vacía no se pueden poner
  r.postTrack(T::kSetTrackReverse, 1, 1);
  r.runFor(10);
  CHECK_EQ(r.core.status().trackReverse[1], 0);
}

void testQuantizedChanges() {
  std::printf("Silencio y efectos en el siguiente 1 (rampa que acaba en el 1)\n");
  Rig r(kSr, 2222, 9);
  const int64_t base0 = recordBase(r);
  const int64_t len = 2 * kBar;
  auto grid = [&](int64_t n) { return d1(wrapPos(n - base0, len)); };
  r.post(T::kSetQuantize, 1);

  // Silenciar a mitad de compás: nada cambia hasta el 1; ahí baja en 5 ms
  const int64_t m = base0 + 4 * kBar + kBar / 3;
  const int64_t b1 = base0 + 5 * kBar;
  r.runTo(m);
  r.postTrack(T::kSetTrackMuted, 0, 1);
  r.runFor(100);
  CHECK_EQ(r.core.status().trackMuted[0], 1);    // lo pedido
  CHECK_EQ(r.core.status().trackPending[0], 1);  // esperando al 1
  r.runTo(b1 + kBar);
  expectRange(r, m, b1, grid, "silencio: antes del 1, normal");
  expectRange(r, b1 + kX, b1 + kBar, [](int64_t) { return 0.0f; }, "silencio desde el 1");
  CHECK_EQ(r.core.status().trackPending[0], 0);
  // Justo después del 1 aún se oye (bajando): no corta de golpe
  CHECK(std::fabs(r.hist[size_t(b1 + 10)]) > 0.0f);

  // Quitar el silencio: la rampa empieza antes y en el 1 ya suena entero
  const int64_t m2 = b1 + kBar + kBar / 2;
  const int64_t b2 = b1 + 2 * kBar;
  r.runTo(m2);
  r.postTrack(T::kSetTrackMuted, 0, 0);
  r.runTo(b2 + kBar);
  expectRange(r, m2, b2 - kX, [](int64_t) { return 0.0f; }, "sigue en silencio hasta la rampa");
  expectRange(r, b2, b2 + kBar, grid, "entra entero en el 1");

  // Pedir y anular antes del 1: no pasa nada
  const int64_t m3 = r.outPos + 1000;
  r.runTo(m3);
  r.postTrack(T::kSetTrackMuted, 0, 1);
  r.runFor(1000);
  r.postTrack(T::kSetTrackMuted, 0, 0);
  r.runFor(2 * kBar);
  expectRange(r, m3, r.outPos, grid, "silencio anulado");

  // Reverse: también en el 1, desde la posición de ese 1
  const int64_t m4 = r.outPos + kBar / 4;
  r.runTo(m4);
  const int64_t b4 = base0 + ((m4 - base0) / kBar + 1) * kBar;
  r.postTrack(T::kSetTrackReverse, 0, 1);
  r.runFor(100);
  CHECK_EQ(r.core.status().trackPending[0], 2);
  CHECK_EQ(r.core.status().trackReverse[0], 1);
  r.runTo(b4 + 2 * kBar);
  const int64_t p4 = wrapPos(b4 - base0, len);
  expectRange(r, m4, b4, grid, "reverse: antes del 1, normal");
  expectRange(r, b4 + kX, b4 + 2 * kBar,
              [&](int64_t n) { return d1(wrapPos(p4 - (n - b4), len)); }, "reverse desde el 1");

  // Con todo parado, los cambios son al momento
  r.post(T::kPause);
  r.runFor(100);
  r.postTrack(T::kSetTrackHalf, 0, 1);
  r.runFor(10);
  CHECK_EQ(r.core.status().trackPending[0], 0);
  CHECK_EQ(r.lp().trackStep(0), -1);
}

void testOverdubWithEffects() {
  std::printf("Overdub sobre una pista al revés o a media velocidad: se graba donde se oye\n");
  // 0: reverse al momento · 1: media velocidad al momento · 2: reverse pedido
  // para el siguiente 1 y overdub que empieza en ese mismo 1
  for (int mode = 0; mode < 3; ++mode) {
    const bool reverse = mode != 1;
    Rig r(kSr, 4113, 21 + mode);
    const int64_t base0 = recordBase(r);
    const int64_t len = 2 * kBar;
    if (mode == 2) r.post(T::kSetQuantize, 1);
    const int64_t ask = r.outPos + 3333;
    r.runTo(ask);
    r.postTrack(reverse ? T::kSetTrackReverse : T::kSetTrackHalf, 0, 1);
    r.runFor(10);
    // Cuándo cambia: al momento o en el siguiente 1
    const int64_t n0 = mode == 2 ? base0 + ((ask - base0) / kBar + 1) * kBar : ask;
    // Posición (medias muestras) que se oye en o
    const int64_t q0 = 2 * wrapPos(n0 - base0, len);
    auto heardQ = [&](int64_t o) {
      return reverse ? wrapPos(q0 - 2 * (o - n0), 2 * len) : wrapPos(q0 + (o - n0), 2 * len);
    };
    // Overdub de 1 compás: el músico toca sig(7, posición que oye)
    const int64_t press = r.outPos + 500;
    const int64_t a = base0 + ((press - base0) / kBar + 1) * kBar;
    if (mode == 2) CHECK_EQ(a, n0);
    r.player = [&](int64_t o) {
      return o >= a && o < a + kBar ? sig(7, heardQ(o) >> 1) : 0.0f;
    };
    r.postAt(press, T::kLoopPress);
    r.runFor(1);
    CHECK(r.state() == St::kOverdubbing);
    // Mientras dura el overdub no se puede cambiar el efecto de esa pista
    r.postTrack(T::kSetTrackHalf, 0, reverse ? 1 : 0);
    r.runFor(1);
    CHECK_EQ(r.core.status().trackHalf[0], reverse ? 0 : 1);
    r.postAt(a + kBar, T::kLoopPress);
    r.runFor(r.L + 1000);
    r.player = [](int64_t) { return 0.0f; };
    CHECK_EQ(r.lp().trackLayers(0), 2);
    if (mode == 2) r.post(T::kSetQuantize, 0);
    // Qué posiciones del buffer cubre el overdub y cuántas muestras recibió cada una
    std::vector<int> hits(size_t(len), 0);
    for (int64_t o = a; o < a + kBar; ++o) ++hits[size_t(heardQ(o) >> 1)];
    const int full = reverse ? 1 : 2;
    // Sin efecto: lo grabado suena en su sitio
    r.postTrack(reverse ? T::kSetTrackReverse : T::kSetTrackHalf, 0, 0);
    const int64_t from = r.outPos + kX;
    r.runFor(2 * kBar + kX);
    expectRange(
        r, from, r.outPos,
        [&](int64_t n) {
          const int64_t p = wrapPos(n - base0, len);
          const int h = hits[size_t(p)];
          // En los bordes de media velocidad una posición recibe solo una muestra
          const float layer = h == 0 ? 0.0f : sig(7, p) * float(h) / float(full);
          return d1(p) + layer;
        },
        mode == 0   ? "overdub al revés, oído normal"
        : mode == 1 ? "overdub a media velocidad, oído normal"
                    : "reverse y overdub en el mismo 1, oído normal");
  }
}

void testStopModes() {
  std::printf("Parar: al momento, en el siguiente 1 o con fundido\n");
  // En el siguiente 1
  {
    Rig r(kSr, 2000, 31);
    const int64_t base0 = recordBase(r);
    r.post(T::kSetStopMode, 1);
    const int64_t m = base0 + 6 * kBar + kBar / 2;
    const int64_t b = base0 + 7 * kBar;
    r.runTo(m);
    r.post(T::kStop);
    r.runFor(10);
    CHECK_EQ(r.core.status().stopping, 1);
    CHECK(r.core.status().playing);
    r.runTo(b + kBar);
    CHECK(!r.core.status().playing);
    CHECK(r.state() == St::kStopped);
    CHECK_EQ(r.core.status().stopping, 0);
    const int64_t len = 2 * kBar;
    expectRange(r, m, b, [&](int64_t n) { return d1(wrapPos(n - base0, len)); },
                "en el 1: suena hasta el 1");
    expectRange(r, b, b + kBar, [](int64_t) { return 0.0f; }, "en el 1: luego nada");
    // Otra vez ▶ y parar dos veces: la segunda, al momento
    r.post(T::kPlay);
    r.runFor(kBar / 2);
    r.post(T::kStop);
    r.runFor(100);
    CHECK_EQ(r.core.status().stopping, 1);
    r.post(T::kStop);
    r.runFor(10);
    CHECK(!r.core.status().playing);
    // Pisar mientras espera: también para ya (y no graba nada)
    r.post(T::kPlay);
    r.runFor(kBar / 3);
    r.post(T::kStop);
    r.runFor(100);
    r.post(T::kLoopPress);
    r.runFor(10);
    CHECK(!r.core.status().playing);
    CHECK(r.state() == St::kStopped);
    CHECK_EQ(r.lp().trackLayers(0), 1);
    // Con un overdub en marcha: se acaba al pedirlo y para en el 1
    r.post(T::kPlay);
    r.runFor(1000);
    r.post(T::kLoopPress);  // overdub desde el siguiente compás
    r.runFor(kBar + 5000);
    CHECK(r.state() == St::kOverdubbing);
    r.post(T::kStop);
    r.runFor(10);
    CHECK(r.state() == St::kPlaying);
    CHECK_EQ(r.lp().trackLayers(0), 2);
    CHECK_EQ(r.core.status().stopping, 1);
  }
  // Con fundido (1 s)
  {
    Rig r(kSr, 2000, 33);
    const int64_t base0 = recordBase(r);
    const int64_t len = 2 * kBar;
    r.post(T::kSetStopMode, 2);
    r.post(T::kSetFadeSeconds, 1.0);
    const int64_t s = r.outPos + 1234;
    r.runTo(s);
    r.post(T::kStop);
    r.runFor(kSr / 2);
    CHECK_EQ(r.core.status().stopping, 2);
    CHECK(r.core.status().playing);
    // El volumen baja en exponencial (−60 dB en 1 s): la misma cuenta que el motor
    const float mul = static_cast<float>(std::pow(10.0, -3.0 / kSr));
    float g = 1.0f;
    int64_t bad = 0;
    for (int64_t n = s; n < s + kSr / 2; ++n) {
      const float want = d1(wrapPos(n - base0, len)) * g;
      if (std::fabs(r.hist[size_t(n)] - want) > 1e-6f) ++bad;
      g *= mul;
    }
    CHECK_EQ(bad, 0);
    CHECK(std::fabs(20 * std::log10(g) + 30) < 0.1);  // a la mitad, −30 dB
    r.runFor(kSr / 2 + 2000);
    CHECK(!r.core.status().playing);
    CHECK(r.state() == St::kStopped);
    CHECK_EQ(r.core.status().stopping, 0);
    // Al volver a arrancar, suena a su volumen
    r.post(T::kPlay);
    const int64_t p = r.outPos;
    r.runFor(kBar);
    expectRange(r, p, r.outPos, [&](int64_t n) { return d1(wrapPos(n - p, len)); },
                "tras el fundido, a su volumen");
    // El doble toque también para con fundido; pisar mientras baja para ya
    r.post(T::kLoopPress);
    r.post(T::kLoopDoubleTap);
    r.runFor(1000);
    CHECK_EQ(r.core.status().stopping, 2);
    CHECK_EQ(r.lp().trackLayers(0), 1);  // el toque empezó un overdub: se quita
    r.post(T::kLoopPress);
    r.runFor(10);
    CHECK(!r.core.status().playing);
    CHECK(r.state() == St::kStopped);
    // Al momento (el modo de siempre)
    r.post(T::kSetStopMode, 0);
    r.post(T::kPlay);
    r.runFor(kBar / 2);
    r.post(T::kStop);
    r.runFor(1);
    CHECK(!r.core.status().playing);
  }
  // Con el clic sonando: el fundido lo baja también y luego no queda nada
  {
    Rig r(kSr, 2000, 35);
    r.post(T::kSetBpm, 120);
    r.post(T::kSetStopMode, 2);
    r.post(T::kSetFadeSeconds, 0.5);
    r.post(T::kSetClickMode, 2);
    r.post(T::kPlay);
    r.runFor(2 * kBar);
    r.post(T::kStop);
    r.runFor(kSr / 2 + 1000);
    CHECK(!r.core.status().playing);
    float tail = 0.0f;
    for (int64_t n = r.outPos - 500; n < r.outPos; ++n)
      tail = std::max(tail, std::fabs(r.hist[size_t(n)]));
    CHECK(tail < 0.002f);
    r.runFor(kSr);
    float after = 0.0f;
    for (int64_t n = r.outPos - kSr / 2; n < r.outPos; ++n)
      after = std::max(after, std::fabs(r.hist[size_t(n)]));
    CHECK(after == 0.0f);
  }
}

// Inicios de los clics del metrónomo (con al menos 2000 muestras de silencio delante)
std::vector<int64_t> clickOnsets(const Rig& r, int64_t from, int64_t to) {
  std::vector<int64_t> on;
  int64_t quiet = 2000;  // antes de from, silencio
  for (int64_t n = from; n < to; ++n) {
    if (r.hist[size_t(n)] != 0.0f) {
      if (quiet >= 2000) on.push_back(n);
      quiet = 0;
    } else {
      ++quiet;
    }
  }
  return on;
}

void testTrainer() {
  std::printf("Entrenador: +5 BPM cada 2 compases hasta 110, justo en el 1; al parar vuelve\n");
  Rig r(kSr, 2000, 41);
  r.post(T::kSetBpm, 100);
  r.post(T::kSetClickMode, 2);
  r.core.post({T::kSetTrainer, 5.0, 2});
  r.post(T::kSetTrainerTop, 110);
  r.runFor(100);
  const int64_t start = r.outPos;
  r.post(T::kPlay);
  r.runFor(int64_t(kSr) * 18);
  const std::vector<int64_t> on = clickOnsets(r, start, r.outPos);
  CHECK(on.size() > 28);
  const int32_t s100 = Transport::computeSamplesPerBeat(kSr, 100);
  const int32_t s105 = Transport::computeSamplesPerBeat(kSr, 105);
  const int32_t s110 = Transport::computeSamplesPerBeat(kSr, 110);
  int64_t bad = 0;
  for (size_t k = 1; k < on.size(); ++k) {
    const size_t beat = k - 1;  // tiempo que acaba en on[k]
    const int32_t want = beat < 8 ? s100 : (beat < 16 ? s105 : s110);
    if (on[k] - on[k - 1] != want) {
      if (bad == 0)
        std::printf("  tiempo %zu: %lld muestras, esperado %d\n", beat,
                    (long long)(on[k] - on[k - 1]), want);
      ++bad;
    }
  }
  CHECK_EQ(bad, 0);
  CHECK(std::fabs(r.core.status().bpm - 110.0) < 1e-9);
  CHECK_EQ(r.core.status().trainerBars, 2);
  // Al parar, vuelve el tempo del usuario
  r.post(T::kPause);
  r.runFor(100);
  CHECK(std::fabs(r.core.status().bpm - 100.0) < 1e-9);
  // Y al arrancar empieza otra vez desde ahí
  r.post(T::kPlay);
  r.runFor(kSr);
  CHECK(std::fabs(r.core.status().bpm - 100.0) < 1e-9);
  // Apagarlo a medias vuelve al tempo del usuario
  r.runFor(int64_t(kSr) * 6);
  CHECK(r.core.status().bpm > 100.0);
  r.core.post({T::kSetTrainer, 5.0, 0});
  r.runFor(kSr);
  CHECK(std::fabs(r.core.status().bpm - 100.0) < 1e-9);
  r.post(T::kPause);

  // Con loops no hace nada (el tempo es del loop)
  Rig q(kSr, 2000, 43);
  recordBase(q);
  q.core.post({T::kSetTrainer, 10.0, 1});
  q.runFor(8 * kBar);
  CHECK(std::fabs(q.core.status().bpm - 120.0) < 1e-9);
}

// ---------------------------------------------------------------- afinador

double cents(double f, double ref) { return 1200.0 * std::log2(f / ref); }

// Cuerda «sintética»: armónicos que se apagan, más rápido los agudos
std::vector<float> stringTone(double f, int32_t sr, int32_t frames, double fundamental,
                              double inharm = 0.0, uint32_t seed = 1) {
  std::vector<float> x(size_t(frames), 0.0f);
  std::mt19937 rng(seed);
  std::uniform_real_distribution<double> ph(0.0, 6.283185307);
  for (int k = 1; k <= 16; ++k) {
    const double fk = k * f * std::sqrt(1.0 + inharm * k * k);
    if (fk > sr / 2.2) break;
    const double amp = (k == 1 ? fundamental : 0.8 / k) * 0.3;
    const double decay = 1.5 + 0.6 * k;
    const double p = ph(rng);
    for (int32_t i = 0; i < frames; ++i) {
      const double t = double(i) / sr;
      x[size_t(i)] += float(amp * std::exp(-decay * t) * std::sin(6.283185307 * fk * t + p));
    }
  }
  return x;
}

void testTuner() {
  std::printf("Afinador: notas de guitarra a ±1 cent, sin saltos de octava\n");
  const double notes[] = {41.20, 55.0, 73.42, 82.41, 110.0, 146.83, 196.0, 246.94, 329.63,
                          440.0, 659.26, 987.77, 1318.5};
  for (int32_t sr : {48000, 44100, 96000}) {
    Tuner tuner;
    tuner.prepare(sr);
    double worst = 0.0;
    for (double f : notes) {
      for (double fund : {1.0, 0.15}) {  // con la fundamental débil (micro del móvil)
        if (f > 1000 && fund < 1) continue;
        const std::vector<float> x = stringTone(f, sr, tuner.frames() + sr / 10, fund, 0.0,
                                                uint32_t(f));
        // Un trozo de unos 100 ms después del ataque
        const TunerResult res = tuner.analyze(x.data() + sr / 10);
        if (res.frequency <= 0) {
          std::printf("  %d Hz: %.2f Hz (fundamental %.2f) sin resultado\n", sr, f, fund);
          CHECK(false);
          continue;
        }
        const double c = cents(res.frequency, f);
        worst = std::max(worst, std::fabs(c));
        if (std::fabs(c) > 1.0) {
          std::printf("  %d Hz: %.2f Hz (fundamental %.2f) → %.3f Hz (%.2f cents)\n", sr, f, fund,
                      res.frequency, c);
          CHECK(false);
        }
        CHECK(res.clarity > 0.8f);
      }
    }
    std::printf("  %d Hz: peor error %.3f cents\n", sr, worst);
  }
  // Con algo de inharmonicidad (cuerdas reales): ±3 cents
  {
    Tuner tuner;
    tuner.prepare(48000);
    for (double f : {82.41, 110.0, 146.83, 196.0, 246.94, 329.63}) {
      const std::vector<float> x = stringTone(f, 48000, tuner.frames() + 4800, 0.5, 6e-5, 7);
      const TunerResult res = tuner.analyze(x.data() + 4800);
      CHECK(res.frequency > 0 && std::fabs(cents(res.frequency, f)) < 3.0);
    }
  }
  // Ruido y silencio: sin nota
  {
    Tuner tuner;
    tuner.prepare(48000);
    std::vector<float> x(size_t(tuner.frames()), 0.0f);
    CHECK(tuner.analyze(x.data()).frequency == 0.0f);
    std::mt19937 rng(3);
    std::normal_distribution<float> g(0.0f, 0.1f);
    for (float& v : x) v = g(rng);
    const TunerResult res = tuner.analyze(x.data());
    CHECK(res.frequency == 0.0f);
    CHECK(res.levelDb > -30.0f);
    // Muy flojo (por debajo de −60 dBFS): ni se intenta
    const std::vector<float> soft = stringTone(110.0, 48000, tuner.frames(), 1.0);
    std::vector<float> quiet(soft.size());
    for (size_t i = 0; i < soft.size(); ++i) quiet[i] = soft[i] * 1e-4f;
    CHECK(tuner.analyze(quiet.data()).frequency == 0.0f);
  }
  // Coste: lo que tarda un análisis (se hace en el hilo de la interfaz)
  {
    Tuner tuner;
    tuner.prepare(48000);
    const std::vector<float> x = stringTone(82.41, 48000, tuner.frames(), 0.5);
    const auto t0 = std::chrono::steady_clock::now();
    float sink = 0.0f;
    for (int i = 0; i < 200; ++i) sink += tuner.analyze(x.data()).frequency;
    const double ms =
        std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count() /
        200;
    std::printf("  un análisis: %.2f ms (%d muestras, %.0f ms de audio)%s\n", ms, tuner.frames(),
                1000.0 * tuner.frames() / 48000, sink > 0 ? "" : " ?");
  }
  // Por el motor: la entrada llega a la toma y se lee sin bloquear
  {
    Rig r(kSr, 2000, 51);
    const double f = 196.0;
    r.player = [f](int64_t n) {
      return 0.2f * float(std::sin(6.283185307 * f * double(n) / kSr));
    };
    r.runFor(kSr / 2);
    Tuner tuner;
    tuner.prepare(kSr);
    std::vector<float> buf(size_t(tuner.frames()));
    CHECK(!r.core.tunerTap().latest(buf.data(), tuner.frames()));  // apagada: nada
    r.core.tunerTap().setEnabled(true);
    r.runFor(kSr / 4);
    CHECK(r.core.tunerTap().latest(buf.data(), tuner.frames()));
    const TunerResult res = tuner.analyze(buf.data());
    CHECK(res.frequency > 0 && std::fabs(cents(res.frequency, f)) < 0.5);
    CHECK(std::fabs(res.levelDb - float(20 * std::log10(0.2 / std::sqrt(2.0)))) < 0.5f);
    r.core.tunerTap().setEnabled(false);
    const int64_t w = r.core.tunerTap().written();
    r.runFor(kSr / 10);
    CHECK_EQ(r.core.tunerTap().written(), w);
  }
}

}  // namespace

void runLiveTests() {
  testReverseAndHalf();
  testQuantizedChanges();
  testOverdubWithEffects();
  testStopModes();
  testTrainer();
  testTuner();
}
