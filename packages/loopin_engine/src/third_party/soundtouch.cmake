# SoundTouch 2.4.1 (LGPL 2.1, ver soundtouch/COPYING.TXT): estirar el audio
# importado sin cambiar el tono. Copia de las fuentes de
# https://codeberg.org/soundtouch/soundtouch (solo lo que se usa).
# Lo incluyen el motor (CMakeLists.txt de src) y los tests del PC.
set(SOUNDTOUCH_DIR ${CMAKE_CURRENT_LIST_DIR}/soundtouch)
add_library(loopin_soundtouch STATIC
  ${SOUNDTOUCH_DIR}/source/AAFilter.cpp
  ${SOUNDTOUCH_DIR}/source/BPMDetect.cpp
  ${SOUNDTOUCH_DIR}/source/FIFOSampleBuffer.cpp
  ${SOUNDTOUCH_DIR}/source/FIRFilter.cpp
  ${SOUNDTOUCH_DIR}/source/InterpolateCubic.cpp
  ${SOUNDTOUCH_DIR}/source/InterpolateLinear.cpp
  ${SOUNDTOUCH_DIR}/source/InterpolateShannon.cpp
  ${SOUNDTOUCH_DIR}/source/PeakFinder.cpp
  ${SOUNDTOUCH_DIR}/source/RateTransposer.cpp
  ${SOUNDTOUCH_DIR}/source/SoundTouch.cpp
  ${SOUNDTOUCH_DIR}/source/TDStretch.cpp
  ${SOUNDTOUCH_DIR}/source/cpu_detect_x86.cpp
  ${SOUNDTOUCH_DIR}/source/sse_optimized.cpp
)
target_include_directories(loopin_soundtouch PUBLIC ${SOUNDTOUCH_DIR}/include)
target_compile_definitions(loopin_soundtouch PUBLIC SOUNDTOUCH_FLOAT_SAMPLES=1)
set_target_properties(loopin_soundtouch PROPERTIES POSITION_INDEPENDENT_CODE ON)
if(MSVC)
  target_compile_options(loopin_soundtouch PRIVATE /w)
else()
  target_compile_options(loopin_soundtouch PRIVATE -w -O3)
endif()
