// Loopin — batería: un secuenciador con muestras que sigue al transporte
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <array>
#include <cstdint>
#include <vector>

namespace loopin {

// Los sonidos del kit. Las muestras llegan desde la app (archivos WAV de
// assets/drums, CC0) antes de abrir el audio y se pasan aquí a la frecuencia
// del móvil en prepare(). Un sonido sin muestra no suena.
enum class DrumSound : int32_t {
  kKick = 0,
  kSnare = 1,
  kSnareSoft = 2,   // caja floja (notas fantasma)
  kCrossStick = 3,  // aro
  kHat = 4,         // charles cerrado
  kHatSoft = 5,
  kHatOpen = 6,
  kRide = 7,
  kCrash = 8,
  kSticks = 9,      // baquetas: la cuenta de entrada
  kCount = 10,
};

// Estilos (mismo orden en la app). Básico sale de los acentos del compás y
// vale para todos; los demás son de un compás concreto y, si el compás no
// coincide, suena el básico.
enum class DrumStyle : int32_t {
  kBasic = 0,
  kRock = 1,
  kPop = 2,
  kShuffle = 3,
  kFunk = 4,
  kBallad = 5,
  kReggae = 6,
  kWaltz = 7,    // 3/4
  kSixEight = 8, // 6/8
  kSlowBlues = 9,  // 12/8
  kCount = 10,
};

// Cómo funciona: en cada tiempo (cuando el transporte dice que empieza uno)
// se apuntan los golpes de ese tiempo con su desfase en muestras dentro del
// tiempo; luego, muestra a muestra, se disparan al llegar a su desfase. Como
// un tiempo dura un número entero de muestras y el tempo solo cambia al
// empezar un tiempo, los golpes caen siempre en la misma muestra respecto al
// compás: no hay deriva.
//
// La batería entra siempre en un primer tiempo: si el transporte arranca a
// mitad de compás (empezar al tocar, modo libre) o se enciende con todo
// sonando, espera al siguiente 1.
class Drums {
 public:
  // Para los tests: cada golpe que se dispara (muestra de salida, sonido, fuerza)
  struct LoggedHit {
    int64_t frame;
    DrumSound sound;
    float gain;
  };

  static constexpr int32_t kVoices = 16;
  static constexpr int32_t kMaxEvents = 64;  // golpes en un tiempo

  // --- Fuera del hilo de audio ---
  // Copia la muestra de un sonido (mono, en float, a srcRate). Se aplica en
  // el siguiente prepare().
  void setSample(DrumSound sound, const float* data, int32_t frames, int32_t srcRate);
  // Pasa las muestras a la frecuencia del móvil y reserva todo lo necesario.
  void prepare(int32_t sampleRate);
  // Copia las muestras de otra batería (fuera del hilo de audio de las dos:
  // las de origen solo cambian con el audio cerrado). Se aplican en prepare().
  void copySamples(const Drums& from) {
    raw_ = from.raw_;
    rawRate_ = from.rawRate_;
  }

  // --- Hilo de audio ---
  void setEnabled(bool on);
  void setStyle(DrumStyle style, bool beatIsEighth);
  void setVolume(float v);

  // Al empezar un tiempo (después de transport.tick()). countIn: es un tiempo
  // de la cuenta de entrada (suenan las baquetas, si sticks). Devuelve true
  // si en este tiempo suena la batería (entonces el clic se calla).
  // late: el tiempo empezó hace late muestras (el transporte ha arrancado
  // «desde atrás», justo pasado un 1): lo que tocaba hasta ahora suena ya.
  bool beat(int32_t bar, int32_t beat, int32_t beatsPerBar, uint32_t accentMask,
            int32_t samplesPerBeat, bool countIn, bool sticks, bool freshStart,
            int32_t late = 0);
  // El transporte se ha parado: la batería volverá a entrar en un 1.
  void halt();
  // Como halt() y además corta lo que aún suena (al acabar un fundido)
  void silence();
  // Siguiente muestra (llamar en todas, aunque el transporte esté parado: así
  // acaban de sonar los platos).
  float next();

