package com.kairos.plus

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Schermata principale (interfaccia Flutter) e ponte verso le parti native:
 * - "device": modello, memoria e versione, per il pannello e per la modalità leggera
 * - "play": apre il lettore nativo (Media3/ExoPlayer su SurfaceView, il più fluido sulle Fire TV)
 *   e restituisce le posizioni di visione quando si chiude
 * - "closePlayer": chiude il lettore (es. «Disconnetti» dal pannello)
 * Il lettore manda a Flutter gli eventi "playerEvent" (canale in onda, posizione).
 */
class MainActivity : FlutterActivity() {
    private var pendingPlay: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "device" -> result.success(deviceInfo())
                "play" -> {
                    val data = call.arguments as? String
                    if (data.isNullOrEmpty()) {
                        result.error("args", "Dati di riproduzione mancanti", null)
                    } else {
                        // una richiesta precedente rimasta senza risposta si chiude adesso
                        pendingPlay?.success(null)
                        pendingPlay = result
                        try {
                            @Suppress("DEPRECATION")
                            startActivityForResult(Intent(this, PlayerActivity::class.java).putExtra("data", data), REQ_PLAY)
                        } catch (e: Exception) {
                            pendingPlay = null
                            result.error("play", e.message ?: "Lettore non disponibile", null)
                        }
                    }
                }
                "closePlayer" -> {
                    PlayerActivity.closeCurrent()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PLAY) {
            val r = pendingPlay
            pendingPlay = null
            r?.success(data?.getStringExtra("result"))
        }
    }

    private fun deviceInfo(): Map<String, Any> {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        val version = try {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0).versionName ?: ""
        } catch (_: Exception) { "" }
        return mapOf(
            "model" to (Build.MANUFACTURER + " " + Build.MODEL).trim().take(80),
            "rawModel" to (Build.MODEL ?: ""),
            "release" to (Build.VERSION.RELEASE ?: ""),
            "sdk" to Build.VERSION.SDK_INT,
            "lowRam" to am.isLowRamDevice,
            "totalMemMb" to (mi.totalMem / (1024L * 1024L)).toInt(),
            "version" to version,
        )
    }

    companion object {
        const val CHANNEL = "kairos/native"
        private const val REQ_PLAY = 7301

        /** canale verso Flutter: il lettore lo usa per gli eventi */
        @Volatile var channel: MethodChannel? = null
    }
}
