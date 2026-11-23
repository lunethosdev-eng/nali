#!/usr/bin/env python3
"""Idempotent Nali provider and playback fixes. Run from repository root."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def edit(relative_path, transform):
    path = ROOT / relative_path
    if not path.is_file():
        raise FileNotFoundError(f"Required source file not found: {relative_path}")
    before = path.read_text(encoding="utf-8")
    after = transform(before)
    if after != before:
        path.write_text(after, encoding="utf-8", newline="\n")
        print(f"Patched {relative_path}")
    else:
        print(f"Already patched: {relative_path}")


def replace_once(text, old, new, label):
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"Could not locate expected source block: {label}")
    return text.replace(old, new, 1)


def patch_supabase(text):
    helper = """  static Map<String, dynamic> _tagCatalogRow(Map<String, dynamic> row) {
    final provider = (row['provider'] ?? row['source'] ?? 'supabase')
        .toString()
        .toLowerCase();
    return {
      ...row,
      'provider': provider,
      'source': (row['source'] ?? provider).toString().toLowerCase(),
    };
  }

"""
    text = replace_once(text, "class SupabaseService {\n",
                        "class SupabaseService {\n" + helper,
                        "SupabaseService provider tag helper")
    text = text.replace(
        "map((row) => { ...row, 'provider': 'supabase', 'source': 'supabase' })",
        "map((row) => _tagCatalogRow(Map<String, dynamic>.from(row)))")
    text = replace_once(
        text,
        "return row == null ? null : {...row, 'provider': 'supabase', 'source': 'supabase'};",
        "return row == null ? null : _tagCatalogRow(Map<String, dynamic>.from(row));",
        "SupabaseService.getSongById provider preservation")
    return text


def patch_unified_search(text):
    text = replace_once(
        text,
        """      }).toList();
    } catch (e) {
      debugPrint('UnifiedSearch Supabase error: $e');""",
        """      }).toList();
      // Supabase rows can originate from optional providers. Do not leak
      // previews from providers the user has disabled.
      supabaseResults = supabaseResults.where((row) {
        final source = (row['provider'] ?? row['source'] ?? 'supabase').toString();
        return ps.isEnabled(source);
      }).toList();
    } catch (e) {
      debugPrint('UnifiedSearch Supabase error: $e');""",
        "UnifiedSearchService full-search provider isolation")
    text = replace_once(
        text,
        "for (final s in local) {",
        """for (final s in local.where((row) =>
            ProviderService.instance.isEnabled(
              (row['provider'] ?? row['source'] ?? 'supabase').toString(),
            ))) {""",
        "UnifiedSearchService autocomplete provider isolation")
    return text


def patch_provider_service(text):
    text = replace_once(
        text,
        "  static const _kInternetArchiveEnabled = 'provider_internet_archive_enabled';",
        """  static const _kInternetArchiveEnabled = 'provider_internet_archive_enabled';
  static const _kAppleTapPreview = 'provider_apple_music_tap_preview';
  static const _kDeezerTapPreview = 'provider_deezer_tap_preview';""",
        "ProviderService preview preference keys")
    text = replace_once(
        text,
        "  bool internetArchiveEnabled = false;",
        """  bool internetArchiveEnabled = false;
  bool appleMusicTapPreviewEnabled = true;
  bool deezerTapPreviewEnabled = true;""",
        "ProviderService preview preference state")
    text = replace_once(
        text,
        "    internetArchiveEnabled = prefs.getBool(_kInternetArchiveEnabled) ?? false;",
        """    internetArchiveEnabled = prefs.getBool(_kInternetArchiveEnabled) ?? false;
    appleMusicTapPreviewEnabled = prefs.getBool(_kAppleTapPreview) ?? true;
    deezerTapPreviewEnabled = prefs.getBool(_kDeezerTapPreview) ?? true;""",
        "ProviderService preview preference loading")
    text = replace_once(
        text,
        "  // ── Queries ───────────────────────────────────────────────────────",
        """  Future<void> setAppleMusicTapPreviewEnabled(bool value) async {
    if (appleMusicTapPreviewEnabled == value) return;
    appleMusicTapPreviewEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAppleTapPreview, value);
    notifyListeners();
  }

  Future<void> setDeezerTapPreviewEnabled(bool value) async {
    if (deezerTapPreviewEnabled == value) return;
    deezerTapPreviewEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDeezerTapPreview, value);
    notifyListeners();
  }

  // ── Queries ───────────────────────────────────────────────────────""",
        "ProviderService preview preference setters")
    return text


