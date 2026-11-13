# Loopin

Looper de guitarra libre para Android: varias pistas que cuadran al compás, metrónomo y backing tracks.

> **Estado:** Etapa 5. Modo simple (lo justo para grabar y tocar: pulsador más grande, 1 compás de cuenta y se cierra al pulsar) y avanzado (todo). Looper de 4 pistas con interfaz de pedal, metrónomo con 10 compases, batería con 10 estilos, tus propias canciones (WAV, MP3, FLAC) estiradas al tempo, modo libre, «empezar al tocar», controles externos y latencia compensada (medida sola, tocando al clic o a mano). Para el directo y la práctica: afinador, reverse y media velocidad por pista, silenciar y entrar en el 1, parar en el 1 o con fundido, y entrenador de tempo. Próximo: guardar sesiones y exportar.

## Cómo se usa

El botón grande hace de pedal (actúa al pulsar, no al soltar) sobre la pista elegida:

- **Toque:** pista vacía → graba; pista con loop → graba encima (overdub, desde el siguiente compás). Con el avance automático, al cerrar una pista queda elegida la siguiente vacía.
- **Mantener:** deshacer lo último (una capa o la pista recién grabada).
- **Doble toque:** parar / arrancar todo.

Modos de grabación: **sincronizado** (1, 2, 4 u 8 compases), **manual** (se cierra al pulsar, al compás más cercano) y **libre** (sin metrónomo: el tempo sale del primer loop). La primera pista lleva 1 compás de cuenta, o arranca con la primera nota si está encendido «empezar al tocar».

