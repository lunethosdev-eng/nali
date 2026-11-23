package com.pokke.music.data.youtube

import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.webkit.CookieManager
import com.music.bitchord.data.MonotonicClock
import com.music.bitchord.data.TrackLog
import com.music.bitchord.data.innertube.InnerTubeXResolver
import com.music.bitchord.data.innertube.potoken.PoTokenGenerator
import com.music.bitchord.data.innertube.potoken.PoTokenWebView
import com.pokke.music.BuildConfig

/**
 * Installs the Android-specific pieces required by BitChord's shared
 * InnerTubeX resolver: persistent player configuration, a monotonic clock,
 * debug logging and the BotGuard/PoToken WebView minter.
 */
object AndroidInnerTubeBootstrap {
    @Volatile private var initialized = false

    fun install(context: Context) {
        if (initialized) return
        synchronized(this) {
            if (initialized) return

            val app = context.applicationContext
            MonotonicClock.nowMs = SystemClock::elapsedRealtime
            TrackLog.echo = if (BuildConfig.DEBUG) {
                { level, tag, message, error ->
                    when (level) {
                        'E' -> Log.e(tag, message, error)
                        'W' -> Log.w(tag, message, error)
                        'I' -> Log.i(tag, message)
                        else -> Log.d(tag, message)
                    }
                }
            } else null
            InnerTubeXResolver.debugLogging = BuildConfig.DEBUG

            val preferences = app.getSharedPreferences(
                "innertubex_player_config",
                Context.MODE_PRIVATE,
            )
            val webViewSupported by lazy {
                runCatching { CookieManager.getInstance() }.isSuccess
            }
            val poTokens = PoTokenGenerator(
                createMinter = { PoTokenWebView.getNewPoTokenGenerator(app) },
                available = { webViewSupported },
            )

            InnerTubeXResolver.init(
                filesDir = app.filesDir,
                store = object : InnerTubeXResolver.ConfigStore {
                    override fun getString(key: String): String? =
                        preferences.getString(key, null)

                    override fun getLong(key: String): Long? =
                        if (preferences.contains(key)) preferences.getLong(key, 0L) else null

                    override fun putString(key: String, value: String) {
                        preferences.edit().putString(key, value).apply()
                    }

                    override fun putLong(key: String, value: Long) {
                        preferences.edit().putLong(key, value).apply()
                    }
                },
                poTokenProvider = poTokens.asTokenProvider(),
            )

            initialized = true
            Log.i("NaliInnerTube", "InnerTubeX and Android PoToken initialized")
        }
    }
}
