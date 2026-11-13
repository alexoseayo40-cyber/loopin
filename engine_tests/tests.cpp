// Loopin — tests del motor (PC)
// SPDX-License-Identifier: GPL-3.0-or-later
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <thread>
#include <vector>

#include "EngineCore.h"
#include "OnsetDetector.h"
#include "LatencyMeter.h"
#include "LoadMeter.h"
#include "Metronome.h"
#include "SpscQueue.h"
#include "Transport.h"
#include "test_util.h"

using namespace loopin;


static void testSamplesPerBeat() {
  std::printf("Muestras por tiempo\n");
  CHECK_EQ(Transport::computeSamplesPerBeat(48000, 120), 24000);
  CHECK_EQ(Transport::computeSamplesPerBeat(48000, 92), 31304);  // 31304,35
  CHECK_EQ(Transport::computeSamplesPerBeat(44100, 100), 26460);
  CHECK_EQ(Transport::computeSamplesPerBeat(48000, 10), 72000);   // se limita a 40
  CHECK_EQ(Transport::computeSamplesPerBeat(48000, 999), 12000);  // se limita a 240
}

// 5 minutos de transporte: cada tiempo empieza exactamente en k * muestras/tiempo
static void testTransportNoDrift() {
  std::printf("Transporte: 5 minutos sin deriva\n");
  Transport t;
  t.setSampleRate(48000);
  t.setBpm(92);
  t.setBeatsPerBar(4);
  t.play();
  const int64_t spb = t.samplesPerBeat();
  const int64_t total = 48000LL * 300;
  int64_t beats = 0;
  bool exact = true;
  for (int64_t i = 0; i < total; ++i) {
    const int32_t beatBefore = t.beat();
    const int32_t barBefore = t.bar();
    if (t.tick()) {
      if (i != beats * spb) exact = false;
      if (beatBefore != beats % 4 || barBefore != beats / 4) exact = false;
      ++beats;
    }
  }
  CHECK(exact);
  CHECK_EQ(beats, (total + spb - 1) / spb);
  CHECK_EQ(t.framePosition(), total);
}

static void testTempoChangeAtBeat() {
  std::printf("Cambio de tempo en el siguiente tiempo\n");
  Transport t;
  t.setSampleRate(48000);
  t.setBpm(120);  // 24000
  t.play();
  for (int i = 0; i < 1000; ++i) t.tick();  // a mitad del primer tiempo
  t.setBpm(60);   // 48000
  std::vector<int64_t> starts;
  for (int64_t i = 1000; i < 200000; ++i)
    if (t.tick()) starts.push_back(i);
  CHECK(starts.size() >= 2);
  CHECK_EQ(starts[0], 24000);          // el tiempo en curso termina con el tempo viejo
  CHECK_EQ(starts[1], 24000 + 48000);  // y el siguiente ya va a 60 BPM
}

static void testMeterChangeAtBar() {
  std::printf("Cambio de compás en el siguiente compás\n");
  Transport t;
  t.setSampleRate(48000);
  t.setBpm(120);
  t.setBeatsPerBar(4);
  t.play();
  for (int i = 0; i < 24000 * 2 + 10; ++i) t.tick();  // tiempo 3 del compás 0
  t.setBeatsPerBar(3);
  int64_t i = 24000 * 2 + 10;
  for (; i < 24000 * 4; ++i) t.tick();
  CHECK_EQ(t.bar(), 1);  // el compás 0 tuvo sus 4 tiempos
  CHECK_EQ(t.beat(), 0);
  for (; i < 24000 * 7; ++i) t.tick();
  CHECK_EQ(t.bar(), 2);  // el compás 1 ya es de 3 tiempos
  CHECK_EQ(t.beatsPerBar(), 3);
}