def patch_provider_settings(text):
    text = replace_once(
        text,
        """              value: ps.appleMusicEnabled,
              onChanged: (v) => ps.setAppleMusicEnabled(v),
            ),""",
        """              value: ps.appleMusicEnabled,
              onChanged: (v) => ps.setAppleMusicEnabled(v),
              extra: SwitchListTile(
                contentPadding: const EdgeInsets.only(left: 16, right: 16),
                dense: true,
                title: Text(t('Reproducir avance al tocar', 'Play preview on tap'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                subtitle: Text(t('Avance oficial de hasta 30 segundos', 'Official preview up to 30 seconds'),
                    style: TextStyle(color: Colors.white.withOpacity(0.42), fontSize: 11)),
                value: ps.appleMusicTapPreviewEnabled,
                onChanged: ps.setAppleMusicTapPreviewEnabled,
                activeColor: const Color(0xfffc3c44),
              ),
            ),""",
        "Apple Music preview setting")
    text = replace_once(
        text,
        """              value: ps.deezerEnabled,
              onChanged: (v) => ps.setDeezerEnabled(v),
            ),""",
        """              value: ps.deezerEnabled,
              onChanged: (v) => ps.setDeezerEnabled(v),
              extra: SwitchListTile(
                contentPadding: const EdgeInsets.only(left: 16, right: 16),
                dense: true,
                title: Text(t('Reproducir avance al tocar', 'Play preview on tap'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                subtitle: Text(t('Avance oficial de hasta 30 segundos', 'Official preview up to 30 seconds'),
                    style: TextStyle(color: Colors.white.withOpacity(0.42), fontSize: 11)),
                value: ps.deezerTapPreviewEnabled,
                onChanged: ps.setDeezerTapPreviewEnabled,
                activeColor: const Color(0xffef5b24),
              ),
            ),""",
        "Deezer preview setting")
    return text


