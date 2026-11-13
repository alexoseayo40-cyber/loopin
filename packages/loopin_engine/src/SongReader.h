// Loopin — lee un archivo de audio (WAV, MP3 o FLAC) a trozos, en mono
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace loopin {

// Decodifica con dr_libs (dominio público / MIT-0). El formato se mira por el
// contenido, no por la extensión. Si tiene varios canales, se mezclan en uno.
// No es para el hilo de audio: reserva memoria y lee del disco.
class SongReader {
 public:
  SongReader();
  ~SongReader();
  SongReader(const SongReader&) = delete;
  SongReader& operator=(const SongReader&) = delete;

  enum class Format { kNone, kWav, kMp3, kFlac };

  bool open(const std::string& path);
  void close();

  Format format() const { return format_; }
  int32_t sampleRate() const { return rate_; }
  int32_t channels() const { return channels_; }
  // Muestras (por canal) que tiene; 0 si no se sabe.
  uint64_t frames() const { return frames_; }

  // Lee hasta maxFrames muestras en mono. Devuelve cuántas (0 = se acabó).
  size_t read(float* mono, size_t maxFrames);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
  Format format_ = Format::kNone;
  int32_t rate_ = 0;
  int32_t channels_ = 0;
  uint64_t frames_ = 0;
  std::vector<float> interleaved_;
};

}  // namespace loopin
