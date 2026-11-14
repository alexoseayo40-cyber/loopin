# Loopin — cómo funciona el motor

Notas para quien quiera tocar el motor de audio (C++). Lo de compilar está en [BUILDING.md](BUILDING.md).

- Un stream full-duplex de Oboe: la entrada se lee dentro del callback de salida, así que las dos van a la par.
- Dentro del callback no se reserva memoria, no hay bloqueos y no se lee ningún archivo. Las órdenes llegan por una cola SPSC y el estado sale por variables atómicas.
- Todo se cuenta en muestras enteras: un tiempo dura exactamente `round(fs × 60 / BPM)` muestras, así que compases y loops son múltiplos exactos y no hay deriva.
- La latencia se mide emitiendo un pulso y detectándolo en la entrada, con los índices absolutos de las muestras de salida y de entrada. Es el mismo valor que usa el looper para compensar la grabación.
- En cada callback se lee **toda** la entrada que haya llegado (no un bloque fijo, como hace `oboe::FullDuplexStream`), así no se acumula retraso. Entrada y salida se cuentan por separado y no necesitan bloques iguales.
- El looper decide todo (inicio, fin, overdub) en índices de salida, que es lo que oye el músico. La muestra de entrada *j* se tocó mientras sonaba la salida *j − latencia*, y se escribe en esa posición del loop: la escritura va con retraso, a medida que llega la entrada (un anillo de 6 s guarda lo último).
- Las sesiones se leen y se cargan sin tocar el hilo de audio: el motor publica cuándo las pistas están «quietas» (no se graba, no queda entrada por capturar ni trabajo de fondo, y la cola de órdenes está vacía); solo entonces la interfaz las copia o escribe en ellas. Si la sesión se grabó a otra frecuencia, se pasa a la del móvil.
- Exportar usa un segundo núcleo del motor, sin audio, que vuelve a tocar la sesión: lo exportado es exactamente lo que suena. Dos pasadas: la primera mide el pico (si pasa de 0 dB, todo baja lo mismo) y la segunda escribe WAV de 16 bits.
- Cada overdub va a una capa aparte para poder deshacerlo. Al acabar el siguiente overdub, la capa anterior se suma al loop base poco a poco en segundo plano; como lo que suena es la suma de todo, no se nota.
- La batería es un secuenciador de muestras: al empezar cada tiempo apunta los golpes de ese tiempo con su desfase en muestras y los dispara al llegar. Como el tiempo dura un número entero de muestras y el tempo solo cambia al empezar uno, cada golpe cae siempre en la misma muestra respecto al compás.
- Las canciones importadas se decodifican (dr_libs) y se estiran (SoundTouch) **una vez**, en un hilo aparte, y se guardan en memoria en 16 bits, mono, con el 1 en un inicio de compás y compases enteros. El callback solo las lee. Si cambia el tempo, la canción se calla y se vuelve a preparar; entra en el siguiente 1 por donde iría. Los audios nuevos llegan al hilo de audio con un intercambio atómico y los viejos vuelven por una cola para borrarlos fuera de él.
- Cada pista se lee en una posición contada en medias muestras que avanza +2 (normal), +1 (media velocidad), −2 (al revés) o −1 por muestra; al cambiar hay un fundido cruzado de 5 ms. Un overdub sobre una pista con efecto se escribe donde se oye.
- El afinador copia la entrada en un anillo sin bloqueos y la analiza fuera del hilo de audio (YIN a ~24 kHz y el periodo afinado en la señal original: en los tests, menos de 1 cent de error de 41 a 1319 Hz).
- La carga del callback (media y pico de cada segundo, en % del tiempo disponible) se ve en Audio y latencia › Detalles técnicos y en «Copiar resultados».
