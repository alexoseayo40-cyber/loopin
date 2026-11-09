// Loopin — actividad principal
// SPDX-License-Identifier: GPL-3.0-or-later
package io.github.alexoseayo40_cyber.loopin

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingMicResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // La versión 1 solo funciona en primer plano: mantenemos la pantalla encendida
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // Los botones de volumen controlan el volumen de la música
        volumeControlStream = AudioManager.STREAM_MUSIC
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "loopin/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestMicrophone" -> requestMicrophone(result)
                    "audioInfo" -> result.success(audioInfo())
                    "audioDevices" -> result.success(audioDevices())
                    else -> result.notImplemented()
                }
            }
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
