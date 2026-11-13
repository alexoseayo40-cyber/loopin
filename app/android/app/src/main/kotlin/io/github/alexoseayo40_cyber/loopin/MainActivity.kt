// Loopin — actividad principal
// SPDX-License-Identifier: GPL-3.0-or-later
package io.github.alexoseayo40_cyber.loopin

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingMicResult: MethodChannel.Result? = null
    private var pendingPickResult: MethodChannel.Result? = null

    // Controles externos: teclas que hacen de pedal (botones de volumen, botón
    // de los cascos, pedal Bluetooth…). Dart dice cuáles quiere.
    private var keysChannel: MethodChannel? = null
    private var capturedKeys: Set<Int> = emptySet()
    private var learningKeys = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // La versión 1 solo funciona en primer plano: mantenemos la pantalla encendida
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // Los botones de volumen controlan el volumen de la música
        volumeControlStream = AudioManager.STREAM_MUSIC
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        keysChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "loopin/keys").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setCapture" -> {
                        capturedKeys = (call.argument<List<Int>>("codes") ?: emptyList()).toSet()
                        learningKeys = call.argument<Boolean>("learning") ?: false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "loopin/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestMicrophone" -> requestMicrophone(result)
                    "audioInfo" -> result.success(audioInfo())
                    "audioDevices" -> result.success(audioDevices())
                    // Audio importado: carpeta de las canciones y elegir una
                    "songsDir" -> result.success(songsDir().absolutePath)
                    "pickAudio" -> pickAudio(result)
                    // Ajustes pequeños (texto) que se guardan entre sesiones
                    "prefsGet" -> result.success(
                        prefs().getString(call.argument<String>("key"), null)
                    )
                    "prefsSet" -> {
                        prefs().edit()
                            .putString(call.argument<String>("key"), call.argument<String>("value"))
                            .apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun prefs() = getSharedPreferences("loopin", MODE_PRIVATE)

    // Las canciones importadas se copian aquí (dentro de la app: no hace falta
    // ningún permiso y siguen aunque se borre el original)
    private fun songsDir(): File = File(filesDir, "songs").also { it.mkdirs() }

    // Abre el selector de archivos de Android (solo audio). Devuelve el nombre
    // del archivo copiado en songsDir, el nombre para mostrar y el tamaño; null
    // si se cancela.
    private fun pickAudio(result: MethodChannel.Result) {
        pendingPickResult?.success(null)
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "audio/mpeg", "audio/mp3", "audio/wav", "audio/x-wav", "audio/wave",
                    "audio/vnd.wave", "audio/flac", "audio/x-flac",
                ),
            )
        }
        try {
            startActivityForResult(intent, PICK_AUDIO)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("noPicker", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_AUDIO) return
        val result = pendingPickResult ?: return
        pendingPickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // Nombre y tamaño que da Android
        var name = "audio"
        var size = -1L
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val s = c.getColumnIndex(OpenableColumns.SIZE)
                if (n >= 0) name = c.getString(n) ?: name
                if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
            }
        }
        if (size > MAX_SONG_BYTES) {
            result.error("tooBig", null, null)
            return
        }
        // La copia puede tardar (un WAV largo): en otro hilo
        Thread {
            val ext = name.substringAfterLast('.', "").lowercase().take(5)
            val file = File(songsDir(), "${System.currentTimeMillis()}" +
                (if (ext.isNotEmpty()) ".$ext" else ""))
            try {
                var copied = 0L
                contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input)
                    file.outputStream().use { out ->
                        val buf = ByteArray(1 shl 16)
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            copied += n
                            if (copied > MAX_SONG_BYTES) throw IllegalStateException("tooBig")
                            out.write(buf, 0, n)
                        }
                    }
                }
                runOnUiThread {
                    result.success(mapOf("file" to file.name, "name" to name, "size" to copied))
                }
            } catch (e: Exception) {
                file.delete()  // lo que se haya copiado a medias
                val code = if (e.message == "tooBig") "tooBig" else "copy"
                runOnUiThread { result.error(code, e.message, null) }
            }
        }.start()
    }

    // Las teclas que hacen de pedal se pasan a Dart y no siguen su camino (así
    // los botones de volumen no cambian el volumen). Aquí llegan antes que a
    // nadie y sin esperas: el toque tiene que notarse al instante. Mientras se
    // «aprende» un pedal, se pasa cualquier tecla salvo las del sistema.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val channel = keysChannel
        val code = event.keyCode
        val wanted = if (learningKeys) code !in SYSTEM_KEYS else code in capturedKeys
        val downOrUp = event.action == KeyEvent.ACTION_DOWN || event.action == KeyEvent.ACTION_UP
        if (channel != null && wanted && downOrUp) {
            channel.invokeMethod(
                "key",
                mapOf(
                    "code" to code,
                    "down" to (event.action == KeyEvent.ACTION_DOWN),
                    "repeat" to event.repeatCount,
                    "name" to KeyEvent.keyCodeToString(code),
                )
            )
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    // Lo que el móvil dice que sabe hacer con el audio
    private fun audioInfo(): Map<String, Any> {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        val unprocessed =
            am.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
        return mapOf(
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "android" to Build.VERSION.RELEASE,
            "unprocessed" to unprocessed,
            "lowLatency" to packageManager.hasSystemFeature(PackageManager.FEATURE_AUDIO_LOW_LATENCY),
            "proAudio" to packageManager.hasSystemFeature(PackageManager.FEATURE_AUDIO_PRO),
        )
    }

    // Entradas y salidas de audio conectadas. El id es el que usa Oboe.
    private fun audioDevices(): Map<String, Any> {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        fun describe(d: AudioDeviceInfo): Map<String, Any> = mapOf(
            "id" to d.id,
            "type" to d.type,
            "name" to (d.productName?.toString() ?: ""),
            "address" to (if (Build.VERSION.SDK_INT >= 28) d.address else ""),
        )
        val inputs = am.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .filter { it.type in INPUT_TYPES }
            .map(::describe)
        val outputs = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map(::describe)
        return mapOf("inputs" to inputs, "outputs" to outputs)
    }

    // Devuelve "granted", "denied" o "permanentlyDenied"
    private fun requestMicrophone(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success("granted")
            return
        }
        pendingMicResult?.success("denied")
        pendingMicResult = result
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != MIC_REQUEST) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val answer = when {
            granted -> "granted"
            shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) -> "denied"
            else -> "permanentlyDenied"
        }
        pendingMicResult?.success(answer)
        pendingMicResult = null
    }

    companion object {
        private const val MIC_REQUEST = 4201
        private const val PICK_AUDIO = 4202

        // Un archivo de audio más grande no cabe (10 min de WAV de 24 bits a
        // 96 kHz en estéreo son unos 350 MB)
        private const val MAX_SONG_BYTES = 400L * 1024 * 1024

        // Teclas que nunca se capturan, ni al aprender un pedal
        private val SYSTEM_KEYS = setOf(
            KeyEvent.KEYCODE_BACK,
            KeyEvent.KEYCODE_HOME,
            KeyEvent.KEYCODE_APP_SWITCH,
            KeyEvent.KEYCODE_POWER,
            KeyEvent.KEYCODE_MENU,
        )

        // Entradas que sirven para tocar (fuera teléfono, radio FM, eco…)
        private val INPUT_TYPES = setOf(
            15, // TYPE_BUILTIN_MIC
            3,  // TYPE_WIRED_HEADSET
            5,  // TYPE_LINE_ANALOG
            6,  // TYPE_LINE_DIGITAL
            7,  // TYPE_BLUETOOTH_SCO
            11, // TYPE_USB_DEVICE
            12, // TYPE_USB_ACCESSORY
            22, // TYPE_USB_HEADSET
            26, // TYPE_BLE_HEADSET
        )
    }
}
