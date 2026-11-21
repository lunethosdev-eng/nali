package com.pokke.app

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.pokke.music.data.model.LyricLine
import com.pokke.music.data.model.Song
import com.pokke.music.player.PlayerController
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Flutter facade for the single Android/Media3 player. BitChord remains the native player UI. */
class FlutterPlayerBridge(private val activity: Activity, engine: FlutterEngine) {
    private val methods = MethodChannel(engine.dartExecutor.binaryMessenger, "nali/player")
    private val events = EventChannel(engine.dartExecutor.binaryMessenger, "nali/player/events")
    private var sink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    private val ticker = object : Runnable {
        override fun run() { sink?.success(snapshot()); handler.postDelayed(this, 350L) }
    }
    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) { sink = eventSink; handler.removeCallbacks(ticker); handler.post(ticker) }
            override fun onCancel(arguments: Any?) { sink = null; handler.removeCallbacks(ticker) }
        })
        methods.setMethodCallHandler(::handle)
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try { when (call.method) {
            "playQueue" -> {
                val maps = call.argument<List<Map<String, Any?>>>("songs").orEmpty()
                PlayerController.setShuffleEnabled(call.argument<Boolean>("shuffle") ?: false)
                PlayerController.playQueue(maps.map(::songFromMap), call.argument<Int>("startIndex") ?: 0)
                result.success(true)
            }
            "playSong" -> { val map = call.argument<Map<String, Any?>>("song"); if (map == null) result.error("bad_song", "Song payload missing", null) else { PlayerController.playSong(songFromMap(map)); result.success(true) } }
            "toggle" -> { PlayerController.togglePlayPause(); result.success(true) }
            "pause" -> { PlayerController.pause(); result.success(true) }
            "resume" -> { PlayerController.resume(); result.success(true) }
            "next" -> { PlayerController.playNext(); result.success(true) }
            "previous" -> { PlayerController.playPrevious(); result.success(true) }
            "seek" -> { PlayerController.seekTo(call.argument<Number>("positionMs")?.toLong() ?: 0L); result.success(true) }
            "shuffle" -> { PlayerController.toggleShuffle(); result.success(true) }
            "repeat" -> {
                val next = when (PlayerController.repeatMode.value) {
                    androidx.media3.common.Player.REPEAT_MODE_OFF -> androidx.media3.common.Player.REPEAT_MODE_ALL
                    androidx.media3.common.Player.REPEAT_MODE_ALL -> androidx.media3.common.Player.REPEAT_MODE_ONE
                    else -> androidx.media3.common.Player.REPEAT_MODE_OFF
                }
                PlayerController.setRepeatMode(next); result.success(true)
            }
            "addToQueue" -> { val map = call.argument<Map<String, Any?>>("song"); if (map == null) result.error("bad_song", "Song payload missing", null) else { PlayerController.addToQueue(songFromMap(map), call.argument<Boolean>("playNext") ?: false); result.success(true) } }
            "playQueueItem" -> { PlayerController.playQueueItem(call.argument<Int>("index") ?: 0); result.success(true) }
            "removeQueueItem" -> { PlayerController.removeQueueItem(call.argument<Int>("index") ?: -1); result.success(true) }
            "moveQueueItem" -> { PlayerController.moveQueueItem(call.argument<Int>("from") ?: -1, call.argument<Int>("to") ?: -1); result.success(true) }
            "clearQueue" -> { PlayerController.clearQueue(); result.success(true) }
            "setVolume" -> { PlayerController.setVolume(call.argument<Number>("volume")?.toFloat() ?: 1f); result.success(true) }
            "openNativePlayer" -> {
                activity.startActivity(Intent(activity, com.pokke.music.ui.player.BitChordPlayerActivity::class.java))
                result.success(true)
            }
            "setPipEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                activity.getSharedPreferences("nali_player", android.content.Context.MODE_PRIVATE)
                    .edit().putBoolean("pip_enabled", enabled).apply()
                result.success(true)
            }
            "state" -> result.success(snapshot())
            else -> result.notImplemented()
        } } catch (t: Throwable) { result.error("player_error", t.localizedMessage ?: "Player operation failed", null) }
    }
    private fun songFromMap(m: Map<String, Any?>): Song {
        val lines = (m["lyrics"] as? List<*>)?.mapNotNull { it as? Map<*, *> }.orEmpty().mapNotNull { line ->
            val time = (line["timeMs"] ?: line["time_ms"] ?: line["time"]) as? Number
            val text = line["text"]?.toString()
            if (time == null || text == null) null else LyricLine(time.toLong(), text)
        }
        return Song(
            id = (m["id"] ?: m["video_id"] ?: m["youtube_id"] ?: m["title"] ?: "unknown").toString(),
            title = m["title"]?.toString().orEmpty(), artist = m["artist"]?.toString().orEmpty(),
            album = (m["album"] ?: m["album_name"])?.toString(),
            coverUrl = (m["cover_url"] ?: m["coverUrl"] ?: m["thumbnail_url"] ?: m["artwork_url"])?.toString(),
            animatedCoverUrl = (m["animated_cover_url"] ?: m["animatedCoverUrl"] ?: m["canvas_url"])?.toString(),
            audioUrl = (m["audio_url"] ?: m["audioUrl"] ?: m["stream_url"] ?: m["path"] ?: m["url"])?.toString(),
            durationSeconds = ((m["duration_seconds"] ?: m["duration"] ?: m["durationSeconds"]) as? Number)?.toInt() ?: 0,
            lyricsText = m["lyrics_text"]?.toString(), lyricsUrl = m["lyrics_url"]?.toString(),
            genre = m["genre"]?.toString(), youtubeId = (m["youtube_id"] ?: m["video_id"])?.toString(), lyrics = lines,
        )
    }
    private fun songMap(s: Song): Map<String, Any?> = mapOf(
        "id" to s.id, "title" to s.title, "artist" to s.artist, "album" to s.album,
        "cover_url" to s.coverUrl, "animated_cover_url" to s.animatedCoverUrl, "audio_url" to s.audioUrl,
        "duration_seconds" to s.durationSeconds, "lyrics_text" to s.lyricsText, "lyrics_url" to s.lyricsUrl,
        "genre" to s.genre, "youtube_id" to s.youtubeId,
        "lyrics" to s.lyrics.map { mapOf("timeMs" to it.timeMs, "text" to it.text) },
    )
    private fun snapshot(): Map<String, Any?> = mapOf(
        "current" to PlayerController.currentSong.value?.let(::songMap),
        "queue" to PlayerController.queue.value.map(::songMap), "queueIndex" to PlayerController.currentIndex.value,
        "isPlaying" to PlayerController.isPlaying.value, "positionMs" to PlayerController.positionMs.value,
        "durationMs" to PlayerController.durationMs.value, "shuffle" to PlayerController.shuffleEnabled.value,
        "repeatMode" to when (PlayerController.repeatMode.value) {
            androidx.media3.common.Player.REPEAT_MODE_ALL -> 1
            androidx.media3.common.Player.REPEAT_MODE_ONE -> 2
            else -> 0
        }, "error" to PlayerController.playbackError.value,
    )
}
