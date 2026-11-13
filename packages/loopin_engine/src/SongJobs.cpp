// Loopin — trabajos con el audio importado: decodificar y estirar
// SPDX-License-Identifier: GPL-3.0-or-later
#include "SongJobs.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <new>
#include <vector>

#if defined(__linux__)
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

#include "SongReader.h"
#include "third_party/soundtouch/include/BPMDetect.h"
#include "third_party/soundtouch/include/SoundTouch.h"

namespace loopin {

// ---------------------------------------------------------------- Worker

void Worker::run(int32_t id, std::function<int32_t(Worker&)> fn) {
  stop();
  cancel_.store(false);
  id_.store(id, std::memory_order_relaxed);
  progress_.store(0, std::memory_order_relaxed);
  error_.store(0, std::memory_order_relaxed);
  state_.store(kRunning, std::memory_order_release);
  thread_ = std::thread([this, fn = std::move(fn)]() {
#if defined(__linux__)
    // Menos prioridad que la interfaz (y mucha menos que el audio)
    setpriority(PRIO_PROCESS, static_cast<id_t>(syscall(SYS_gettid)), 10);
#endif
    int32_t err = 0;
    try {
      err = fn(*this);
    } catch (const std::bad_alloc&) {
      err = SongJobs::kErrMemory;
    } catch (...) {
      err = SongJobs::kErrOpen;
    }
    if (cancelled()) {
      state_.store(kIdle, std::memory_order_release);
      return;
    }
    error_.store(err, std::memory_order_relaxed);
    if (err == 0) progress_.store(1000, std::memory_order_relaxed);
    state_.store(err == 0 ? kDone : kFailed, std::memory_order_release);
  });
}

void Worker::stop() {
  if (!thread_.joinable()) return;
  cancel_.store(true);
  thread_.join();
  if (state_.load() == kRunning) state_.store(kIdle);
}

void Worker::finishNow(int32_t id) {
  stop();
  id_.store(id, std::memory_order_relaxed);
  error_.store(0, std::memory_order_relaxed);
  progress_.store(1000, std::memory_order_relaxed);
  state_.store(kDone, std::memory_order_release);
}

void Worker::setProgress(double fraction) {
  progress_.store(static_cast<int32_t>(std::clamp(fraction, 0.0, 1.0) * 1000.0),
                  std::memory_order_relaxed);
}

// ---------------------------------------------------------------- estirar

namespace {

constexpr size_t kChunk = 4096;

// SoundTouch con atajo: si no hay que cambiar nada, pasa tal cual.
class Stretcher {
 public:
  // tempo: > 1 acelera. rateOnly: cambia la velocidad (y el tono) en vez de
  // estirar.
  Stretcher(int32_t srcRate, int32_t dstRate, double tempo, bool rateOnly) {
    bypass_ = srcRate == dstRate && std::fabs(tempo - 1.0) < 1e-9;
    if (bypass_) return;
    st_.setSampleRate(static_cast<unsigned>(srcRate));
    st_.setChannels(1);
    const double resample = double(srcRate) / double(dstRate);
    if (rateOnly) {
      st_.setTempo(1.0);
      st_.setRate(resample * tempo);
    } else {
      st_.setTempo(tempo);
      st_.setRate(resample);
      // Trozos más cortos que los de serie (que van por 80 ms): los golpes
      // secos (batería, rasgueos) se mueven menos y se duplican menos al
      // frenar. Medido con golpes sobre un acorde, a 0,92: de 5,7 a 4 ms de
      // media y de 12 a 2 golpes «dobles» de 200.
      st_.setSetting(SETTING_SEQUENCE_MS, 35);
      st_.setSetting(SETTING_SEEKWINDOW_MS, 12);
      st_.setSetting(SETTING_OVERLAP_MS, 8);
    }
  }
  void put(const float* in, size_t n) {
    if (bypass_) {
      pending_.insert(pending_.end(), in, in + n);
    } else {
      st_.putSamples(in, static_cast<unsigned>(n));
    }
  }
  size_t receive(float* out, size_t max) {
    if (bypass_) {
      const size_t n = std::min(max, pending_.size() - head_);
      std::copy(pending_.begin() + long(head_), pending_.begin() + long(head_ + n), out);
      head_ += n;
      if (head_ == pending_.size()) {
        pending_.clear();
        head_ = 0;
      }
      return n;
    }
    return st_.receiveSamples(out, static_cast<unsigned>(max));
  }
  void flush() {
    if (!bypass_) st_.flush();
  }

