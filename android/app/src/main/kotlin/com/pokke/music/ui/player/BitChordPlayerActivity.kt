package com.pokke.music.ui.player

import android.os.Bundle
import android.os.Build
import android.app.PictureInPictureParams
import android.util.Rational
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.pokke.music.data.repository.AuthRepository
import com.pokke.music.player.PlayerController
import com.pokke.music.ui.queue.QueueScreen

/** Hosts Tori's original BitChord Now Playing Compose screen for the Flutter shell. */
class BitChordPlayerActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PlayerController.init(applicationContext)
        val auth = AuthRepository(applicationContext)
        setContent {
            MaterialTheme {
                var showQueue by remember { mutableStateOf(false) }
                var showLyrics by remember { mutableStateOf(false) }
                LaunchedEffect(auth) { auth.restoreSession() }
                when {
                    showQueue -> QueueScreen(onBack = { showQueue = false })
                    showLyrics -> LyricsScreen(onBack = { showLyrics = false })
                    else -> BitChordNowPlayingHost(
                        authRepository = auth,
                        onClose = { finish() },
                        onOpenQueue = { showQueue = true },
                        onOpenLyrics = { showLyrics = true },
                        onRequireLogin = { toast("Inicia sesión en Nali para usar esta función") },
                        onOpenArtist = { name -> toast(name) },
                    )
                }
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val enabled = getSharedPreferences("nali_player", MODE_PRIVATE)
            .getBoolean("pip_enabled", false)
        if (!enabled || PlayerController.currentSong.value == null || isInPictureInPictureMode) return
        runCatching {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        }.onFailure { android.util.Log.w("NaliPiP", "Could not enter PiP", it) }
    }

    private fun toast(message: String) = Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
}
