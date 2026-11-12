package com.kairos.plus

import android.app.ActivityManager
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Guida XMLTV di riserva (come in Kairos XC e KAIROS Ultimate). La guida «breve» del server resta la prima scelta e la chiede
 * Flutter; qui c'è il resto:
 *  - la guida XMLTV del server (xmltv.php) e, dopo, quella esterna messa dal cliente: lette in sottofondo, una fonte dopo
 *    l'altra (a parità di canale e orario resta il programma letto per primo), e tenute in un piccolo archivio (guide.db);
 *  - i canali si riconoscono per id della guida oppure per nome, tolti paese e qualità (vedi EpgName);
 *  - la lettura non parte e si interrompe mentre il lettore è aperto; 24 ore di programmi (12 sui dispositivi con poca
 *    memoria), con un tetto; si rifà dopo 8 ore o quando cambiano le fonti o i canali.
 */
object Guide {
    private const val BUILD_MS = 8 * 60 * 60_000L
    private const val RETRY_MS = 30 * 60_000L
    private const val BATCH = 500
    private val TABLES = listOf(
        "CREATE TABLE IF NOT EXISTS prog (ch TEXT, start INTEGER, stop INTEGER, title TEXT, descr TEXT)",
        "CREATE INDEX IF NOT EXISTS prog_ch_stop ON prog(ch, stop)",
        "CREATE TABLE IF NOT EXISTS prog_stage (ch TEXT NOT NULL, start INTEGER NOT NULL, stop INTEGER NOT NULL, title TEXT NOT NULL, descr TEXT NOT NULL, PRIMARY KEY(ch, start))",
    )

