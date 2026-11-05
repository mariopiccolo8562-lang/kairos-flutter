package com.kairos.plus

import android.util.Base64
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** Guida TV breve dei server Xtream (get_short_epg): programma in onda e successivo */
object Epg {
    class Prog(val title: String, val start: Long, val end: Long)

    fun fetch(url: String, ua: String): List<Prog> {
        var c: HttpURLConnection? = null
        return try {
            c = URL(url).openConnection() as HttpURLConnection
            c.connectTimeout = 8_000
            c.readTimeout = 10_000
            c.setRequestProperty("User-Agent", ua)
            if (c.responseCode != 200) return emptyList()
            val text = c.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            val arr = JSONObject(text).optJSONArray("epg_listings") ?: return emptyList()
            val out = ArrayList<Prog>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val s = o.optString("start_timestamp").trim().toLongOrNull() ?: continue
                val e = o.optString("stop_timestamp").trim().toLongOrNull() ?: continue
                if (e <= s) continue
                out.add(Prog(decode(o.optString("title")), s * 1000L, e * 1000L))
            }
            out.sortedBy { it.start }
        } catch (_: Exception) {
            emptyList()
        } finally {
            c?.disconnect()
        }
    }

    /** i titoli arrivano in base64 */
    private fun decode(s: String): String = try {
        String(Base64.decode(s, Base64.DEFAULT), Charsets.UTF_8).trim().ifEmpty { s }
    } catch (_: Exception) {
        s
    }
}