static void testAccents() {
  std::printf("Acentos\n");
  CHECK(Metronome::accentFor(0, 0) == Metronome::Accent::kStrong);
  CHECK(Metronome::accentFor(2, 0) == Metronome::Accent::kWeak);
  CHECK(Metronome::accentFor(3, 1u << 3) == Metronome::Accent::kMedium);  // 6/8
  CHECK(Metronome::accentFor(3, 0) == Metronome::Accent::kWeak);
  // 7/8 en 2+2+3
  const uint32_t m78 = (1u << 2) | (1u << 4);
  CHECK(Metronome::accentFor(2, m78) == Metronome::Accent::kMedium);
  CHECK(Metronome::accentFor(4, m78) == Metronome::Accent::kMedium);
  CHECK(Metronome::accentFor(5, m78) == Metronome::Accent::kWeak);
  CHECK(Metronome::accentFor(0, m78) == Metronome::Accent::kStrong);

  // El compás nuevo (con sus acentos) entra en el siguiente compás
  Transport t;
  t.setSampleRate(48000);
  t.setBpm(120);
  t.setMeter(4, 0);
  t.play();
  for (int i = 0; i < 24000; ++i) t.tick();
  t.setMeter(7, m78);
  CHECK_EQ(t.accentMask(), 0u);
  CHECK_EQ(t.beatsPerBar(), 4);
  for (int i = 24000; i < 24000 * 4; ++i) t.tick();
  CHECK_EQ(t.beatsPerBar(), 7);
  CHECK_EQ(t.accentMask(), m78);
}

static void testPlayFrom() {
  std::printf("Arrancar el tempo desde una posición\n");
  Transport t;
  t.setSampleRate(48000);
  t.setBpm(120);  // 24000 por tiempo
  t.setMeter(3, 0);
  t.playFrom(24000 * 4 + 100);  // compás 1, tiempo 1, 100 muestras dentro
  CHECK_EQ(t.bar(), 1);
  CHECK_EQ(t.beat(), 1);
  CHECK_EQ(t.framesSinceBeat(), 100);
  CHECK_EQ(t.framesSinceBar(), 24000 + 100);
  CHECK_EQ(t.framePosition(), 24000 * 4 + 100);
  // El siguiente tiempo empieza justo donde toca
  int64_t i = 0;
  while (!t.tick()) ++i;
  CHECK_EQ(i, 24000 - 100);
  CHECK_EQ(t.beat(), 2);
  t.playFrom(0);
  CHECK_EQ(t.bar(), 0);
  CHECK(t.tick());  // la primera muestra es un tiempo
}

static void testOnsetDetector() {
  std::printf("Detector de ataques\n");
  const int32_t sr = 48000;
  OnsetDetector d;
  d.prepare(sr);
  d.reset(0.02f, sr / 4);
  std::mt19937 rng(5);
  std::normal_distribution<float> noise(0.0f, 0.003f);
  // Ruido de fondo: nada
  int hits = 0;
  for (int i = 0; i < sr; ++i) hits += d.push(noise(rng));
  CHECK_EQ(hits, 0);
  // Una nota (seno que decae) cada 600 ms, con ruido: un ataque por nota,
  // justo al empezar
  const double kPi = 3.14159265358979;
  std::vector<int64_t> found;
  for (int64_t i = 0; i < sr * 3; ++i) {
    const int64_t k = i % (sr * 6 / 10);
    const float note = float(0.3 * std::exp(-double(k) / (0.15 * sr)) * std::sin(2 * kPi * 196.0 * k / sr));
    if (d.push(note + noise(rng))) found.push_back(i);
  }
  CHECK_EQ((int)found.size(), 5);
  for (size_t n = 0; n < found.size(); ++n) {
    const int64_t want = int64_t(n) * (sr * 6 / 10);
    CHECK(found[n] >= want && found[n] < want + sr / 1000);  // < 1 ms tarde
  }
}

