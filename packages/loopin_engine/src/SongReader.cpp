// Loopin — lectura de archivos de audio con dr_libs
// SPDX-License-Identifier: GPL-3.0-or-later
#include "SongReader.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

// dr_libs: una sola implementación de cada uno, aquí
#define DR_WAV_IMPLEMENTATION
#define DR_MP3_IMPLEMENTATION
#define DR_FLAC_IMPLEMENTATION
#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wunused-parameter"
#pragma GCC diagnostic ignored "-Wsign-compare"
#pragma GCC diagnostic ignored "-Wimplicit-fallthrough"
#endif
#include "third_party/dr_libs/dr_flac.h"
#include "third_party/dr_libs/dr_mp3.h"
#include "third_party/dr_libs/dr_wav.h"
#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic pop
#endif

namespace loopin {

struct SongReader::Impl {
  drwav wav{};
  drmp3 mp3{};
  drflac* flac = nullptr;
};

SongReader::SongReader() : impl_(std::make_unique<Impl>()) {}

SongReader::~SongReader() { close(); }

namespace {

// Los primeros bytes dicen qué es (las extensiones engañan)
SongReader::Format sniff(const std::string& path) {
  unsigned char h[12] = {};
  FILE* f = std::fopen(path.c_str(), "rb");
  if (f == nullptr) return SongReader::Format::kNone;
  const size_t n = std::fread(h, 1, sizeof(h), f);
  std::fclose(f);
  if (n >= 12 && (std::memcmp(h, "RIFF", 4) == 0 || std::memcmp(h, "RF64", 4) == 0) &&
      std::memcmp(h + 8, "WAVE", 4) == 0)
    return SongReader::Format::kWav;
  if (n >= 4 && std::memcmp(h, "fLaC", 4) == 0) return SongReader::Format::kFlac;
  if (n >= 3 && std::memcmp(h, "ID3", 3) == 0) return SongReader::Format::kMp3;
  if (n >= 2 && h[0] == 0xFF && (h[1] & 0xE0) == 0xE0) return SongReader::Format::kMp3;
  // Un FLAC con etiquetas ID3 delante, o algo raro: se prueba más abajo
  return SongReader::Format::kNone;
}

}  // namespace

bool SongReader::open(const std::string& path) {
  close();
  Format guess = sniff(path);
  auto tryWav = [&]() {
    if (!drwav_init_file(&impl_->wav, path.c_str(), nullptr)) return false;
    format_ = Format::kWav;
    rate_ = int32_t(impl_->wav.sampleRate);
    channels_ = int32_t(impl_->wav.channels);
    frames_ = impl_->wav.totalPCMFrameCount;
    return true;
  };
  auto tryFlac = [&]() {
    impl_->flac = drflac_open_file(path.c_str(), nullptr);
    if (impl_->flac == nullptr) return false;
    format_ = Format::kFlac;
    rate_ = int32_t(impl_->flac->sampleRate);
    channels_ = int32_t(impl_->flac->channels);
    frames_ = impl_->flac->totalPCMFrameCount;
    return true;
  };
  auto tryMp3 = [&]() {
    if (!drmp3_init_file(&impl_->mp3, path.c_str(), nullptr)) return false;
    format_ = Format::kMp3;
    rate_ = int32_t(impl_->mp3.sampleRate);
    channels_ = int32_t(impl_->mp3.channels);
    // Recorre el archivo (sin sintetizar el sonido) y vuelve al principio
    frames_ = drmp3_get_pcm_frame_count(&impl_->mp3);
    drmp3_seek_to_pcm_frame(&impl_->mp3, 0);
    return true;
  };
  bool ok = false;
  switch (guess) {
    case Format::kWav: ok = tryWav(); break;
    case Format::kFlac: ok = tryFlac(); break;
    case Format::kMp3: ok = tryMp3(); break;
    case Format::kNone: ok = tryWav() || tryFlac() || tryMp3(); break;
  }
  if (!ok || rate_ <= 0 || channels_ <= 0) {
    close();
    return false;
  }
  return true;
}

void SongReader::close() {
  switch (format_) {
    case Format::kWav: drwav_uninit(&impl_->wav); break;
    case Format::kMp3: drmp3_uninit(&impl_->mp3); break;
    case Format::kFlac:
      drflac_close(impl_->flac);
      impl_->flac = nullptr;
      break;
    case Format::kNone: break;
  }
  format_ = Format::kNone;
  rate_ = channels_ = 0;
  frames_ = 0;
}

size_t SongReader::read(float* mono, size_t maxFrames) {
  if (format_ == Format::kNone || maxFrames == 0) return 0;
  const size_t ch = size_t(channels_);
  if (interleaved_.size() < maxFrames * ch) interleaved_.resize(maxFrames * ch);
  float* buf = ch == 1 ? mono : interleaved_.data();
  uint64_t got = 0;
  switch (format_) {
    case Format::kWav: got = drwav_read_pcm_frames_f32(&impl_->wav, maxFrames, buf); break;
    case Format::kMp3: got = drmp3_read_pcm_frames_f32(&impl_->mp3, maxFrames, buf); break;
    case Format::kFlac: got = drflac_read_pcm_frames_f32(impl_->flac, maxFrames, buf); break;
    case Format::kNone: break;
  }
  if (ch > 1) {
    // Mezcla en mono: la media de los canales (así no se sale de rango)
    const float k = 1.0f / float(ch);
    for (size_t i = 0; i < got; ++i) {
      float s = 0.0f;
      for (size_t c = 0; c < ch; ++c) s += buf[i * ch + c];
      mono[i] = s * k;
    }
  }
  return size_t(got);
}

}  // namespace loopin
