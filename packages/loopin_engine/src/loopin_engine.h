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

// Cuándo suena el clic
#define LOOPIN_CLICK_SILENT 0    // nunca: metrónomo solo visual
#define LOOPIN_CLICK_COUNT_IN 1  // solo en la cuenta de entrada
#define LOOPIN_CLICK_ALWAYS 2

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

// Batería: sonidos del kit (loopin_set_drum_sample)
#define LOOPIN_DRUM_KICK 0
#define LOOPIN_DRUM_SNARE 1
#define LOOPIN_DRUM_SNARE_SOFT 2
#define LOOPIN_DRUM_CROSS_STICK 3
#define LOOPIN_DRUM_HAT 4
#define LOOPIN_DRUM_HAT_SOFT 5
#define LOOPIN_DRUM_HAT_OPEN 6
#define LOOPIN_DRUM_RIDE 7
#define LOOPIN_DRUM_CRASH 8
#define LOOPIN_DRUM_STICKS 9
#define LOOPIN_DRUM_SOUNDS 10

// Batería: estilos (loopin_set_drum_style). Básico vale para cualquier compás;
// los demás son de un compás concreto (si no coincide, suena el básico).
#define LOOPIN_STYLE_BASIC 0
#define LOOPIN_STYLE_ROCK 1        // 4/4
#define LOOPIN_STYLE_POP 2         // 4/4
#define LOOPIN_STYLE_SHUFFLE 3     // 4/4 (tresillos)
#define LOOPIN_STYLE_FUNK 4        // 4/4
#define LOOPIN_STYLE_BALLAD 5      // 4/4
#define LOOPIN_STYLE_REGGAE 6      // 4/4
#define LOOPIN_STYLE_WALTZ 7       // 3/4
#define LOOPIN_STYLE_SIX_EIGHT 8   // 6/8
#define LOOPIN_STYLE_SLOW_BLUES 9  // 12/8

// Audio importado: estado de un trabajo en segundo plano (abrir o preparar)
#define LOOPIN_JOB_IDLE 0
#define LOOPIN_JOB_RUNNING 1
#define LOOPIN_JOB_DONE 2
#define LOOPIN_JOB_FAILED 3

// Audio importado: errores
#define LOOPIN_SONG_ERR_OPEN 1      // no se puede abrir o no es WAV, MP3 ni FLAC
#define LOOPIN_SONG_ERR_TOO_LONG 2  // más de 10 minutos (a ese tempo)
#define LOOPIN_SONG_ERR_MEMORY 3
#define LOOPIN_SONG_ERR_EMPTY 4     // no suena nada
#define LOOPIN_SONG_ERR_TEMPO 5     // a más del doble o menos de la mitad de su tempo

// Duración máxima de una canción (o de lo que dure estirada)
#define LOOPIN_SONG_MAX_SECONDS 600

// Cómo para el botón de parar (loopin_stop_playing) y el doble toque
#define LOOPIN_STOP_NOW 0   // al momento
#define LOOPIN_STOP_BAR 1   // en el siguiente 1
#define LOOPIN_STOP_FADE 2  // bajando poco a poco y luego para