// El núcleo completo durante 5 minutos con bloques de tamaño variable:
// cada clic empieza en su muestra exacta y la salida nunca satura ni da NaN.
static void testEngineClickTiming() {
  std::printf("Motor: clic con precisión de muestra durante 5 minutos\n");
  for (int32_t sr : {48000, 44100}) {
    EngineCore core;
    core.prepare(sr);
    core.post({Command::Type::kSetBpm, 137});
    core.post({Command::Type::kSetBeatsPerBar, 6});
    core.post({Command::Type::kPlay, 0});

    std::mt19937 rng(42);
    const int64_t total = int64_t(sr) * 300;
    std::vector<float> in(EngineCore::kMaxBlockFrames * 1, 0.0f);
    std::vector<float> out(EngineCore::kMaxBlockFrames * 2, 0.0f);
    std::vector<int64_t> onsets;
    int64_t pos = 0;
    float prev = 0.0f;
    bool sane = true, stereoEqual = true;
    while (pos < total) {
      const int32_t n = randomBlock(rng);
      core.process(in.data(), n, 1, out.data(), n, 2);
      for (int32_t i = 0; i < n; ++i) {
        const float s = out[i * 2];
        if (!std::isfinite(s) || std::fabs(s) > 1.0f) sane = false;
        if (out[i * 2 + 1] != s) stereoEqual = false;
        if (prev == 0.0f && s != 0.0f) onsets.push_back(pos + i);
        prev = s;
      }
      pos += n;
    }
    const int64_t spb = Transport::computeSamplesPerBeat(sr, 137);
    bool exact = true;
    for (size_t k = 0; k < onsets.size(); ++k) {
      // la envolvente vale 0 en la muestra 0 del clic: el primer valor no nulo es la 1
      if (onsets[k] != int64_t(k) * spb + 1) {
        exact = false;
        std::printf("  clic %zu en %lld, esperado %lld\n", k, (long long)onsets[k],
                    (long long)(int64_t(k) * spb + 1));
        break;
      }
    }
    CHECK(sane);
    CHECK(stereoEqual);
    CHECK(exact);
    CHECK_EQ((long long)onsets.size(), (pos - 2) / spb + 1);  // clics con k*spb+1 < pos
    const CoreStatus st = core.status();
    CHECK_EQ(st.framePosition, pos);
    CHECK_EQ(st.beatsPerBar, 6);
    std::printf("  %d Hz: %zu clics, todos en su muestra\n", sr, onsets.size());
  }
}

static void testMonitorAndMute() {
  std::printf("Monitor y silencio del clic\n");
  EngineCore core;
  core.prepare(48000);
  core.post({Command::Type::kSetClickEnabled, 0});
  core.post({Command::Type::kSetMonitorEnabled, 1});
  core.post({Command::Type::kSetMonitorVolume, 0.5});
  core.post({Command::Type::kPlay, 0});
  std::vector<float> in(256), out(512);
  for (int i = 0; i < 256; ++i) in[i] = 0.4f * std::sin(i * 0.1f);
  core.process(in.data(), 256, 1, out.data(), 256, 2);
  bool ok = true;
  for (int i = 0; i < 256; ++i)
    if (std::fabs(out[i * 2] - in[i] * 0.5f) > 1e-6f) ok = false;
  CHECK(ok);
  CHECK(core.status().inputPeak > 0.39f);
}

static void testInputGain() {
  std::printf("Ganancia de entrada\n");
  EngineCore core;
  core.prepare(48000);
  core.post({Command::Type::kSetClickEnabled, 0});
  core.post({Command::Type::kSetMonitorEnabled, 1});
  core.post({Command::Type::kSetMonitorVolume, 1.0});
  core.post({Command::Type::kSetInputGain, 4.0});  // +12 dB
  std::vector<float> in(128, 0.1f), out(256);
  core.process(in.data(), 128, 1, out.data(), 128, 2);
  CHECK(std::fabs(out[0] - 0.4f) < 1e-6f);
  CHECK(std::fabs(core.status().inputPeak - 0.4f) < 1e-6f);
  // y nunca satura la salida
  core.post({Command::Type::kSetInputGain, 32.0});
  core.process(in.data(), 128, 1, out.data(), 128, 2);
  CHECK(out[0] <= 1.0f);
}

// Simula el bucle altavoz → micrófono con un retardo conocido.
static int32_t runLatency(int32_t sr, int32_t delay, float gain, float noise, bool connected,
                          LatencyMeter::State* finalState) {
  EngineCore core;
  core.prepare(sr);
  core.post({Command::Type::kPlay, 0});  // el clic debe quedar en silencio al medir
  core.post({Command::Type::kMeasureLatency, 0});
  std::mt19937 rng(7);
  std::normal_distribution<float> nd(0.0f, noise);
    std::vector<float> in(EngineCore::kMaxBlockFrames), out(EngineCore::kMaxBlockFrames * 2);
  std::vector<float> history;  // toda la salida
  int64_t pos = 0;
  CoreStatus st{};
  for (int iter = 0; iter < 100000; ++iter) {
    const int32_t n = randomBlock(rng);
    for (int32_t i = 0; i < n; ++i) {
      const int64_t src = pos + i - delay;
      float s = (connected && src >= 0 && src < (int64_t)history.size()) ? history[src] * gain : 0.0f;
      in[i] = s + (noise > 0 ? nd(rng) : 0.0f);
    }
    core.process(in.data(), n, 1, out.data(), n, 2);
    for (int32_t i = 0; i < n; ++i) history.push_back(out[i * 2]);
    pos += n;
    st = core.status();
    if (st.latencyState == 2 || st.latencyState == 3) break;
  }
  *finalState = static_cast<LatencyMeter::State>(st.latencyState);
  return st.latencyFrames;
}