  // --- Estado ---
  bool enabled() const { return enabled_; }
  // El estilo pedido (si está sonando, puede que aún espere al compás)
  DrumStyle style() const { return pendingStyle_; }
  bool beatIsEighth() const { return eighths_; }
  // El estilo que suena con el compás de ahora (el básico si no coincide)
  DrumStyle effectiveStyle() const { return effective_; }
  bool playing() const { return started_ && enabled_; }
  float volume() const { return volume_; }
  bool hasSample(DrumSound s) const { return !kit_[idx(s)].empty(); }
  int32_t sampleFrames(DrumSound s) const { return int32_t(kit_[idx(s)].size()); }

  // Solo para tests (mismo hilo que el audio): apunta cada golpe en log. Las
  // muestras se cuentan desde prepare().
  void setTestLog(std::vector<LoggedHit>* log) { log_ = log; }

  // Compás de un estilo (0 tiempos = cualquiera)
  static int32_t styleBeats(DrumStyle style);
  static uint32_t styleAccents(DrumStyle style);

 private:
  static size_t idx(DrumSound s) { return static_cast<size_t>(s); }

  struct Event {
    int32_t offset;
    DrumSound sound;
    float gain;
  };
  struct Voice {
    const std::vector<float>* sample = nullptr;
    DrumSound sound = DrumSound::kKick;
    size_t pos = 0;
    float gain = 0.0f;
    int32_t fade = 0;  // > 0: se está apagando (le quedan fade muestras)
  };
  // Un golpe de un patrón: paso dentro del patrón, sonido y fuerza
  struct Hit {
    int32_t step;
    DrumSound sound;
    float gain;
  };
  struct Pattern {
    int32_t beats = 0;
    uint32_t accents = 0;
    int32_t stepsPerBeat = 1;
    int32_t bars = 1;
    std::vector<Hit> hits;  // ordenados por paso
  };

  void add(int32_t offset, DrumSound sound, float gain);
  void trigger(DrumSound sound, float gain);
  void basicBeat(int32_t beat, int32_t beatsPerBar, uint32_t accentMask, int32_t spb);
  DrumStyle resolve(int32_t beatsPerBar, uint32_t accentMask) const;
  static Pattern parse(int32_t beats, uint32_t accents, int32_t stepsPerBeat,
                       std::initializer_list<const char*> rows);
  void buildPatterns();

  int32_t sampleRate_ = 48000;
  std::array<std::vector<float>, static_cast<size_t>(DrumSound::kCount)> raw_;
  std::array<int32_t, static_cast<size_t>(DrumSound::kCount)> rawRate_{};
  std::array<std::vector<float>, static_cast<size_t>(DrumSound::kCount)> kit_;
  std::array<Pattern, static_cast<size_t>(DrumStyle::kCount)> patterns_;

  bool enabled_ = false;
  DrumStyle style_ = DrumStyle::kBasic;
  DrumStyle pendingStyle_ = DrumStyle::kBasic;
  DrumStyle effective_ = DrumStyle::kBasic;
  bool eighths_ = false;
  bool started_ = false;
  float volume_ = 0.7f;
  float gain_ = 0.7f;  // el aplicado (sigue a volume_ poco a poco)

  std::array<Event, kMaxEvents> events_{};
  int32_t eventCount_ = 0;
  int32_t eventIdx_ = 0;
  int32_t posInBeat_ = 0;
  std::array<Voice, kVoices> voices_{};
  int32_t chokeFrames_ = 240;  // el charles cerrado corta el abierto en 5 ms
  int64_t frame_ = 0;          // muestras desde prepare()
  std::vector<LoggedHit>* log_ = nullptr;
};

}  // namespace loopin
