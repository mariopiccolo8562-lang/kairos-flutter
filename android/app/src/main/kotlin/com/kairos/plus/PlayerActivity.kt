package com.kairos.plus

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.TextUtils
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Lettore a schermo intero, nativo (Media3/ExoPlayer su SurfaceView): il video non passa
 * dall'interfaccia Flutter, così resta fluido anche sulle Fire TV Stick.
 *
 * Diretta: ▲▼ (o CH+/CH−) cambia canale, i numeri vanno al canale, OK mostra le informazioni.
 * Film ed episodi: OK pausa, ◀▶ indietro/avanti (tenendo premuto accelera), l'episodio dopo parte da solo.
 *
 * Recupero (Kairos Adaptive, sezione 6): ai primi stalli non si riavvia nulla, si allarga il cuscinetto;
 * il cambio di formato TS↔HLS avviene solo per errori della sorgente o se il TS continua a fermarsi;
 * dopo 8 tentativi in 5 minuti si chiede al cliente («Riprova» o l'altro formato).
 */
@OptIn(UnstableApi::class)
class PlayerActivity : Activity() {
    companion object {
        @Volatile private var current: PlayerActivity? = null

        /** chiude il lettore aperto (es. «Disconnetti» dal pannello) */
        fun closeCurrent() {
            val a = current ?: return
            a.runOnUiThread {
                if (!a.isFinishing) {
                    a.kicked = true
                    a.leave()
                }
            }
        }

        private val RETRY = longArrayOf(1_000, 2_000, 4_000, 8_000)
        private val ACCENT = 0xFFA855F7.toInt()
        private const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
        private const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT
        private const val MAX_RETRIES = 8
        private const val RETRY_WINDOW_MS = 5 * 60_000L
    }

    private class Item(
        val key: String,
        val title: String,
        val sub: String,
        val urls: List<String>,
        val live: Boolean,
        val kind: String,
        val num: Int,
        val epg: String,
        val group: String,
        val chId: String,
    )

    private val h = Handler(Looper.getMainLooper())
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
    private var items: List<Item> = emptyList()
    private var idx = 0
    private var ua = "KairosPlus"
    private var devClass = "" // D | N | O (da Dart, altrimenti calcolata da Adaptive)

    private var player: ExoPlayer? = null
    private var playerCls = -1 // classe effettiva con cui è stato costruito il lettore
    private var profile = Adaptive.profile(Adaptive.NORMAL, true)
    private var pendingSeek = 0L
    private var urlIdx = 0
    private var curFmt = "ts" // formato effettivo in uso (hls / ts / estensione del file)
    private var attempt = 0
    private var retryPending = false // un nuovo tentativo è già in programma
    private var statusTimed = false // messaggio di stato a tempo (non va tolto al READY)
    private var bufferingSince = 0L
    private var readyOnce = false
    private var errorShown = false
    private var seekTarget = -1L
    private var zapBuf = ""
    private var kicked = false
    private var leaving = false
    private var epgSeq = 0
    private var epgAt = 0L
    private var progs: List<Epg.Prog> = emptyList()
    private var lastProgressEvent = 0L
    private val updates = LinkedHashMap<String, JSONObject>()
    private val clock = SimpleDateFormat("HH:mm", Locale.ITALY)

    // --- stalli, cuscinetto e statistiche (Kairos Adaptive)
    private var openAt = 0L
    private var firstReadyAt = 0L // primo READY di questo avvio
    private var transitionAt = 0L // ultimo seek / cambio traccia / nuovo prepare: il buffering che segue non è uno stallo
    private var bufEligible = false // il buffering in corso conta come stallo
    private var stallCounted = false
    private var stallMs = 0L
    private val stallLog = ArrayDeque<Pair<Long, Int>>() // (elapsedRealtime, indice del canale) dell'ultima ora
    private val retryLog = ArrayDeque<Long>() // tentativi degli ultimi 5 minuti
    private var longBuf = 0 // buffering lunghi consecutivi sullo stesso contenuto
    private var behindLive = 0
    private var holding = false // cuscinetto crescente: in pausa finché il buffer non è abbastanza pieno
    private var holdTarget = 0L
    private var holdStart = 0L
    private var audioOff = false
    private var lastGoodPos = 0L
    private var endedAtPos = -1L
    private var ttff = 0L
    private var fill = 0.0
    private var fillDone = false
    private var fillB0 = 0L
    private var lastStatsEvent = 0L

    // --- riquadro qualità · risoluzione · FPS dei canali in diretta (permesso «resInd» del pannello)
    private var resInd = true
    private var resKnown = false // primo fotogramma del canale già a schermo
    private var resHeight = 0
    private var resUntil = 0L

    private lateinit var pv: PlayerView
    private lateinit var topBox: LinearLayout
    private lateinit var bottomBox: LinearLayout
    private lateinit var titleV: TextView
    private lateinit var subV: TextView
    private lateinit var clockV: TextView
    private lateinit var spin: ProgressBar
    private lateinit var pauseV: View
    private lateinit var msgV: TextView
    private lateinit var statusV: TextView
    private lateinit var zapV: TextView
    private lateinit var bar: ProgressBar
    private lateinit var timeRow: LinearLayout
    private lateinit var tStart: TextView
    private lateinit var tEnd: TextView
    private lateinit var nowV: TextView
    private lateinit var nextV: TextView
    private lateinit var hintV: TextView
    private lateinit var resV: TextView

    private val hideR = Runnable { hideOverlay() }
    private val tuneR = Runnable {
        resetRecovery()
        open()
    }
    private val zapR = Runnable { commitZap() }
    private val retryR = Runnable { open() }
    private val seekR = Runnable { commitSeek() }
    private val holdR = Runnable { pollHold() }
    private val resR = Runnable { updateRes() }
    private val statusHideR = Runnable {
        statusV.visibility = View.GONE
        statusTimed = false
    }
    // dopo 60 s di riproduzione buona i tentativi ripartono da zero (il tetto di 5 minuti resta)
    private val healthyR = Runnable {
        attempt = 0
        longBuf = 0
        behindLive = 0
    }
    private val tickR = object : Runnable {
        override fun run() {
            tick()
            h.postDelayed(this, 1_000)
        }
    }

    /* ---------------- ciclo di vita ---------------- */

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = this
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        parse(intent.getStringExtra("data") ?: "")
        if (items.isEmpty()) {
            finish()
            return
        }
        setContentView(buildUi())
        immersive()
        showOverlay()
    }

    override fun onStart() {
        super.onStart()
        if (items.isEmpty() || leaving) return
        open()
        h.removeCallbacks(tickR)
        h.post(tickR)
        event("foreground")
    }

    override fun onStop() {
        if (items.isNotEmpty()) {
            savePos()
            if (!cur().live) updates[cur().key]?.optLong("pos")?.let { if (it > 0) pendingSeek = it }
            h.removeCallbacksAndMessages(null)
            releasePlayer()
            if (!isFinishing) event("background")
        }
        super.onStop()
    }

    override fun onDestroy() {
        if (current === this) current = null
        h.removeCallbacksAndMessages(null)
        releasePlayer()
        io.shutdownNow()
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) immersive()
    }

    @Suppress("DEPRECATION")
    private fun immersive() {
        window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_FULLSCREEN
            or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN)
    }

    private fun parse(s: String) {
        try {
            val j = JSONObject(s)
            ua = j.optString("ua").ifEmpty { ua }
            devClass = j.optString("playerClass")
            resInd = j.optBoolean("resInd", true)
            val a = j.optJSONArray("items") ?: JSONArray()
            val list = ArrayList<Item>()
            for (i in 0 until a.length()) {
                val o = a.optJSONObject(i) ?: continue
                val urls = ArrayList<String>()
                o.optString("url").takeIf { it.isNotEmpty() }?.let { urls.add(it) }
                val alt = o.optJSONArray("alt")
                if (alt != null) {
                    for (k in 0 until alt.length()) {
                        val u = alt.optString(k)
                        if (u.isNotEmpty() && !urls.contains(u)) urls.add(u)
                    }
                }
                list.add(
                    Item(
                        key = o.optString("key"),
                        title = o.optString("title"),
                        sub = o.optString("sub"),
                        urls = urls,
                        live = o.optBoolean("live"),
                        kind = o.optString("kind"),
                        num = o.optInt("num", 0),
                        epg = o.optString("epg"),
                        group = o.optString("group"),
                        chId = o.optString("chId"),
                    ),
                )
            }
            items = list
            idx = j.optInt("index", 0).coerceIn(0, maxOf(0, list.size - 1))
            pendingSeek = j.optLong("resumeMs", 0L).coerceAtLeast(0L)
        } catch (_: Exception) {
            items = emptyList()
        }
    }

    private fun cur(): Item = items[idx]

    /* ---------------- riproduzione ---------------- */

    private val listener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            val now = SystemClock.elapsedRealtime()
            when (playbackState) {
                Player.STATE_BUFFERING -> {
                    if (bufferingSince == 0L) {
                        bufferingSince = now
                        // stallo solo se il video andava da almeno 4 s e non è un seek / cambio traccia
                        bufEligible = readyOnce && firstReadyAt > 0 && now - firstReadyAt >= 4_000 && now - transitionAt > 1_500
                        stallCounted = false
                    }
                    spin.visibility = View.VISIBLE
                }
                Player.STATE_READY -> {
                    if (!readyOnce) {
                        readyOnce = true
                        firstReadyAt = now
                        fillB0 = player?.bufferedPosition ?: 0L
                    } else if (bufferingSince > 0) {
                        val d = now - bufferingSince
                        if (!stallCounted && bufEligible && d >= 1_000) noteStall(now)
                        if (stallCounted) {
                            stallMs += d
                            afterStall(now)
                        }
                    }
                    bufferingSince = 0L
                    if (!holding) spin.visibility = View.GONE
                    if (!statusTimed) statusV.visibility = View.GONE
                    h.removeCallbacks(healthyR)
                    h.postDelayed(healthyR, 60_000)
                }
                Player.STATE_ENDED -> onEnded()
                else -> {}
            }
            updatePause()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            updatePause()
        }

        override fun onRenderedFirstFrame() {
            if (ttff == 0L && openAt > 0) ttff = SystemClock.elapsedRealtime() - openAt
            // primo fotogramma del canale: qualità, risoluzione e FPS per qualche secondo
            if (!resKnown) {
                resKnown = true
                player?.videoSize?.height?.let { if (it > 0) resHeight = it }
                flashRes(6_000)
            }
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            // qualità adattiva: a ogni cambio di risoluzione il riquadro torna per qualche secondo
            val hgt = videoSize.height
            if (hgt <= 0) return
            val changed = resKnown && resHeight > 0 && hgt != resHeight
            resHeight = hgt
            if (changed) flashRes(4_000) else updateRes()
        }

        override fun onPlayerError(error: PlaybackException) {
            onError(error)
        }
    }

    /** classe effettiva ricalcolata a ogni avvio: se cambia, il lettore si ricostruisce con i buffer giusti */
    private fun ensurePlayer(): ExoPlayer {
        val live = items.any { it.live }
        val cls = Adaptive.effective(this, devClass)
        player?.let {
            if (cls == playerCls) return it
            releasePlayer()
        }
        profile = Adaptive.profile(cls, live)
        val p = Players.build(this, ua, live, cls)
        p.addListener(listener)
        pv.player = p
        player = p
        playerCls = cls
        audioOff = false
        return p
    }

    private fun releasePlayer() {
        val p = player ?: return
        player = null
        holding = false
        p.removeListener(listener)
        if (::pv.isInitialized) pv.player = null
        p.release()
        Adaptive.mode = Adaptive.Mode.NONE
        Adaptive.save(this, force = true)
    }

    private fun open() {
        h.removeCallbacks(retryR)
        h.removeCallbacks(holdR)
        holding = false
        val item = cur()
        msgV.visibility = View.GONE
        errorShown = false
        if (item.urls.isEmpty()) {
            showError("Indirizzo del contenuto mancante")
            return
        }
        val url = item.urls[urlIdx % item.urls.size]
        curFmt = Players.format(url, item.live)
        retryPending = false
        val p = ensurePlayer()
        // da qui i trasferimenti del lettore contano (o no) per la misura della banda
        Adaptive.mode = Adaptive.modeFor(url, item.live)
        val now = SystemClock.elapsedRealtime()
        openAt = now
        resKnown = false
        resHeight = 0
        resUntil = 0L
        updateRes()
        bufferingSince = now
        readyOnce = false
        firstReadyAt = 0L
        bufEligible = false
        stallCounted = false
        ttff = 0L
        fillDone = false
        lastStatsEvent = now
        spin.visibility = View.VISIBLE
        val start = if (!item.live && pendingSeek > 0) pendingSeek else C.TIME_UNSET
        lastGoodPos = if (start == C.TIME_UNSET) 0L else start
        pendingSeek = 0
        p.setMediaItem(Players.item(url), start)
        p.prepare()
        p.playWhenReady = true
        if (item.live && (progs.isEmpty() || epgSeq == 0)) loadEpg(item)
        updatePause()
        event("playing")
    }

    /** nuovo canale o titolo: tentativi, formato e contatori ripartono da zero */
    private fun resetRecovery() {
        attempt = 0
        urlIdx = 0
        pendingSeek = 0
        longBuf = 0
        behindLive = 0
        endedAtPos = -1L
        retryLog.clear()
        restoreAudio()
    }

    private fun restoreAudio() {
        if (!audioOff) return
        audioOff = false
        player?.let { it.trackSelectionParameters = it.trackSelectionParameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false).build() }
    }

    /** errore del decoder audio (AC-3 / MP2 assenti sulle chiavette): il video deve continuare */
    private fun isAudioDecoderError(e: PlaybackException): Boolean {
        val mime = (e as? ExoPlaybackException)?.rendererFormat?.sampleMimeType ?: return false
        if (!mime.startsWith("audio/")) return false
        return when (e.errorCode) {
            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES,
            PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED -> true
            else -> false
        }
    }

    private fun onError(e: PlaybackException) {
        val item = cur()
        val p = player
        val code = e.errorCode
        if (item.live && code == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
            behindLive++
            if (behindLive <= 3 && p != null) {
                transitionAt = SystemClock.elapsedRealtime()
                p.seekToDefaultPosition()
                p.prepare()
                return
            }
            // ricade sempre dietro la finestra: si prova l'altro formato
            event("error", JSONObject().put("code", code))
            scheduleRetry(switchFormat = true)
            return
        }
        if (!audioOff && p != null && isAudioDecoderError(e)) {
            audioOff = true
            p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true).build()
            transitionAt = SystemClock.elapsedRealtime()
            p.prepare()
            p.playWhenReady = true
            status("Audio non supportato da questo dispositivo: video senza audio", 8_000)
            event("error", JSONObject().put("code", code).put("audioOff", true))
            return
        }
        if (!item.live) p?.currentPosition?.let { if (it > 0) pendingSeek = it }
        event("error", JSONObject().put("code", code))
        // solo gli errori della sorgente (IO_*, PARSING_*, formato non riconosciuto) fanno cambiare formato
        scheduleRetry(switchFormat = code in 2000..3999)
    }

    private fun scheduleRetry(switchFormat: Boolean, text: String = "Connessione persa, riprovo…") {
        h.removeCallbacks(retryR)
        h.removeCallbacks(healthyR)
        h.removeCallbacks(holdR)
        holding = false
        bufferingSince = 0L
        val now = SystemClock.elapsedRealtime()
        while (retryLog.isNotEmpty() && now - retryLog.first() > RETRY_WINDOW_MS) retryLog.removeFirst()
        if (retryLog.size >= MAX_RETRIES) {
            showError("Il flusso continua a interrompersi")
            return
        }
        retryLog.addLast(now)
        val delay = RETRY[attempt.coerceAtMost(RETRY.size - 1)]
        attempt++
        if (switchFormat && cur().urls.size > 1) urlIdx++
        status(text, 0)
        retryPending = true
        h.postDelayed(retryR, delay)
    }

    private fun status(text: String, hideAfterMs: Long) {
        statusV.text = text
        statusV.visibility = View.VISIBLE
        statusTimed = hideAfterMs > 0
        h.removeCallbacks(statusHideR)
        if (statusTimed) h.postDelayed(statusHideR, hideAfterMs)
    }

    private fun retryNow() {
        attempt = 0
        retryLog.clear()
        open()
    }

    /** dalla schermata di errore: stesso contenuto con l'altro formato (HLS / TS) */
    private fun retryAlt() {
        attempt = 0
        retryLog.clear()
        urlIdx++
        open()
    }

    /** nome dell'altro formato disponibile (per i suggerimenti), null se non c'è */
    private fun altName(): String? {
        val item = cur()
        if (item.urls.size < 2) return null
        return if (Players.isHls(item.urls[(urlIdx + 1) % item.urls.size])) "HLS" else "TS"
    }

    private fun showError(m: String) {
        errorShown = true
        h.removeCallbacks(retryR)
        h.removeCallbacks(holdR)
        retryPending = false
        holding = false
        bufferingSince = 0L
        spin.visibility = View.GONE
        statusV.visibility = View.GONE
        pauseV.visibility = View.GONE
        player?.stop()
        updateRes()
        val hint = buildString {
            append("OK per riprovare")
            altName()?.let { append("  ·  ▶ prova in $it") }
            if (cur().live && items.size > 1) append("  ·  ▲▼ altro canale")
            append("  ·  Indietro per uscire")
        }
        msgV.text = m + "\n\n" + hint
        msgV.visibility = View.VISIBLE
    }

    /* ---------------- stalli e cuscinetto crescente ---------------- */

    private fun noteStall(now: Long) {
        stallCounted = true
        stallLog.addLast(Pair(now, idx))
        while (stallLog.isNotEmpty() && now - stallLog.first().first > 3_600_000L) stallLog.removeFirst()
        Adaptive.registerStall(this, cur().key)
        event("stall")
        // TS che continua a fermarsi (dal 3º stallo in 2 minuti sullo stesso canale): si passa all'HLS
        val recent = stallLog.count { it.second == idx && now - it.first <= 120_000L }
        if (curFmt == "ts" && recent >= 3 && cur().urls.size > 1) {
            if (!cur().live) player?.currentPosition?.let { if (it > 0) pendingSeek = it }
            scheduleRetry(switchFormat = true, text = "Flusso instabile, provo in HLS…")
        }
    }

    /** tornati in READY dopo uno stallo: in pausa finché il cuscinetto non cresce (2 s × stalli, max +6 s) */
    private fun afterStall(now: Long) {
        val p = player ?: return
        if (errorShown || retryPending) return
        val n = stallLog.count { it.second == idx && now - it.first <= 90_000L }
        val target = profile.rebufferMs + (2_000L * n).coerceAtMost(6_000L)
        if (p.totalBufferedDuration >= target) return
        holding = true
        holdTarget = target
        holdStart = now
        p.playWhenReady = false
        spin.visibility = View.VISIBLE
        h.removeCallbacks(holdR)
        h.postDelayed(holdR, 250)
    }

    private fun pollHold() {
        if (!holding) return
        val p = player
        val now = SystemClock.elapsedRealtime()
        val done = p == null || errorShown || p.playbackState != Player.STATE_READY ||
            p.totalBufferedDuration >= holdTarget || now - holdStart >= 15_000
        if (!done) {
            h.postDelayed(holdR, 250)
            return
        }
        holding = false
        if (p != null && !errorShown) {
            p.playWhenReady = true
            if (p.playbackState == Player.STATE_READY) spin.visibility = View.GONE
        }
        updatePause()
    }

    private fun cancelHold() {
        if (!holding) return
        holding = false
        h.removeCallbacks(holdR)
        if (player?.playbackState == Player.STATE_READY) spin.visibility = View.GONE
    }

    private fun onEnded() {
        val item = cur()
        if (item.live) {
            scheduleRetry(switchFormat = false)
            return
        }
        val p = player
        val dur = p?.duration ?: 0L
        val pos = p?.currentPosition ?: 0L
        // il server ha chiuso la transcodifica prima della fine: si riprende dall'ultima posizione buona
        // (se da lì non si avanza più, è davvero la fine)
        if ((dur <= 0 || pos < dur / 10 * 9) && lastGoodPos > 0 && (endedAtPos < 0 || lastGoodPos - endedAtPos >= 5_000)) {
            endedAtPos = lastGoodPos
            pendingSeek = lastGoodPos
            scheduleRetry(switchFormat = false, text = "Flusso interrotto, riprendo…")
            return
        }
        if (dur > 0) record(item, dur, dur)
        updates[item.key]?.let { event("progress", it) }
        if (idx + 1 < items.size) {
            idx++
            resetRecovery()
            showOverlay()
            open()
        } else {
            leave()
        }
    }

    private fun record(item: Item, pos: Long, dur: Long) {
        if (item.live || item.key.isEmpty() || dur <= 0) return
        updates[item.key] = JSONObject().put("key", item.key).put("pos", pos).put("dur", dur)
    }

    private fun savePos() {
        val p = player ?: return
        val item = cur()
        if (item.live) return
        val d = p.duration
        if (d > 0 && d != C.TIME_UNSET) record(item, p.currentPosition, d)
    }

    private fun tick() {
        val p = player
        val item = cur()
        val now = SystemClock.elapsedRealtime()
        if (p != null && !errorShown && bufferingSince > 0 && p.playWhenReady && !holding) {
            // stallo confermato dopo 1 s di buffering
            if (!stallCounted && bufEligible && now - bufferingSince >= 1_000) noteStall(now)
            // buffering lungo: prima si ricarica lo stesso indirizzo, se si ripete in TS si passa all'HLS
            val limit = if (!readyOnce) 20_000L else if (item.live) 12_000L else 20_000L
            if (!retryPending && now - bufferingSince > limit) {
                if (!item.live && p.currentPosition > 0) pendingSeek = p.currentPosition
                longBuf++
                scheduleRetry(switchFormat = curFmt == "ts" && longBuf >= 2)
            }
        }
        if (p != null && readyOnce && p.playbackState == Player.STATE_READY && p.currentPosition > 0) lastGoodPos = p.currentPosition
        // fill-ratio: secondi di video scaricati per secondo reale nei primi 10 s (TS: < 1 ⇒ la linea non regge)
        if (p != null && !fillDone && firstReadyAt > 0 && now - firstReadyAt >= 10_000) {
            fillDone = true
            fill = (p.bufferedPosition - fillB0).toDouble() / (now - firstReadyAt)
        }
        if (overlayShown()) updateTexts()
        if (::resV.isInitialized && resV.visibility == View.VISIBLE) updateRes() // es. FPS noti dopo
        if (!item.live) {
            savePos()
            if (now - lastProgressEvent > 10_000) {
                lastProgressEvent = now
                updates[item.key]?.let { event("progress", it) }
            }
        } else {
            if (now - lastStatsEvent > 30_000) {
                lastStatsEvent = now
                event("stats")
            }
            if (item.epg.isNotEmpty() && now - epgAt > 60_000 && progs.none { it.end > System.currentTimeMillis() }) {
                loadEpg(item) // il programma in onda è finito: guida aggiornata
            }
        }
    }

    private fun loadEpg(item: Item) {
        val seq = ++epgSeq
        progs = emptyList()
        epgAt = SystemClock.elapsedRealtime()
        if (item.epg.isEmpty()) return
        val url = item.epg
        val agent = ua
        try {
            io.execute {
                val list = Epg.fetch(url, agent)
                h.post {
                    if (seq == epgSeq && !isFinishing) {
                        progs = list
                        if (overlayShown()) updateTexts()
                    }
                }
            }
        } catch (_: Exception) {}
    }

    /* ---------------- comandi ---------------- */

    private fun zapBy(d: Int) {
        if (items.size <= 1) return
        idx = (idx + d).mod(items.size)
        epgSeq++
        progs = emptyList()
        msgV.visibility = View.GONE
        statusV.visibility = View.GONE
        errorShown = false
        resKnown = false // il riquadro torna con il primo fotogramma del canale nuovo
        cancelHold()
        player?.pause()
        showOverlay()
        h.removeCallbacks(tuneR)
        h.postDelayed(tuneR, 350)
    }

    private fun digit(n: Int) {
        if (zapBuf.length >= 4) zapBuf = ""
        zapBuf += n.toString()
        zapV.text = zapBuf
        zapV.visibility = View.VISIBLE
        updateRes()
        h.removeCallbacks(zapR)
        h.postDelayed(zapR, 1_500)
    }

    private fun commitZap() {
        val n = zapBuf.toIntOrNull()
        zapBuf = ""
        zapV.visibility = View.GONE
        updateRes()
        if (n == null) return
        val i = items.indexOfFirst { it.num == n }
        if (i < 0) {
            Toast.makeText(this, "Canale $n non trovato", Toast.LENGTH_SHORT).show()
            return
        }
        if (i == idx) return
        idx = i
        epgSeq++
        progs = emptyList()
        resetRecovery()
        showOverlay()
        open()
    }

    private fun seekBy(dir: Int, repeat: Int) {
        val p = player ?: return
        val dur = p.duration
        if (dur <= 0 || dur == C.TIME_UNSET) return
        val step = when {
            repeat > 12 -> 60_000L
            repeat > 4 -> 30_000L
            else -> 10_000L
        }
        val base = if (seekTarget >= 0) seekTarget else p.currentPosition
        seekTarget = (base + dir * step).coerceIn(0L, maxOf(0L, dur - 1_000L))
        updatePause()
        showOverlay()
        h.removeCallbacks(seekR)
        h.postDelayed(seekR, 650)
    }

    private fun commitSeek() {
        val t = seekTarget
        seekTarget = -1
        if (t >= 0) {
            cancelHold()
            transitionAt = SystemClock.elapsedRealtime()
            player?.seekTo(t)
        }
        updatePause()
        if (overlayShown()) updateTexts()
    }

    private fun togglePlay() {
        val p = player ?: return
        if (p.playWhenReady) {
            pause()
        } else {
            cancelHold()
            p.play()
        }
        showOverlay()
    }

    private fun pause() {
        val p = player ?: return
        cancelHold()
        p.pause()
        savePos()
        updates[cur().key]?.let { event("progress", it) }
    }

    private fun updatePause() {
        if (!::pauseV.isInitialized) return
        val p = player
        val paused = p != null && !cur().live && !p.playWhenReady && !holding && p.playbackState == Player.STATE_READY
        pauseV.visibility = if (paused && seekTarget < 0 && !errorShown) View.VISIBLE else View.GONE
    }

    private fun isPausedVod(): Boolean {
        val p = player ?: return false
        return !cur().live && !p.playWhenReady && !holding
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (items.isEmpty() || !::msgV.isInitialized) return super.onKeyDown(keyCode, event)
        val repeat = event.repeatCount
        if (keyCode == KeyEvent.KEYCODE_BACK || keyCode == KeyEvent.KEYCODE_ESCAPE) {
            if (repeat == 0) handleBack()
            return true
        }
        val item = cur()
        val ok = keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER || keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER
        if (errorShown) {
            if (ok) {
                if (repeat == 0) retryNow()
                return true
            }
            if (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT && altName() != null) {
                if (repeat == 0) retryAlt()
                return true
            }
        }
        if (item.live) {
            when (keyCode) {
                KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_CHANNEL_UP -> { zapBy(1); return true }
                KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_CHANNEL_DOWN -> { zapBy(-1); return true }
                KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_MENU, KeyEvent.KEYCODE_INFO -> { showOverlay(); return true }
            }
            if (ok) {
                if (repeat == 0) toggleOverlay()
                return true
            }
            if (keyCode >= KeyEvent.KEYCODE_0 && keyCode <= KeyEvent.KEYCODE_9) {
                if (repeat == 0) digit(keyCode - KeyEvent.KEYCODE_0)
                return true
            }
        } else {
            when (keyCode) {
                KeyEvent.KEYCODE_DPAD_LEFT -> { seekBy(-1, repeat); return true }
                KeyEvent.KEYCODE_DPAD_RIGHT -> { seekBy(1, repeat); return true }
                KeyEvent.KEYCODE_MEDIA_REWIND -> { seekBy(-1, maxOf(repeat, 5)); return true }
                KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> { seekBy(1, maxOf(repeat, 5)); return true }
                KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_MENU, KeyEvent.KEYCODE_INFO -> { showOverlay(); return true }
            }
            if (ok) {
                if (repeat == 0) togglePlay()
                return true
            }
        }
        when (keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> { if (repeat == 0) togglePlay(); return true }
            KeyEvent.KEYCODE_MEDIA_PLAY -> { if (repeat == 0) { cancelHold(); player?.play(); showOverlay() }; return true }
            KeyEvent.KEYCODE_MEDIA_PAUSE -> { if (repeat == 0) { pause(); showOverlay() }; return true }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK || keyCode == KeyEvent.KEYCODE_ESCAPE) return true
        return super.onKeyUp(keyCode, event)
    }

    private fun handleBack() {
        when {
            zapV.visibility == View.VISIBLE -> {
                h.removeCallbacks(zapR)
                zapBuf = ""
                zapV.visibility = View.GONE
                updateRes()
            }
            overlayShown() && !isPausedVod() && !errorShown -> {
                h.removeCallbacks(hideR)
                topBox.visibility = View.GONE
                bottomBox.visibility = View.GONE
                updateRes()
            }
            else -> leave()
        }
    }

    /** chiusura: a Flutter tornano le posizioni di visione */
    private fun leave() {
        if (leaving) return
        leaving = true
        savePos()
        val arr = JSONArray()
        updates.values.forEach { arr.put(it) }
        val out = JSONObject().put("index", idx).put("kicked", kicked).put("updates", arr).put("stats", stats())
        setResult(RESULT_OK, Intent().putExtra("result", out.toString()))
        finish()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_UP) {
            toggleOverlay()
            return true
        }
        return super.onTouchEvent(event)
    }

    /** misure per il pannello (sezione 9): banda, classi, fill-ratio, primo fotogramma, stalli, formato, frame persi */
    private fun stats(): JSONObject {
        val o = JSONObject()
        val bw = Adaptive.bitrate
        if (bw > 0) o.put("bw", Math.round(bw / 100_000.0) / 10.0)
        o.put("line", Adaptive.lineName(this)).put("dev", devClass.ifEmpty { Adaptive.deviceClass(this) })
            .put("fmt", curFmt).put("net", Adaptive.netType(this)).put("stallMs", stallMs)
        if (fillDone) o.put("fill", Math.round(fill * 100) / 100.0)
        if (ttff > 0) o.put("ttff", ttff)
        val now = SystemClock.elapsedRealtime()
        o.put("stalls10", stallLog.count { now - it.first <= 600_000L }).put("stallsH", stallLog.size)
        val c = player?.videoDecoderCounters
        if (c != null) {
            c.ensureUpdated()
            val total = c.renderedOutputBufferCount + c.droppedBufferCount
            if (total > 0) o.put("drop", Math.round(c.droppedBufferCount * 1000.0 / total) / 10.0)
        }
        return o
    }

    /** eventi per Flutter: canale in onda (pannello «Online ora»), posizione di visione, misure di rete */
    private fun event(type: String, extra: JSONObject? = null) {
        val ch = MainActivity.channel ?: return
        val item = items.getOrNull(idx) ?: return
        try {
            val o = if (extra != null) JSONObject(extra.toString()) else JSONObject()
            o.put("type", type).put("index", idx).put("key", item.key).put("live", item.live)
                .put("title", item.title).put("kind", item.kind).put("chId", item.chId).put("group", item.group)
                .put("stats", stats())
            ch.invokeMethod("playerEvent", o.toString())
        } catch (_: Exception) {}
    }

    /* ---------------- interfaccia ---------------- */

    private fun overlayShown(): Boolean = ::bottomBox.isInitialized && bottomBox.visibility == View.VISIBLE

    private fun showOverlay(ms: Long = 4_500) {
        if (!::bottomBox.isInitialized) return
        updateTexts()
        topBox.visibility = View.VISIBLE
        bottomBox.visibility = View.VISIBLE
        h.removeCallbacks(hideR)
        h.postDelayed(hideR, ms)
        updateRes()
    }

    private fun hideOverlay() {
        h.removeCallbacks(hideR)
        // in pausa (o con un errore) le informazioni restano a schermo
        if (isPausedVod() || errorShown || seekTarget >= 0) {
            h.postDelayed(hideR, 4_500)
            return
        }
        topBox.visibility = View.GONE
        bottomBox.visibility = View.GONE
        updateRes()
    }

    private fun toggleOverlay() {
        if (overlayShown()) {
            h.removeCallbacks(hideR)
            topBox.visibility = View.GONE
            bottomBox.visibility = View.GONE
            updateRes()
        } else {
            showOverlay()
        }
    }

    /** riquadro qualità · risoluzione · FPS per [ms] millisecondi (e sempre mentre è aperta la barra informazioni) */
    private fun flashRes(ms: Long) {
        if (!resInd || items.isEmpty() || !cur().live) return
        resUntil = SystemClock.elapsedRealtime() + ms
        h.removeCallbacks(resR)
        h.postDelayed(resR, ms + 50)
        updateRes()
    }

    /** solo canali in diretta, dopo il primo fotogramma; mai con un errore a schermo o mentre si digita un numero */
    private fun updateRes() {
        if (!::resV.isInitialized) return
        val show = resInd && resKnown && items.isNotEmpty() && cur().live && !errorShown && zapV.visibility != View.VISIBLE &&
            (overlayShown() || SystemClock.elapsedRealtime() < resUntil)
        val text = if (show) resLabel() else ""
        if (text.isEmpty()) {
            resV.visibility = View.GONE
            return
        }
        if (resV.text.toString() != text) resV.text = text
        resV.visibility = View.VISIBLE
    }

    /** es. «FHD · 1080p · 50 fps» (FPS omessi se il formato non li dice) */
    private fun resLabel(): String {
        val p = player ?: return ""
        val f = p.videoFormat
        val hgt = p.videoSize.height.takeIf { it > 0 } ?: f?.height?.takeIf { it > 0 } ?: resHeight
        if (hgt <= 0) return ""
        val q = when {
            hgt >= 2000 -> "4K"
            hgt >= 1000 -> "FHD"
            hgt >= 700 -> "HD"
            else -> "SD"
        }
        val fps = f?.frameRate ?: -1f
        return if (fps > 0f) "$q · ${hgt}p · ${Math.round(fps)} fps" else "$q · ${hgt}p"
    }

    private fun updateTexts() {
        val item = cur()
        titleV.text = if (item.live && item.num > 0) "${item.num}  ·  ${item.title}" else item.title
        subV.text = item.sub
        subV.visibility = if (item.sub.isEmpty()) View.GONE else View.VISIBLE
        clockV.text = clock.format(Date())
        if (item.live) liveBar() else vodBar()
    }

    private fun liveBar() {
        timeRow.visibility = View.GONE
        val now = System.currentTimeMillis()
        val curP = progs.firstOrNull { it.start <= now && now < it.end }
        val nextP = progs.firstOrNull { it.start >= (curP?.end ?: now) }
        if (curP != null) {
            nowV.visibility = View.VISIBLE
            nowV.text = "ORA   ${hm(curP.start)} – ${hm(curP.end)}   ${curP.title}"
            bar.visibility = View.VISIBLE
            bar.secondaryProgress = 0
            bar.progress = (((now - curP.start).toDouble() / (curP.end - curP.start)) * 1000).toInt().coerceIn(0, 1000)
        } else {
            nowV.visibility = View.GONE
            bar.visibility = View.GONE
        }
        if (nextP != null) {
            nextV.visibility = View.VISIBLE
            nextV.text = "DOPO   ${hm(nextP.start)}   ${nextP.title}"
        } else {
            nextV.visibility = View.GONE
        }
        hintV.text = if (items.size > 1) "${idx + 1} / ${items.size}   ·   ▲▼ cambia canale   ·   numeri: vai al canale   ·   OK informazioni"
        else "OK informazioni"
    }

    private fun vodBar() {
        val p = player
        nowV.visibility = View.GONE
        nextV.visibility = View.GONE
        val rawDur = p?.duration ?: 0L
        val dur = if (rawDur > 0 && rawDur != C.TIME_UNSET) rawDur else 0L
        val pos = if (seekTarget >= 0) seekTarget else (p?.currentPosition ?: 0L)
        bar.visibility = View.VISIBLE
        timeRow.visibility = View.VISIBLE
        bar.progress = if (dur > 0) ((pos.toDouble() / dur) * 1000).toInt().coerceIn(0, 1000) else 0
        bar.secondaryProgress = if (dur > 0) (((p?.bufferedPosition ?: 0L).toDouble() / dur) * 1000).toInt().coerceIn(0, 1000) else 0
        tStart.text = fmt(pos)
        tStart.textSize = if (seekTarget >= 0) 20f else 14f
        tEnd.text = if (dur > 0) fmt(dur) else ""
        hintV.text = "OK pausa   ·   ◀▶ indietro/avanti (tieni premuto per andare più veloce)" +
            (if (items.size > 1) "   ·   ${idx + 1} di ${items.size}" else "")
    }

    private fun hm(ms: Long): String = clock.format(Date(ms))

    private fun fmt(ms: Long): String {
        val s = (ms / 1000).coerceAtLeast(0)
        val hh = s / 3600
        val mm = (s % 3600) / 60
        val ss = s % 60
        return if (hh > 0) String.format(Locale.ITALY, "%d:%02d:%02d", hh, mm, ss) else String.format(Locale.ITALY, "%d:%02d", mm, ss)
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density + 0.5f).toInt()

    private fun rounded(color: Int, radius: Int): GradientDrawable = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius.toFloat()
    }

    private fun label(size: Float, color: Int, bold: Boolean = false): TextView = TextView(this).apply {
        setTextColor(color)
        textSize = size
        if (bold) typeface = Typeface.DEFAULT_BOLD
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        includeFontPadding = false
    }

    private fun lp(w: Int, h: Int, t: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(w, h).apply { topMargin = dp(t) }

    private fun pauseIcon(): View {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x99000000.toInt())
            }
            visibility = View.GONE
        }
        for (i in 0 until 2) {
            val b = View(this).apply { background = rounded(Color.WHITE, dp(3)) }
            box.addView(b, LinearLayout.LayoutParams(dp(10), dp(34)).apply { if (i == 1) leftMargin = dp(12) })
        }
        return box
    }

    private fun buildUi(): View {
        val root = FrameLayout(this)
        root.setBackgroundColor(Color.BLACK)

        pv = PlayerView(this).apply {
            useController = false
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setShutterBackgroundColor(Color.BLACK)
            setKeepContentOnPlayerReset(true)
            setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
            isFocusable = false
            isFocusableInTouchMode = false
        }
        root.addView(pv, FrameLayout.LayoutParams(MATCH, MATCH))

        // in alto: titolo, sottotitolo, orologio
        topBox = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(0xD9000000.toInt(), 0x00000000))
            setPadding(dp(48), dp(26), dp(48), dp(56))
        }
        val titles = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        titleV = label(22f, Color.WHITE, true)
        subV = label(14f, 0xCCFFFFFF.toInt())
        titles.addView(titleV, lp(MATCH, WRAP))
        titles.addView(subV, lp(MATCH, WRAP, 6))
        topBox.addView(titles, LinearLayout.LayoutParams(0, WRAP, 1f))
        clockV = label(18f, 0xE6FFFFFF.toInt(), true)
        topBox.addView(clockV, LinearLayout.LayoutParams(WRAP, WRAP).apply { leftMargin = dp(24) })
        root.addView(topBox, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.TOP))

        // in basso: guida (diretta) o avanzamento (film ed episodi)
        bottomBox = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, intArrayOf(0xE6000000.toInt(), 0x00000000))
            setPadding(dp(48), dp(64), dp(48), dp(28))
        }
        nowV = label(16f, Color.WHITE, true)
        bar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 1000
            isIndeterminate = false
            progressTintList = ColorStateList.valueOf(ACCENT)
            secondaryProgressTintList = ColorStateList.valueOf(0x66FFFFFF)
            progressBackgroundTintList = ColorStateList.valueOf(0x40FFFFFF)
        }
        timeRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        tStart = label(14f, Color.WHITE, true)
        tEnd = label(14f, 0xCCFFFFFF.toInt())
        timeRow.addView(tStart, LinearLayout.LayoutParams(0, WRAP, 1f))
        timeRow.addView(tEnd, LinearLayout.LayoutParams(WRAP, WRAP))
        nextV = label(14f, 0xCCFFFFFF.toInt())
        hintV = label(12f, 0x99FFFFFF.toInt())
        bottomBox.addView(nowV, LinearLayout.LayoutParams(MATCH, WRAP).apply { bottomMargin = dp(8) })
        bottomBox.addView(bar, LinearLayout.LayoutParams(MATCH, dp(4)))
        bottomBox.addView(timeRow, lp(MATCH, WRAP, 8))
        bottomBox.addView(nextV, lp(MATCH, WRAP, 10))
        bottomBox.addView(hintV, lp(MATCH, WRAP, 12))
        root.addView(bottomBox, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM))

        // al centro: caricamento, pausa, messaggi
        spin = ProgressBar(this).apply {
            isIndeterminate = true
            indeterminateTintList = ColorStateList.valueOf(ACCENT)
        }
        root.addView(spin, FrameLayout.LayoutParams(dp(56), dp(56), Gravity.CENTER))
        pauseV = pauseIcon()
        root.addView(pauseV, FrameLayout.LayoutParams(dp(84), dp(84), Gravity.CENTER))
        msgV = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.15f)
            setPadding(dp(32), dp(20), dp(32), dp(20))
            background = rounded(0xCC000000.toInt(), dp(12))
            visibility = View.GONE
        }
        root.addView(msgV, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        // in alto a destra, sotto l'orologio della barra informazioni: qualità, risoluzione e FPS (solo diretta)
        resV = label(13f, Color.WHITE, true).apply {
            setPadding(dp(10), dp(5), dp(10), dp(5))
            background = rounded(0xB3000000.toInt(), dp(6))
            isFocusable = false
            isFocusableInTouchMode = false
            visibility = View.GONE
        }
        root.addView(resV, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP or Gravity.END).apply { setMargins(0, dp(60), dp(48), 0) })
        statusV = label(14f, Color.WHITE).apply {
            setPadding(dp(14), dp(8), dp(14), dp(8))
            background = rounded(0xCC000000.toInt(), dp(20))
            visibility = View.GONE
        }
        root.addView(statusV, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP or Gravity.END).apply { setMargins(0, dp(96), dp(48), 0) })
        zapV = label(44f, Color.WHITE, true).apply {
            setPadding(dp(22), dp(8), dp(22), dp(8))
            background = rounded(0xCC000000.toInt(), dp(10))
            visibility = View.GONE
        }
        root.addView(zapV, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP or Gravity.END).apply { setMargins(0, dp(26), dp(48), 0) })
        return root
    }
}