**Batería:** la fila de debajo de la pista. Sigue el tempo y el compás; el estilo «Básico» sale de los acentos del compás y vale para los 10, y hay rock, pop, blues shuffle, funk, balada y reggae (4/4), vals (3/4), balada 6/8 y blues lento (12/8). Entra siempre en un 1; con ella encendida la cuenta de entrada suena con baquetas y el clic se calla mientras toca. Los sonidos son de [Virtuosity Drums](https://github.com/sfzinstruments/virtuosity_drums) (CC0).

**Canciones:** la misma fila, en la posición «CANCIÓN». Importas un audio tuyo, marcas su tempo y dónde cae un 1 (escuchándola, con un clic encima para comprobarlo; el tempo exacto sale de marcar otro 1 más adelante) y suena con los loops, estirada al tempo del metrónomo sin cambiar el tono ([SoundTouch](https://codeberg.org/soundtouch/soundtouch), LGPL). Entra siempre en un 1 y al acabar vuelve a empezar.

**Directo y práctica:** el **afinador** (el diapasón de arriba) usa la entrada que tengas. Cada pista puede ir al revés (**REV**) o a media velocidad (**½**); silenciarla, REV y ½ esperan al siguiente 1 para entrar a tiempo. **Al parar** (Ajustes) puede ser al momento, en el siguiente 1 o con un fundido de 4 s. El **entrenador de tempo** (la flecha junto al ▶) sube el tempo X BPM cada N compases hasta donde digas.

Mide la latencia una vez por cada combinación de entrada y salida (Ajustes › Audio y latencia): se guarda y se aplica sola.

Licencia: [GPLv3](LICENSE).

## Qué hay

```
app/                        App Flutter (interfaz)
  lib/engine/               Estado y órdenes al motor, latencia por ruta, teclas externas
  lib/ui/                   Pantallas; ui/looper/ son las piezas de la del looper
  lib/l10n/strings.dart     Todos los textos (preparado para traducir)
  assets/drums/             Sonidos de la batería (CC0; tool/make_drums.py los genera)
packages/loopin_engine/     Plugin FFI: puente Dart ↔ motor C++
  src/                      Motor C++ (Oboe)
  src/third_party/oboe/     Oboe 1.11.0 (submódulo de git)
  src/third_party/          SoundTouch 2.4.1 y dr_libs (copiados; ver su README.md)
engine_tests/               Tests del motor que se ejecutan en el PC
app/test/                   Tests de la interfaz (flutter test)
.github/workflows/          Compila y pasa los tests en cada push
```

## Compilar en Windows

Necesitas Git, Flutter y Android Studio (ver el plan del proyecto). Después:

```powershell
# Ruta corta: Windows falla con rutas de más de 260 caracteres al compilar C++
cd C:\dev
git clone --recursive https://github.com/alexoseayo40-cyber/loopin.git
cd loopin\app
flutter run --release
```

Si ya lo clonaste sin `--recursive`: `git submodule update --init --recursive`.

La primera compilación descarga el NDK y CMake de Android (más de 1 GB) y tarda un rato.

### Tests del motor (opcional)

Necesitan un compilador de C++ (Visual Studio Build Tools en Windows):

```powershell
cmake -S engine_tests -B build/engine_tests
cmake --build build/engine_tests --config Release
build\engine_tests\Release\loopin_engine_tests.exe
```

`drum_demo app/assets/drums <carpeta>` deja en la carpeta un WAV por estilo de batería, para oírlos sin móvil.

## Cómo funciona el motor

- Un stream full-duplex de Oboe: la entrada se lee dentro del callback de salida, así que las dos van a la par.
- Dentro del callback no se reserva memoria, no hay bloqueos y no se lee ningún archivo. Las órdenes llegan por una cola SPSC y el estado sale por variables atómicas.
- Todo se cuenta en muestras enteras: un tiempo dura exactamente `round(fs × 60 / BPM)` muestras, así que compases y loops son múltiplos exactos y no hay deriva.
- La latencia se mide emitiendo un pulso y detectándolo en la entrada, con los índices absolutos de las muestras de salida y de entrada. Es el mismo valor que usa el looper para compensar la grabación.
- En cada callback se lee **toda** la entrada que haya llegado (no un bloque fijo, como hace `oboe::FullDuplexStream`), así no se acumula retraso. Entrada y salida se cuentan por separado y no necesitan bloques iguales.
- El looper decide todo (inicio, fin, overdub) en índices de salida, que es lo que oye el músico. La muestra de entrada *j* se tocó mientras sonaba la salida *j − latencia*, y se escribe en esa posición del loop: la escritura va con retraso, a medida que llega la entrada (un anillo de 6 s guarda lo último).
- Cada overdub va a una capa aparte para poder deshacerlo. Al acabar el siguiente overdub, la capa anterior se suma al loop base poco a poco en segundo plano; como lo que suena es la suma de todo, no se nota.
- La batería es un secuenciador de muestras: al empezar cada tiempo apunta los golpes de ese tiempo con su desfase en muestras y los dispara al llegar. Como el tiempo dura un número entero de muestras y el tempo solo cambia al empezar uno, cada golpe cae siempre en la misma muestra respecto al compás.
- Las canciones importadas se decodifican (dr_libs) y se estiran (SoundTouch) **una vez**, en un hilo aparte, y se guardan en memoria en 16 bits, mono, con el 1 en un inicio de compás y compases enteros. El callback solo las lee. Si cambia el tempo, la canción se calla y se vuelve a preparar; entra en el siguiente 1 por donde iría. Los audios nuevos llegan al hilo de audio con un intercambio atómico y los viejos vuelven por una cola para borrarlos fuera de él.
- Cada pista se lee en una posición contada en medias muestras que avanza +2 (normal), +1 (media velocidad), −2 (al revés) o −1 por muestra; al cambiar hay un fundido cruzado de 5 ms. Un overdub sobre una pista con efecto se escribe donde se oye.
- El afinador copia la entrada en un anillo sin bloqueos y la analiza fuera del hilo de audio (YIN a ~24 kHz y el periodo afinado en la señal original: en los tests, menos de 1 cent de error de 41 a 1319 Hz).
- La carga del callback (media y pico de cada segundo, en % del tiempo disponible) se ve en Audio y latencia › Detalles técnicos y en «Copiar resultados».
