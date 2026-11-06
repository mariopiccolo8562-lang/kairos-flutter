package com.kairos.plus

import android.app.ActivityManager
import android.content.Context
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.SystemClock
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import androidx.media3.exoplayer.video.MediaCodecVideoRenderer
import androidx.media3.exoplayer.video.VideoRendererEventListener
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory

/**
 * Kairos Adaptive v1 (KAIROS_ADAPTIVE.md): classe del dispositivo (dalla RAM, separata dalla grafica
 * leggera), classe della linea (banda misurata e stalli, salvata con scadenza) e un solo misuratore di
 * banda per tutto il processo. La classe effettiva (debole / normale / ottima) è la peggiore delle due
 * e decide buffer, offset dalla diretta e ABR del lettore.
 */
@OptIn(UnstableApi::class)
object Adaptive {
    const val WEAK = 0
    const val NORMAL = 1
    const val GOOD = 2

    private const val PREFS = "kairos_adaptive"
    private const val DECAY_MS = 12 * 3_600_000L
    private const val MIN_SAMPLE_MS = 2_000L
    private const val MIN_SAMPLE_BYTES = 512L * 1024L
    private val LINE_NAMES = arrayOf("weak", "normal", "good")

    /** come arriva il flusso al lettore principale: TS live (misura il canale, non la rete), HLS, VOD progressivo */
    enum class Mode { NONE, HLS, VOD }

    /** parametri del DefaultLoadControl per una classe effettiva (tabella della sezione 2) */
    data class Profile(val minMs: Int, val maxMs: Int, val startMs: Int, val rebufferMs: Int, val bytes: Int, val backMs: Int)

    private var prefsStore: SharedPreferences? = null
    private var deviceClass = ""
    @Volatile private var meter: DefaultBandwidthMeter? = null
    private var initialEstimate = 0L
    private var lastSave = 0L
    private val stalls = ArrayDeque<Pair<Long, String>>() // (elapsedRealtime, canale) degli ultimi 30 minuti

    /** stima della banda (bit/s): EMA 0,2 sui soli campioni validi; 0 = nessuna misura */
    @Volatile var bitrate = 0L
        private set

    /** flusso in riproduzione nel lettore principale: decide quali trasferimenti misurano la banda */
    @Volatile var mode = Mode.NONE

