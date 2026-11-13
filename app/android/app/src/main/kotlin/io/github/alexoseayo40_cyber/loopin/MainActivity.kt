// Loopin — actividad principal
// SPDX-License-Identifier: GPL-3.0-or-later
package io.github.alexoseayo40_cyber.loopin

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
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
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveFiles: List<File> = emptyList()

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
                    // Sesiones (Etapa 6): su carpeta, y exportar y compartir
                    "sessionsDir" -> result.success(
                        File(filesDir, "sessions").also { it.mkdirs() }.absolutePath
                    )
                    "exportsDir" -> result.success(
                        exportsDir(call.argument<Boolean>("clear") ?: false).absolutePath
                    )
                    "shareFiles" -> shareFiles(call.argument<List<String>>("paths") ?: emptyList(), result)
                    "saveFiles" -> saveFiles(call.argument<List<String>>("paths") ?: emptyList(), result)
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
        if (requestCode == SAVE_TREE) {
            onSaveTree(if (resultCode == Activity.RESULT_OK) data?.data else null)
            return
        }
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

    // Lo exportado va a la caché (Android la vacía si le falta sitio); se
    // borra lo de la vez anterior al exportar otra vez
    private fun exportsDir(clear: Boolean): File {
        val dir = File(cacheDir, ExportProvider.EXPORTS)
        if (clear) dir.listFiles()?.forEach { it.delete() }
        dir.mkdirs()
        return dir
    }

    private fun exportFiles(paths: List<String>): List<File> {
        val dir = File(cacheDir, ExportProvider.EXPORTS).canonicalFile
        return paths.map { File(it).canonicalFile }.filter { it.parentFile == dir && it.isFile }
    }

    // «Compartir» de Android con los WAV (WhatsApp, Drive, correo…)
    private fun shareFiles(paths: List<String>, result: MethodChannel.Result) {
        val files = exportFiles(paths)
        if (files.isEmpty()) {
            result.success(null)
            return
        }
        val uris = ArrayList(files.map { ExportProvider.uriFor(packageName, it) })
        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        }
        intent.type = "audio/wav"
        // El permiso de leerlos viaja con el ClipData
        intent.clipData = ClipData.newRawUri(files[0].name, uris[0]).also { clip ->
            for (u in uris.drop(1)) clip.addItem(ClipData.Item(u))
        }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            startActivity(Intent.createChooser(intent, null))
            result.success(null)
        } catch (e: Exception) {
            result.error("noShare", e.message, null)
        }
    }

    // Copia los WAV en una carpeta que elige el usuario (Descargas, una
    // tarjeta…). Devuelve cuántos (null si cancela).
    private fun saveFiles(paths: List<String>, result: MethodChannel.Result) {
        val files = exportFiles(paths)
        if (files.isEmpty()) {
            result.success(0)
            return
        }
        pendingSaveResult?.success(null)
        pendingSaveResult = result
        pendingSaveFiles = files
        try {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), SAVE_TREE)
        } catch (e: Exception) {
            pendingSaveResult = null
            result.error("noPicker", e.message, null)
        }
    }

    private fun onSaveTree(tree: Uri?) {
        val result = pendingSaveResult ?: return
        pendingSaveResult = null
        val files = pendingSaveFiles
        if (tree == null) {
            result.success(null)
            return
        }
        Thread {
            try {
                val parent = DocumentsContract.buildDocumentUriUsingTree(
                    tree, DocumentsContract.getTreeDocumentId(tree)
                )
                var n = 0
                for (f in files) {
                    val doc = DocumentsContract.createDocument(
                        contentResolver, parent, "audio/wav", f.name
                    ) ?: continue
                    contentResolver.openOutputStream(doc).use { out ->
                        requireNotNull(out)
                        f.inputStream().use { it.copyTo(out, 1 shl 16) }
                    }
                    n++
                }
                runOnUiThread { result.success(n) }
            } catch (e: Exception) {
                runOnUiThread { result.error("save", e.message, null) }
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
        private const val SAVE_TREE = 4203

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
