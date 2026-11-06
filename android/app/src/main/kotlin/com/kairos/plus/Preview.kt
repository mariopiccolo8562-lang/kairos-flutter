package com.kairos.plus

import android.app.Activity
import android.graphics.Color
import android.view.Gravity
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import org.json.JSONObject
import kotlin.math.roundToInt

/**
 * Anteprima dei canali nella TV in diretta (come Kairos Lite e Kairos TV): al primo OK il canale
 * parte nel riquadro, al secondo si apre lo schermo intero.
 *
 * Il video è una vista nativa (SurfaceView) messa esattamente sopra il riquadro disegnato da Flutter:
 * lo compone il sistema, quindi resta fluido anche sulle chiavette e l'interfaccia non rallenta.
 * Un solo decoder alla volta: prima dello schermo intero il riquadro si chiude.
 */
@OptIn(UnstableApi::class)
class PreviewBox(private val activity: Activity, private val onEvent: (key: String, state: String) -> Unit) {
    private var box: FrameLayout? = null
    private var view: PlayerView? = null
    private var player: ExoPlayer? = null
    private var urls: List<String> = emptyList()
    private var urlIdx = 0
    private var key = ""

    private val listener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            if (key.isEmpty()) return
            when (playbackState) {
                Player.STATE_BUFFERING -> onEvent(key, "loading")
                Player.STATE_READY -> onEvent(key, "playing")
                else -> {}
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            if (key.isEmpty()) return
            // prima si prova l'altro formato del canale (HLS / MPEG-TS), poi il riquadro si arrende:
            // lo schermo intero ha il recupero automatico completo
            if (urlIdx + 1 < urls.size) {
                urlIdx++
                player?.let {
                    it.setMediaItem(Players.item(urls[urlIdx]))
                    it.prepare()
                    it.playWhenReady = true
                }
                return
            }
            try { player?.stop() } catch (_: Exception) {}
            box?.visibility = View.GONE
            onEvent(key, "error")
        }
    }

    /** dati da Flutter: key, url, alt, x, y, w, h (punti logici), ua, lite */
    fun show(data: String) {
        val j = try { JSONObject(data) } catch (_: Exception) { return }
        val url = j.optString("url")
        if (url.isEmpty()) return
        val list = ArrayList<String>()
        list.add(url)
        val alt = j.optJSONArray("alt")
        if (alt != null) {
            for (i in 0 until alt.length()) {
                val u = alt.optString(i)
                if (u.isNotEmpty() && !list.contains(u)) list.add(u)
            }
        }
        urls = list
        urlIdx = 0
        key = j.optString("key")
        val b = ensureBox()
        place(j)
        b.visibility = View.VISIBLE
        val p = player ?: Players.build(activity, j.optString("ua").ifEmpty { "KairosPlus" }, live = true, lite = j.optBoolean("lite"), preview = true).also {
            it.addListener(listener)
            view?.player = it
            player = it
        }
        onEvent(key, "loading")
        p.setMediaItem(Players.item(urls[0]))
        p.prepare()
        p.playWhenReady = true
    }

    /** il riquadro si è spostato (es. cambio di dimensioni dello schermo) */
    fun move(data: String) {
        val j = try { JSONObject(data) } catch (_: Exception) { return }
        if (box != null) place(j)
    }

    /** ferma il video e nasconde il riquadro (il lettore resta pronto per il prossimo canale) */
    fun stop() {
        val old = key
        key = ""
        try {
            player?.stop()
            player?.clearMediaItems()
        } catch (_: Exception) {}
        box?.visibility = View.GONE
        if (old.isNotEmpty()) onEvent(old, "stopped")
    }

    /** libera il decoder (prima dello schermo intero, uscendo dalla TV in diretta, app in pausa) */
    fun release() {
        stop()
        val p = player
        player = null
        view?.player = null
        if (p != null) {
            p.removeListener(listener)
            try { p.release() } catch (_: Exception) {}
        }
        val b = box
        box = null
        view = null
        (b?.parent as? ViewGroup)?.removeView(b)
    }

    private fun place(j: JSONObject) {
        val b = box ?: return
        val d = activity.resources.displayMetrics.density
        val lp = (b.layoutParams as? FrameLayout.LayoutParams) ?: FrameLayout.LayoutParams(1, 1)
        lp.gravity = Gravity.TOP or Gravity.START
        lp.leftMargin = (j.optDouble("x", 0.0) * d).roundToInt()
        lp.topMargin = (j.optDouble("y", 0.0) * d).roundToInt()
        lp.width = (j.optDouble("w", 16.0) * d).roundToInt().coerceAtLeast(1)
        lp.height = (j.optDouble("h", 9.0) * d).roundToInt().coerceAtLeast(1)
        b.layoutParams = lp
    }

    private fun ensureBox(): FrameLayout {
        box?.let { return it }
        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        val b = FrameLayout(activity).apply {
            setBackgroundColor(Color.BLACK)
            isFocusable = false
            isFocusableInTouchMode = false
            descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
            visibility = View.GONE
        }
        val pv = PlayerView(activity).apply {
            useController = false
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setShutterBackgroundColor(Color.BLACK)
            setKeepContentOnPlayerReset(false)
            setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
            isFocusable = false
            isFocusableInTouchMode = false
        }
        // il video va sopra la superficie su cui disegna Flutter (deve essere detto prima di agganciarla)
        (pv.videoSurfaceView as? SurfaceView)?.setZOrderMediaOverlay(true)
        b.addView(pv, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        root.addView(b, FrameLayout.LayoutParams(1, 1).apply { gravity = Gravity.TOP or Gravity.START })
        box = b
        view = pv
        return b
    }
}