def patch_search_page(text):
    text = replace_once(text, "import 'package:flutter/material.dart';",
                        "import 'package:flutter/material.dart';\nimport 'package:audioplayers/audioplayers.dart';",
                        "SearchPage audio preview import")
    text = replace_once(text, "import 'package:nali/services/native_player_bridge.dart';",
                        "import 'package:nali/services/native_player_bridge.dart';\nimport 'package:nali/services/provider_service.dart';",
                        "SearchPage provider service import")
    text = replace_once(text, "  Timer? _debounce;",
                        "  Timer? _debounce;\n  Timer? _previewStopTimer;\n  final AudioPlayer _previewPlayer = AudioPlayer();",
                        "SearchPage preview player state")
    text = replace_once(text, "    _debounce?.cancel();\n    _searchCtrl.dispose();",
                        "    _debounce?.cancel();\n    _previewStopTimer?.cancel();\n    unawaited(_previewPlayer.dispose());\n    _searchCtrl.dispose();",
                        "SearchPage preview player disposal")
    text = replace_once(
        text,
        "  @override\n  Widget build(BuildContext context) {",
        """  Future<void> _startPreview(Map<String, dynamic> song) async {
    final provider = (song['provider'] ?? song['source'] ?? '').toString().toLowerCase();
    if (provider != 'apple_music' && provider != 'apple' && provider != 'deezer') return;
    if (!ProviderService.instance.isEnabled(provider)) return;
    final url = (song['audio_url'] ?? song['stream_url'] ?? '').toString();
    if (!url.startsWith('https://')) return;
    _previewStopTimer?.cancel();
    try {
      await _previewPlayer.stop();
      await _previewPlayer.play(UrlSource(url));
      _previewStopTimer = Timer(const Duration(seconds: 30), _stopPreview);
    } catch (error) {
      debugPrint('Catalog preview error: $error');
    }
  }

  void _stopPreview() {
    _previewStopTimer?.cancel();
    _previewStopTimer = null;
    unawaited(_previewPlayer.stop());
  }

  @override
  Widget build(BuildContext context) {""",
        "SearchPage preview handlers")
    text = replace_once(
        text,
        "                          return ListTile(",
        """                          return GestureDetector(
                            onLongPressStart: (_) { _startPreview(s); },
                            onLongPressEnd: (_) => _stopPreview(),
                            onSecondaryTap: () { _startPreview(s); },
                            child: ListTile(""",
        "SearchPage hold/right-click preview gesture")
    text = replace_once(
        text,
        "                              final stream = (s['audio_url'] ?? s['stream_url'] ?? '').toString();",
        """                              if ((provider == 'apple_music' || provider == 'apple') &&
                                      !ProviderService.instance.appleMusicTapPreviewEnabled ||
                                  provider == 'deezer' &&
                                      !ProviderService.instance.deezerTapPreviewEnabled) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(t(
                                    'El avance al tocar está desactivado para este proveedor. Puedes cambiarlo en Settings → Proveedores.',
                                    'Tap-to-preview is disabled for this provider. Change it in Settings → Providers.',
                                  )),
                                ));
                                return;
                              }
                              final stream = (s['audio_url'] ?? s['stream_url'] ?? '').toString();""",
        "SearchPage tap-preview preference check")
    text = replace_once(
        text,
        """                              Navigator.pushNamed(context, '/player', arguments: s);
                            },
                          );""",
        """                              Navigator.pushNamed(context, '/player', arguments: s);
                            },
                          ),
                          );""",
        "SearchPage GestureDetector closing")
    return text


