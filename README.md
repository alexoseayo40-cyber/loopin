# Loopin

Looper de guitarra libre para Android: varias pistas que cuadran al compás, metrónomo y backing tracks.

> **Estado:** Etapa 2, looper de una pista: grabar, reproducir, overdub, deshacer y borrar, sincronizado con el metrónomo y con la latencia compensada.

## Cómo se usa

El botón grande hace de pedal (actúa al pulsar, no al soltar):

- **Toque:** grabar → reproducir → overdub → reproducir → overdub…
- **Mantener:** deshacer la última capa.
- **Doble toque:** parar / arrancar todo.

Modos de grabación:

- **Sincronizado:** al pulsar, el metrónomo empieza de cero (aunque ya estuviera sonando), cuenta 1 compás y graba 1, 2, 4 u 8 compases.
- **Manual:** vuelve a tocar para cerrar; el loop se ajusta al compás más cercano (si pulsas tarde se recorta, si pulsas pronto sigue hasta el final del compás). También empieza con 1 compás de cuenta desde que pulsas.

Mide la latencia una vez por cada combinación de entrada y salida (Ajustes › Audio y latencia): se guarda y se aplica sola.

Licencia: [GPLv3](LICENSE).

## Qué hay

```
app/                        App Flutter (interfaz)
packages/loopin_engine/     Plugin FFI: puente Dart ↔ motor C++
  src/                      Motor C++ (Oboe)
  src/third_party/oboe/     Oboe 1.11.0 (submódulo de git)
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

## Cómo funciona el motor

- Un stream full-duplex de Oboe: la entrada se lee dentro del callback de salida, así que las dos van a la par.
- Dentro del callback no se reserva memoria, no hay bloqueos y no se lee ningún archivo. Las órdenes llegan por una cola SPSC y el estado sale por variables atómicas.
- Todo se cuenta en muestras enteras: un tiempo dura exactamente `round(fs × 60 / BPM)` muestras, así que compases y loops son múltiplos exactos y no hay deriva.
- La latencia se mide emitiendo un pulso y detectándolo en la entrada, con los índices absolutos de las muestras de salida y de entrada. Es el mismo valor que usa el looper para compensar la grabación.
- En cada callback se lee **toda** la entrada que haya llegado (no un bloque fijo, como hace `oboe::FullDuplexStream`), así no se acumula retraso. Entrada y salida se cuentan por separado y no necesitan bloques iguales.
- El looper decide todo (inicio, fin, overdub) en índices de salida, que es lo que oye el músico. La muestra de entrada *j* se tocó mientras sonaba la salida *j − latencia*, y se escribe en esa posición del loop: la escritura va con retraso, a medida que llega la entrada (un anillo de 6 s guarda lo último).
- Cada overdub va a una capa aparte para poder deshacerlo. Al acabar el siguiente overdub, la capa anterior se suma al loop base poco a poco en segundo plano; como lo que suena es la suma de todo, no se nota.
