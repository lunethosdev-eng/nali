package com.pokke.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.pokke.music.data.preferences.UserPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import com.pokke.music.player.PlayerController
import com.pokke.music.player.PokkeAndroidPlayerHost
import com.pokke.music.player.PokkeCanvasPlayerHost

class MainActivity : AudioServiceActivity() {
    private val bridgeScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PlayerController.init(this)
        PokkeAndroidPlayerHost.install(applicationContext)
        PokkeCanvasPlayerHost.install(applicationContext)
    }

    private val audioChannel = "com.pokke.app/audio_output"

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterPlayerBridge(this, flutterEngine)
        val nativePreferences = UserPreferences(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nali/native_preferences")
            .setMethodCallHandler { call, result ->
                bridgeScope.launch {
                    try {
                        when (call.method) {
                            "getCanvasSettings" -> result.success(mapOf(
                                "appleMusic" to nativePreferences.appleCanvasEnabled.first(),
                                "spotify" to nativePreferences.spotifyCanvasEnabled.first(),
                                "external" to nativePreferences.externalCanvasEnabled.first(),
                                "repeat" to nativePreferences.canvasRepeatEnabled.first(),
                                "animatedCovers" to nativePreferences.pokkeAnimatedCoversEnabled.first(),
                            ))
                            "setCanvasSetting" -> {
                                val key = call.argument<String>("key") ?: error("Missing setting key")
                                val enabled = call.argument<Boolean>("enabled") ?: false
                                when (key) {
                                    "appleMusic" -> nativePreferences.setAppleCanvasEnabled(enabled)
                                    "spotify" -> nativePreferences.setSpotifyCanvasEnabled(enabled)
                                    "external" -> nativePreferences.setExternalCanvasEnabled(enabled)
                                    "repeat" -> nativePreferences.setCanvasRepeatEnabled(enabled)
                                    "animatedCovers" -> nativePreferences.setPokkeAnimatedCoversEnabled(enabled)
                                    else -> error("Unknown canvas setting: $key")
                                }
                                result.success(true)
                            }
                            else -> result.notImplemented()
                        }
                    } catch (error: Throwable) {
                        result.error("native_preferences_error", error.localizedMessage ?: "Preference update failed", null)
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getAudioOutput") {
                    result.success(currentOutput())
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        bridgeScope.cancel()
        super.onDestroy()
    }

    private fun currentOutput(): Map<String, String> {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            // Prefer Bluetooth, then wired, then built-in speaker
            val bt = devices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    (Build.VERSION.SDK_INT >= 31 && it.type == AudioDeviceInfo.TYPE_BLE_HEADSET) ||
                    (Build.VERSION.SDK_INT >= 31 && it.type == AudioDeviceInfo.TYPE_BLE_SPEAKER)
            }
            val wired = devices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                    it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_USB_DEVICE
            }
            val chosen = bt ?: wired
            if (chosen != null) {
                val name = chosen.productName?.toString()?.trim().orEmpty()
                val type = when (chosen.type) {
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
                    AudioDeviceInfo.TYPE_WIRED_HEADSET,
                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired"
                    else -> "other"
                }
                return mapOf(
                    "name" to if (name.isNotEmpty()) name else if (type == "bluetooth") "Bluetooth" else "Auriculares",
                    "type" to type
                )
            }
        }
        // Fallback pre-M / speaker
        @Suppress("DEPRECATION")
        if (am.isBluetoothA2dpOn) {
            return mapOf("name" to "Bluetooth", "type" to "bluetooth")
        }
        @Suppress("DEPRECATION")
        if (am.isWiredHeadsetOn) {
            return mapOf("name" to "Auriculares", "type" to "wired")
        }
        return mapOf("name" to "Este teléfono", "type" to "speaker")
    }
}
