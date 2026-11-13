// Loopin — utilidades de los tests del motor
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <cstdint>
#include <cstdio>
#include <random>

inline int gFailures = 0;
#define CHECK(cond)                                                     \
  do {                                                                  \
    if (!(cond)) {                                                      \
      std::printf("  FALLO %s:%d: %s\n", __FILE__, __LINE__, #cond);    \
      ++gFailures;                                                      \
    }                                                                   \
  } while (0)
#define CHECK_EQ(a, b)                                                                \
  do {                                                                                \
    const long long _a = (long long)(a), _b = (long long)(b);                         \
    if (_a != _b) {                                                                   \
      std::printf("  FALLO %s:%d: %s == %s (%lld != %lld)\n", __FILE__, __LINE__, #a, \
                  #b, _a, _b);                                                        \
      ++gFailures;                                                                    \
    }                                                                                 \
  } while (0)


// Tamaños de bloque variables, como los que da Android
inline int32_t randomBlock(std::mt19937& rng) {
  static const int32_t sizes[] = {48, 96, 128, 144, 192, 240, 256, 480, 512, 960, 1024};
  return sizes[rng() % (sizeof(sizes) / sizeof(sizes[0]))];
}

void runLooperTests();
void runDrumTests();
void runSongTests();
void runLiveTests();