    private fun prefs(ctx: Context): SharedPreferences =
        prefsStore ?: ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).also { prefsStore = it }

    /** D: ≤ 1,2 GB o Android < 7 · O: ≥ 2 GB (si presentano come ~1,9 GB) e Android ≥ 9 · N: il resto */
    @Synchronized
    fun deviceClass(ctx: Context): String {
        if (deviceClass.isNotEmpty()) return deviceClass
        val mb = try {
            val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val mi = ActivityManager.MemoryInfo()
            am.getMemoryInfo(mi)
            mi.totalMem / (1024L * 1024L)
        } catch (_: Exception) { 0L }
        val sdk = Build.VERSION.SDK_INT
        deviceClass = when {
            sdk < 24 || (mb in 1..1228) -> "D"
            mb >= 1900 && sdk >= 28 -> "O"
            else -> "N"
        }
        return deviceClass
    }

    /** classe effettiva per questo avvio: [dev] arriva da Dart (playerClass), altrimenti si calcola qui */
    @Synchronized
    fun effective(ctx: Context, dev: String = ""): Int {
        if (dev == "D" || dev == "N" || dev == "O") deviceClass = dev
        val d = deviceClass(ctx)
        val l = lineClass(ctx)
        return when {
            d == "D" || l == WEAK -> WEAK
            d == "O" && l == GOOD -> GOOD
            else -> NORMAL
        }
    }

    /** classe della linea salvata; senza misure nuove torna a normal dopo 12 ore */
    fun lineClass(ctx: Context): Int {
        val p = prefs(ctx)
        val saved = p.getInt("line", NORMAL)
        if (saved == NORMAL) return NORMAL
        return if (System.currentTimeMillis() - p.getLong("lineAt", 0L) > DECAY_MS) NORMAL else saved
    }

    fun lineName(ctx: Context): String = LINE_NAMES[lineClass(ctx).coerceIn(WEAK, GOOD)]

    fun profile(cls: Int, live: Boolean): Profile = when (cls) {
        WEAK -> if (live) Profile(12_000, 30_000, 1_500, 6_000, 16 shl 20, 0) else Profile(20_000, 40_000, 2_500, 4_000, 32 shl 20, 6_000)
        GOOD -> if (live) Profile(15_000, 60_000, 800, 3_000, 32 shl 20, 0) else Profile(25_000, 90_000, 800, 2_500, 64 shl 20, 12_000)
        else -> if (live) Profile(15_000, 50_000, 1_000, 4_000, 24 shl 20, 0) else Profile(20_000, 60_000, 1_000, 3_000, 48 shl 20, 10_000)
    }

    /** un solo misuratore per processo; stima iniziale: quella salvata ×0,8 oppure 2 / 6 / 12 Mbps per classe */
    @Synchronized
    fun meter(ctx: Context): DefaultBandwidthMeter {
        meter?.let { return it }
        val saved = prefs(ctx).getLong("bw", 0L)
        if (bitrate <= 0 && saved > 0) bitrate = saved
        initialEstimate = if (saved > 0) saved * 8 / 10 else when (effective(ctx)) {
            WEAK -> 2_000_000L
            GOOD -> 12_000_000L
            else -> 6_000_000L
        }
        return DefaultBandwidthMeter.Builder(ctx.applicationContext).setInitialBitrateEstimate(initialEstimate).build().also { meter = it }
    }

    fun modeFor(url: String, live: Boolean): Mode = when {
        Players.isHls(url) -> Mode.HLS
        live -> Mode.NONE
        else -> Mode.VOD
    }

    /** stallo sul canale [key]: la linea è debole con ≥ 2 stalli in 30 minuti su almeno 2 canali diversi */
    @Synchronized
    fun registerStall(ctx: Context, key: String) {
        stalls.addLast(Pair(SystemClock.elapsedRealtime(), key))
        evaluate(ctx, fromStall = true)
    }

    /** salva la stima su disco (al più ogni 30 s; [force] quando il lettore viene rilasciato) */
    @Synchronized
    fun save(ctx: Context, force: Boolean = false) {
        if (bitrate <= 0) return
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastSave < 30_000) return
        lastSave = now
        prefs(ctx).edit().putLong("bw", bitrate).apply()
    }

    /** tipo di rete per il pannello: wifi | eth | mobile | "" */
    @Suppress("DEPRECATION")
    fun netType(ctx: Context): String = try {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        when (cm.activeNetworkInfo?.type) {
            ConnectivityManager.TYPE_WIFI -> "wifi"
            ConnectivityManager.TYPE_ETHERNET -> "eth"
            ConnectivityManager.TYPE_MOBILE -> "mobile"
            else -> ""
        }
    } catch (_: Exception) { "" }

    @Synchronized
    private fun sample(ctx: Context, bps: Long) {
        if (bps <= 0 || bps == initialEstimate) return
        bitrate = if (bitrate <= 0) bps else (bitrate * 8 + bps * 2) / 10
        evaluate(ctx, fromStall = false)
        save(ctx)
    }

    /** regole della sezione 1; con sola evidenza «stalli» una linea debole non viene promossa */
    private fun evaluate(ctx: Context, fromStall: Boolean) {
        val now = SystemClock.elapsedRealtime()
        while (stalls.isNotEmpty() && now - stalls.first().first > 30 * 60_000L) stalls.removeFirst()
        val mbps = bitrate / 1_000_000.0
        val recent20 = stalls.count { now - it.first <= 20 * 60_000L }
        val channels = stalls.map { it.second }.toSet().size
        val cls = when {
            (bitrate > 0 && mbps < 4.0) || (stalls.size >= 2 && channels >= 2) -> WEAK
            bitrate > 0 && mbps >= 15.0 && recent20 == 0 -> GOOD
            else -> NORMAL
        }
        val p = prefs(ctx)
        val saved = p.getInt("line", NORMAL)
        if (cls == NORMAL && fromStall && saved == WEAK) return
        p.edit().putInt("line", cls).putLong("lineAt", System.currentTimeMillis()).apply()
    }

    /**
     * Filtro dei trasferimenti del lettore principale (l'anteprima non misura nulla).
     * - TS live: nessun campione (arriva alla velocità del canale, non della linea);
     * - HLS: segmenti e playlist vanno anche al DefaultBandwidthMeter (ABR); per la stima salvata si somma
     *   il solo tempo con trasferimenti attivi e si campiona con ≥ 512 KB e ≥ 2 s;
     * - VOD progressivo: la connessione resta aperta per tutto il film e poi è strozzata dal buffer, quindi
     *   vale un solo campione per connessione, preso appena il riempimento iniziale supera le soglie.
     */
    @OptIn(UnstableApi::class)
    class Gate(ctx: Context) : TransferListener {
        private val app = ctx.applicationContext
        private val open = HashMap<DataSource, Mode>()
        private var hlsActive = 0
        private var hlsSince = 0L
        private var hlsMs = 0L
        private var hlsBytes = 0L
        private var vodSince = 0L
        private var vodBytes = 0L
        private var vodSampled = false

        override fun onTransferInitializing(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {}

        override fun onTransferStart(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {
            val m = mode
            if (!isNetwork || m == Mode.NONE) return
            val now = SystemClock.elapsedRealtime()
            synchronized(this) {
                open[source] = m
                if (m == Mode.HLS) {
                    if (hlsActive == 0) hlsSince = now
                    hlsActive++
                } else {
                    vodSince = now
                    vodBytes = 0
                    vodSampled = false
                }
            }
            if (m == Mode.HLS) meter?.onTransferStart(source, dataSpec, isNetwork)
        }

        override fun onBytesTransferred(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean, bytesTransferred: Int) {
            var bps = 0L
            var m: Mode? = null
            synchronized(this) {
                m = open[source] ?: return
                if (m == Mode.HLS) {
                    hlsBytes += bytesTransferred
                } else {
                    vodBytes += bytesTransferred
                    val ms = SystemClock.elapsedRealtime() - vodSince
                    if (!vodSampled && ms >= MIN_SAMPLE_MS && vodBytes >= MIN_SAMPLE_BYTES) {
                        vodSampled = true
                        bps = vodBytes * 8_000L / ms
                    }
                }
            }
            if (m == Mode.HLS) meter?.onBytesTransferred(source, dataSpec, isNetwork, bytesTransferred)
            if (bps > 0) sample(app, bps)
        }

        override fun onTransferEnd(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {
            var bps = 0L
            var m: Mode? = null
            synchronized(this) {
                m = open.remove(source) ?: return
                if (m == Mode.HLS) {
                    val now = SystemClock.elapsedRealtime()
                    hlsMs += now - hlsSince
                    hlsSince = now
                    hlsActive = (hlsActive - 1).coerceAtLeast(0)
                    if (hlsMs >= MIN_SAMPLE_MS && hlsBytes >= MIN_SAMPLE_BYTES) {
                        bps = hlsBytes * 8_000L / hlsMs
                        hlsMs = 0
                        hlsBytes = 0
                    }
                }
            }
            if (m == Mode.HLS) meter?.onTransferEnd(source, dataSpec, isNetwork)
            if (bps > 0) sample(app, bps)
        }
    }

    private var gateInstance: Gate? = null

    @Synchronized
    fun gate(ctx: Context): Gate = gateInstance ?: Gate(ctx).also { gateInstance = it }
}

/**
 * ExoPlayer configurato per IPTV sulle Fire TV, anche quelle con poca memoria
 * (stessa configurazione collaudata di Kairos Lite e Kairos TV), con i parametri di Kairos Adaptive.
 */
@OptIn(UnstableApi::class)
object Players {
    /**
     * [cls] = classe effettiva di [Adaptive] (debole / normale / ottima): buffer, offset dalla diretta e ABR
     * seguono le tabelle di KAIROS_ADAPTIVE.md. [preview] = riquadro della TV in diretta: pochi secondi di
     * memoria, qualità adatta al riquadro e nessuna misura della banda.
     */
    fun build(ctx: Context, ua: String, live: Boolean, cls: Int, preview: Boolean = false): ExoPlayer {
        val http = DefaultHttpDataSource.Factory()
            .setUserAgent(ua)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(8_000) // con IPv6 morto 15 s se ne andavano prima di provare l'IPv4
            .setReadTimeoutMs(20_000)
        val extractors = DefaultExtractorsFactory()
            .setTsExtractorFlags(DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES or DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS)
        val data = DefaultDataSource.Factory(ctx, http)
        if (!preview) data.setTransferListener(Adaptive.gate(ctx))
        val sources = DefaultMediaSourceFactory(data, extractors)
        // HLS live: più lontani dal bordo e senza rincorsa, altrimenti i buffer della tabella sono irraggiungibili
        if (live && !preview) {
            when (cls) {
                Adaptive.WEAK -> sources.setLiveTargetOffsetMs(20_000).setLiveMinSpeed(1f).setLiveMaxSpeed(1f)
                Adaptive.NORMAL -> sources.setLiveTargetOffsetMs(12_000).setLiveMaxSpeed(1.02f)
                else -> {}
            }
        }
        // memoria per il video: il tetto in byte è la vera protezione dagli OOM (mai prioritizeTimeOverSizeThresholds)
        val pr = Adaptive.profile(cls, live)
        val load = if (preview) DefaultLoadControl.Builder()
            .setBufferDurationsMs(2_500, 8_000, 1_000, 2_000)
            .setTargetBufferBytes(6 shl 20)
            .setPrioritizeTimeOverSizeThresholds(false)
            .setBackBuffer(0, false)
            .build()
        else DefaultLoadControl.Builder()
            .setBufferDurationsMs(pr.minMs, pr.maxMs, pr.startMs, pr.rebufferMs)
            .setTargetBufferBytes(pr.bytes)
            .setPrioritizeTimeOverSizeThresholds(false)
            .setBackBuffer(pr.backMs, false)
            .build()
        val renderers = PlusRenderersFactory(ctx)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF)
        // ABR per classe (sezione 4): frazione di banda e tempo prima di salire di qualità
        val abr = when (cls) {
            Adaptive.WEAK -> AdaptiveTrackSelection.Factory(15_000, 25_000, 25_000, 0.55f)
            Adaptive.GOOD -> AdaptiveTrackSelection.Factory(6_000, 25_000, 25_000, 0.80f)
            else -> AdaptiveTrackSelection.Factory(10_000, 25_000, 25_000, 0.70f)
        }
        val selector = DefaultTrackSelector(ctx, abr)
        // niente qualità più alta dello schermo (una TV 720p non scarica il 1080p); audio in italiano se c'è
        selector.setParameters(selector.buildUponParameters().setViewportSizeToPhysicalDisplaySize(ctx, true).setPreferredAudioLanguage("it"))
        if (preview) {
            // anteprima: nei canali HLS con più qualità si prende la più bassa adatta al riquadro
            selector.setParameters(selector.buildUponParameters().setMaxVideoSize(960, 540).setMaxVideoBitrate(3_000_000))
        } else if (cls == Adaptive.WEAK) {
            // classe debole: tetto 1080p e 5 Mbps, l'ABR resta attivo sotto il tetto
            selector.setParameters(selector.buildUponParameters().setMaxVideoSize(1920, 1080).setMaxVideoBitrate(5_000_000))
        }
        val p = ExoPlayer.Builder(ctx, renderers)
            .setBandwidthMeter(Adaptive.meter(ctx))
            .setTrackSelector(selector)
            .setLoadControl(load)
            .setMediaSourceFactory(sources)
            .build()
        p.setVideoChangeFrameRateStrategy(C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS)
        return p
    }

    fun isHls(url: String): Boolean {
        val low = url.lowercase().substringBefore('?')
        return low.endsWith(".m3u8") || low.endsWith(".m3u")
    }

    /** formato effettivo per il pannello: hls | ts | estensione del file (VOD) */
    fun format(url: String, live: Boolean): String {
        if (isHls(url)) return "hls"
        if (live) return "ts"
        val ext = url.lowercase().substringBefore('?').substringAfterLast('.', "")
        return if (ext.length in 2..4) ext else "vod"
    }

    fun item(url: String): MediaItem {
        val b = MediaItem.Builder().setUri(Uri.parse(url))
        val low = url.lowercase().substringBefore('?')
        when {
            isHls(url) -> b.setMimeType(MimeTypes.APPLICATION_M3U8)
            low.endsWith(".ts") -> b.setMimeType(MimeTypes.VIDEO_MP2T)
        }
        return b.build()
    }
}

/**
 * Alcune Fire TV (chip MediaTek MT8695) bloccano il decoder quando cambia la superficie
 * (audio che continua, immagine ferma): su quei modelli il decoder viene ricreato.
 */
object SurfaceFix {
    private val MODELS = setOf("AFTSSS", "AFTSS", "AFTMM")
    fun needed(): Boolean = MODELS.contains(android.os.Build.MODEL)
}

@OptIn(UnstableApi::class)
class PlusRenderersFactory(ctx: Context) : DefaultRenderersFactory(ctx) {
    override fun buildVideoRenderers(
        context: Context, extensionRendererMode: Int, mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean, eventHandler: Handler, eventListener: VideoRendererEventListener,
        allowedVideoJoiningTimeMs: Long, out: ArrayList<Renderer>,
    ) {
        if (!SurfaceFix.needed()) {
            super.buildVideoRenderers(context, extensionRendererMode, mediaCodecSelector, enableDecoderFallback, eventHandler, eventListener, allowedVideoJoiningTimeMs, out)
            return
        }
        out.add(object : MediaCodecVideoRenderer(
            context, codecAdapterFactory, mediaCodecSelector, allowedVideoJoiningTimeMs, enableDecoderFallback, eventHandler, eventListener, MAX_DROPPED_VIDEO_FRAME_COUNT_TO_NOTIFY,
        ) {
            override fun codecNeedsSetOutputSurfaceWorkaround(name: String): Boolean =
                !(name.startsWith("OMX.google") || name.startsWith("c2.android")) || super.codecNeedsSetOutputSurfaceWorkaround(name)
        })
    }
}
