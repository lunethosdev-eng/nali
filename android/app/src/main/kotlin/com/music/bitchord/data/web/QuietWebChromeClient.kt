package com.music.bitchord.data.web

import android.webkit.ConsoleMessage
import android.webkit.WebChromeClient

/** Suppresses WebView console output from leaking into Android's global logcat. */
internal open class QuietWebChromeClient : WebChromeClient() {
    override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean = true
}