def patch_dart_player(text):
    text = replace_once(text, "  bool _advancing = false;",
                        "  bool _advancing = false;\n  int _playRequestToken = 0;",
                        "PlayerController playback request token")
    start = text.find("  Future<void> playSong(Map<String, dynamic> song,")
    end = text.find("  Future<void> _recordPlay(Map<String, dynamic> song)", start)
    if start < 0 or end < 0:
        raise RuntimeError("Could not locate PlayerController.playSong block")
    old = text[start:end]
    if "final requestToken" in old and "_playRequestToken" in old:
        return text
    new = r"""  Future<void> playSong(Map<String, dynamic> song,
      {bool forceRestart = false}) async {
    if (_usesNativePlayer) {
      await NativePlayerBridge.instance.invoke('playSong', {'song': NativePlayerBridge.safeSong(song)});
      return;
    }
    final key = _songKey(song);
    if (!forceRestart &&
        currentSong != null &&
        _songKey(currentSong!) == key &&
        isPlaying) {
      return;
    }

    final requestToken = ++_playRequestToken;
    final selected = Map<String, dynamic>.from(song);
    final provider = (selected['provider'] ?? selected['source'] ?? '').toString().toLowerCase();
    final rawVideoId = (selected['youtube_id'] ?? selected['video_id'] ?? '').toString();
    final idFromKey = (selected['id'] ?? '').toString().replaceFirst('yt_', '');
    final videoId = rawVideoId.isNotEmpty ? rawVideoId : idFromKey;
    final isYoutubeTrack = provider == 'youtube_music' ||
        RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId);
    var url = (selected['audio_url'] ?? selected['stream_url'] ?? selected['path'] ?? '').toString();

    // Never use a third-party 30-second preview as a YouTube Music stream.
    if (isYoutubeTrack) url = '';

    currentSong = selected;
    isPlaying = false;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();

    // Stop the old preview immediately while the new InnerTube URL resolves.
    try { await _active.stop(); } catch (_) {}
    if (requestToken != _playRequestToken) return;

    if (isYoutubeTrack) {
      try {
        url = await YoutubeStreamService.instance.resolve(videoId);
        if (requestToken != _playRequestToken) return;
        selected['audio_url'] = url;
        selected['stream_url'] = url;
      } catch (error) {
        if (requestToken == _playRequestToken) {
          debugPrint('YouTube Music InnerTube playback error: $error');
          currentSong = selected;
          isPlaying = false;
          notifyListeners();
        }
        return;
      }
    }
    if (requestToken != _playRequestToken) return;

    final id = (selected['id'] ?? key).toString();
    final title = (selected['title'] ?? '').toString();
    final artist = (selected['artist'] ?? '').toString();
    final isLocal = selected['is_local'] == true ||
        (url.isNotEmpty && !url.startsWith('http://') && !url.startsWith('https://'));

    String? sourcePath;
    if (!isYoutubeTrack) {
      sourcePath = await AudioCacheService.instance.localPathForSongId(id);
    }
    if (requestToken != _playRequestToken) return;
    if (sourcePath == null && isLocal && url.isNotEmpty) sourcePath = url;
    if (sourcePath == null && url.isNotEmpty && !isLocal && !isYoutubeTrack) {
      unawaited(AudioCacheService.instance.ensureSongCached(
        id: id, title: title, artist: artist, url: url,
      ));
    }

    try {
      if (sourcePath != null) {
        await _active.play(DeviceFileSource(sourcePath));
      } else if (url.isNotEmpty) {
        await _active.play(UrlSource(url));
      } else {
        debugPrint('No audio_url for song: $title');
        return;
      }
      if (requestToken != _playRequestToken) {
        await _active.stop();
        return;
      }
      isPlaying = true;
      _pausedForDj = false;
      _nextReady = false;
      if (queue.isEmpty) {
        queue = [selected];
        queueIndex = 0;
        if (selected['is_local'] == true) {
          final local = LocalMusicService.instance.tracks;
          if (local.length > 1) {
            queue = List<Map<String, dynamic>>.from(local);
            final idx = queue.indexWhere((s) => _songKey(s) == key);
            queueIndex = idx >= 0 ? idx : 0;
          }
        } else {
          unawaited(_expandQueueAround(selected));
        }
      } else {
        final idx = queue.indexWhere((s) => _songKey(s) == key);
        if (idx >= 0) queueIndex = idx;
      }
      notifyListeners();
      unawaited(_recordPlay(selected));
      unawaited(_persistSession());
      unawaited(Future.delayed(const Duration(milliseconds: 400), _preloadNext));
    } catch (e) {
      debugPrint('playSong error: $e');
    }
  }

"""
    text = text[:start] + new + text[end:]
    text = replace_once(
        text,
        "      if (provider == 'youtube_music') return; // signed streams are resolved only when selected",
        """      if (provider == 'youtube_music' ||
          next['youtube_id'] != null ||
          (next['id'] ?? '').toString().startsWith('yt_')) {
        return; // InnerTube streams resolve only when selected
      }""",
        "PlayerController YouTube preload guard")
    return text


