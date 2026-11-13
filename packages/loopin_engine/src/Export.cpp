// Loopin — exportar la sesión a WAV
// SPDX-License-Identifier: GPL-3.0-or-later
#include "Export.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <new>

#if defined(__linux__)
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

namespace loopin {

namespace {

using T = Command::Type;

void post(EngineCore& core, T type, double value = 0.0, int32_t arg = 0) {
  Command c;
  c.type = type;
  c.value = value;
  c.arg = arg;
  core.post(c);
}

// Aplica las órdenes pendientes sin avanzar el tiempo
void flush(EngineCore& core) {
  float dummy = 0.0f;
  core.process(nullptr, 0, 1, &dummy, 0, 1);
}

void put16(std::FILE* f, uint16_t v) {
  const unsigned char b[2] = {static_cast<unsigned char>(v & 0xff),
                              static_cast<unsigned char>(v >> 8)};
  std::fwrite(b, 1, 2, f);
}
void put32(std::FILE* f, uint32_t v) {
  const unsigned char b[4] = {static_cast<unsigned char>(v & 0xff),
                              static_cast<unsigned char>((v >> 8) & 0xff),
                              static_cast<unsigned char>((v >> 16) & 0xff),
                              static_cast<unsigned char>(v >> 24)};
  std::fwrite(b, 1, 4, f);
}

// Escribe la cabecera de un WAV mono de 16 bits con frames muestras
void wavHeader(std::FILE* f, int32_t rate, int64_t frames) {
  const uint32_t data = static_cast<uint32_t>(frames * 2);
  std::fwrite("RIFF", 1, 4, f);
  put32(f, 36 + data);
  std::fwrite("WAVEfmt ", 1, 8, f);
  put32(f, 16);
  put16(f, 1);  // PCM
  put16(f, 1);  // mono
  put32(f, static_cast<uint32_t>(rate));
  put32(f, static_cast<uint32_t>(rate) * 2);
  put16(f, 2);
  put16(f, 16);
  std::fwrite("data", 1, 4, f);
  put32(f, data);
}

struct Output {
  enum Kind { kMix, kTrack, kDrums, kSong } kind;
  int32_t track;
  std::string path;
};

}  // namespace

bool Exporter::writeWav(const std::string& path, const std::vector<int16_t>& pcm, int32_t rate) {
  std::FILE* f = std::fopen(path.c_str(), "wb");
  if (f == nullptr) return false;
  wavHeader(f, rate, int64_t(pcm.size()));
  for (int16_t s : pcm) put16(f, static_cast<uint16_t>(s));
  const bool ok = std::ferror(f) == 0;
  return std::fclose(f) == 0 && ok;
}

int32_t Exporter::run(EngineCore& core, ExportSpec& spec, const std::atomic<bool>* cancel,
                      std::atomic<int32_t>* progress, int64_t* framesOut) {
  const SessionSpec& s = spec.session;
  const int32_t rate = s.sampleRate > 0 ? s.sampleRate : 48000;
  int64_t maxLen = 0;
  for (int32_t i = 0; i < Looper::kTracks; ++i) maxLen = std::max(maxLen, s.len[i]);
  if (maxLen <= 0) return kErrNothing;
  const int32_t loops = std::clamp(spec.loops, 1, 64);
  const int64_t total = maxLen * loops;
  if (framesOut != nullptr) *framesOut = total;

  // Un núcleo sin audio, con las pistas justas
  core.prepare(rate, static_cast<int32_t>(maxLen / rate) + 1);
  core.setClampOutput(false);
  post(core, T::kSetClickMode, 0);  // el clic no se exporta
  post(core, T::kSetMonitorEnabled, 0);
  post(core, T::kSetQuantize, 0);
  post(core, T::kSetLoopVolume, 1.0);
  post(core, T::kSetRecordDuck, 1.0);
  flush(core);
  const float* data[Looper::kTracks] = {};
  for (int32_t i = 0; i < Looper::kTracks; ++i)
    data[i] = s.len[i] > 0 && int64_t(spec.data[i].size()) >= s.len[i] ? spec.data[i].data() : nullptr;
  if (core.loadSession(s, data) != EngineCore::kSessionOk) return kErrLoad;
  flush(core);
  if (core.looper().state() != Looper::State::kStopped) return kErrLoad;
  // Ya están en el núcleo: la copia sobra
  for (auto& d : spec.data) std::vector<float>().swap(d);

  for (int32_t i = 0; i < Looper::kTracks; ++i) {
    post(core, T::kSetTrackVolume, spec.volume[i], i);
    post(core, T::kSetTrackReverse, spec.reverse[i] ? 1 : 0, i);
    post(core, T::kSetTrackHalf, spec.half[i] ? 1 : 0, i);
  }
  post(core, T::kSetDrumStyle, static_cast<int32_t>(spec.drumStyle), spec.beatIsEighth ? 1 : 0);
  post(core, T::kSetDrumVolume, spec.drumVolume);
  post(core, T::kSetBackingVolume, spec.songVolume);
  const bool hasSong = spec.song != nullptr;
  if (hasSong) core.backing().songSlot().offer(spec.song.release(), core.clipBin());
  flush(core);

  std::vector<Output> outs;
  if (!spec.mixPath.empty()) outs.push_back({Output::kMix, -1, spec.mixPath});
  for (int32_t i = 0; i < Looper::kTracks; ++i)
    if (!spec.trackPath[i].empty() && s.len[i] > 0)
      outs.push_back({Output::kTrack, i, spec.trackPath[i]});
  if (spec.drums && !spec.drumsPath.empty()) outs.push_back({Output::kDrums, -1, spec.drumsPath});
  if (hasSong && !spec.songPath.empty()) outs.push_back({Output::kSong, -1, spec.songPath});
  if (outs.empty()) return kErrNothing;

  constexpr int32_t kBlock = 1024;
  std::vector<float> out(kBlock, 0.0f);
  std::vector<float> zeros(kBlock, 0.0f);
  std::vector<int16_t> pcm(kBlock, 0);
  const double work = 2.0 * double(outs.size()) * double(total);
  double done = 0.0;
  float peak = 0.0f;
  float gain = 1.0f;

  for (int32_t pass = 0; pass < 2; ++pass) {
    if (pass == 1) gain = peak > 0.98f ? 0.98f / peak : 1.0f;
    for (const Output& o : outs) {
      // Qué suena en esta: la mezcla, como se oye; las demás, solas
      for (int32_t i = 0; i < Looper::kTracks; ++i) {
        const bool muted = o.kind == Output::kMix ? spec.muted[i]
                           : o.kind == Output::kTrack ? i != o.track
                                                      : true;
        post(core, T::kSetTrackMuted, muted ? 1 : 0, i);
      }
      post(core, T::kSetDrumsEnabled,
           (o.kind == Output::kMix && spec.drums) || o.kind == Output::kDrums ? 1 : 0);
      post(core, T::kSetBackingEnabled,
           (o.kind == Output::kMix && hasSong) || o.kind == Output::kSong ? 1 : 0);
      post(core, T::kPlay);

      std::FILE* f = nullptr;
      if (pass == 1) {
        f = std::fopen(o.path.c_str(), "wb");
        if (f == nullptr) return kErrWrite;
        wavHeader(f, rate, total);
      }
      for (int64_t pos = 0; pos < total; pos += kBlock) {
        if (cancel != nullptr && cancel->load(std::memory_order_relaxed)) {
          if (f != nullptr) std::fclose(f);
          return 0;
        }
        const int32_t n = static_cast<int32_t>(std::min<int64_t>(kBlock, total - pos));
        core.process(zeros.data(), n, 1, out.data(), n, 1);
        if (pass == 0) {
          for (int32_t k = 0; k < n; ++k) peak = std::max(peak, std::fabs(out[k]));
        } else {
          for (int32_t k = 0; k < n; ++k) {
            const float x = std::clamp(out[k] * gain, -1.0f, 1.0f);
            pcm[k] = static_cast<int16_t>(std::lrint(x * 32767.0f));
          }
          std::fwrite(pcm.data(), sizeof(int16_t), static_cast<size_t>(n), f);
        }
        done += n;
        if (progress != nullptr)
          progress->store(static_cast<int32_t>(1000.0 * done / work), std::memory_order_relaxed);
      }
      if (f != nullptr) {
        const bool ok = std::ferror(f) == 0;
        if (std::fclose(f) != 0 || !ok) return kErrWrite;
      }
      // Se para y se corta lo que aún suena: la siguiente empieza en limpio
      post(core, T::kPause);
      flush(core);
      core.silenceTails();
      core.process(zeros.data(), kBlock, 1, out.data(), kBlock, 1);
    }
  }
  return 0;
}

Exporter::~Exporter() {
  cancel();
  join();
}

void Exporter::join() {
  if (thread_.joinable()) thread_.join();
}

void Exporter::cancel() { cancel_.store(true, std::memory_order_relaxed); }

bool Exporter::start(ExportSpec spec, const EngineCore& kitFrom) {
  if (state() == kRunning) return false;
  join();
  cancel_.store(false);
  progress_.store(0, std::memory_order_relaxed);
  error_.store(0, std::memory_order_relaxed);
  frames_.store(0, std::memory_order_relaxed);
  std::unique_ptr<EngineCore> core;
  try {
    core = std::make_unique<EngineCore>();
  } catch (const std::bad_alloc&) {
    error_.store(kErrMemory, std::memory_order_relaxed);
    state_.store(kFailed, std::memory_order_release);
    return true;
  }
  core->copyDrumKit(kitFrom);  // aquí: el kit solo cambia en este hilo
  state_.store(kRunning, std::memory_order_release);
  thread_ = std::thread([this, core = std::move(core), spec = std::move(spec)]() mutable {
#if defined(__linux__)
    setpriority(PRIO_PROCESS, static_cast<id_t>(syscall(SYS_gettid)), 10);
#endif
    int32_t err = 0;
    int64_t frames = 0;
    try {
      err = run(*core, spec, &cancel_, &progress_, &frames);
    } catch (const std::bad_alloc&) {
      err = kErrMemory;
    } catch (...) {
      err = kErrWrite;
    }
    core.reset();
    frames_.store(frames, std::memory_order_relaxed);
    const bool cancelled = cancel_.load(std::memory_order_relaxed);
    if (err != 0 || cancelled) {
      // Lo que se haya escrito a medias, fuera
      std::remove(spec.mixPath.c_str());
      for (const std::string& p : spec.trackPath) std::remove(p.c_str());
      std::remove(spec.drumsPath.c_str());
      std::remove(spec.songPath.c_str());
    }
    error_.store(err, std::memory_order_relaxed);
    if (!cancelled && err == 0) progress_.store(1000, std::memory_order_relaxed);
    state_.store(cancelled ? kIdle : (err == 0 ? kDone : kFailed), std::memory_order_release);
  });
  return true;
}

}  // namespace loopin
