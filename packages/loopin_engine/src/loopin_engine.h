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

// Número de pistas del looper
#define LOOPIN_TRACKS 4

// Estado del looper (y de cada pista)
#define LOOPIN_LOOP_EMPTY 0
#define LOOPIN_LOOP_ARMED 1      // cuenta de entrada / esperando al compás
#define LOOPIN_LOOP_RECORDING 2
#define LOOPIN_LOOP_PLAYING 3
#define LOOPIN_LOOP_OVERDUBBING 4
#define LOOPIN_LOOP_STOPPED 5

// Modo de grabación
#define LOOPIN_MODE_SYNC 0    // cuenta de entrada y N compases
#define LOOPIN_MODE_MANUAL 1  // se cierra al pulsar

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
  int32_t input_device_id;    // id del dispositivo de entrada en uso (Android)
  int32_t output_device_id;   // id del dispositivo de salida en uso
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

  // Entrada (diagnóstico de latencia)
  int32_t input_frames_per_burst;
  int32_t input_buffer_frames;
  int32_t input_exclusive;
  int32_t input_low_latency;
  int32_t input_max_read;     // máx. muestras leídas en un callback (últimos ~2 s)

  // Looper. loop_layers, loop_length y loop_position son de la pista seleccionada.
  int32_t loop_state;         // LOOPIN_LOOP_* (estado general)
  int32_t loop_mode;          // LOOPIN_MODE_*
  int32_t loop_sync_bars;     // compases del modo sincronizado
  int32_t loop_layers;        // capas que suenan (la primera grabación cuenta como 1)
  int32_t loop_can_undo;
  int32_t loop_latency_frames;  // compensación que se está aplicando
  int64_t loop_length;        // muestras (0 = sin loop)
  int64_t loop_position;      // posición de reproducción en muestras
  int64_t loop_recorded;      // armado: negativo (falta para grabar); grabando: grabado
  int64_t loop_target;        // grabando: longitud a la que se cerrará (0 = abierta)
  int64_t loop_bar_frames;    // muestras por compás del loop

  // Pistas
  int32_t loop_selected;      // pista que usará el siguiente toque (0..3)
  int32_t loop_active;        // pista en la que se graba (-1 si ninguna)
  int32_t loop_auto_advance;  // 1 = tras grabar una pista se elige la siguiente vacía
  int64_t loop_base_length;   // duración base en muestras (0 = no hay loops)
  int64_t loop_base_position; // posición dentro del ciclo base
  int32_t track_state[LOOPIN_TRACKS];   // LOOPIN_LOOP_*
  int32_t track_layers[LOOPIN_TRACKS];
  int32_t track_muted[LOOPIN_TRACKS];
  float track_volume[LOOPIN_TRACKS];
  int64_t track_length[LOOPIN_TRACKS];  // 1, 2 o 4 veces la base (0 = vacía)
  int64_t track_position[LOOPIN_TRACKS];
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
// Dispositivo de entrada (id de AudioDeviceInfo de Android). 0 = el que elija
// Android. Se aplica al abrir el audio. Si ese dispositivo ya no existe, se usa
// el de Android.
FFI_PLUGIN_EXPORT void loopin_set_input_device(int32_t device_id);
// Ganancia lineal aplicada a la entrada (1.0 = 0 dB), antes del monitor y de
// lo que se grabe.
FFI_PLUGIN_EXPORT void loopin_set_input_gain(float gain);

// Monitor: escuchar la entrada en directo
FFI_PLUGIN_EXPORT void loopin_set_monitor_enabled(int32_t enabled);
FFI_PLUGIN_EXPORT void loopin_set_monitor_volume(float volume);

// Mide la latencia de ida y vuelta emitiendo clics y detectándolos en la entrada.
FFI_PLUGIN_EXPORT void loopin_measure_latency(void);

// Looper. El botón principal hace de pedal sobre la pista seleccionada:
//   toque: graba → reproduce → overdub → reproduce → overdub…
//   (con el avance automático, tras grabar una pista se elige la siguiente
//   vacía, así que el siguiente toque graba en ella)
//   mantener (llamar a loopin_loop_hold tras el toque): deshacer lo último
//   doble toque (en el 2º toque llamar a loopin_loop_double_tap en vez de
//   loopin_loop_press): parar / arrancar todo
// Hold y double_tap interpretan lo que hizo el toque anterior y lo corrigen.
FFI_PLUGIN_EXPORT void loopin_loop_press(void);
FFI_PLUGIN_EXPORT void loopin_loop_hold(void);
FFI_PLUGIN_EXPORT void loopin_loop_double_tap(void);
FFI_PLUGIN_EXPORT void loopin_loop_undo(void);
// Borra todas las pistas
FFI_PLUGIN_EXPORT void loopin_loop_clear(void);
// Pistas (track de 0 a LOOPIN_TRACKS - 1)
FFI_PLUGIN_EXPORT void loopin_select_track(int32_t track);
FFI_PLUGIN_EXPORT void loopin_select_next_track(void);
FFI_PLUGIN_EXPORT void loopin_set_track_volume(int32_t track, float volume);
FFI_PLUGIN_EXPORT void loopin_set_track_muted(int32_t track, int32_t muted);
FFI_PLUGIN_EXPORT void loopin_clear_track(int32_t track);
FFI_PLUGIN_EXPORT void loopin_set_auto_advance(int32_t enabled);
FFI_PLUGIN_EXPORT void loopin_set_loop_mode(int32_t mode);
FFI_PLUGIN_EXPORT void loopin_set_sync_bars(int32_t bars);
FFI_PLUGIN_EXPORT void loopin_set_loop_volume(float volume);
// Compensación de latencia de la grabación: la latencia de ida y vuelta en
// muestras (la que da loopin_measure_latency para la entrada y salida en uso).
FFI_PLUGIN_EXPORT void loopin_set_latency_compensation(int32_t frames);

// Copia el estado actual en *out.
FFI_PLUGIN_EXPORT void loopin_get_status(LoopinStatus* out);

#ifdef __cplusplus
}
#endif

#endif  // LOOPIN_ENGINE_H
