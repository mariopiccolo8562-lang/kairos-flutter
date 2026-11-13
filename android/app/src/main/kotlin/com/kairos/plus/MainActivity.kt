package com.kairos.plus

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

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

    /** link di riserva dell'APK decisi da Flutter (stesso APK sulle basi successive, poi GitHub): solo https */
    private fun alts(call: MethodCall): List<String> =
        (call.argument<List<Any?>>("alts") ?: emptyList()).mapNotNull { it as? String }.filter { it.startsWith("https://") }
    /** rete del dispositivo per «Online ora» del pannello: tipo (wifi, eth, mobile, none) e segnale Wi-Fi in dBm (13 novembre 2026) */
    private fun netInfo(): Map<String, Any> {
        val out = HashMap<String, Any>()
        var type = "none"
        try {
            val cm = getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
            if (android.os.Build.VERSION.SDK_INT >= 23) {
                val c = cm.activeNetwork?.let { cm.getNetworkCapabilities(it) }
                if (c != null) type = when {
                    c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET) -> "eth"
                    c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                    c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                    else -> ""
                }
            } else {
                @Suppress("DEPRECATION") val ni = cm.activeNetworkInfo
                @Suppress("DEPRECATION")
                if (ni != null && ni.isConnected) type = when (ni.type) {
                    android.net.ConnectivityManager.TYPE_ETHERNET -> "eth"
                    android.net.ConnectivityManager.TYPE_WIFI -> "wifi"
                    android.net.ConnectivityManager.TYPE_MOBILE -> "mobile"
                    else -> ""
                }
            }
            if (type == "wifi") {
                val wm = applicationContext.getSystemService(android.content.Context.WIFI_SERVICE) as android.net.wifi.WifiManager
                @Suppress("DEPRECATION") val wi = wm.connectionInfo
                if (wi != null && wi.rssi in -126..-1) out["rssi"] = wi.rssi
            }
        } catch (_: Throwable) { }
        out["type"] = type
        return out
    }


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        Quiet.watch(application) // Android 12+: aggiornamento senza conferma quando il cliente esce dall'app
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "netInfo" -> result.success(netInfo())
                "device" -> result.success(deviceInfo())
                "openInstallPerm" -> {
                    val ok = android.os.Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()
                    if (!ok) {
                        android.widget.Toast.makeText(this, "Attiva «Consenti da questa fonte» per gli aggiornamenti dell'app, poi premi INDIETRO", android.widget.Toast.LENGTH_LONG).show()
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
                            // elenchi di migliaia di canali: i dati restano in memoria (nell'Intent supererebbero il limite di Binder)
                            @Suppress("DEPRECATION")
                            startActivityForResult(PlayerActivity.intentFor(this, data), REQ_PLAY)
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
                // riquadro della qualità cambiato dal pannello durante la visione (permesso «resInd», voce «qbox»)
                "playerBox" -> result.success((call.arguments as? String)?.let { PlayerActivity.boxCurrent(it) } ?: false)
                // aggiornamento dell'app: stato, scaricamento in background, installazione (vedi Updater.kt)
                "updateStatus" -> {
                    // la verifica dell'APK già scaricato legge tutto il file: mai sul thread principale (scatti, ANR)
                    val code = (call.argument<Number>("code") ?: 0).toInt()
                    val app = applicationContext
                    thread(name = "kx-upd-status") {
                        val st = try { Updater.status(app, code) } catch (_: Exception) { emptyMap<String, Any>() }
                        runOnUiThread { result.success(st) }
                    }
                }
                "updatePrefetch" -> {
                    val url = call.argument<String>("url") ?: ""
                    val code = (call.argument<Number>("code") ?: 0).toInt()
                    if (url.startsWith("https://") && code > 0) Updater.prefetch(this, url, code, alts(call))
                    result.success(true)
                }
                "updateInstall" -> {
                    val url = call.argument<String>("url") ?: ""
                    val code = (call.argument<Number>("code") ?: 0).toInt()
                    if (url.startsWith("https://") && code > 0) Updater.install(this, url, code, alts(call))
                    result.success(true)
                }
                // è partita la visione: il download in background dell'APK si ferma (riparte a fine visione)
                "updateCancel" -> {
                    Updater.cancelPrefetch()
                    result.success(true)
                }
                // DNS cifrato (voce «sdns» del pannello): lo decide la parte Flutter, qui si accende e si spegne (DnsShield.kt)
                "dnsStart" -> { DnsShield.start(this); result.success(DnsShield.state) }
                "dnsStop" -> { DnsShield.stop(applicationContext); result.success(DnsShield.state) }
                "dnsState" -> result.success(DnsShield.state)
                // guida XMLTV di riserva (Guide.kt): Flutter passa le fonti in ordine e i canali (id della guida, nome)
                "guideBuild" -> {
                    val sources = (call.argument<List<Any?>>("sources") ?: emptyList()).mapNotNull { it as? String }
                    val channels = (call.argument<List<Any?>>("channels") ?: emptyList()).mapNotNull { row ->
                        (row as? List<*>)?.let { ((it.getOrNull(0) as? String) ?: "") to ((it.getOrNull(1) as? String) ?: "") }
                    }
                    val ua = call.argument<String>("ua") ?: "KairosPlus"
                    val force = call.argument<Boolean>("force") == true
                    result.success(try { Guide.build(applicationContext, sources, channels, ua, force) } catch (_: Throwable) { "error" })
                }
                "guideQuery" -> {
                    val epg = call.argument<String>("epg") ?: ""
                    val name = call.argument<String>("name") ?: ""
                    val limit = call.argument<Int>("limit") ?: 4
                    val app = applicationContext
                    Guide.reader.execute {
                        val list = Guide.query(app, epg, name, limit)
                        runOnUiThread { try { result.success(list) } catch (_: Throwable) {} }
                    }
                }
                "guideBuiltAt" -> result.success(Guide.builtAt(applicationContext))
                "guideResume" -> result.success(try { Guide.resume(applicationContext) } catch (_: Throwable) { "error" })
                // trailer di YouTube dentro l'app (TrailerActivity, in un processo a parte)
                "trailer" -> {
                    val id = Yt.id(call.argument<String>("yt") ?: "")
                    if (id == null) result.success(false)
                    else {
                        preview?.release()
                        TrailerActivity.start(this, id, call.argument<String>("title") ?: "")
                        result.success(true)
                    }
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
        if (requestCode == DnsShield.REQ) DnsShield.onConsent(applicationContext, resultCode == RESULT_OK)
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
