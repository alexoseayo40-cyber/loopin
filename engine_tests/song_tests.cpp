// Loopin — tests del audio importado (PC)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Dos partes:
// - Preparar: se escribe un WAV con golpes en tiempos conocidos (una canción
//   de mentira a un tempo con decimales) y se comprueba que, estirado al tempo
//   del transporte, cada golpe cae donde debe: el 1 en un inicio de compás, y
//   sin deriva hasta el final.
// - Sonar: con clips hechos a mano se comprueba muestra a muestra qué suena
//   con el transporte (entrar en un 1, volver a empezar, cambios de tempo, de
//   canción, cuenta de entrada…) y en la vista previa (con su clic).
#include <chrono>
#include <cmath>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>

#include "Backing.h"
#include "Clip.h"
#include "EngineCore.h"
#include "SongJobs.h"
#include "rig.h"
#include "test_util.h"

using namespace loopin;
using namespace loopin_test;

namespace {

constexpr double kPi = 3.14159265358979323846;

// ---------------------------------------------------------------- archivos

void put16(std::FILE* f, uint32_t v) {
  const unsigned char b[2] = {uint8_t(v), uint8_t(v >> 8)};
  std::fwrite(b, 1, 2, f);
}
void put32(std::FILE* f, uint32_t v) {
  const unsigned char b[4] = {uint8_t(v), uint8_t(v >> 8), uint8_t(v >> 16), uint8_t(v >> 24)};
  std::fwrite(b, 1, 4, f);
}

// WAV PCM de 16 bits; data va por canales entrelazados
bool writeWav(const std::string& path, int32_t rate, int32_t channels,
              const std::vector<float>& data) {
  std::FILE* f = std::fopen(path.c_str(), "wb");
  if (f == nullptr) return false;
  const uint32_t bytes = uint32_t(data.size() * 2);
  std::fwrite("RIFF", 1, 4, f);
  put32(f, 36 + bytes);
  std::fwrite("WAVEfmt ", 1, 8, f);
  put32(f, 16);
  put16(f, 1);
  put16(f, uint32_t(channels));
  put32(f, uint32_t(rate));
  put32(f, uint32_t(rate * channels * 2));
  put16(f, uint32_t(channels * 2));
  put16(f, 16);
  std::fwrite("data", 1, 4, f);
  put32(f, bytes);
  for (float s : data) {
    const int v = int(std::lrint(std::clamp(s, -1.0f, 1.0f) * 32767.0f));
    put16(f, uint32_t(uint16_t(int16_t(v))));
  }
  std::fclose(f);
  return true;
}

std::string tmpPath(const char* name) { return std::string("/tmp/loopin_test_") + name; }

// Una canción de mentira: un golpe seco (2 kHz que se apaga en ~2 ms) en cada
// tiempo, desde un tiempo antes del 1 (la anacrusa) si cabe. Devuelve dónde
// empieza cada golpe en el archivo (segundos), con el 1 el primero de
// firstBeats.
struct FakeSong {
  std::vector<double> beats;  // segundos de cada golpe
  int32_t pickups = 0;        // golpes antes del 1
};

FakeSong writeSong(const std::string& path, int32_t rate, int32_t channels, double bpm,
                   double markSec, int32_t beats, double tailSec = 1.0) {
  FakeSong song;
  const double beat = 60.0 / bpm;
  for (double t = markSec - beat; t >= 0.0; t -= beat) {
    song.beats.insert(song.beats.begin(), t);
    ++song.pickups;
  }
  for (int32_t k = 0; k < beats; ++k) song.beats.push_back(markSec + k * beat);
  const size_t frames = size_t((song.beats.back() + tailSec) * rate);
  std::vector<float> data(frames * size_t(channels), 0.0f);
  const int32_t len = rate / 100;  // 10 ms
  for (double t : song.beats) {
    const int64_t at = int64_t(std::llround(t * rate));
    for (int32_t i = 0; i < len && at + i < int64_t(frames); ++i) {
      const double x = double(i) / rate;
      const float v = float(0.8 * std::sin(2 * kPi * 2000 * x) * std::exp(-x / 0.002));
      for (int32_t c = 0; c < channels; ++c) data[size_t(at + i) * size_t(channels) + size_t(c)] = v;
    }
  }
  writeWav(path, rate, channels, data);
  return song;
}

// Dónde empieza cada golpe: lo primero que pasa de thr tras 20 ms sin pasar
std::vector<int64_t> onsets(const std::vector<int16_t>& pcm, int32_t rate, float thr = 0.1f) {
  std::vector<int64_t> v;
  const int64_t gap = rate / 50;
  int64_t last = -gap - 1;
  for (size_t i = 0; i < pcm.size(); ++i) {
    const float a = std::fabs(float(pcm[i]) / 32768.0f);
    if (a < thr) continue;
    if (int64_t(i) - last > gap) v.push_back(int64_t(i));
    last = int64_t(i);
  }
  return v;
}

// Dónde suena cada golpe esperado: el pico más alto a menos de 50 ms (el
// estirado puede «ensuciar» el principio de un golpe seco, pero su energía
// queda en su sitio). Devuelve la mayor diferencia y la del primero y el
// último (para ver si hay deriva). peakAt: dónde tiene el pico un golpe
// desde que empieza.
struct Match {
  int64_t worst = 0, first = 0, last = 0;  // first/last: media de los 20 primeros/últimos
};

Match measureBeats(const std::vector<int16_t>& pcm, const std::vector<int64_t>& want,
                   int32_t rate, int64_t peakAt) {
  Match m;
  const int64_t radius = rate / 20;
  for (size_t i = 0; i < want.size(); ++i) {
    const int64_t a = std::max<int64_t>(0, want[i] - radius);
    const int64_t z = std::min<int64_t>(int64_t(pcm.size()), want[i] + radius);
    int64_t best = a;
    for (int64_t j = a; j < z; ++j)
      if (std::abs(int(pcm[size_t(j)])) > std::abs(int(pcm[size_t(best)]))) best = j;
    const int64_t d = best - peakAt - want[i];
    if (i < 20) m.first += d;
    if (i + 20 >= want.size()) m.last += d;
    if (std::llabs(d) > std::llabs(m.worst)) m.worst = d;
  }
  const int64_t n = int64_t(std::min<size_t>(20, want.size()));
  if (n > 0) {
    m.first /= n;
    m.last /= n;
  }
  return m;
}

// ---------------------------------------------------------------- preparar

// Una canción a 97,3 BPM con anacrusa, a 44,1 kHz y en estéreo, estirada a
// 90 BPM a 48 kHz (más lenta). Cada golpe, a menos de 2 ms de su sitio.
void testStretchAlignment() {
  std::printf("Preparar: estirada al tempo, el 1 en un compás y sin deriva\n");
  // tolerance: muestras (a 48 kHz) que puede moverse un golpe. Al estirar
  // mucho, el estirado (WSOLA) mueve un poco los golpes secos; estirando poco
  // o solo cambiando la velocidad, casi nada.
  struct Case {
    double songBpm, targetBpm, mark;
    int32_t srcRate, channels, beatsPerBar;
    int64_t tolerance;
    const char* name;
  };
  const Case cases[] = {
      {97.3, 90.0, 0.73, 44100, 2, 4, 240, "97,3 → 90 BPM, 44,1 kHz estéreo, 4/4"},
      {97.3, 112.0, 0.73, 44100, 2, 4, 240, "97,3 → 112 BPM (más rápida)"},
      {120.0, 120.2, 0.5, 48000, 1, 4, 48, "120 → 120,2 BPM (solo velocidad)"},
      {84.0, 84.0, 1.2, 48000, 1, 3, 48, "84 → 84 BPM, 3/4 (solo velocidad)"},
      {140.0, 72.0, 2.0, 22050, 1, 6, 960, "140 → 72 BPM (casi la mitad), 22,05 kHz, 6/8"},
  };
  for (const Case& c : cases) {
    const std::string path = tmpPath("stretch.wav");
    const FakeSong song = writeSong(path, c.srcRate, c.channels, c.songBpm, c.mark, 240);
    PrepareParams p;
    p.path = path;
    p.songBpm = c.songBpm;
    p.markSeconds = c.mark;
    p.samplesPerBeat = Transport::computeSamplesPerBeat(48000, c.targetBpm);
    p.beatsPerBar = c.beatsPerBar;
    p.rate = 48000;
    p.id = 3;
    Clip* clip = nullptr;
    const int32_t err = SongJobs::buildBacking(p, &clip, nullptr);
    CHECK_EQ(err, 0);
    if (clip == nullptr) continue;
    const int64_t bar = int64_t(p.samplesPerBeat) * p.beatsPerBar;
    CHECK_EQ(clip->barFrames, bar);
    CHECK_EQ(clip->frames(), clip->bars * bar);
    CHECK_EQ(clip->samplesPerBeat, p.samplesPerBeat);
    CHECK_EQ(clip->id, 3);
    // El 1 cae en un inicio de compás, con la anacrusa delante
    const int64_t padBars = song.pickups > 0 ? 1 : 0;
    std::vector<int64_t> want;
    for (size_t k = 0; k < song.beats.size(); ++k) {
      want.push_back(padBars * bar + (int64_t(k) - song.pickups) * p.samplesPerBeat);
    }
    const Match m = measureBeats(clip->pcm, want, 48000, 6);
    CHECK(std::llabs(m.worst) <= c.tolerance);
    // Sin deriva: los 20 últimos caen igual que los 20 primeros (± 1 ms)
    CHECK(std::llabs(m.last - m.first) <= 48);
    std::printf("  %s: %zu golpes, %lld compases, error máx. %.2f ms (deriva %.2f ms)\n",
                c.name, want.size(), (long long)clip->bars, m.worst / 48.0,
                (m.last - m.first) / 48.0);
    delete clip;
  }
}

// Si antes del 1 casi no hay nada (menos de 1/8 de tiempo), se quita en vez
// de añadir un compás casi vacío.
void testStretchCutsTinyLead() {
  std::printf("Preparar: lo poco que hay antes del 1 se quita\n");
  const std::string path = tmpPath("lead.wav");
  const FakeSong song = writeSong(path, 48000, 1, 120.0, 0.01, 16);
  PrepareParams p;
  p.path = path;
  p.songBpm = 120.0;
  p.markSeconds = 0.01;
  p.samplesPerBeat = 24000;
  p.beatsPerBar = 4;
  p.rate = 48000;
  Clip* clip = nullptr;
  CHECK_EQ(SongJobs::buildBacking(p, &clip, nullptr), 0);
  if (clip == nullptr) return;
  CHECK_EQ(song.pickups, 0);
  const std::vector<int64_t> got = onsets(clip->pcm, 48000);
  CHECK(!got.empty() && got[0] <= 2);  // el 1, en la primera muestra
  CHECK_EQ(clip->bars, 5);  // 8,99 s en compases de 2 s
  delete clip;
}

void testStretchErrors() {
  std::printf("Preparar: errores (archivo, tempo, silencio, demasiado largo)\n");
  const std::string path = tmpPath("err.wav");
  writeSong(path, 48000, 1, 100.0, 0.5, 8);
  PrepareParams p;
  p.path = path;
  p.songBpm = 100.0;
  p.samplesPerBeat = 28800;
  p.beatsPerBar = 4;
  p.rate = 48000;
  Clip* clip = nullptr;
  p.path = tmpPath("no_existe.wav");
  CHECK_EQ(SongJobs::buildBacking(p, &clip, nullptr), SongJobs::kErrOpen);
  // No es audio
  {
    std::FILE* f = std::fopen(tmpPath("texto.mp3").c_str(), "wb");
    std::fputs("esto no es una canción, aunque se llame .mp3", f);
    std::fclose(f);
  }
  p.path = tmpPath("texto.mp3");
  CHECK_EQ(SongJobs::buildBacking(p, &clip, nullptr), SongJobs::kErrOpen);
  p.path = path;
  // A menos de la mitad o más del doble de su tempo
  p.samplesPerBeat = Transport::computeSamplesPerBeat(48000, 45.0);
  CHECK_EQ(SongJobs::buildBacking(p, &clip, nullptr), SongJobs::kErrTempo);
  p.samplesPerBeat = Transport::computeSamplesPerBeat(48000, 210.0);
  CHECK_EQ(SongJobs::buildBacking(p, &clip, nullptr), SongJobs::kErrTempo);
  p.samplesPerBeat = 28800;
  p.songBpm = 0;
  CHECK_EQ(SongJobs::buildBacking(p, &clip, nullptr), SongJobs::kErrTempo);
  CHECK(clip == nullptr);
  // Todo silencio: no vale para prepararla
  writeWav(tmpPath("silencio.wav"), 48000, 1, std::vector<float>(48000, 0.0f));
  PreviewInfo info;
  CHECK_EQ(SongJobs::buildPreview(tmpPath("silencio.wav"), 48000, 1, &clip, &info, nullptr),
           SongJobs::kErrEmpty);
  // Más de 10 minutos a ese tempo: 6 min a la mitad de velocidad son 12
  {
    std::vector<float> longSong(size_t(48000) * 360, 0.0f);
    longSong[1000] = 0.5f;
    writeWav(tmpPath("larga.wav"), 48000, 1, longSong);
  }
  p.path = tmpPath("larga.wav");
  p.songBpm = 100.0;
  p.samplesPerBeat = Transport::computeSamplesPerBeat(48000, 50.0);
  CHECK_EQ(SongJobs::buildBacking(p, &clip, nullptr), SongJobs::kErrTooLong);
  p.samplesPerBeat = 28800;  // a su tempo sí cabe
  CHECK_EQ(SongJobs::buildBacking(p, &clip, nullptr), 0);
  delete clip;
}

// La vista previa: a la frecuencia del motor, sin estirar; sugiere el tempo
// y el primer golpe.
void testPreview() {
  std::printf("Abrir: vista previa, tempo sugerido, primer golpe, picos\n");
  const std::string path = tmpPath("preview.wav");
  const FakeSong song = writeSong(path, 44100, 2, 97.3, 0.73, 120);
  Clip* clip = nullptr;
  PreviewInfo info;
  CHECK_EQ(SongJobs::buildPreview(path, 48000, 5, &clip, &info, nullptr), 0);
  if (clip == nullptr) return;
  const double secs = song.beats.back() + 1.0;
  CHECK(std::llabs(clip->frames() - int64_t(secs * 48000)) < 480);
  CHECK_EQ(info.frames, clip->frames());
  CHECK_EQ(clip->id, 5);
  CHECK_EQ(clip->bars, 0);  // la vista previa no lleva rejilla
  const int64_t first = std::llround(song.beats[0] * 48000);
  CHECK(std::llabs(info.firstAttack - first) <= 48);  // ~0,65 ms antes: el filtro de SoundTouch
  std::printf("  tempo sugerido %.2f BPM (de verdad 97,30) · primer golpe %.2f ms de su sitio\n",
              info.bpmGuess, (info.firstAttack - first) / 48.0);
  CHECK(std::fabs(info.bpmGuess - 97.3) < 2.0);
  // Cada golpe, a menos de 1 ms (solo se cambia la frecuencia)
  std::vector<int64_t> want;
  for (double t : song.beats) want.push_back(std::llround(t * 48000));
  CHECK(std::llabs(measureBeats(clip->pcm, want, 48000, 6).worst) <= 48);
  CHECK_EQ(onsets(clip->pcm, 48000).size(), want.size());
  // El ataque más cercano a un sitio un poco equivocado es el golpe
  const int64_t g = want[10];
  const int64_t a1 = SongJobs::attackNear(*clip, g + 1500, 2400);
  const int64_t a2 = SongJobs::attackNear(*clip, g - 2000, 2400);
  if (std::llabs(a1 - g) > 48 || std::llabs(a2 - g) > 48)
    std::printf("  ataque esperado %lld: %lld y %lld\n", (long long)g, (long long)a1, (long long)a2);
  CHECK(std::llabs(a1 - g) <= 48);
  CHECK(std::llabs(a2 - g) <= 48);
  // Picos: el golpe se ve y el silencio no
  float pk[4] = {};
  CHECK_EQ(SongJobs::peaksOf(*clip, a1 - 4800, a1 + 4800, 4, pk), 4);
  if (!(pk[0] < 0.01f && pk[1] < 0.2f && pk[2] > 0.5f && pk[3] < 0.05f))
    std::printf("  picos %.3f %.3f %.3f %.3f\n", pk[0], pk[1], pk[2], pk[3]);
  // (lo poco del segundo trozo es el filtro de SoundTouch, justo antes del golpe)
  CHECK(pk[0] < 0.01f && pk[1] < 0.2f && pk[2] > 0.5f && pk[3] < 0.05f);
  delete clip;
}

// ---------------------------------------------------------------- sonar

// Un clip hecho a mano: cada muestra distinta (nunca 0), para comprobar
// exactamente qué posición suena.
Clip* handClip(int32_t id, int32_t spb, int32_t bpb, int64_t bars, int seed) {
  Clip* c = new Clip();
  c->rate = 48000;
  c->id = id;
  c->samplesPerBeat = spb;
  c->beatsPerBar = bpb;
  c->barFrames = int64_t(spb) * bpb;
  c->bars = bars;
  c->pcm.resize(size_t(c->barFrames * bars));
  for (size_t i = 0; i < c->pcm.size(); ++i)
    c->pcm[i] = int16_t(100 + (int64_t(i) * 7 + seed * 1000) % 20000);
  return c;
}

// Lo que debe sonar en la muestra i de una entrada (fundido de 1 ms)
float entering(const Clip& c, int64_t pos, int64_t i) {
  const float env = std::min(1.0f, float(i + 1) / 48.0f);
  return c.at(pos) * env;
}

// Compara la salida desde la muestra from con el clip desde pos (en una
// entrada), durante n muestras. Devuelve las que no coinciden.
int64_t mismatches(const Rig& r, int64_t from, const Clip& c, int64_t pos, int64_t n,
                   bool entry = true) {
  int64_t bad = 0;
  for (int64_t i = 0; i < n; ++i) {
    const int64_t p = (pos + i) % c.frames();
    const float want = entry ? entering(c, p, i) : c.at(p);
    if (std::fabs(r.hist[size_t(from + i)] - want) > 1e-5f) ++bad;
  }
  return bad;
}

bool silent(const Rig& r, int64_t from, int64_t to) {
  for (int64_t i = from; i < to; ++i)
    if (r.hist[size_t(i)] != 0.0f) return false;
  return true;
}

void offerSong(Rig& r, Clip* c) { r.core.backing().songSlot().offer(c, r.core.clipBin()); }

// Sin clic (solo suena la canción), a 90 BPM: 32 000 muestras por tiempo
struct SongRig : Rig {
  SongRig() : Rig(48000, 0) {
    post(T::kSetClickMode, 0);
    post(T::kSetBpm, 90.0);
    post(T::kSetBackingVolume, 1.0);
  }
};

constexpr int32_t kSpb90 = 32000;
constexpr int64_t kBar90 = 4 * kSpb90;

void testBackingPlays() {
  std::printf("Sonar: entra en el 1, cada muestra en su sitio, vuelve a empezar\n");
  SongRig r;
  Clip* c = handClip(7, kSpb90, 4, 8, 1);
  offerSong(r, c);
  r.post(T::kSetBackingEnabled, 1);
  r.runFor(1000);
  CHECK(silent(r, 0, 1000));  // con el transporte parado no suena
  const int64_t P = r.outPos;
  r.post(T::kPlay);
  r.runFor(9 * kBar90 + 5000);
  CHECK_EQ(mismatches(r, P, *c, 0, 8 * kBar90), 0);
  // Al acabar los 8 compases vuelve a empezar, sin fundido
  CHECK_EQ(mismatches(r, P + 8 * kBar90, *c, 0, 5000, false), 0);
  const CoreStatus s = r.core.status();
  CHECK_EQ(s.backingId, 7);
  CHECK_EQ(s.backingPlaying, 1);
  CHECK_EQ(s.backingSpb, kSpb90);
  CHECK_EQ(s.backingLength, 8 * kBar90);

  // Parar y arrancar: desde el principio
  r.post(T::kPause);
  r.runFor(2000);
  CHECK(silent(r, r.outPos - 1000, r.outPos));
  const int64_t P2 = r.outPos;
  r.post(T::kPlay);
  r.runFor(kBar90);
  CHECK_EQ(mismatches(r, P2, *c, 0, kBar90), 0);

  // Apagarla: se calla (en 5 ms) y no para nada
  r.post(T::kSetBackingEnabled, 0);
  r.runFor(kSpb90 + 500);
  CHECK(silent(r, r.outPos - 200, r.outPos));
  CHECK(r.core.status().playing);
}

void testBackingTempoChange() {
  std::printf("Sonar: cambio de tempo → se calla y vuelve por donde iría\n");
  SongRig r;
  Clip* c = handClip(7, kSpb90, 4, 8, 1);
  offerSong(r, c);
  r.post(T::kSetBackingEnabled, 1);
  const int64_t P = r.outPos;
  r.post(T::kPlay);
  // A mitad del compás 9 se pide 100 BPM: se aplica en el siguiente tiempo
  r.runTo(P + 9 * kBar90 + 1000);
  r.post(T::kSetBpm, 100.0);
  const int64_t change = P + 9 * kBar90 + kSpb90;
  r.runTo(change + 3000);
  CHECK(silent(r, change + 240, change + 3000));
  // Llega la misma canción estirada a 100 BPM: entra en el siguiente 1, en
  // el compás que tocaría (el 10, que es el 2 de 8)
  Clip* c2 = handClip(7, 28800, 4, 8, 2);
  offerSong(r, c2);
  const int64_t bar10 = P + 9 * kBar90 + kSpb90 + 3 * 28800;
  r.runTo(bar10 + 20000);
  CHECK(silent(r, change + 3000, bar10));
  CHECK_EQ(mismatches(r, bar10, *c2, 2 * 4 * 28800, 20000), 0);

  // Otra canción (otro id): empieza desde el principio en el siguiente 1
  Clip* c3 = handClip(9, 28800, 4, 4, 3);
  r.runTo(bar10 + 4 * 28800 + 5000);
  offerSong(r, c3);
  const int64_t bar12 = bar10 + 2 * 4 * 28800;
  r.runTo(bar12 + 10000);
  // La anterior se apaga en 5 ms en vez de cortarse
  CHECK(r.hist[size_t(bar10 + 4 * 28800 + 5000 + 100)] != 0.0f);
  CHECK(silent(r, bar10 + 4 * 28800 + 5000 + 600, bar12));
  CHECK_EQ(mismatches(r, bar12, *c3, 0, 10000), 0);

  // Otro compás (3/4): ya no cuadra, se calla
  r.post(T::kSetMeter, 3);
  const int64_t bar13 = bar12 + 4 * 28800;
  r.runTo(bar13 + 3000);
  CHECK(silent(r, bar13 + 240, bar13 + 3000));
  CHECK_EQ(r.core.status().backingPlaying, 0);
}

void testBackingCountIn() {
  std::printf("Sonar: con cuenta de entrada entra con la grabación\n");
  SongRig r;
  Clip* c = handClip(4, kSpb90, 4, 8, 1);
  offerSong(r, c);
  r.post(T::kSetBackingEnabled, 1);
  r.runFor(500);
  const int64_t P = r.outPos;
  r.post(T::kLoopPress);  // cuenta 1 compás y graba 4
  r.runTo(P + 3 * kBar90);
  CHECK(silent(r, P, P + kBar90));
  CHECK_EQ(mismatches(r, P + kBar90, *c, 0, 2 * kBar90), 0);
}

void testBackingLateEnable() {
  std::printf("Sonar: encenderla con todo sonando espera al siguiente 1\n");
  SongRig r;
  Clip* c = handClip(4, kSpb90, 4, 8, 1);
  offerSong(r, c);
  const int64_t P = r.outPos;
  r.post(T::kPlay);
  r.runTo(P + kBar90 + kBar90 / 2);
  r.post(T::kSetBackingEnabled, 1);
  r.runTo(P + 3 * kBar90);
  CHECK(silent(r, P, P + 2 * kBar90));
  CHECK_EQ(mismatches(r, P + 2 * kBar90, *c, 0, kBar90), 0);
  // Sin canción preparada para ese tempo no suena nada (y no pasa nada)
  r.post(T::kSetBpm, 120.0);
  r.runFor(3 * kBar90);
  CHECK(silent(r, r.outPos - kBar90, r.outPos));
}

void testPreviewPlayback() {
  std::printf("Vista previa: suena desde donde se pida, con su clic en la rejilla\n");
  Rig r(48000, 0);
  r.post(T::kSetClickVolume, 0.8);
  Clip* c = handClip(11, 0, 0, 0, 0);
  c->pcm.resize(48000 * 5);
  for (size_t i = 0; i < c->pcm.size(); ++i) c->pcm[i] = int16_t(100 + (int64_t(i) * 7) % 20000);
  r.core.backing().previewSlot().offer(c, r.core.clipBin());
  r.runFor(256);
  CHECK_EQ(r.core.status().previewId, 11);
  const int64_t Q = r.outPos;
  r.post(T::kPreviewPlay, 30000);
  r.runFor(10000);
  int64_t bad = 0;
  for (int64_t i = 0; i < 10000; ++i)
    if (std::fabs(r.hist[size_t(Q + i)] - c->at(30000 + i) * 0.8f) > 1e-5f) ++bad;
  CHECK_EQ(bad, 0);
  r.post(T::kPreviewStop);
  r.runFor(1000);
  CHECK(silent(r, r.outPos - 500, r.outPos));

  // Con un clip en silencio, solo se oye el clic: en el 1 y cada tiempo
  Clip* quiet = new Clip();
  quiet->rate = 48000;
  quiet->id = 12;
  quiet->pcm.assign(48000 * 8, 0);
  r.core.backing().previewSlot().offer(quiet, r.core.clipBin());
  r.runFor(256);
  const double mark = 5000.5, beat = 29599.18;
  r.core.post({T::kSetPreviewBeat, beat, 4});
  r.core.post({T::kSetPreviewMark, mark, 0});
  r.post(T::kSetPreviewClick, 1);
  const int64_t from = 40000;
  const int64_t R = r.outPos;
  r.post(T::kPreviewPlay, double(from));
  r.runFor(48000 * 3);
  // Clics esperados: los tiempos de la rejilla desde «from»
  const int64_t k0 = int64_t(std::ceil((from - mark) / beat));
  int checked = 0;
  for (int64_t k = k0; k < k0 + 4; ++k) {
    const int64_t at = R + std::llround(mark + k * beat) - from;
    // Antes del clic, silencio; en sus primeras muestras, sonido
    CHECK(silent(r, at - 200, at));
    bool sound = false;
    for (int64_t i = at; i < at + 48; ++i) sound = sound || r.hist[size_t(i)] != 0.0f;
    CHECK(sound);
    ++checked;
  }
  CHECK_EQ(checked, 4);
  // Al cerrar la canción, la vista previa se calla
  r.core.backing().previewSlot().offer(nullptr, r.core.clipBin());
  r.runFor(48000);
  CHECK(silent(r, r.outPos - 40000, r.outPos));
  CHECK_EQ(r.core.status().previewId, 0);
}

// Los trabajos de verdad, en su hilo, mientras el audio sigue sonando.
void testJobsThreaded() {
  std::printf("Trabajos en segundo plano mientras suena el audio\n");
  const std::string path = tmpPath("jobs.wav");
  writeSong(path, 44100, 2, 97.3, 0.73, 60);
  SongRig r;
  SongJobs jobs(r.core.backing(), r.core.clipBin());
  auto waitFor = [&](const Worker& w) {
    const auto t0 = std::chrono::steady_clock::now();
    while (w.state() == Worker::kRunning &&
           std::chrono::steady_clock::now() - t0 < std::chrono::seconds(30)) {
      r.runFor(4800);
      r.core.collectClips();
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
  };
  // Abrir: la vista previa llega al hilo de audio
  jobs.open(path, 48000, 21);
  waitFor(jobs.opener());
  CHECK_EQ(jobs.opener().state(), Worker::kDone);
  CHECK_EQ(jobs.opener().progress(), 1000);
  r.runFor(256);
  CHECK_EQ(r.core.status().previewId, 21);
  CHECK(jobs.previewInfo().frames > 48000 * 30);
  float pk[8] = {};
  CHECK_EQ(jobs.peaks(0, jobs.previewInfo().frames, 8, pk), 8);
  CHECK(pk[0] > 0.5f);

  // Preparar: dos seguidas, la primera se cancela; suena la segunda
  PrepareParams p;
  p.path = path;
  p.songBpm = 97.3;
  p.markSeconds = 0.73;
  p.samplesPerBeat = 30000;
  p.beatsPerBar = 4;
  p.rate = 48000;
  p.id = 30;
  jobs.prepare(p);
  p.samplesPerBeat = kSpb90;
  p.id = 31;
  jobs.prepare(p);
  waitFor(jobs.preparer());
  CHECK_EQ(jobs.preparer().state(), Worker::kDone);
  CHECK_EQ(jobs.preparer().id(), 31);
  r.runFor(256);
  CHECK_EQ(r.core.status().backingId, 31);
  CHECK_EQ(r.core.status().backingSpb, kSpb90);

  // Un error se publica
  p.path = tmpPath("no_existe.wav");
  p.id = 32;
  jobs.prepare(p);
  waitFor(jobs.preparer());
  CHECK_EQ(jobs.preparer().state(), Worker::kFailed);
  CHECK_EQ(jobs.preparer().error(), SongJobs::kErrOpen);
  CHECK_EQ(r.core.status().backingId, 31);  // la que había sigue

  // Cerrar y quitar
  jobs.closeOpen();
  jobs.unload();
  r.runFor(256);
  r.core.collectClips();
  CHECK_EQ(r.core.status().previewId, 0);
  CHECK_EQ(r.core.status().backingId, 0);
  CHECK_EQ(jobs.peaks(0, 100, 8, pk), 0);
}

// Volver a un tempo de hace poco (el de la canción, después de practicar
// más despacio) no la prepara otra vez: se guardan las 2 últimas.
void testKeptVersions() {
  std::printf("Volver a un tempo de hace poco es instantáneo\n");
  const std::string path = tmpPath("kept.wav");
  writeSong(path, 48000, 1, 97.3, 0.73, 40);
  SongRig r;
  SongJobs jobs(r.core.backing(), r.core.clipBin());
  auto waitFor = [&]() {
    const auto t0 = std::chrono::steady_clock::now();
    while (jobs.preparer().state() == Worker::kRunning &&
           std::chrono::steady_clock::now() - t0 < std::chrono::seconds(30)) {
      r.runFor(4800);
      r.core.collectClips();
    }
    r.runFor(256);
    r.core.collectClips();
  };
  PrepareParams p;
  p.path = path;
  p.songBpm = 97.3;
  p.markSeconds = 0.73;
  p.samplesPerBeat = 29599;  // su tempo
  p.beatsPerBar = 4;
  p.rate = 48000;
  p.id = 40;
  jobs.prepare(p);
  waitFor();
  CHECK_EQ(r.core.status().backingSpb, 29599);
  p.samplesPerBeat = 34000;  // más despacio
  jobs.prepare(p);
  waitFor();
  CHECK_EQ(r.core.status().backingSpb, 34000);
  CHECK_EQ(int(r.core.clipBin().keptCount()), 1);
  // Vuelta a su tempo: hecho al momento, sin trabajar
  const auto t0 = std::chrono::steady_clock::now();
  p.samplesPerBeat = 29599;
  jobs.prepare(p);
  CHECK_EQ(jobs.preparer().state(), Worker::kDone);
  r.runFor(256);
  const double ms =
      std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  CHECK_EQ(r.core.status().backingSpb, 29599);
  CHECK(ms < 50.0);
  r.core.collectClips();
  CHECK_EQ(int(r.core.clipBin().keptCount()), 1);  // ahora guarda la lenta
  // Otro 1 u otro tempo de la canción: ya no vale lo guardado
  p.markSeconds = 0.74;
  CHECK(SongJobs::keyOf(p) != 0);
  jobs.prepare(p);
  CHECK_EQ(jobs.preparer().state(), Worker::kRunning);
  jobs.cancelPrepare();
  CHECK_EQ(jobs.preparer().state(), Worker::kIdle);
  CHECK_EQ(r.core.status().backingSpb, 29599);  // la que sonaba sigue
}

// Con el audio cerrado se cambia de frecuencia: los clips de la otra ya no
// valen (la app los vuelve a preparar).
void testRateChange() {
  std::printf("Al cambiar de frecuencia los clips se descartan\n");
  SongRig r;
  offerSong(r, handClip(1, kSpb90, 4, 2, 1));
  r.runFor(256);
  CHECK_EQ(r.core.status().backingId, 1);
  r.core.prepare(48000);  // misma frecuencia: se queda
  r.runFor(256);
  CHECK_EQ(r.core.status().backingId, 1);
  r.core.prepare(44100);
  r.runFor(256);
  CHECK_EQ(r.core.status().backingId, 0);
  // Ofrecido con el audio cerrado y de la frecuencia buena: se queda
  offerSong(r, handClip(2, 30000, 4, 2, 1));
  Clip* other = handClip(3, 30000, 4, 2, 1);
  other->rate = 44100;
  r.core.prepare(48000);
  offerSong(r, other);
  r.core.prepare(44100);
  r.runFor(256);
  CHECK_EQ(r.core.status().backingId, 3);
}

// Cuánto cuesta preparar una canción de 4 minutos (en el PC; en el móvil
// será unas cuantas veces más)
void testCost() {
  std::printf("Coste de preparar una canción de 4 min (44,1 kHz estéreo)\n");
  const std::string path = tmpPath("cost.wav");
  writeSong(path, 44100, 2, 97.3, 0.73, 389, 0.5);  // ~4 min
  PrepareParams p;
  p.path = path;
  p.songBpm = 97.3;
  p.markSeconds = 0.73;
  p.samplesPerBeat = Transport::computeSamplesPerBeat(48000, 90.0);
  p.beatsPerBar = 4;
  p.rate = 48000;
  Clip* clip = nullptr;
  PreviewInfo info;
  auto t0 = std::chrono::steady_clock::now();
  CHECK_EQ(SongJobs::buildPreview(path, 48000, 1, &clip, &info, nullptr), 0);
  const double open = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  const double mb = clip != nullptr ? clip->pcm.size() * 2 / 1e6 : 0;
  delete clip;
  t0 = std::chrono::steady_clock::now();
  CHECK_EQ(SongJobs::buildBacking(p, &clip, nullptr), 0);
  const double prep = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  std::printf("  abrir %.2f s · estirar a 90 BPM %.2f s · %.1f MB en memoria (estirada %.1f MB)\n",
              open, prep, mb, clip != nullptr ? clip->pcm.size() * 2 / 1e6 : 0.0);
  delete clip;
}

}  // namespace

void runSongTests() {
  // El marcador de «quitar» de los huecos es un clip que vive siempre
  {
    ClipSlot s;
    ClipBin b;
    s.offer(nullptr, b);
  }
  const int before = Clip::count().load();
  testStretchAlignment();
  testStretchCutsTinyLead();
  testStretchErrors();
  testPreview();
  testBackingPlays();
  testBackingTempoChange();
  testBackingCountIn();
  testBackingLateEnable();
  testPreviewPlayback();
  testJobsThreaded();
  testKeptVersions();
  testRateChange();
  testCost();
  std::printf("Ningún clip se queda sin borrar\n");
  CHECK_EQ(Clip::count().load(), before);
}
