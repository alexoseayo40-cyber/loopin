# Loopin — tests del motor que se ejecutan en el PC (sin móvil)
# Uso:
#   cmake -S engine_tests -B build/engine_tests
#   cmake --build build/engine_tests
#   ./build/engine_tests/loopin_engine_tests
cmake_minimum_required(VERSION 3.16)
project(loopin_engine_tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(SRC ${CMAKE_CURRENT_SOURCE_DIR}/../packages/loopin_engine/src)

add_executable(loopin_engine_tests
  tests.cpp
  looper_tests.cpp
  drum_tests.cpp
  ${SRC}/Drums.cpp
  ${SRC}/EngineCore.cpp
  ${SRC}/LatencyMeter.cpp
  ${SRC}/Looper.cpp
  ${SRC}/LooperBuffers.cpp
  ${SRC}/LooperRecord.cpp
  ${SRC}/Metronome.cpp
  ${SRC}/TapCalibrator.cpp
  ${SRC}/Transport.cpp
)
target_include_directories(loopin_engine_tests PRIVATE ${SRC})
find_package(Threads REQUIRED)
target_link_libraries(loopin_engine_tests PRIVATE Threads::Threads)
if(MSVC)
  target_compile_options(loopin_engine_tests PRIVATE /W4)
else()
  target_compile_options(loopin_engine_tests PRIVATE -Wall -Wextra -O2)
endif()

# Demo de la batería (no es un test): drum_demo app/assets/drums <salida>
add_executable(drum_demo drum_demo.cpp ${SRC}/Drums.cpp ${SRC}/EngineCore.cpp ${SRC}/Transport.cpp
  ${SRC}/Metronome.cpp ${SRC}/LatencyMeter.cpp ${SRC}/TapCalibrator.cpp ${SRC}/Looper.cpp
  ${SRC}/LooperRecord.cpp ${SRC}/LooperBuffers.cpp)
target_include_directories(drum_demo PRIVATE ${SRC})
