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
 * - "device": modello, memoria, versione e classe del lettore (D/N/O), per il pannello e per la modalità leggera
 * - "play": apre il lettore nativo (Media3/ExoPlayer su SurfaceView, il più fluido sulle Fire TV)
 *   e restituisce le posizioni di visione quando si chiude
 * - "closePlayer": chiude il lettore (es. «Disconnetti» dal pannello)
 * Il lettore manda a Flutter gli eventi "playerEvent" (canale in onda, posizione).
 */
class MainActivity : FlutterActivity() {
    private var pendingPlay: MethodChannel.Result? = null
    private var preview: PreviewBox? = null

    private fun previewBox(): PreviewBox = preview ?: PreviewBox(this) { key, state ->
        try {
            channel?.invokeMethod("previewEvent", org.json.JSONObject().put("key", key).put("state", state).toString())
        } catch (_: Exception) {}
    }.also { preview = it }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "device" -> result.success(deviceInfo())
                "openInstallPerm" -> {
                    val ok = android.os.Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()
                    if (!ok) {
                        android.widget.Toast.makeText(this, "Attiva «Consenti da questa fonte», poi premi INDIETRO", android.widget.Toast.LENGTH_LONG).show()
                        for (i in listOf(android.content.Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, android.net.Uri.parse("package:$packageName")), android.content.Intent(android.provider.Settings.ACTION_SETTINGS))) { try { startActivity(i); break } catch (_: Exception) {} }
                    }
                    result.success(ok)
                }
                "previewShow" -> {
                    (call.arguments as? String)?.let { previewBox().show(it) }
                    result.success(true)
                }
                "previewMove" -> {
                    (call.arguments as? String)?.let { preview?.move(it) }
                    result.success(true)
                }
                "previewStop" -> {
                    preview?.stop()
                    result.success(true)
                }
                "previewRelease" -> {
                    preview?.release()
                    result.success(true)
                }
                "play" -> {
                    // un solo decoder alla volta: l'anteprima si chiude prima dello schermo intero
                    preview?.release()
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
                // aggiornamento dell'app: stato, scaricamento in background, installazione (vedi Updater.kt)
                "updateStatus" -> result.success(Updater.status(this, (call.argument<Number>("code") ?: 0).toInt()))
                "updatePrefetch" -> {
                    val url = call.argument<String>("url") ?: ""
                    val code = (call.argument<Number>("code") ?: 0).toInt()
                    if (url.startsWith("https://") && code > 0) Updater.prefetch(this, url, code)
                    result.success(true)
                }
                "updateInstall" -> {
                    val url = call.argument<String>("url") ?: ""
                    val code = (call.argument<Number>("code") ?: 0).toInt()
                    if (url.startsWith("https://") && code > 0) Updater.install(this, url, code)
                    result.success(true)
                }
                // è partita la visione: il download in background dell'APK si ferma (riparte a fine visione)
                "updateCancel" -> {
                    Updater.cancelPrefetch()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPause() {
        // app in pausa (Home, lettore a schermo intero…): il riquadro libera il decoder
        preview?.release()
        super.onPause()
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
        val versionCode = try {
            val pi = packageManager.getPackageInfo(packageName, 0)
            @Suppress("DEPRECATION")
            (if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else pi.versionCode.toLong()).toInt()
        } catch (_: Exception) { 0 }
        return mapOf(
            "model" to (Build.MANUFACTURER + " " + Build.MODEL).trim().take(80),
            "rawModel" to (Build.MODEL ?: ""),
            "release" to (Build.VERSION.RELEASE ?: ""),
            "sdk" to Build.VERSION.SDK_INT,
            "lowRam" to am.isLowRamDevice,
            "totalMemMb" to (mi.totalMem / (1024L * 1024L)).toInt(),
            // classe del dispositivo per il lettore (Kairos Adaptive): D | N | O, separata dalla grafica leggera
            "playerClass" to Adaptive.deviceClass(this),
            "version" to version,
            "versionCode" to versionCode,
        )
    }

    companion object {
        const val CHANNEL = "kairos/native"
        private const val REQ_PLAY = 7301

        /** canale verso Flutter: il lettore lo usa per gli eventi */
        @Volatile var channel: MethodChannel? = null
    }
}