// Cambios de una pista que esperan al siguiente 1 (track_pending, bits)
#define LOOPIN_PENDING_MUTE 1
#define LOOPIN_PENDING_REVERSE 2
#define LOOPIN_PENDING_HALF 4

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

  // Metrónomo
  int32_t beat_frames;        // muestras ya sonadas del tiempo actual
  int32_t accent_mask;        // tiempos con acento medio (bit k = tiempo k)
  int32_t click_mode;         // LOOPIN_CLICK_*
  // Empezar al tocar
  int32_t start_on_sound;
  int32_t loop_waiting;       // 1 = esperando a que suene la guitarra
  // Calibración tocando al clic
  int32_t tap_state;          // LOOPIN_LATENCY_* (mismos valores)
  int32_t tap_clicks;         // clics que ya han sonado (de 16)
  int32_t tap_hits;           // golpes que cuentan (de 12)
  int32_t tap_frames;         // resultado en muestras
  int32_t tap_spread;         // dispersión de los golpes en muestras
  // Carga del callback de audio: fracción del tiempo disponible (1.0 = 100 %;
  // por encima, el audio se corta)
  float cpu_load_avg;         // media del último segundo
  float cpu_load_peak;        // pico del último segundo
  float cpu_load_max;         // mayor pico desde que se abrió el audio
  // Batería
  int32_t drums_enabled;
  int32_t drum_style;         // LOOPIN_STYLE_* pedido
  int32_t drums_playing;      // 1 = ya ha entrado (en un primer tiempo) y suena
  float drum_volume;
  // Audio importado: abrir una canción para prepararla (vista previa)
  int32_t song_open_id;       // el id que se pasó a loopin_song_open
  int32_t song_open_state;    // LOOPIN_JOB_*
  int32_t song_open_progress; // 0..1000
  int32_t song_open_error;    // LOOPIN_SONG_ERR_*
  int64_t song_open_frames;   // duración (a sample_rate)
  double song_bpm_guess;      // tempo sugerido (0 = ni idea)
  int64_t song_first_attack;  // primer golpe claro (muestra; -1 = ninguno)
  // Audio importado: preparar la canción para que suene (estirarla al tempo)
  int32_t song_prep_id;
  int32_t song_prep_state;    // LOOPIN_JOB_*
  int32_t song_prep_progress; // 0..1000
  int32_t song_prep_error;    // LOOPIN_SONG_ERR_*
  // La canción que suena con el transporte
  int32_t backing_enabled;
  int32_t backing_playing;    // 1 = ha entrado (en un primer tiempo) y suena
  int32_t backing_id;         // id de la que está cargada (0 = ninguna)
  int32_t backing_samples_per_beat;  // tempo y compás a los que está estirada
  int32_t backing_beats_per_bar;
  int64_t backing_position;
  int64_t backing_length;
  float backing_volume;
  // Vista previa (la canción abierta, sin estirar)
  int32_t preview_id;
  int32_t preview_playing;
  int32_t preview_click;
  int64_t preview_position;
  int64_t preview_length;

  // Etapa 5: reverse y media velocidad (lo pedido; puede esperar al 1)
  int32_t track_reverse[LOOPIN_TRACKS];
  int32_t track_half[LOOPIN_TRACKS];
  int32_t track_pending[LOOPIN_TRACKS];  // LOOPIN_PENDING_* (bits)
  int32_t quantize;           // 1 = silencio y efectos en el siguiente 1
  // Parar
  int32_t stop_mode;          // LOOPIN_STOP_*
  int32_t stopping;           // 0 no, 1 esperando al 1, 2 bajando (fundido)
  // Entrenador de tempo (sube trainer_step BPM cada trainer_bars compases)
  int32_t trainer_bars;       // 0 = apagado
  double trainer_step;
  double trainer_top;
} LoopinStatus;

// Afinador: lo último que ha entrado, analizado al pedirlo
typedef struct {
  float frequency;            // Hz (0 = no hay una nota clara)
  float clarity;              // 0..1
  float level_db;             // nivel de la entrada (dBFS)
  int32_t fresh;              // 1 si ha llegado audio desde la última lectura
} LoopinTuner;

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
// Compás con acentos: accent_mask marca con un bit cada tiempo con acento
// medio (el tiempo 0 siempre es fuerte). En los compases de 8 el tiempo es la
// corchea. Ej.: 6/8 → (6, 1 << 3); 7/8 en 2+2+3 → (7, (1 << 2) | (1 << 4)).
FFI_PLUGIN_EXPORT void loopin_set_meter(int32_t beats_per_bar, int32_t accent_mask);

// Metrónomo
FFI_PLUGIN_EXPORT void loopin_set_click_enabled(int32_t enabled);
FFI_PLUGIN_EXPORT void loopin_set_click_mode(int32_t mode);  // LOOPIN_CLICK_*
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
// Calibración tocando al clic (con cascos, donde el clic no vuelve al micro):
// 4 clics para entrar y 12 que cuentan, a 80 BPM.
FFI_PLUGIN_EXPORT void loopin_start_tap_calibration(void);
FFI_PLUGIN_EXPORT void loopin_cancel_tap_calibration(void);

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
// Volumen de lo que ya suena mientras se graba una pista o un overdub
// (1 = normal, 0 = silencio). Con el altavoz y el micro del móvil, lo que
// suena se volvería a grabar.
FFI_PLUGIN_EXPORT void loopin_set_record_duck(float gain);
// Compensación de latencia de la grabación: la latencia de ida y vuelta en
// muestras (la que da loopin_measure_latency para la entrada y salida en uso).
FFI_PLUGIN_EXPORT void loopin_set_latency_compensation(int32_t frames);
// Ajuste a mano: cambia la compensación y mueve lo ya grabado lo mismo que
// cambie (para corregirla a oído con un loop sonando).
FFI_PLUGIN_EXPORT void loopin_nudge_latency(int32_t frames);
// La primera pista espera a que suene la guitarra y empieza en ese ataque.
FFI_PLUGIN_EXPORT void loopin_set_start_on_sound(int32_t enabled);

// Batería. Las muestras se copian y se aplican la próxima vez que se abra el
// audio (loopin_start): hay que darlas antes. Mono, en float, a sample_rate
// (se pasan solas a la frecuencia del móvil).
FFI_PLUGIN_EXPORT void loopin_set_drum_sample(int32_t sound, const float* data, int32_t frames,
                                              int32_t sample_rate);
// Encendida, suena mientras corre el transporte; entra siempre en un primer
// tiempo. En la cuenta de entrada suenan las baquetas en vez del clic y,
// mientras toca, el clic se calla.
FFI_PLUGIN_EXPORT void loopin_set_drums_enabled(int32_t enabled);
// beat_is_eighth: 1 si el tiempo es la corchea (compases de 8); el básico
// añade la corchea del charles solo cuando el tiempo es la negra.
// Sonando, el cambio espera al siguiente compás.
FFI_PLUGIN_EXPORT void loopin_set_drum_style(int32_t style, int32_t beat_is_eighth);
FFI_PLUGIN_EXPORT void loopin_set_drum_volume(float volume);

