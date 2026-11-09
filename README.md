# Loopin

Looper de guitarra libre para Android: varias pistas que cuadran al compás, metrónomo y backing tracks.

> **Estado:** Etapa 1, prototipo de audio. De momento la app es una pantalla de prueba: metrónomo, escucharte en directo y medir la latencia del móvil.

Licencia: [GPLv3](LICENSE).

## Qué hay

```
app/                        App Flutter (interfaz)
packages/loopin_engine/     Plugin FFI: puente Dart ↔ motor C++
  src/                      Motor C++ (Oboe)
  src/third_party/oboe/     Oboe 1.11.0 (submódulo de git)
engine_tests/               Tests del motor que se ejecutan en el PC
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

## Cómo funciona el motor

- Un stream full-duplex de Oboe: la entrada se lee dentro del callback de salida, así que las dos van a la par.
- Dentro del callback no se reserva memoria, no hay bloqueos y no se lee ningún archivo. Las órdenes llegan por una cola SPSC y el estado sale por variables atómicas.
- Todo se cuenta en muestras enteras: un tiempo dura exactamente `round(fs × 60 / BPM)` muestras, así que compases y loops son múltiplos exactos y no hay deriva.
- La latencia se mide emitiendo un pulso y detectándolo en la entrada, contando muestras de salida y de entrada. Es el mismo valor que usará el looper para compensar la grabación.