def patch_native_player(text):
    text = replace_once(text, "import kotlinx.coroutines.Job",
                        "import kotlinx.coroutines.CancellationException\nimport kotlinx.coroutines.Job",
                        "Native PlayerController cancellation import")
    text = replace_once(
        text,
        "    private var pendingQueue: Pair<List<Song>, Int>? = null",
        """    private var pendingQueue: Pair<List<Song>, Int>? = null
    private var playQueueJob: Job? = null
    private var playRequestId: Long = 0L""",
        "Native PlayerController request state")
    start = text.find("    fun playQueue(songs: List<Song>, startIndex: Int = 0) {")
    end = text.find("\n    fun addToQueue(", start)
    if start < 0 or end < 0:
        raise RuntimeError("Could not locate native PlayerController.playQueue block")
    old = text[start:end]
    if "playQueueJob?.cancel()" in old and "resolveSongForPlayback" in old:
        return text
    new = r"""    private suspend fun resolveSongForPlayback(song: Song): Song {
        val localAudio = song.audioUrl?.let { raw ->
            raw.startsWith("file://") || raw.startsWith("content://") || File(raw).isFile
        } == true
        if (localAudio) return song

        val ytId = song.youtubeId?.takeIf { it.isNotBlank() }
            ?: song.id.removePrefix("yt_").takeIf { it.matches(Regex("[A-Za-z0-9_-]{11}")) }
        if (ytId.isNullOrBlank()) return song

        // Ignore a pre-existing URL for YouTube catalogue items: it may be a
        // 30-second third-party preview or a stale signed stream.
        return song.copy(
            youtubeId = ytId,
            audioUrl = YouTubeStreamResolver.resolve(ytId),
            coverUrl = song.coverUrl ?: "https://i.ytimg.com/vi/$ytId/hqdefault.jpg"
        )
    }

    fun playQueue(songs: List<Song>, startIndex: Int = 0) {
        if (songs.isEmpty()) return
        val safeStart = startIndex.coerceIn(0, songs.lastIndex)
        val ordered = songs.drop(safeStart) + songs.take(safeStart)
        val selected = ordered.first()
        val requestId = ++playRequestId
        playQueueJob?.cancel()
        _playbackError.value = null
        _currentSong.value = selected
        _isPlaying.value = false
        _positionMs.value = 0L
        _durationMs.value = selected.durationMs
        _queue.value = emptyList()

        val player = controller
        if (player == null) {
            pendingQueue = songs to safeStart
            return
        }

        // Stop the previous preview before resolving the newly selected song.
        runCatching {
            player.stop()
            player.clearMediaItems()
        }

        playQueueJob = scope.launch {
            try {
                val first = resolveSongForPlayback(selected)
                if (requestId != playRequestId) return@launch
                if (first.audioUrl.isNullOrBlank()) {
                    throw IllegalStateException("InnerTube no devolvió un stream reproducible para ${first.title}")
                }

                _queue.value = listOf(first)
                player.setMediaItems(listOf(toMediaItem(first)), 0, 0L)
                player.prepare()
                player.playWhenReady = true
                player.play()
                syncCurrentItem()

                // The selected track starts first. Resolve the rest of the
                // queue afterwards so old requests cannot replace this track.
                for (next in ordered.drop(1)) {
                    val resolvedNext = try {
                        resolveSongForPlayback(next)
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (error: Throwable) {
                        _playbackError.value = "No se pudo preparar ${next.title}: ${error.localizedMessage ?: "stream no disponible"}"
                        null
                    }
                    if (requestId != playRequestId) return@launch
                    if (resolvedNext != null && !resolvedNext.audioUrl.isNullOrBlank()) {
                        player.addMediaItem(toMediaItem(resolvedNext))
                        _queue.value = _queue.value + resolvedNext
                    }
                }
                if (requestId == playRequestId) syncQueue()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                if (requestId == playRequestId) {
                    runCatching {
                        player.stop()
                        player.clearMediaItems()
                    }
                    _queue.value = emptyList()
                    _currentSong.value = selected
                    _isPlaying.value = false
                    _positionMs.value = 0L
                    _playbackError.value =
                        "No se pudo reproducir ${selected.title}: ${error.localizedMessage ?: "InnerTube no disponible"}"
                }
            }
        }
    }
"""
    text = text[:start] + new + text[end:]
    return text


def main():
    edit("lib/services/supabase_service.dart", patch_supabase)
    edit("lib/services/unified_search_service.dart", patch_unified_search)
    edit("lib/services/provider_service.dart", patch_provider_service)
    edit("lib/screens/settings_providers_section.dart", patch_provider_settings)
    edit("lib/pages/search_page.dart", patch_search_page)
    edit("lib/services/player_controller.dart", patch_dart_player)
    edit("android/app/src/main/kotlin/com/pokke/music/player/PlayerController.kt", patch_native_player)


if __name__ == "__main__":
    main()