    private class H(c: Context) : SQLiteOpenHelper(c, "guide.db", null, 1) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onCreate(db: SQLiteDatabase) { TABLES.forEach { db.execSQL(it) } }
        override fun onUpgrade(db: SQLiteDatabase, oldV: Int, newV: Int) = rebuild(db)
        override fun onDowngrade(db: SQLiteDatabase, oldV: Int, newV: Int) = rebuild(db)
        private fun rebuild(db: SQLiteDatabase) {
            listOf("prog", "prog_stage").forEach { db.execSQL("DROP TABLE IF EXISTS $it") }
            onCreate(db)
        }
    }

    @Volatile private var helper: H? = null
    private fun db(c: Context): H = helper ?: synchronized(this) { helper ?: H(c.applicationContext).also { helper = it } }
    private fun prefs(c: Context) = c.applicationContext.getSharedPreferences("guide", Context.MODE_PRIVATE)

    private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "kp-guide").apply { isDaemon = true; priority = Thread.MIN_PRIORITY } }
    /** letture per l'interfaccia: fuori dal thread principale, separate dalla costruzione */
    val reader = Executors.newSingleThreadExecutor { r -> Thread(r, "kp-guide-read").apply { isDaemon = true } }
    @Volatile private var running = false
    @Volatile private var failedSig = ""
    @Volatile private var retryAt = 0L

    private enum class Out { DONE, ABORTED, FAILED }

    /** richiesta rimandata o interrotta dal lettore: si riprende alla chiusura della visione, senza richiedere tutto a Flutter */
    private class Request(val sources: List<String>, val channels: List<Pair<String, String>>, val ua: String)
    @Volatile private var pending: Request? = null

    /** dopo la visione: riparte la lettura rimasta in sospeso (none se non ce n'era) */
    fun resume(c: Context): String {
        val r = pending ?: return "none"
        return build(c, r.sources, r.channels, r.ua, false)
    }

    /** chiavi con cui un canale è salvato nell'archivio: id della guida e nome «pulito» */
    fun keys(epg: String, name: String): List<String> = buildList(2) {
        epg.trim().lowercase(Locale.ROOT).takeIf { it.isNotEmpty() }?.let { add("id:$it") }
        EpgName.key(name).takeIf { it.isNotEmpty() }?.let { add("n:$it") }
    }

    fun builtAt(c: Context): Long = prefs(c).getLong("at", 0L)

    private fun signature(urls: List<String>, channels: List<Pair<String, String>>): String {
        val d = MessageDigest.getInstance("SHA-256")
        fun add(v: String) { d.update(v.toByteArray(Charsets.UTF_8)); d.update(0.toByte()) }
        urls.forEach(::add)
        channels.forEach { add(it.first.lowercase(Locale.ROOT)); add(EpgName.key(it.second)) }
        return d.digest().joinToString("") { "%02x".format(it) }
    }

    /**
     * Chiede di (ri)leggere la guida. Risponde subito: none (niente fonti o canali) | busy | fresh (già letta da meno di 8 ore
     * con le stesse fonti e gli stessi canali) | wait (ultimo tentativo fallito da poco) | player | started.
     */
    fun build(c: Context, sources: List<String>, channels: List<Pair<String, String>>, ua: String, force: Boolean): String {
        val app = c.applicationContext
        val urls = sources.map { it.trim() }.filter { it.startsWith("http://", true) || it.startsWith("https://", true) }.distinct().take(4)
        if (urls.isEmpty() || channels.isEmpty()) return "none"
        if (running) return "busy"
        if (PlayerActivity.isOpen()) { pending = Request(urls, channels, ua); return "player" }
        val sig = signature(urls, channels)
        val now = System.currentTimeMillis()
        val p = prefs(app)
        if (!force && p.getString("sig", "") == sig && now - p.getLong("at", 0L) < BUILD_MS) return "fresh"
        if (!force && failedSig == sig && now < retryAt) return "wait"
        running = true
        worker.execute {
            try {
                when (readAll(app, urls, channels, ua)) {
                    Out.DONE -> { pending = null; failedSig = ""; p.edit().putString("sig", sig).putLong("at", System.currentTimeMillis()).apply() }
                    Out.FAILED -> { pending = null; failedSig = sig; retryAt = System.currentTimeMillis() + RETRY_MS }
                    Out.ABORTED -> pending = Request(urls, channels, ua)
                }
            } catch (_: Throwable) {
                failedSig = sig; retryAt = System.currentTimeMillis() + RETRY_MS
            } finally { running = false }
        }
        return "started"
    }

    private fun readAll(app: Context, urls: List<String>, channels: List<Pair<String, String>>, ua: String): Out {
        val idMap = HashMap<String, MutableSet<String>>()
        val nameMap = HashMap<String, MutableSet<String>>()
        for ((epg, name) in channels) {
            val epgId = epg.trim().lowercase(Locale.ROOT)
            val nameKey = EpgName.key(name)
            val key = when { epgId.isNotEmpty() -> "id:$epgId"; nameKey.isNotEmpty() -> "n:$nameKey"; else -> "" }
            if (key.isEmpty()) continue
            if (epgId.isNotEmpty()) idMap.getOrPut(epgId) { LinkedHashSet() }.add(key)
            if (nameKey.isNotEmpty()) nameMap.getOrPut(nameKey) { LinkedHashSet() }.add(key)
        }
        if (idMap.isEmpty() && nameMap.isEmpty()) return Out.FAILED
        val index = XmltvIndex(idMap, nameMap)
        val low = try { (app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).isLowRamDevice } catch (_: Throwable) { false }
        val now = System.currentTimeMillis() / 1000L
        val ahead = if (low) 12L else 24L
        val limiter = XmltvLimiter(perChannel = 60, total = if (low) 16_000 else 40_000)
        val w = try { db(app).writableDatabase } catch (_: Throwable) { return Out.FAILED }
        var inTx = false
        var batch = 0
        var inserted = 0
        var anyOk = false
        fun flush() { if (inTx) { w.setTransactionSuccessful(); w.endTransaction(); inTx = false; batch = 0 } }
        fun clearStage() { try { if (inTx) { w.endTransaction(); inTx = false }; w.execSQL("DELETE FROM prog_stage") } catch (_: Throwable) {} }
        var st: android.database.sqlite.SQLiteStatement? = null
        return try {
            w.execSQL("DELETE FROM prog_stage")
            val ins = w.compileStatement("INSERT OR IGNORE INTO prog_stage(ch, start, stop, title, descr) VALUES(?,?,?,?,?)")
            st = ins
            for (url in urls) {
                if (PlayerActivity.isOpen()) throw XmltvAborted()
                var conn: HttpURLConnection? = null
                try {
                    conn = URL(url).openConnection() as HttpURLConnection
                    conn.connectTimeout = 15_000
                    conn.readTimeout = 20_000
                    conn.setRequestProperty("User-Agent", ua)
                    if (conn.responseCode != 200) continue // questa fonte non risponde: si prova la successiva
                    anyOk = true
                    XmltvParser.parse(
                        conn.inputStream, android.util.Xml.newPullParser(), index, now - 2 * 3600L, now + ahead * 3600L,
                        stopAtLimit = { limiter.full },
                        shouldAbort = { PlayerActivity.isOpen() },
                    ) { p ->
                        if (!limiter.accept(p.channel, p.start)) return@parse
                        if (!inTx) { w.beginTransactionNonExclusive(); inTx = true }
                        ins.clearBindings()
                        ins.bindString(1, p.channel); ins.bindLong(2, p.start); ins.bindLong(3, p.stop)
                        ins.bindString(4, p.title); ins.bindString(5, p.description)
                        if (ins.executeInsert() >= 0L) { inserted++; batch++ }
                        if (batch >= BATCH) flush()
                    }
                    flush()
                } catch (e: XmltvAborted) {
                    throw e
                } catch (_: Exception) {
                    flush() // fonte interrotta a metà: restano i programmi già letti, si passa alla successiva
                } finally { try { conn?.disconnect() } catch (_: Throwable) {} }
                if (limiter.full) break
            }
            ins.close(); st = null
            if (PlayerActivity.isOpen()) { clearStage(); return Out.ABORTED }
            if (inserted == 0) { clearStage(); return if (anyOk) Out.DONE.also { swapEmpty(w) } else Out.FAILED }
            w.beginTransactionNonExclusive()
            try {
                w.execSQL("DELETE FROM prog")
                w.execSQL("INSERT INTO prog(ch, start, stop, title, descr) SELECT ch, start, stop, title, descr FROM prog_stage")
                w.execSQL("DELETE FROM prog_stage")
                w.setTransactionSuccessful()
            } finally { w.endTransaction() }
            Out.DONE
        } catch (_: XmltvAborted) {
            clearStage(); Out.ABORTED
        } catch (_: Throwable) {
            clearStage(); Out.FAILED
        } finally {
            try { st?.close() } catch (_: Throwable) {}
            if (inTx) try { w.endTransaction() } catch (_: Throwable) {}
        }
    }

    /** le fonti hanno risposto ma senza programmi per questi canali: la guida vecchia si toglie, non si riprova per 8 ore */
    private fun swapEmpty(w: SQLiteDatabase) { try { w.execSQL("DELETE FROM prog") } catch (_: Throwable) {} }

    /** programmi da adesso in poi per il canale (vuoto se la guida non c'è): t titolo, d descrizione, s inizio ed e fine in ms */
    fun query(c: Context, epg: String, name: String, limit: Int): List<Map<String, Any>> {
        val k = keys(epg, name)
        if (k.isEmpty() || builtAt(c) <= 0L) return emptyList()
        val max = limit.coerceIn(1, 60)
        val now = System.currentTimeMillis() / 1000L
        val out = LinkedHashMap<Long, Map<String, Any>>()
        return try {
            val args = k.toTypedArray() + arrayOf(now.toString(), (max * 2).toString())
            db(c).readableDatabase.rawQuery(
                "SELECT start, stop, title, descr FROM prog WHERE ch IN (${k.joinToString(",") { "?" }}) AND stop > ? ORDER BY start LIMIT ?", args,
            ).use { cur ->
                while (cur.moveToNext() && out.size < max) {
                    val s = cur.getLong(0)
                    if (!out.containsKey(s)) out[s] = mapOf("t" to (cur.getString(2) ?: ""), "d" to (cur.getString(3) ?: ""), "s" to s * 1000L, "e" to cur.getLong(1) * 1000L)
                }
            }
            out.values.toList()
        } catch (_: Throwable) { emptyList() }
    }
}
