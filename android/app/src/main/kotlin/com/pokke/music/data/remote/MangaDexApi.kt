package com.pokke.music.data.remote

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Manga search via the public Supabase Edge proxy. MangaDex is primary;
 * AniList is used automatically when MangaDex blocks cloud egress with 403.
 */
object MangaDexApi {
    private const val BASE = "https://api.mangadex.org"

    data class MangaItem(
        val id: String,
        val title: String,
        val coverUrl: String?,
        val description: String?,
        val year: Int?,
        val status: String?
    )

    suspend fun searchManga(query: String, limit: Int = 20): Result<List<MangaItem>> = withContext(Dispatchers.IO) {
        runCatching {
            require(query.isNotBlank()) { "Escribe un título de manga" }
            val payload = JSONObject().apply {
                put("query", query.trim())
                put("limit", limit.coerceIn(1, 32))
            }
            val json = JSONObject(functionPost("mangadex-search", payload.toString()))
            val data = json.optJSONArray("data") ?: JSONArray()
            (0 until data.length()).map { i ->
                val item = data.getJSONObject(i)
                val id = item.optString("id")
                val attrs = item.optJSONObject("attributes") ?: JSONObject()
                val titleObj = attrs.optJSONObject("title")
                val title = titleObj?.optString("en")?.takeIf { it.isNotBlank() }
                    ?: titleObj?.optString("romaji")?.takeIf { it.isNotBlank() }
                    ?: titleObj?.keys()?.asSequence()?.firstOrNull()?.let { titleObj.optString(it) }
                    ?: "Sin título"
                val descObj = attrs.optJSONObject("description")
                val desc = descObj?.optString("en")?.takeIf { it.isNotBlank() }
                val year = if (attrs.has("year") && !attrs.isNull("year")) attrs.optInt("year") else null
                val status = attrs.optString("status").takeIf { it.isNotBlank() }
                val coverFromFallback = attrs.optString("coverUrl").takeIf { it.startsWith("https://") }
                val coverFile = findCoverFileName(item.optJSONArray("relationships"))
                val coverUrl = coverFromFallback ?: coverFile?.let { "https://uploads.mangadex.org/covers/$id/$it.256.jpg" }
                MangaItem(id, title, coverUrl, desc?.take(280), year, status)
            }
        }
    }

    private fun functionPost(function: String, body: String): String {
        val connection = (URL("${KokoroConfig.SUPABASE_URL}/functions/v1/$function").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 12_000
            readTimeout = 18_000
            doOutput = true
            setRequestProperty("apikey", KokoroConfig.SUPABASE_ANON_KEY)
            setRequestProperty("Authorization", "Bearer ${KokoroConfig.SUPABASE_ANON_KEY}")
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
        }
        try {
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val response = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (code !in 200..299) throw java.io.IOException("Manga search proxy HTTP $code: ${response.take(160)}")
            return response
        } finally { connection.disconnect() }
    }

    suspend fun getManga(id: String): Result<MangaItem?> = withContext(Dispatchers.IO) {
        runCatching {
            val url = "$BASE/manga/$id?includes[]=cover_art"
            val json = JSONObject(httpGet(url))
            val item = json.optJSONObject("data") ?: return@runCatching null
            val attrs = item.getJSONObject("attributes")
            val titleObj = attrs.optJSONObject("title")
            val title = titleObj?.optString("en")?.takeIf { it.isNotBlank() }
                ?: titleObj?.keys()?.asSequence()?.firstOrNull()?.let { titleObj.optString(it) }
                ?: "Sin título"
            val coverFile = findCoverFileName(item.optJSONArray("relationships"))
            val coverUrl = coverFile?.let { "https://uploads.mangadex.org/covers/$id/$it.256.jpg" }
            MangaItem(id, title, coverUrl, null, null, attrs.optString("status").takeIf { it.isNotBlank() })
        }
    }

    private fun findCoverFileName(rels: JSONArray?): String? {
        if (rels == null) return null
        for (i in 0 until rels.length()) {
            val r = rels.getJSONObject(i)
            if (r.optString("type") == "cover_art") {
                return r.optJSONObject("attributes")?.optString("fileName")?.takeIf { it.isNotBlank() }
            }
        }
        return null
    }

    private fun httpGet(url: String): String {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 12_000
            readTimeout = 15_000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("User-Agent", "Pokke/1.0 (profile customization)")
        }
        try {
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (code !in 200..299) throw java.io.IOException("MangaDex HTTP $code: ${body.take(120)}")
            return body
        } finally {
            conn.disconnect()
        }
    }
}