 private:
  bool bypass_ = false;
  soundtouch::SoundTouch st_;
  std::vector<float> pending_;
  size_t head_ = 0;
};

inline int16_t toPcm16(float s) {
  const float c = std::clamp(s, -1.0f, 1.0f) * 32767.0f;
  return static_cast<int16_t>(std::lrint(c));
}

}  // namespace

int32_t SongJobs::buildPreview(const std::string& path, int32_t rate, int32_t id, Clip** out,
                               PreviewInfo* info, Worker* w) {
  *out = nullptr;
  SongReader r;
  if (!r.open(path) || rate <= 0) return kErrOpen;
  const int32_t src = r.sampleRate();
  const uint64_t total = r.frames();
  if (total > uint64_t(kMaxSeconds) * uint64_t(src)) return kErrTooLong;
  const int64_t maxFrames = int64_t(kMaxSeconds) * rate;

  auto clip = std::make_unique<Clip>();
  clip->rate = rate;
  clip->id = id;
  if (total > 0) clip->pcm.reserve(size_t(double(total) * rate / src) + kChunk);

  Stretcher st(src, rate, 1.0, true);
  soundtouch::BPMDetect bpm(1, src);
  std::vector<float> in(kChunk), res(kChunk);
  uint64_t read = 0;
  auto drain = [&]() {
    size_t m;
    while ((m = st.receive(res.data(), res.size())) > 0)
      for (size_t i = 0; i < m; ++i) clip->pcm.push_back(toPcm16(res[i]));
  };
  for (;;) {
    if (w != nullptr && w->cancelled()) return kOk;
    const size_t n = r.read(in.data(), in.size());
    if (n == 0) break;
    // Para sugerir el tempo basta con el primer minuto y medio (es lo que
    // más cuesta de abrirla)
    if (read < uint64_t(src) * 90) bpm.inputSamples(in.data(), int(n));
    read += n;
    st.put(in.data(), n);
    drain();
    if (clip->frames() > maxFrames) return kErrTooLong;
    if (w != nullptr && total > 0) w->setProgress(double(read) / double(total) * 0.95);
  }
  st.flush();
  drain();
  if (clip->frames() > maxFrames) clip->pcm.resize(size_t(maxFrames));
  if (clip->pcm.empty()) return kErrEmpty;

  int16_t peak = 0;
  for (int16_t s : clip->pcm) peak = std::max<int16_t>(peak, int16_t(std::abs(int(s))));
  if (peak < 33) return kErrEmpty;  // todo silencio (menos de −60 dB)

  if (info != nullptr) {
    info->frames = clip->frames();
    const double guess = bpm.getBpm();
    info->bpmGuess = std::isfinite(guess) && guess > 0.0 ? guess : 0.0;
    // Primer golpe claro: lo primero que pasa de un 20 % del pico, ajustado
    // al ataque de ahí cerca
    int64_t first = -1;
    const int32_t thr = peak / 5;
    for (int64_t i = 0; i < clip->frames(); ++i) {
      if (std::abs(int(clip->pcm[size_t(i)])) >= thr) {
        first = i;
        break;
      }
    }
    info->firstAttack = first < 0 ? -1 : attackNear(*clip, first, rate / 30);
  }
  *out = clip.release();
  return kOk;
}

int32_t SongJobs::buildBacking(const PrepareParams& p, Clip** out, Worker* w) {
  *out = nullptr;
  if (p.songBpm <= 0.0 || p.samplesPerBeat <= 0 || p.beatsPerBar <= 0 || p.rate <= 0)
    return kErrTempo;
  // Un tiempo de la canción (a la frecuencia del motor) frente a uno del
  // transporte: lo que hay que acelerar (> 1) o frenar
  const double tempo = (double(p.rate) * 60.0 / p.songBpm) / double(p.samplesPerBeat);
  if (tempo < kMinTempo || tempo > kMaxTempo) return kErrTempo;
  SongReader r;
  if (!r.open(p.path)) return kErrOpen;
  const int32_t src = r.sampleRate();
  const uint64_t total = r.frames();

  // Dónde cae el 1 una vez estirado, y cuántos compases van delante (lo que
  // suena antes del 1: una anacrusa, una intro…). Si antes del 1 hay muy poco
  // (menos de 1/8 de tiempo) se quita en vez de añadir un compás casi vacío.
  const int64_t barFrames = int64_t(p.samplesPerBeat) * p.beatsPerBar;
  const double markOut = std::max(0.0, p.markSeconds) * p.songBpm / 60.0 * p.samplesPerBeat;
  const int64_t markI = std::llround(markOut);
  const int64_t padBars =
      markOut <= p.samplesPerBeat / 8.0 ? 0 : int64_t(std::ceil(markOut / double(barFrames)));
  // posición en el clip = posición estirada + offset
  const int64_t offset = padBars * barFrames - markI;
  const int64_t maxFrames = int64_t(kMaxSeconds) * p.rate;
  const double outPerIn = double(p.rate) / double(src) / tempo;
  if (total > 0 && double(offset) + double(total) * outPerIn > double(maxFrames))
    return kErrTooLong;

  auto clip = std::make_unique<Clip>();
  clip->rate = p.rate;
  clip->id = p.id;
  clip->samplesPerBeat = p.samplesPerBeat;
  clip->beatsPerBar = p.beatsPerBar;
  clip->barFrames = barFrames;
  clip->key = keyOf(p);
  if (total > 0)
    clip->pcm.reserve(size_t(std::max<int64_t>(0, offset) + int64_t(double(total) * outPerIn) +
                             barFrames + int64_t(kChunk)));
  if (offset > 0) clip->pcm.assign(size_t(offset), 0);
  int64_t skip = offset < 0 ? -offset : 0;

  const bool rateOnly = std::fabs(tempo - 1.0) < kRateOnly;
  Stretcher st(src, p.rate, tempo, rateOnly);
  std::vector<float> in(kChunk), res(kChunk);
  uint64_t read = 0;
  auto drain = [&]() {
    size_t m;
    while ((m = st.receive(res.data(), res.size())) > 0) {
      size_t from = 0;
      if (skip > 0) {
        from = size_t(std::min<int64_t>(skip, int64_t(m)));
        skip -= int64_t(from);
      }
      for (size_t i = from; i < m; ++i) clip->pcm.push_back(toPcm16(res[i]));
    }
  };
  for (;;) {
    if (w != nullptr && w->cancelled()) return kOk;
    const size_t n = r.read(in.data(), in.size());
    if (n == 0) break;
    read += n;
    st.put(in.data(), n);
    drain();
    if (clip->frames() > maxFrames) return kErrTooLong;
    if (w != nullptr && total > 0) w->setProgress(double(read) / double(total) * 0.98);
  }
  st.flush();
  drain();
  if (clip->frames() <= std::max<int64_t>(0, offset)) return kErrEmpty;
  // Compases enteros: así, al acabar, vuelve a empezar en un 1
  const int64_t bars = (clip->frames() + barFrames - 1) / barFrames;
  if (bars * barFrames > maxFrames + barFrames) return kErrTooLong;
  clip->pcm.resize(size_t(bars * barFrames), 0);
  clip->bars = bars;
  *out = clip.release();
  return kOk;
}

// ---------------------------------------------------------------- consultas

int32_t SongJobs::peaksOf(const Clip& c, int64_t start, int64_t end, int32_t bins, float* out) {
  if (out == nullptr || bins <= 0) return 0;
  start = std::clamp<int64_t>(start, 0, c.frames());
  end = std::clamp<int64_t>(end, start, c.frames());
  const double per = double(end - start) / double(bins);
  for (int32_t b = 0; b < bins; ++b) {
    const int64_t a = start + int64_t(std::floor(per * b));
    int64_t z = start + int64_t(std::floor(per * (b + 1)));
    if (z <= a) z = std::min(a + 1, end);
    int32_t m = 0;
    for (int64_t i = a; i < z; ++i) m = std::max(m, std::abs(int32_t(c.pcm[size_t(i)])));
    out[b] = float(m) / 32768.0f;
  }
  return bins;
}

// Busca el ataque más claro: trocea en bloques de 1 ms, mira cuánto sube
// cada bloque sobre los 6 anteriores y se queda con la mayor subida. Luego
// afina a la muestra: la primera del bloque (o del anterior) que sale del
// nivel que había antes.
int64_t SongJobs::attackNear(const Clip& c, int64_t center, int64_t radius) {
  const int64_t n = c.frames();
  if (n == 0) return -1;
  const int64_t block = std::max<int64_t>(1, c.rate / 1000);
  constexpr int64_t kLook = 6;
  const int64_t from = std::max<int64_t>(0, center - radius - kLook * block);
  const int64_t to = std::min<int64_t>(n, center + radius + block);
  if (to <= from) return std::clamp<int64_t>(center, 0, n - 1);
  const int64_t blocks = (to - from + block - 1) / block;
  std::vector<int32_t> env(size_t(blocks), 0);
  for (int64_t k = 0; k < blocks; ++k) {
    const int64_t a = from + k * block, z = std::min(n, a + block);
    int32_t m = 0;
    for (int64_t i = a; i < z; ++i) m = std::max(m, std::abs(int32_t(c.pcm[size_t(i)])));
    env[size_t(k)] = m;
  }
  int64_t best = -1;
  int32_t bestRise = 0;
  for (int64_t k = kLook; k < blocks; ++k) {
    const int64_t at = from + k * block;
    if (at < center - radius || at > center + radius) continue;
    int32_t before = 0;
    for (int64_t j = k - kLook; j < k; ++j) before = std::max(before, env[size_t(j)]);
    const int32_t rise = env[size_t(k)] - before;
    if (rise > bestRise) {
      bestRise = rise;
      best = k;
    }
  }
  if (best < 0) return std::clamp<int64_t>(center, 0, n - 1);
  int32_t before = 0;
  for (int64_t j = std::max<int64_t>(0, best - kLook); j < best - 1; ++j)
    before = std::max(before, env[size_t(j)]);
  const int32_t level = before + (env[size_t(best)] - before) / 4;
  const int64_t a = from + std::max<int64_t>(0, best - 1) * block;
  const int64_t z = std::min(n, from + (best + 1) * block);
  for (int64_t i = a; i < z; ++i)
    if (std::abs(int32_t(c.pcm[size_t(i)])) > level) return i;
  return from + best * block;
}

// ---------------------------------------------------------------- SongJobs

SongJobs::~SongJobs() {
  opener_.stop();
  preparer_.stop();
}

void SongJobs::open(const std::string& path, int32_t rate, int32_t id) {
  // La que estaba abierta deja de estarlo (se borrará cuando el audio la suelte)
  opener_.stop();
  open_.store(nullptr);
  openFrames_.store(0);
  backing_.previewSlot().offer(nullptr, bin_);
  opener_.run(id, [this, path, rate, id](Worker& w) {
    Clip* clip = nullptr;
    PreviewInfo info;
    const int32_t err = buildPreview(path, rate, id, &clip, &info, &w);
    if (err != kOk || w.cancelled()) {
      delete clip;
      return err;
    }
    openFrames_.store(info.frames);
    bpmGuess_.store(info.bpmGuess);
    firstAttack_.store(info.firstAttack);
    open_.store(clip);
    backing_.previewSlot().offer(clip, bin_);
    return int32_t(kOk);
  });
}

void SongJobs::closeOpen() {
  opener_.stop();
  open_.store(nullptr);
  openFrames_.store(0);
  backing_.previewSlot().offer(nullptr, bin_);
}

uint64_t SongJobs::keyOf(const PrepareParams& p) {
  // FNV-1a de todo lo que cambia el resultado
  uint64_t h = 1469598103934665603ull;
  auto mix = [&h](const void* data, size_t n) {
    const auto* b = static_cast<const unsigned char*>(data);
    for (size_t i = 0; i < n; ++i) {
      h ^= b[i];
      h *= 1099511628211ull;
    }
  };
  mix(p.path.data(), p.path.size());
  mix(&p.songBpm, sizeof(p.songBpm));
  mix(&p.markSeconds, sizeof(p.markSeconds));
  mix(&p.samplesPerBeat, sizeof(p.samplesPerBeat));
  mix(&p.beatsPerBar, sizeof(p.beatsPerBar));
  mix(&p.rate, sizeof(p.rate));
  mix(&p.id, sizeof(p.id));
  return h == 0 ? 1 : h;
}

void SongJobs::prepare(const PrepareParams& p) {
  if (Clip* kept = bin_.takeKept(keyOf(p))) {
    preparer_.finishNow(p.id);
    backing_.songSlot().offer(kept, bin_);
    return;
  }
  preparer_.run(p.id, [this, p](Worker& w) {
    Clip* clip = nullptr;
    const int32_t err = buildBacking(p, &clip, &w);
    if (err != kOk || w.cancelled()) {
      delete clip;
      return err;
    }
    backing_.songSlot().offer(clip, bin_);
    return int32_t(kOk);
  });
}

void SongJobs::unload() {
  preparer_.stop();
  backing_.songSlot().offer(nullptr, bin_);
}

PreviewInfo SongJobs::previewInfo() const {
  PreviewInfo i;
  i.frames = openFrames_.load();
  i.bpmGuess = bpmGuess_.load();
  i.firstAttack = firstAttack_.load();
  return i;
}

int32_t SongJobs::peaks(int64_t start, int64_t end, int32_t bins, float* out) const {
  const Clip* c = open_.load();
  return c == nullptr ? 0 : peaksOf(*c, start, end, bins, out);
}

int64_t SongJobs::findAttack(int64_t center, int64_t radius) const {
  const Clip* c = open_.load();
  return c == nullptr ? -1 : attackNear(*c, center, radius);
}

}  // namespace loopin
