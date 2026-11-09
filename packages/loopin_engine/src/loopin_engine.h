// Loopin — motor de audio
// Copyright (C) 2026 Alex
// SPDX-License-Identifier: GPL-3.0-or-later
//
// API en C plana que Dart llama con dart:ffi.
// Todas las funciones se llaman desde el mismo hilo (el isolate principal de
// Flutter). Ninguna bloquea al hilo de audio: las órdenes viajan por una cola
// sin bloqueos y el estado vuelve por variables atómicas.

#ifndef LOOPIN_ENGINE_H
#define LOOPIN_ENGINE_H

#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Estado del test de latencia
#define LOOPIN_LATENCY_IDLE 0
#define LOOPIN_LATENCY_RUNNING 1
#define LOOPIN_LATENCY_DONE 2
#define LOOPIN_LATENCY_FAILED 3

// Modo del micrófono (valores de Android / Oboe InputPreset)
#define LOOPIN_PRESET_GENERIC 1
#define LOOPIN_PRESET_CAMCORDER 5
#define LOOPIN_PRESET_VOICE_RECOGNITION 6
#define LOOPIN_PRESET_UNPROCESSED 9
#define LOOPIN_PRESET_VOICE_PERFORMANCE 10

// API de audio que Oboe ha elegido
#define LOOPIN_API_UNKNOWN 0
#define LOOPIN_API_OPENSLES 1
#define LOOPIN_API_AAUDIO 2

typedef struct {
  // Stream
  int32_t running;            // 1 si el audio está funcionando
  int32_t sample_rate;        // Hz
  int32_t frames_per_burst;   // tamaño del bloque del dispositivo
  int32_t buffer_size_frames; // tamaño del buffer de salida en uso
  int32_t audio_api;          // LOOPIN_API_*
  int32_t exclusive;          // 1 = modo exclusivo (menos latencia)
  int32_t low_latency;        // 1 = ruta de baja latencia concedida
  int32_t input_channels;
  int32_t output_channels;
  int32_t input_preset;       // LOOPIN_PRESET_* que está usando la entrada
  int32_t preset_fallback;    // 1 si el modo pedido falló y se usó otro
  int32_t xrun_count;         // cortes de la salida (-1 si no se sabe)
  int32_t disconnected;       // 1 si se desconectó un dispositivo
  double output_latency_ms;   // estimación de Oboe (-1 si no se sabe)
  double input_latency_ms;    // estimación de Oboe (-1 si no se sabe)

  // Transporte / metrónomo
  int32_t playing;
  int32_t bar;                // compás actual (empieza en 0)
  int32_t beat;               // tiempo dentro del compás (empieza en 0)
  int32_t beats_per_bar;
  int32_t samples_per_beat;
  double bpm;
  int64_t frame_position;     // muestras desde que arrancó el transporte

  // Entrada
  float input_peak;           // 0..1, con caída lenta

  // Test de latencia (ida y vuelta)
  int32_t latency_state;      // LOOPIN_LATENCY_*
  int32_t latency_progress;   // clics detectados hasta ahora
  int32_t latency_frames;     // resultado en muestras
  double latency_ms;          // resultado en ms
} LoopinStatus;

// Abre los streams de entrada y salida y empieza a procesar audio.
// Devuelve 0 si todo va bien o un código de error de Oboe (negativo).
FFI_PLUGIN_EXPORT int32_t loopin_start(void);
FFI_PLUGIN_EXPORT void loopin_stop(void);

// Transporte (metrónomo en marcha o parado)
FFI_PLUGIN_EXPORT void loopin_play(void);
FFI_PLUGIN_EXPORT void loopin_pause(void);
FFI_PLUGIN_EXPORT void loopin_set_bpm(double bpm);
// beats_per_bar: 4 (4/4), 3 (3/4) o 6 (6/8, el tiempo es la corchea)
FFI_PLUGIN_EXPORT void loopin_set_beats_per_bar(int32_t beats_per_bar);

// Metrónomo
FFI_PLUGIN_EXPORT void loopin_set_click_enabled(int32_t enabled);
FFI_PLUGIN_EXPORT void loopin_set_click_volume(float volume);

// Entrada. El modo del micrófono se aplica al abrir el audio (loopin_start).
// Por defecto LOOPIN_PRESET_UNPROCESSED: sin control automático de ganancia ni
// filtros, lo mejor para grabar un instrumento.
FFI_PLUGIN_EXPORT void loopin_set_input_preset(int32_t preset);
// Ganancia lineal aplicada a la entrada (1.0 = 0 dB), antes del monitor y de
// lo que se grabe.
FFI_PLUGIN_EXPORT void loopin_set_input_gain(float gain);

// Monitor: escuchar la entrada en directo
FFI_PLUGIN_EXPORT void loopin_set_monitor_enabled(int32_t enabled);
FFI_PLUGIN_EXPORT void loopin_set_monitor_volume(float volume);

// Mide la latencia de ida y vuelta emitiendo clics y detectándolos en la entrada.
FFI_PLUGIN_EXPORT void loopin_measure_latency(void);

// Copia el estado actual en *out.
FFI_PLUGIN_EXPORT void loopin_get_status(LoopinStatus* out);

#ifdef __cplusplus
}
#endif

#endif  // LOOPIN_ENGINE_H
