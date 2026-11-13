// Loopin — audio importado: la canción que suena con el transporte y la
// vista previa para prepararla
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <cstdint>

#include "Clip.h"

namespace loopin {

// La canción llega ya estirada al tempo del transporte (ver SongJobs), con el
// 1 en un inicio de compás y una duración de compases enteros. Aquí solo se lee
// de memoria, muestra a muestra:
//
// - Entra siempre en un 1 (como la batería). Al entrar se apunta en qué compás
//   del transporte empezó (el «ancla»); desde ahí, en cada 1 suena el compás
//   (compás del transporte − ancla) de la canción. Al acabar vuelve a empezar.
// - Si el tempo o el compás del transporte dejan de ser los de la canción
//   (alguien ha cambiado el tempo), se calla; cuando llegue la canción
//   estirada al tempo nuevo, vuelve a entrar en un 1 por donde iría.
// - En la cuenta de entrada no suena: entra con la grabación.
//
// La vista previa suena sola, sin transporte, desde donde se pida. Puede
// llevar un clic en la rejilla de la canción (marca del 1 + tiempos), para
// comprobar a oído el tempo y el 1.
class Backing {
 public:
  ~Backing() { delete fading_; }
  // Fuera del hilo de audio y con el audio cerrado: se quedan los clips de
  // esta frecuencia (los demás ya no valen).
  void prepare(int32_t sampleRate, ClipBin& bin);

  // Fuera del hilo de audio
  ClipSlot& songSlot() { return song_; }
  ClipSlot& previewSlot() { return preview_; }

  // --- Hilo de audio ---
  // Al principio de cada bloque: coge los clips nuevos.
  void takeClips(RetiredClips& retired);
  void setEnabled(bool on);
  void setVolume(float v);
  void previewPlay(int64_t from);
  void previewStop() { previewPlaying_ = false; }
  void setPreviewClick(bool on) { previewClick_ = on; }
  // Rejilla del clic de la vista previa: el 1 cae en mark (muestras, puede
  // tener decimales) y cada tiempo dura beat muestras.
  void setPreviewMark(double mark, uint32_t accentMask);
  void setPreviewBeat(double beat, int32_t beatsPerBar);

  // Al empezar cada tiempo del transporte (tras transport.tick()). late: el
  // tiempo empezó hace late muestras (el transporte arrancó «desde atrás»).
  void beat(int32_t bar, int32_t beat, int32_t samplesPerBeat, int32_t beatsPerBar,
            bool countIn, int32_t late = 0);
  // El transporte se ha parado: la próxima vez entra desde el principio.
  void halt();
  // Antes de next(): si en esta muestra empieza un clic de la vista previa,
  // su acento + 1 (1 = fuerte, 2 = medio, 3 = normal); si no, 0.
  int32_t previewClickNow();
  // Siguiente muestra (canción + vista previa). Llamar en todas.
  float next(RetiredClips& retired);

  // --- Estado ---
  bool enabled() const { return enabled_; }
  float volume() const { return volume_; }
  bool playing() const { return playing_; }
  const Clip* song() const { return song_.current(); }
  const Clip* preview() const { return preview_.current(); }
  int64_t position() const { return pos_; }
  bool previewPlaying() const { return previewPlaying_; }
  int64_t previewPosition() const { return previewPos_; }
  bool previewClick() const { return previewClick_; }

 private:
  static constexpr float kGainSmoothing = 0.004f;

  void stop() { playing_ = false; }
  void retire(Clip* c, RetiredClips& retired);
  void scheduleClick();

  ClipSlot song_;
  ClipSlot preview_;
  int32_t sampleRate_ = 48000;

  bool enabled_ = false;
  float volume_ = 0.7f;
  float gain_ = 0.7f;

  // Canción
  bool started_ = false;   // ha entrado (hay ancla)
  bool playing_ = false;   // suena (o va a sonar: env_ sube)
  int32_t anchor_ = 0;     // compás del transporte en el que empezó
  int64_t pos_ = 0;
  float env_ = 0.0f;       // fundido de entrada y salida (0–1)
  float envUp_ = 1.0f / 48;    // 1 ms para entrar (no se come el ataque del 1)
  float envDown_ = 1.0f / 240; // 5 ms para salir (sin chasquido)
  // El clip que acaba de cambiarse mientras sonaba: se apaga en 5 ms
  Clip* fading_ = nullptr;
  int64_t fadingPos_ = 0;
  float fadingEnv_ = 0.0f;

  // Vista previa
  bool previewPlaying_ = false;
  int64_t previewPos_ = 0;
  bool previewClick_ = false;
  double mark_ = 0.0;
  double beatLen_ = 0.0;
  int32_t gridBeats_ = 4;
  uint32_t gridAccents_ = 0;
  int64_t clickIndex_ = 0;   // tiempo (desde el 1, puede ser negativo) del próximo clic
  int64_t clickAt_ = -1;     // muestra de ese clic
};

}  // namespace loopin
