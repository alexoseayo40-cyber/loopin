// Loopin — tests del motor: sesiones (leer y cargar pistas) y exportar
// SPDX-License-Identifier: GPL-3.0-or-later
#include <cmath>
#include <cstdio>
#include <string>

#include "Export.h"
#include "rig.h"

using namespace loopin_test;

namespace {

int32_t barOf(int32_t sr, double bpm, int32_t beats = 4) {
  return Transport::computeSamplesPerBeat(sr, bpm) * beats;
}

// Lo que hay en un motor: la sesión y sus datos
struct Snapshot {
  SessionSpec spec;
  std::vector<float> data[Looper::kTracks];
  uint64_t hash[Looper::kTracks] = {};
  const float* ptrs[Looper::kTracks] = {};
};

bool snapshot(EngineCore& core, Snapshot& s) {
  const CoreStatus c = core.status();
  s.spec.bpm = c.bpm;
  s.spec.beatsPerBar = c.beatsPerBar;
  s.spec.accentMask = static_cast<uint32_t>(c.accentMask);
  s.spec.sampleRate = core.sampleRate();
  s.spec.barFrames = c.loopBarFrames;
  s.spec.baseLen = c.loopBaseLength;
  s.spec.selected = c.loopSelected;
  for (int32_t i = 0; i < Looper::kTracks; ++i) {
    const int64_t len = core.readTrack(i, nullptr, 0, &s.hash[i]);
    if (len < 0) return false;
    s.data[i].assign(static_cast<size_t>(len), 0.0f);
    if (len > 0 && core.readTrack(i, s.data[i].data(), len, nullptr) != len) return false;
    s.spec.len[i] = len;
    s.spec.offset[i] = c.trackOffset[i];
    s.spec.layers[i] = c.trackLayers[i];
    s.ptrs[i] = len > 0 ? s.data[i].data() : nullptr;
  }
  return true;
}

// Graba la base (2 compases), una capa encima, otra pista del doble y mueve
// la latencia a mano (así el origen de las pistas no cae en un compás)
void recordSession(Rig& r, int64_t& revisionWhileBusy, bool& readWhileBusy) {
  r.post(T::kSetBpm, 100);
  r.post(T::kSetLoopMode, 0);
  r.post(T::kSetSyncBars, 2);
  r.post(T::kSetAutoAdvance, 1);
  const int64_t bar = barOf(r.sr, 100);
  r.player = [](int64_t n) { return sig(3, n) - 0.007f; };
  r.postAt(300, T::kLoopPress);           // pista 1: cuenta + 2 compases
  r.runFor(bar / 2);
  readWhileBusy = r.core.readTrack(0, nullptr, 0, nullptr) >= 0;
  revisionWhileBusy = r.core.status().loopRevision;
  r.runTo(300 + 3 * bar + 2 * r.L + 1000);
  r.post(T::kSetSyncBars, 4);
  r.post(T::kLoopPress);                  // pista 2: 4 compases (el doble)
  r.runFor(6 * bar + 2 * r.L);
  r.postTrack(T::kSelectTrack, 0);
  r.post(T::kLoopPress);                  // overdub en la pista 1
  r.runFor(bar + bar / 3);
  r.post(T::kLoopPress);                  // lo cierra
  r.runFor(2 * bar);
  r.post(T::kNudgeLatency, r.L + 137);    // mueve todo 137 muestras
  r.runFor(1000);
  r.post(T::kPause);
  r.runFor(4 * bar);                      // que acabe el trabajo de fondo
}

void testReadAndRestore() {
  std::printf("Sesiones: leer las pistas y volver a cargarlas (mismo y otra frecuencia)\n");
  Rig a(48000, 2311, 7);
  int64_t revBusy = 0;
  bool readBusy = true;
  const int64_t rev0 = a.core.status().loopRevision;
  recordSession(a, revBusy, readBusy);
  CHECK(!readBusy);  // grabando no se puede leer
  CHECK(revBusy > rev0);
  CoreStatus c = a.core.status();
  CHECK_EQ(c.loopSettled, 1);
  CHECK(a.state() == St::kStopped);
  CHECK(a.lp().trackLength(1) == 2 * a.lp().trackLength(0));
  CHECK(a.lp().trackLayers(0) == 2);
  // Con una orden sin aplicar, no se lee
  a.post(T::kSetTrackVolume, 1.0);
  CHECK_EQ(a.core.readTrack(0, nullptr, 0, nullptr), -1);
  a.runFor(256);
  CHECK(a.core.readTrack(0, nullptr, 0, nullptr) > 0);

  Snapshot s;
  CHECK(snapshot(a.core, s));
  CHECK(s.spec.offset[0] != 0 && s.spec.offset[0] % s.spec.barFrames != 0);  // por el ajuste
  CHECK(s.hash[0] != 0 && s.hash[0] != s.hash[1]);
  CHECK(s.spec.len[2] == 0 && s.ptrs[2] == nullptr);
  // La pista 1 lleva la capa sumada: lo leído es lo que suena
  {
    int64_t nonzero = 0;
    for (float x : s.data[0]) nonzero += x != 0.0f;
    CHECK(nonzero > s.spec.len[0] / 2);
  }

  // Otro motor a la misma frecuencia: suena exactamente igual
  Rig b(48000, 2311, 9);
  b.runFor(1000);
  const int64_t revB = b.core.status().loopRevision;
  CHECK_EQ(b.core.loadSession(s.spec, s.ptrs), EngineCore::kSessionOk);
  b.runFor(256);
  CHECK(b.state() == St::kStopped);
  CHECK(b.core.status().loopRevision > revB);
  CHECK_EQ(b.core.status().bpm, 100);
  for (int32_t i = 0; i < Looper::kTracks; ++i) {
    uint64_t h = 0;
    CHECK_EQ(b.core.readTrack(i, nullptr, 0, &h), s.spec.len[i]);
    CHECK(h == s.hash[i]);
    CHECK_EQ(b.lp().trackOffset(i), s.spec.offset[i]);
    CHECK_EQ(b.lp().trackLayers(i), s.spec.layers[i]);
  }
  CHECK(!b.lp().canUndo());  // lo cargado no se deshace
  // Con loops ya no se puede cargar otra
  CHECK_EQ(b.core.loadSession(s.spec, s.ptrs), EngineCore::kSessionNotReady);

  // Arrancan los dos: muestra a muestra lo mismo durante 3 ciclos
  a.player = [](int64_t) { return 0.0f; };
  b.player = [](int64_t) { return 0.0f; };
  const int64_t cycle = s.spec.len[1];
  const int64_t pa = a.outPos, pb = b.outPos;
  a.post(T::kPlay);
  b.post(T::kPlay);
  a.runFor(3 * cycle);
  b.runFor(3 * cycle);
  int64_t wrong = 0;
  for (int64_t k = 0; k < 3 * cycle; ++k) wrong += a.hist[pa + k] != b.hist[pb + k];
  CHECK_EQ(wrong, 0);

  // A 44,1 kHz: los compases son de 44,1 y las longitudes cuadran
  Rig d(44100, 2000, 2);
  d.runFor(500);
  CHECK_EQ(d.core.loadSession(s.spec, s.ptrs), EngineCore::kSessionOk);
  d.runFor(256);
  CHECK(d.state() == St::kStopped);
  const int64_t bar44 = barOf(44100, 100);
  CHECK_EQ(d.lp().barFrames(), bar44);
  CHECK_EQ(d.lp().baseLength(), 2 * bar44);
  CHECK_EQ(d.lp().trackLength(0), 2 * bar44);
  CHECK_EQ(d.lp().trackLength(1), 4 * bar44);
  CHECK(std::llabs(d.lp().trackOffset(0) - std::llround(s.spec.offset[0] * 44100.0 / 48000)) <= 1);
  // y suena lo mismo (estirado): mismo nivel medio
  {
    std::vector<float> back(static_cast<size_t>(4 * bar44));
    d.post(T::kSetTrackVolume, 1.0);
    d.runFor(256);
    CHECK_EQ(d.core.readTrack(1, back.data(), 4 * bar44, nullptr), 4 * bar44);
    double e1 = 0, e2 = 0;
    for (float x : s.data[1]) e1 += x;
    for (float x : back) e2 += x;
    e1 /= double(s.data[1].size());
    e2 /= double(back.size());
    CHECK(std::fabs(e1) > 1e-4 && std::fabs(e1 - e2) < 0.01 * std::fabs(e1));
  }

  // Datos que no cuadran
  SessionSpec bad = s.spec;
  bad.len[0] = s.spec.len[0] + 1;
  Rig e(48000, 100, 1);
  e.runFor(256);
  CHECK_EQ(e.core.loadSession(bad, s.ptrs), EngineCore::kSessionBad);
  CHECK(e.state() == St::kEmpty);
}

// ---------------------------------------------------------------- exportar

struct Wav {
  int32_t rate = 0;
  std::vector<int16_t> pcm;
};

bool readWav(const std::string& path, Wav& w) {
  std::FILE* f = std::fopen(path.c_str(), "rb");
  if (f == nullptr) return false;
  unsigned char h[44];
  if (std::fread(h, 1, 44, f) != 44) {
    std::fclose(f);
    return false;
  }
  w.rate = h[24] | (h[25] << 8) | (h[26] << 16) | (h[27] << 24);
  const uint32_t bytes = h[40] | (h[41] << 8) | (h[42] << 16) | (uint32_t(h[43]) << 24);
  w.pcm.assign(bytes / 2, 0);
  const size_t got = std::fread(w.pcm.data(), 2, w.pcm.size(), f);
  std::fclose(f);
  return got == w.pcm.size() && std::string((char*)h, 4) == "RIFF";
}

int16_t q16(float x) {
  return static_cast<int16_t>(std::lrint(std::clamp(x, -1.0f, 1.0f) * 32767.0f));
}

// Una sesión hecha a mano: 120 BPM, base de 2 compases; pista 1 la base,
// pista 2 el doble (en silencio en la mezcla), pista 3 la base al revés
ExportSpec handSpec(float amp) {
  ExportSpec e;
  SessionSpec& s = e.session;
  s.sampleRate = 48000;
  s.bpm = 120;
  s.beatsPerBar = 4;
  s.barFrames = barOf(48000, 120);
  s.baseLen = 2 * s.barFrames;
  const int64_t lens[3] = {s.baseLen, 2 * s.baseLen, s.baseLen};
  for (int32_t i = 0; i < 3; ++i) {
    s.len[i] = lens[i];
    s.layers[i] = 1;
    e.data[i].resize(static_cast<size_t>(lens[i]));
    for (int64_t p = 0; p < lens[i]; ++p) e.data[i][p] = amp * sig(i + 1, p);
  }
  e.muted[1] = true;
  e.reverse[2] = true;
  e.volume[0] = 0.5f;
  return e;
}

std::string tmp(const char* name) { return std::string("/tmp/loopin_test_") + name; }

void testExportLoops() {
  std::printf("Exportar: mezcla (volumen, silencio, reverse) y cada pista por separado\n");
  ExportSpec e = handSpec(1.0f);
  const std::vector<float> d0 = e.data[0], d1 = e.data[1], d2 = e.data[2];
  const int64_t base = e.session.baseLen;
  e.loops = 2;
  e.mixPath = tmp("mix.wav");
  for (int32_t i = 0; i < 3; ++i) e.trackPath[i] = tmp(("t" + std::to_string(i) + ".wav").c_str());
  EngineCore core;
  std::atomic<int32_t> progress{0};
  int64_t frames = 0;
  CHECK_EQ(Exporter::run(core, e, nullptr, &progress, &frames), 0);
  CHECK_EQ(frames, 2 * 2 * base);  // 2 vueltas de la pista más larga
  CHECK(progress.load() >= 999);
  Wav mix, t0, t1, t2;
  CHECK(readWav(e.mixPath, mix) && readWav(e.trackPath[0], t0));
  CHECK(readWav(e.trackPath[1], t1) && readWav(e.trackPath[2], t2));
  CHECK_EQ(mix.rate, 48000);
  CHECK_EQ(int64_t(mix.pcm.size()), frames);
  int64_t wrongMix = 0, wrongStems = 0;
  for (int64_t n = 0; n < frames; ++n) {
    const float a = 0.5f * d0[n % base];
    const float c = d2[((-n) % base + base) % base];  // al revés desde el principio
    wrongMix += std::abs(mix.pcm[n] - q16(a + c)) > 1;
    wrongStems += std::abs(t0.pcm[n] - q16(a)) > 1;
    wrongStems += std::abs(t1.pcm[n] - q16(d1[n % (2 * base)])) > 1;  // aunque esté en silencio
    wrongStems += std::abs(t2.pcm[n] - q16(c)) > 1;
  }
  CHECK_EQ(wrongMix, 0);
  CHECK_EQ(wrongStems, 0);

  // Si la mezcla pasa de 0 dB, todo baja lo mismo (a −0,2 dB)
  ExportSpec loud = handSpec(80.0f);
  loud.muted[1] = false;
  loud.mixPath = tmp("loud.wav");
  loud.trackPath[0] = tmp("loud0.wav");
  EngineCore core2;
  CHECK_EQ(Exporter::run(core2, loud, nullptr, nullptr, nullptr), 0);
  Wav lm, l0;
  CHECK(readWav(loud.mixPath, lm) && readWav(loud.trackPath[0], l0));
  int32_t peak = 0;
  for (int16_t x : lm.pcm) peak = std::max(peak, std::abs(int32_t(x)));
  CHECK(std::abs(peak - 32112) <= 2);  // 0,98 × 32767
  // La pista lleva la misma ganancia: sumadas siguen dando la mezcla
  int32_t p0 = 0;
  for (int16_t x : l0.pcm) p0 = std::max(p0, std::abs(int32_t(x)));
  CHECK(p0 < peak);
}

void testExportDrumsAndThread() {
  std::printf("Exportar: con batería (dos pasadas iguales) y en su hilo\n");
  // Un kit de mentira: un golpe corto por sonido
  EngineCore live;
  for (int32_t s = 0; s < static_cast<int32_t>(DrumSound::kCount); ++s) {
    std::vector<float> hit(2000);
    for (size_t k = 0; k < hit.size(); ++k)
      hit[k] = 0.3f * std::exp(-float(k) / 300.0f) * float((k * (s + 3)) % 7) / 7.0f;
    live.setDrumSample(static_cast<DrumSound>(s), hit.data(), int32_t(hit.size()), 44100);
  }
  auto withDrums = [&](const std::string& mix, const std::string& drums) {
    ExportSpec e = handSpec(1.0f);
    e.drums = true;
    e.drumStyle = DrumStyle::kRock;
    e.drumVolume = 0.8f;
    e.mixPath = mix;
    e.drumsPath = drums;
    return e;
  };
  ExportSpec e1 = withDrums(tmp("d1.wav"), tmp("d1drums.wav"));
  ExportSpec e2 = withDrums(tmp("d2.wav"), "");
  EngineCore c1, c2;
  c1.copyDrumKit(live);
  c2.copyDrumKit(live);
  CHECK_EQ(Exporter::run(c1, e1, nullptr, nullptr, nullptr), 0);
  CHECK_EQ(Exporter::run(c2, e2, nullptr, nullptr, nullptr), 0);
  Wav m1, m2, dr;
  CHECK(readWav(e1.mixPath, m1) && readWav(e2.mixPath, m2) && readWav(e1.drumsPath, dr));
  CHECK(m1.pcm == m2.pcm);
  // La batería suena (entra en el 1 con un golpe)
  int32_t first = -1;
  for (size_t k = 0; k < dr.pcm.size() && first < 0; ++k)
    if (dr.pcm[k] != 0) first = int32_t(k);
  CHECK_EQ(first, 1);  // el golpe empieza a la primera muestra (la 0 es 0)
  // Mezcla = pistas + batería (± redondeos)
  ExportSpec loops = handSpec(1.0f);
  loops.mixPath = tmp("d3.wav");
  EngineCore c3;
  CHECK_EQ(Exporter::run(c3, loops, nullptr, nullptr, nullptr), 0);
  Wav lp;
  CHECK(readWav(loops.mixPath, lp));
  int64_t wrong = 0;
  for (size_t k = 0; k < m1.pcm.size(); ++k)
    wrong += std::abs(int32_t(m1.pcm[k]) - int32_t(lp.pcm[k]) - int32_t(dr.pcm[k])) > 2;
  CHECK_EQ(wrong, 0);

  // En su hilo, y cancelar borra lo escrito
  Exporter ex;
  ExportSpec t = handSpec(1.0f);
  t.mixPath = tmp("thread.wav");
  CHECK(ex.start(std::move(t), live));
  for (int i = 0; i < 2000 && ex.state() == Exporter::kRunning; ++i)
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  CHECK_EQ(ex.state(), Exporter::kDone);
  Wav tw;
  CHECK(readWav(tmp("thread.wav"), tw));
  ExportSpec longer = handSpec(1.0f);
  longer.loops = 64;
  longer.mixPath = tmp("cancel.wav");
  longer.trackPath[0] = tmp("cancel0.wav");
  CHECK(ex.start(std::move(longer), live));
  std::this_thread::sleep_for(std::chrono::milliseconds(20));
  ex.cancel();
  for (int i = 0; i < 2000 && ex.state() == Exporter::kRunning; ++i)
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  CHECK_EQ(ex.state(), Exporter::kIdle);
  CHECK(std::fopen(tmp("cancel.wav").c_str(), "rb") == nullptr);

  // Sin pistas no hay nada que exportar
  ExportSpec none;
  none.mixPath = tmp("none.wav");
  EngineCore c4;
  CHECK_EQ(Exporter::run(c4, none, nullptr, nullptr, nullptr), Exporter::kErrNothing);
}

}  // namespace

void runSessionTests() {
  testReadAndRestore();
  testExportLoops();
  testExportDrumsAndThread();
}