static void testLatencyMeter() {
  std::printf("Medidor de latencia (bucle simulado)\n");
  struct Case { int32_t sr, delay; float gain, noise; };
  const Case cases[] = {
      {48000, 1234, 0.3f, 0.002f},   // ~26 ms, micrófono con algo de ruido
      {48000, 480, 1.0f, 0.0f},      // 10 ms, cable de salida a entrada
      {48000, 9600, 0.1f, 0.005f},   // 200 ms, señal débil
      {44100, 3001, 0.5f, 0.001f},
  };
  for (const Case& c : cases) {
    LatencyMeter::State s;
    const int32_t r = runLatency(c.sr, c.delay, c.gain, c.noise, true, &s);
    CHECK(s == LatencyMeter::State::kDone);
    // La detección por umbral llega unas pocas muestras tarde
    CHECK(r >= c.delay && r <= c.delay + 8);
    std::printf("  retardo real %d → medido %d muestras (%.2f ms)\n", c.delay, r,
                1000.0 * r / c.sr);
  }
  LatencyMeter::State s;
  runLatency(48000, 1000, 0.3f, 0.002f, false, &s);  // sin bucle: debe fallar
  CHECK(s == LatencyMeter::State::kFailed);
  std::printf("  sin señal de vuelta → falla como debe\n");
}

static void testSpscQueue() {
  std::printf("Cola SPSC entre dos hilos\n");
  SpscQueue<int, 64> q;
  const int N = 1000000;
  long long sum = 0;
  std::thread consumer([&] {
    int got = 0, v;
    while (got < N)
      if (q.pop(v)) { sum += v; ++got; }
  });
  for (int i = 1; i <= N; ++i)
    while (!q.push(i)) {}
  consumer.join();
  CHECK_EQ(sum, (long long)N * (N + 1) / 2);
}

static void testLoadMeter() {
  std::printf("Carga del callback: media y pico de cada segundo\n");
  LoadMeter m;
  m.prepare(48000);
  // 256 muestras a 48 kHz = 5,333 ms disponibles
  const int64_t avail = 5333333;
  // Antes de completar un segundo no se publica nada
  m.add(avail / 10, 256);
  CHECK(m.average() == 0.0f);
  // 187 bloques más (188 × 256 ≥ 48000): 10 % y uno al 50 %
  for (int i = 0; i < 186; ++i) m.add(avail / 10, 256);
  m.add(avail / 2, 256);
  CHECK(std::fabs(m.peak() - 0.5f) < 0.001f);
  CHECK(std::fabs(m.average() - (187 * 0.1f + 0.5f) / 188) < 0.001f);
  CHECK(std::fabs(m.maxPeak() - 0.5f) < 0.001f);
  // El segundo siguiente, más tranquilo: el pico baja, el máximo se queda
  for (int i = 0; i < 188; ++i) m.add(avail / 20, 256);
  CHECK(std::fabs(m.peak() - 0.05f) < 0.001f);
  CHECK(std::fabs(m.average() - 0.05f) < 0.001f);
  CHECK(std::fabs(m.maxPeak() - 0.5f) < 0.001f);
  std::printf("  media %.1f %% · pico %.1f %% · máximo %.1f %%\n", 100 * m.average(),
              100 * m.peak(), 100 * m.maxPeak());
}

int main() {
  std::printf("=== Etapa 1: transporte, metrónomo y latencia ===\n");
  testSamplesPerBeat();
  testTransportNoDrift();
  testTempoChangeAtBeat();
  testMeterChangeAtBar();
  testAccents();
  testPlayFrom();
  testOnsetDetector();
  testEngineClickTiming();
  testMonitorAndMute();
  testInputGain();
  testLatencyMeter();
  testSpscQueue();
  testLoadMeter();
  std::printf("\n=== Looper ===\n");
  runLooperTests();
  std::printf("\n=== Batería ===\n");
  runDrumTests();
  std::printf("\n=== Audio importado ===\n");
  runSongTests();
  std::printf("\n=== Directo y práctica ===\n");
  runLiveTests();
  if (gFailures == 0) {
    std::printf("\nTodo OK\n");
    return 0;
  }
  std::printf("\n%d fallos\n", gFailures);
  return 1;
}
