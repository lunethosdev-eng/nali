package com.pokke.music.data.remote

import com.pokke.music.data.model.LyricLine
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL

object MusicMetadataApi {
    data class ArtistInfo(val name: String, val image: String?, val description: String?, val albums: Int?)
    data class LyricsResult(val lines: List<LyricLine>, val plain: String?)

    private fun get(url: String): String {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 9000; readTimeout = 9000; requestMethod = "GET"
            setRequestProperty("User-Agent", "Pokke/1.0 (Android music player)")
            setRequestProperty("Accept", "application/json")
        }
        return try {
            if (connection.responseCode !in 200..299) throw IllegalStateException("HTTP ${connection.responseCode}")
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally { connection.disconnect() }
    }

    fun lyrics(title: String, artist: String, album: String?, durationSeconds: Int): LyricsResult {
        // 1) LRCLIB (plain and line-synced).
        val lrclib = runCatching {
            val params = buildList {
                add("track_name=" + enc(title)); add("artist_name=" + enc(artist))
                if (!album.isNullOrBlank()) add("album_name=" + enc(album))
                if (durationSeconds in 1..3600) add("duration=$durationSeconds")
            }.joinToString("&")
            runCatching { JSONObject(get("https://lrclib.net/api/get?$params")) }.getOrElse {
                val results = JSONArray(get("https://lrclib.net/api/search?track_name=${enc(title)}&artist_name=${enc(artist)}"))
                if (results.length() == 0) throw it
                results.getJSONObject(0)
            }
        }.getOrNull()
        val lrclibSynced = lrclib?.optString("syncedLyrics")?.takeIf { it.isNotBlank() && it != "null" }
        val lrclibPlain = lrclib?.optString("plainLyrics")?.takeIf { it.isNotBlank() && it != "null" }
        if (!lrclibSynced.isNullOrBlank() || !lrclibPlain.isNullOrBlank()) {
            return LyricsResult(parseLrc(lrclibSynced), lrclibPlain ?: lrclibSynced)
        }

        // 2) Better Lyrics: free cached TTML results with syllable-level timing.
        if (durationSeconds in 1..3600) {
            val ttml = runCatching {
                val url = "https://api.betterlyrics.org/getLyrics?s=${enc(title)}&a=${enc(artist)}&al=${enc(album?.takeIf { it.isNotBlank() } ?: "Unknown")}&d=$durationSeconds"
                JSONObject(get(url)).optString("ttml").takeIf { it.isNotBlank() && it != "null" }
            }.getOrNull()
            val better = ttml?.let(::ttmlToLrc)
            if (!better.isNullOrBlank()) return LyricsResult(parseLrc(better), better)
        }

        // 3) Lyrics.ovh: free plain-text fallback, no API key.
        val lyricsOvh = runCatching {
            JSONObject(get("https://api.lyrics.ovh/v1/${enc(artist)}/${enc(title)}"))
                .optString("lyrics").takeIf { it.isNotBlank() && it != "null" }
        }.getOrNull()
        if (!lyricsOvh.isNullOrBlank()) return LyricsResult(emptyList(), lyricsOvh)
        return LyricsResult(emptyList(), null)
    }

    private fun parseLrc(raw: String?): List<LyricLine> = raw?.lineSequence()?.mapNotNull { line ->
        val match = Regex("\\[(\\d{2}):(\\d{2})(?:\\.(\\d{1,3}))?]\\s*(.*)").find(line) ?: return@mapNotNull null
        val min = match.groupValues[1].toLong(); val sec = match.groupValues[2].toLong()
        val ms = match.groupValues[3].padEnd(3, '0').take(3).toLongOrNull() ?: 0L
        LyricLine((min * 60 + sec) * 1000 + ms, match.groupValues[4])
    }?.toList().orEmpty()

    private fun ttmlToLrc(source: String): String? {
        val rows = Regex("<p\\b([^>]*)>([\\s\\S]*?)</p>", RegexOption.IGNORE_CASE).findAll(source).mapNotNull { match ->
            val begin = Regex("begin=[\"']([^\"']+)[\"']", RegexOption.IGNORE_CASE).find(match.groupValues[1])?.groupValues?.get(1) ?: return@mapNotNull null
            var text = match.groupValues[2].replace(Regex("<[^>]+>"), "")
                .replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").trim()
            if (text.isEmpty()) return@mapNotNull null
            val parts = begin.split(':')
            val seconds = runCatching {
                when (parts.size) {
                    3 -> parts[0].toLong() * 3600 + parts[1].toLong() * 60 + parts[2].toDouble()
                    2 -> parts[0].toLong() * 60 + parts[1].toDouble()
                    else -> parts[0].toDouble()
                }
            }.getOrNull() ?: return@mapNotNull null
            val ms = (seconds * 1000).toLong()
            val mm = ms / 60000; val ss = (ms % 60000) / 1000; val hundredths = (ms % 1000) / 10
            "[%02d:%02d.%02d]%s".format(mm, ss, hundredths, text)
        }.toList()
        return rows.takeIf { it.isNotEmpty() }?.joinToString("\n")
    }

    fun artistInfo(name: String): ArtistInfo {
        val q = enc(name)
        val search = JSONObject(get("https://api.deezer.com/search/artist?q=$q")).optJSONArray("data") ?: JSONArray()
        val first = if (search.length() > 0) search.getJSONObject(0) else null
        val artistName = first?.optString("name")?.takeIf { it.isNotBlank() } ?: name
        val image = first?.optString("picture_xl")?.takeIf { it.isNotBlank() && it != "null" }
            ?: first?.optString("picture_big")?.takeIf { it.isNotBlank() && it != "null" }
        val id = first?.optLong("id", -1L) ?: -1L
        val albumCount = if (id > 0) runCatching { JSONObject(get("https://api.deezer.com/artist/$id")).optInt("nb_album") }.getOrNull() else null
        val wiki = runCatching {
            val title = enc(artistName.replace(' ', '_'))
            JSONObject(get("https://en.wikipedia.org/api/rest_v1/page/summary/$title")).optString("extract").takeIf { it.isNotBlank() && it != "null" }
        }.getOrNull()
        return ArtistInfo(artistName, image, wiki, albumCount)
    }

    private fun enc(value: String) = URLEncoder.encode(value, "UTF-8")
}
