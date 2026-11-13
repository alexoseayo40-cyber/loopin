// Loopin — demo de la batería: renderiza cada estilo a un WAV (no es un test)
// Uso: drum_demo <carpeta con los WAV de app/assets/drums> <carpeta de salida>
// SPDX-License-Identifier: GPL-3.0-or-later
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "EngineCore.h"

using namespace loopin;
using T = Command::Type;

namespace {

// Lee un WAV mono de 16 bits (los de assets/drums)
std::vector<float> readWav(const std::string& path, int32_t& rate) {
  std::vector<float> out;
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) return out;
  std::vector<uint8_t> b;
  uint8_t buf[4096];
  size_t n;
  while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) b.insert(b.end(), buf, buf + n);
  std::fclose(f);
  size_t p = 12;
  while (p + 8 <= b.size()) {
    uint32_t len;
    std::memcpy(&len, &b[p + 4], 4);
    if (std::memcmp(&b[p], "fmt ", 4) == 0) std::memcpy(&rate, &b[p + 12], 4);
    if (std::memcmp(&b[p], "data", 4) == 0) {
      for (size_t i = p + 8; i + 1 < p + 8 + len && i + 1 < b.size(); i += 2) {
        int16_t s;
        std::memcpy(&s, &b[i], 2);
        out.push_back(float(s) / 32768.0f);
      }
      break;
    }
    p += 8 + len + (len & 1);
  }
  return out;
}

void writeWav(const std::string& path, const std::vector<float>& x, int32_t rate) {
  FILE* f = std::fopen(path.c_str(), "wb");
  const uint32_t data = uint32_t(x.size() * 2), riff = 36 + data, fmt = 16, br = rate * 2;
  const uint16_t pcm = 1, ch = 1, align = 2, bits = 16;
  std::fwrite("RIFF", 1, 4, f); std::fwrite(&riff, 4, 1, f); std::fwrite("WAVEfmt ", 1, 8, f);
  std::fwrite(&fmt, 4, 1, f); std::fwrite(&pcm, 2, 1, f); std::fwrite(&ch, 2, 1, f);
  std::fwrite(&rate, 4, 1, f); std::fwrite(&br, 4, 1, f); std::fwrite(&align, 2, 1, f);
  std::fwrite(&bits, 2, 1, f); std::fwrite("data", 1, 4, f); std::fwrite(&data, 4, 1, f);
  for (float v : x) {
    const int16_t s = int16_t(std::max(-1.0f, std::min(1.0f, v)) * 32767.0f);
    std::fwrite(&s, 2, 1, f);
  }
  std::fclose(f);
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) return 1;
  const std::string in = argv[1], out = argv[2];
  const char* names[] = {"kick", "snare", "snare_soft", "xstick", "hat",
                         "hat_soft", "hat_open", "ride", "crash", "sticks"};
  struct Demo { const char* file; int style, beats; uint32_t mask; bool eighths; double bpm; };
  const Demo demos[] = {
      {"basico_4-4", 0, 4, 0, false, 100},   {"rock", 1, 4, 0, false, 110},
      {"pop", 2, 4, 0, false, 100},          {"blues_shuffle", 3, 4, 0, false, 96},
      {"funk", 4, 4, 0, false, 98},          {"balada", 5, 4, 0, false, 72},
      {"reggae", 6, 4, 0, false, 76},        {"vals_3-4", 7, 3, 0, false, 140},
      {"6-8", 8, 6, 1u << 3, true, 180},     {"blues_lento_12-8", 9, 12, 0x248, true, 170},
      {"basico_7-8", 0, 7, (1u << 2) | (1u << 4), true, 220},
  };
  for (const Demo& d : demos) {
    EngineCore core;
    for (int i = 0; i < int(DrumSound::kCount); ++i) {
      int32_t rate = 48000;
      std::vector<float> s = readWav(in + "/" + names[i] + ".wav", rate);
      core.setDrumSample(DrumSound(i), s.data(), int32_t(s.size()), rate);
    }
    core.prepare(48000);
    core.post({T::kSetMeter, double(d.beats), int32_t(d.mask)});
    core.post({T::kSetBpm, d.bpm});
    core.post({T::kSetClickMode, 1});
    core.post({T::kSetDrumStyle, double(d.style), d.eighths ? 1 : 0});
    core.post({T::kSetDrumsEnabled, 1});
    core.post({T::kSetSyncBars, 4});
    core.post({T::kLoopPress});  // cuenta con baquetas y luego la batería
    const int64_t frames = int64_t(48000 * 60.0 / d.bpm * d.beats * 5 + 48000);
    std::vector<float> wav, inBuf(256, 0.0f), outBuf(512);
    for (int64_t n = 0; n < frames; n += 256) {
      core.process(inBuf.data(), 256, 1, outBuf.data(), 256, 2);
      for (int i = 0; i < 256; ++i) wav.push_back(outBuf[size_t(i) * 2]);
    }
    writeWav(out + "/" + d.file + ".wav", wav, 48000);
    std::printf("%s\n", d.file);
  }
  return 0;
}