// Audio importado (WAV, MP3 o FLAC). Lo pesado va en segundo plano y su
// estado sale en LoopinStatus; el hilo de audio solo lee lo ya preparado.
//
// Abrir: decodifica la canción a la frecuencia del motor, sin estirar, para
// prepararla (escucharla, ver la forma de onda, marcar el 1). Sugiere un tempo
// y el primer golpe. id: cualquier número distinto de 0, para reconocerla.
FFI_PLUGIN_EXPORT void loopin_song_open(const char* path, int32_t id);
FFI_PLUGIN_EXPORT void loopin_song_close(void);
// Picos (0..1) de la canción abierta entre start y end (muestras), en bins
// trozos. Devuelve cuántos ha escrito (0 si no hay ninguna abierta).
FFI_PLUGIN_EXPORT int32_t loopin_song_peaks(int64_t start, int64_t end, int32_t bins, float* out);
// El ataque más claro de la canción abierta cerca de center (± radius).
FFI_PLUGIN_EXPORT int64_t loopin_song_find_attack(int64_t center, int64_t radius);
// Vista previa: suena sola (sin transporte) desde frame. Con el clic, suena
// en la rejilla de la canción: el 1 en mark_frames y un tiempo cada
// beat_frames muestras (los dos con decimales).
FFI_PLUGIN_EXPORT void loopin_preview_play(int64_t frame);
FFI_PLUGIN_EXPORT void loopin_preview_stop(void);
FFI_PLUGIN_EXPORT void loopin_preview_set_click(int32_t enabled);
FFI_PLUGIN_EXPORT void loopin_preview_set_grid(double mark_frames, double beat_frames,
                                               int32_t beats_per_bar, int32_t accent_mask);
// Preparar: decodifica y estira la canción (sin cambiar el tono) para que un
// tiempo dure samples_per_beat muestras, con el 1 (mark_seconds en el archivo)
// en un inicio de compás. Cuando acaba, suena con el transporte: entra en un 1
// y, si el tempo del transporte deja de ser ese, se calla hasta que se prepare
// otra vez. Pedir otra cancela la anterior.
FFI_PLUGIN_EXPORT void loopin_backing_prepare(const char* path, double song_bpm,
                                              double mark_seconds, int32_t samples_per_beat,
                                              int32_t beats_per_bar, int32_t id);
// Cancela la preparación en marcha (la que suena sigue sonando).
FFI_PLUGIN_EXPORT void loopin_backing_cancel(void);
FFI_PLUGIN_EXPORT void loopin_backing_unload(void);
// Encendida, suena mientras corre el transporte (entra siempre en un 1).
FFI_PLUGIN_EXPORT void loopin_set_backing_enabled(int32_t enabled);
FFI_PLUGIN_EXPORT void loopin_set_backing_volume(float volume);

// --- Etapa 5: directo y práctica ---

// Reverse y media velocidad de una pista con loop (no mientras se graba en
// ella). Al ponerlos sigue desde donde suena; al quitarlos todos, vuelve a su
// sitio. Con loopin_set_quantize, en el siguiente 1 (también el silencio).
FFI_PLUGIN_EXPORT void loopin_set_track_reverse(int32_t track, int32_t enabled);
FFI_PLUGIN_EXPORT void loopin_set_track_half(int32_t track, int32_t enabled);
FFI_PLUGIN_EXPORT void loopin_set_quantize(int32_t enabled);
// Parar como diga el modo (LOOPIN_STOP_*). Pedirlo otra vez mientras se para,
// o now = 1, para al momento. loopin_pause para siempre al momento.
FFI_PLUGIN_EXPORT void loopin_stop_playing(int32_t now);
FFI_PLUGIN_EXPORT void loopin_set_stop_mode(int32_t mode);
FFI_PLUGIN_EXPORT void loopin_set_fade_seconds(float seconds);
// Entrenador (sin loops): sube step BPM cada bars compases, hasta top. Al
// parar, vuelve el tempo de loopin_set_bpm. bars = 0 lo apaga.
FFI_PLUGIN_EXPORT void loopin_set_trainer(int32_t bars, double step, double top);
// Afinador: encendido, la entrada se copia para analizarla. loopin_tuner_read
// analiza lo último (unos 70 ms) en el hilo que lo llama (~0,5 ms) y devuelve
// 1 si había audio suficiente.
FFI_PLUGIN_EXPORT void loopin_tuner_enable(int32_t enabled);
FFI_PLUGIN_EXPORT int32_t loopin_tuner_read(LoopinTuner* out);

// Copia el estado actual en *out.
FFI_PLUGIN_EXPORT void loopin_get_status(LoopinStatus* out);

#ifdef __cplusplus
}
#endif

#endif  // LOOPIN_ENGINE_H
