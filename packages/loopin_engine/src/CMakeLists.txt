# Loopin — motor de audio (libloopin_engine.so)
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.22.1)
project(loopin_engine_library VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Núcleo independiente de Oboe (también lo compilan los tests del PC)
set(LOOPIN_CORE_SOURCES
  ${CMAKE_CURRENT_SOURCE_DIR}/Drums.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/EngineCore.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/LatencyMeter.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/Looper.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/LooperBuffers.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/LooperRecord.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/Metronome.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/TapCalibrator.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/Transport.cpp
)

# Oboe desde el submódulo de git (código fuente, como pide F-Droid)
set(OBOE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/oboe)
add_subdirectory(${OBOE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/oboe-bin)

add_library(loopin_engine SHARED
  ${LOOPIN_CORE_SOURCES}
  AudioEngine.cpp
  loopin_engine.cpp
)

set_target_properties(loopin_engine PROPERTIES
  PUBLIC_HEADER loopin_engine.h
  OUTPUT_NAME "loopin_engine"
)

target_include_directories(loopin_engine PRIVATE ${OBOE_DIR}/include)
target_compile_definitions(loopin_engine PUBLIC DART_SHARED_LIB)
target_compile_options(loopin_engine PRIVATE -Wall -Wextra "$<$<CONFIG:Release>:-O3>")
target_link_libraries(loopin_engine PRIVATE oboe android log)

# Páginas de 16 KB (obligatorio para Android 15+ en Google Play)
target_link_options(loopin_engine PRIVATE "-Wl,-z,max-page-size=16384")
