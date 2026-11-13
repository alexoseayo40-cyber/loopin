# Librerías de terceros

Todas son software libre y compatibles con la GPLv3 de Loopin. Van como código
fuente (F-Droid lo pide así).

| Carpeta | Qué es | Versión | Licencia | De dónde |
|---|---|---|---|---|
| `oboe/` | Audio de baja latencia de Google (submódulo de git) | 1.11.0 | Apache 2.0 | https://github.com/google/oboe |
| `soundtouch/` | Estirar el audio importado sin cambiar el tono; tempo sugerido | 2.4.1 (commit f738b11) | LGPL 2.1 (`soundtouch/COPYING.TXT`) | https://codeberg.org/soundtouch/soundtouch |
| `dr_libs/` | Leer WAV, MP3 y FLAC (`dr_wav.h` 0.14.7, `dr_mp3.h` 0.7.5, `dr_flac.h` 0.13.5) | commit f12e197 | Dominio público o MIT-0 (`dr_libs/LICENSE`) | https://github.com/mackron/dr_libs |

De SoundTouch solo se han copiado `include/` y los `.cpp`/`.h` de
`source/SoundTouch` que usa el motor, sin cambios. `soundtouch.cmake` los
compila (lo incluyen el motor y los tests del PC).
