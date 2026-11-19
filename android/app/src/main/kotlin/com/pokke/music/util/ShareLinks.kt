package com.pokke.music.util

import android.content.Context
import android.content.Intent
import android.net.Uri

/** Builds and parses Pokke share links used by the phone and Android TV navigation hosts. */
object ShareLinks {
    private const val SCHEME = "pokke"
    private const val HOST = "share"
    private const val WEB_BASE_URL = "https://lunethosdev-eng.github.io/nali/"

    enum class Kind(val path: String, val label: String) {
        PROFILE("profile", "Perfil"),
        SONG("song", "Canción"),
        PLAYLIST("playlist", "Playlist"),
        LYRICS("lyrics", "Letra"),
        ARTIST("artist", "Artista"),
        ALBUM("album", "Álbum"),
    }

    sealed interface Target {
        data class Profile(val username: String) : Target
        data class Song(val id: String) : Target
        data class Playlist(val id: String) : Target
        data class Lyrics(val id: String) : Target
        /** A normal web URL that can be opened by the system browser. */
        data class Box(val url: Uri) : Target
    }

    fun share(context: Context, kind: Kind, id: String, title: String) {
        if (id.isBlank()) return
        val link = Uri.parse(WEB_BASE_URL).buildUpon()
            .fragment("/${kind.path}/$id")
            .build()
        val message = "$title\n$link"
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, message)
        }
        context.startActivity(Intent.createChooser(intent, "Compartir ${kind.label.lowercase()}"))
    }

    fun parse(uri: Uri?): Target? {
        uri ?: return null
        if (uri.scheme.equals("http", ignoreCase = true) || uri.scheme.equals("https", ignoreCase = true)) {
            val fragment = uri.fragment.orEmpty()
            if (uri.host == "lunethosdev-eng.github.io" && uri.path.startsWith("/nali/") && fragment.startsWith("/")) {
                val route = Uri.parse(fragment)
                val segments = route.pathSegments
                if (segments.size >= 2) return target(segments[0], segments[1])
            }
            val segments = uri.pathSegments
            if (segments.size >= 2 && segments.firstOrNull() == "share") {
                return target(segments[1], segments.getOrNull(2) ?: uri.getQueryParameter("id").orEmpty())
            }
            return Target.Box(uri)
        }
        if (!uri.scheme.equals(SCHEME, ignoreCase = true) || uri.host != HOST) return null
        val segments = uri.pathSegments
        val kind = segments.firstOrNull() ?: uri.getQueryParameter("type") ?: return null
        val id = segments.getOrNull(1) ?: uri.getQueryParameter("id") ?: return null
        return target(kind, id)
    }

    private fun target(kind: String, id: String): Target? {
        if (id.isBlank()) return null
        return when (kind.lowercase()) {
            "profile", "user" -> Target.Profile(id)
            "song", "track" -> Target.Song(id)
            "playlist" -> Target.Playlist(id)
            "lyrics", "lyric" -> Target.Lyrics(id)
            else -> null
        }
    }

    fun webForTarget(target: Target.Box): Uri = target.url
}
