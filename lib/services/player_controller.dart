import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:nali/services/audio_cache_service.dart';
import 'package:nali/services/listening_history.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/services/local_music_service.dart';
import 'package:nali/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nali/services/native_player_bridge.dart';
import 'package:nali/services/youtube_stream_service.dart';
import 'package:nali/services/apple_artwork_service.dart';

class PlayerController extends ChangeNotifier {
  static final PlayerController instance = PlayerController._();

  PlayerController._() {
    if (NativePlayerBridge.instance.supported) {
      NativePlayerBridge.instance.states.listen(_applyNativeState,
          onError: (Object e) => debugPrint('native player events: $e'));
      NativePlayerBridge.instance.invoke<Map<dynamic, dynamic>>('state').then((state) {
        if (state != null) _applyNativeState(Map<String, dynamic>.from(state));
      }).catchError((Object e) => debugPrint('native player state: $e'));
    }
    if (!_usesNativePlayer) {
      _wire(_playerA, false);
      _wire(_playerB, true);
      // Flutter audio is used on web/iOS. Android playback belongs to Media3.
      unawaited(_playerA.setPlayerMode(PlayerMode.mediaPlayer));
      unawaited(_playerB.setPlayerMode(PlayerMode.mediaPlayer));
      unawaited(_configureAudioSession());
    }
  }

  bool get _usesNativePlayer => NativePlayerBridge.instance.supported;

  void _applyNativeState(Map<String, dynamic> state) {
    currentSong = state['current'] == null
        ? null
        : Map<String, dynamic>.from(state['current'] as Map);
    queue = (state['queue'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    queueIndex = (state['queueIndex'] as num?)?.toInt() ?? 0;
    isPlaying = state['isPlaying'] == true;
    position = Duration(milliseconds: (state['positionMs'] as num?)?.toInt() ?? 0);
    duration = Duration(milliseconds: (state['durationMs'] as num?)?.toInt() ?? 0);
    shuffleMode = state['shuffle'] == true;
    repeatMode = (state['repeatMode'] as num?)?.toInt() ?? 0;
    notifyListeners();
  }

  Future<void> _configureAudioSession() async {
    try {
      final ctx = AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          audioMode: AndroidAudioMode.normal,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.mixWithOthers},
        ),
      );
      await AudioPlayer.global.setAudioContext(ctx);
      await _playerA.setAudioContext(ctx);
      await _playerB.setAudioContext(ctx);
    } catch (e) {
      debugPrint('audio session: $e');
    }
  }

  void _wire(AudioPlayer p, bool isB) {
    p.onPlayerComplete.listen((_) {
      if (_usingB == isB && !_advancing) {
        unawaited(_onTrackComplete());
      }
    });
    p.onPositionChanged.listen((pos) {
      if (_usingB == isB) {
        position = pos;
        // near end, ensure next is ready
        if (duration.inMilliseconds > 0 &&
            pos.inMilliseconds > duration.inMilliseconds - 4000) {
          unawaited(_preloadNext());
        }
        notifyListeners();
      }
    });
    p.onDurationChanged.listen((d) {
      if (_usingB == isB) {
        // Prefer a real positive duration from the player, but never overwrite
        // a known good metadata duration with zero (common with googlevideo).
        if (d.inMilliseconds > 0 || duration.inMilliseconds <= 0) {
          duration = d;
          notifyListeners();
        }
      }
    });
  }

  final AudioPlayer _playerA = AudioPlayer();
  final AudioPlayer _playerB = AudioPlayer();
  bool _usingB = false;
  bool _pausedForDj = false;
  bool _advancing = false;
  bool _nextReady = false;
  int _playRequestToken = 0;
  Future<void> _audioMutation = Future<void>.value();
  int _preloadedIndex = -1;

  Map<String, dynamic>? currentSong;
  Map<String, dynamic>? get current => currentSong;

  List<Map<String, dynamic>> queue = [];
  int queueIndex = 0;
  bool shuffleMode = false;
  /// 0 = off, 1 = repeat all, 2 = repeat one
  int repeatMode = 0;
  List<Map<String, dynamic>> _originalQueue = [];

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;

  AudioPlayer get _active => _usingB ? _playerB : _playerA;
  AudioPlayer get _idle => _usingB ? _playerA : _playerB;

  String _songKey(Map<String, dynamic> s) =>
      (s['id'] ?? s['audio_url'] ?? s['title']).toString();

  Future<void> playPlaylist(
    List<Map<String, dynamic>> songs, {
    bool shuffle = false,
    int startIndex = 0,
  }) async {
    if (songs.isEmpty) return;
    if (_usesNativePlayer) {
      await NativePlayerBridge.instance.invoke('playQueue', {
        'songs': songs.map(NativePlayerBridge.safeSong).toList(),
        'startIndex': startIndex,
        'shuffle': shuffle,
      });
      return;
    }
    queue = List<Map<String, dynamic>>.from(songs);
    shuffleMode = shuffle;
    if (shuffle) {
      queue.shuffle();
      queueIndex = 0;
    } else {
      queueIndex = startIndex.clamp(0, queue.length - 1);
    }
    _nextReady = false;
    _preloadedIndex = -1;
    await playSong(queue[queueIndex], forceRestart: true);
  }

  Future<void> _preloadNext() async {
    final requestToken = _playRequestToken;
    try {
      if (queue.length < 2) return;
      final nextIdx = (queueIndex + 1) % queue.length;
      if (_nextReady && _preloadedIndex == nextIdx) return;
      final next = queue[nextIdx];
      final provider = (next['provider'] ?? next['source'] ?? '').toString();
      if (provider == 'youtube_music') return; // signed streams are resolved only when selected
      final url = (next['audio_url'] ?? next['stream_url'] ?? '').toString();
      final id = (next['id'] ?? _songKey(next)).toString();

      // Prefer local cache
      String? local = await AudioCacheService.instance.localPathForSongId(id);
      if (requestToken != _playRequestToken) return;
      await _idle.stop();
      if (local != null) {
        await _idle.play(DeviceFileSource(local), volume: 0);
      } else if (url.isNotEmpty) {
        await _idle.play(UrlSource(url), volume: 0);
        unawaited(AudioCacheService.instance.ensureSongCached(
          id: id,
          title: (next['title'] ?? '').toString(),
          artist: (next['artist'] ?? '').toString(),
          url: url,
        ));
      } else {
        return;
      }
      if (requestToken != _playRequestToken) {
        await _idle.stop();
        return;
      }
      await _idle.pause();
      await _idle.seek(Duration.zero);
      await _idle.setVolume(1);
      _nextReady = true;
      _preloadedIndex = nextIdx;
      debugPrint('preloaded queue[$nextIdx] ${(next['title'] ?? '')}');
    } catch (e) {
      _nextReady = false;
      debugPrint('preloadNext: $e');
    }
  }


  Future<void> _onTrackComplete() async {
    // Repeat one: never advance
    if (repeatMode == 2) {
      try {
        await _active.setReleaseMode(ReleaseMode.loop);
        await _active.seek(Duration.zero);
        final st = await _active.state;
        if (st != PlayerState.playing) {
          await _active.resume();
        }
        isPlaying = true;
        position = Duration.zero;
        notifyListeners();
      } catch (e) {
        debugPrint('repeat one: $e');
        if (currentSong != null) {
          await playSong(currentSong!, forceRestart: true);
        }
      }
      return;
    }
    if (queue.isEmpty) {
      isPlaying = false;
      notifyListeners();
      return;
    }
    final atEnd = queueIndex >= queue.length - 1;
    if (atEnd && repeatMode == 0) {
      isPlaying = false;
      notifyListeners();
      return;
    }
    if (atEnd && repeatMode == 1) {
      queueIndex = -1;
    }
    await _advanceToNext();
  }

  void toggleShuffle() {
    if (_usesNativePlayer) {
      unawaited(NativePlayerBridge.instance.invoke('shuffle'));
      return;
    }
    shuffleMode = !shuffleMode;
    if (shuffleMode) {
      _originalQueue = List<Map<String, dynamic>>.from(queue);
      final cur = currentSong;
      if (cur != null) {
        final rest = queue
            .where((s) => _songKey(s) != _songKey(cur))
            .toList()
          ..shuffle();
        queue = [cur, ...rest];
        queueIndex = 0;
      } else {
        queue.shuffle();
      }
    } else if (_originalQueue.isNotEmpty) {
      final curKey = currentSong != null ? _songKey(currentSong!) : null;
      queue = List<Map<String, dynamic>>.from(_originalQueue);
      if (curKey != null) {
        final idx = queue.indexWhere((s) => _songKey(s) == curKey);
        queueIndex = idx >= 0 ? idx : 0;
      }
    }
    _nextReady = false;
    _preloadedIndex = -1;
    notifyListeners();
  }

  void cycleRepeatMode() {
    if (_usesNativePlayer) {
      unawaited(NativePlayerBridge.instance.invoke('repeat'));
      return;
    }
    repeatMode = (repeatMode + 1) % 3;
    final mode = repeatMode == 2 ? ReleaseMode.loop : ReleaseMode.release;
    unawaited(_playerA.setReleaseMode(mode));
    unawaited(_playerB.setReleaseMode(mode));
    notifyListeners();
  }

  Future<void> _advanceToNext() async {
    if (repeatMode == 2) return;
    if (_advancing || queue.isEmpty) return;
    _advancing = true;
    try {
      // Single-song queue → expand so auto-next has real next tracks
      if (queue.length < 2 && currentSong != null) {
        await _expandQueueAround(currentSong!, _playRequestToken);
      }
      if (queue.isEmpty) return;
      final nextIdx = (queueIndex + 1) % queue.length;
      queueIndex = nextIdx;
      final next = queue[nextIdx];
      currentSong = next;
      notifyListeners();

      if (_nextReady && _preloadedIndex == nextIdx) {
        // Instant switch: idle already has the source
        try {
          await _active.stop();
      await _active.setReleaseMode(
          repeatMode == 2 ? ReleaseMode.loop : ReleaseMode.release);
        } catch (_) {}
        _usingB = !_usingB;
        _nextReady = false;
        _preloadedIndex = -1;
        await _active.resume();
        // if resume fails (some platforms need play), fall through
        final st = await _active.state;
        if (st != PlayerState.playing) {
          await _active.seek(Duration.zero);
          await _active.resume();
        }
        isPlaying = true;
        position = Duration.zero;
        notifyListeners();
        unawaited(_recordPlay(next));
        unawaited(_preloadNext());
        return;
      }

      // Fallback: normal load
      await playSong(next, forceRestart: true);
    } catch (e) {
      debugPrint('advanceToNext: $e');
      try {
        await playSong(queue[queueIndex], forceRestart: true);
      } catch (_) {}
    } finally {
      _advancing = false;
    }
  }

  Future<void> playNextInQueue() async {
    if (_usesNativePlayer) { await NativePlayerBridge.instance.invoke('next'); return; }
    if (queue.isEmpty) return;
    await _advanceToNext();
  }

  Future<void> playPreviousInQueue() async {
    if (_usesNativePlayer) { await NativePlayerBridge.instance.invoke('previous'); return; }
    if (queue.isEmpty) return;
    queueIndex = (queueIndex - 1) < 0 ? queue.length - 1 : queueIndex - 1;
    _nextReady = false;
    _preloadedIndex = -1;
    await playSong(queue[queueIndex], forceRestart: true);
  }

  Future<void> seekTo(Duration pos) async {
    if (_usesNativePlayer) { await NativePlayerBridge.instance.invoke('seek', {'positionMs': pos.inMilliseconds}); return; }
    try {
      await _active.seek(pos);
      position = pos;
      notifyListeners();
    } catch (e) {
      debugPrint('seekTo: $e');
    }
  }

  Future<void> _serializeAudio(Future<void> Function() action) async {
    final previous = _audioMutation;
    final release = Completer<void>();
    _audioMutation = release.future;
    await previous;
    try {
      await action();
    } finally {
      release.complete();
    }
  }

  Future<void> playSong(Map<String, dynamic> song,
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
    final selectedSong = Map<String, dynamic>.from(song);
    final provider = (selectedSong['provider'] ?? selectedSong['source'] ?? '').toString().toLowerCase();
    final isYouTube = provider == 'youtube_music';
    var url = (selectedSong['audio_url'] ?? selectedSong['stream_url'] ??
            selectedSong['path'] ?? '').toString();

    currentSong = selectedSong;
    isPlaying = false;
    position = Duration.zero;
    // Prefer known metadata duration immediately so the UI never stays at 0:00
    // while the stream resolves or while audioplayers is slow to report duration.
    final metaSecs = selectedSong['duration_seconds'] is num
        ? (selectedSong['duration_seconds'] as num).round()
        : (selectedSong['duration'] is num
            ? (selectedSong['duration'] as num).round()
            : null);
    duration = (metaSecs != null && metaSecs > 0)
        ? Duration(seconds: metaSecs)
        : Duration.zero;
    _nextReady = false;
    _preloadedIndex = -1;
    notifyListeners();

    if (selectedSong['is_local'] != true) {
      unawaited(_resolveAppleArtwork(selectedSong, requestToken));
    }

    try {
      // Force both players silent and stopped before any resolve or new source.
      // On web, a single stop() is sometimes ignored while a previous UrlSource
      // is still buffering; mute + stop on both makes the switch reliable.
      await _serializeAudio(() async {
        try {
          await _playerA.setVolume(0);
          await _playerB.setVolume(0);
          await _playerA.stop();
          await _playerB.stop();
          await _playerA.setVolume(1);
          await _playerB.setVolume(1);
        } catch (e) {
          debugPrint('player stop/reset: $e');
        }
      });
      if (requestToken != _playRequestToken) return;

      if (isYouTube) {
        final rawVideoId = (selectedSong['youtube_id'] ?? '').toString().trim();
        final videoId = rawVideoId.isNotEmpty
            ? rawVideoId
            : (selectedSong['id'] ?? '').toString().replaceFirst(RegExp(r'^yt_'), '');
        if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
          throw ArgumentError('Invalid YouTube video ID');
        }
        // Ignore search metadata URLs; they may be short previews or expired.
        final resolved = await YoutubeStreamService.instance.resolveDetailed(videoId);
        if (requestToken != _playRequestToken) return;
        url = resolved.url;
        selectedSong['youtube_id'] = videoId;
        selectedSong['audio_url'] = url;
        selectedSong['stream_url'] = url;
        if (resolved.durationSeconds != null && resolved.durationSeconds! > 0) {
          selectedSong['duration_seconds'] = resolved.durationSeconds;
          duration = Duration(seconds: resolved.durationSeconds!);
          notifyListeners();
        }
        if (resolved.mimeType != null) selectedSong['mime_type'] = resolved.mimeType;
        selectedSong['cover_url'] ??= 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
        // Keep currentSong in sync so UI (cover, title, duration) updates
        // immediately even if the stream takes another moment to start.
        currentSong = Map<String, dynamic>.from(selectedSong);
        notifyListeners();
      }
      if (requestToken != _playRequestToken) return;

      final id = (selectedSong['id'] ?? key).toString();
      final title = (selectedSong['title'] ?? '').toString();
      final artist = (selectedSong['artist'] ?? '').toString();
      final isLocal = selectedSong['is_local'] == true ||
          (url.isNotEmpty && !url.startsWith('http://') && !url.startsWith('https://'));

      String? sourcePath;
      if (!isYouTube) {
        sourcePath = await AudioCacheService.instance.localPathForSongId(id);
      }
      if (requestToken != _playRequestToken) return;
      if (sourcePath == null && isLocal && url.isNotEmpty) sourcePath = url;
      if (sourcePath == null && url.isNotEmpty && !isLocal && !isYouTube) {
        unawaited(AudioCacheService.instance.ensureSongCached(
          id: id,
          title: title,
          artist: artist,
          url: url,
        ));
      }
      if (sourcePath == null && url.isEmpty) {
        throw StateError('No audio stream is available for $title');
      }

      await _serializeAudio(() async {
        if (requestToken != _playRequestToken) return;
        if (sourcePath != null) {
          await _active.play(DeviceFileSource(sourcePath!));
        } else {
          await _active.play(UrlSource(url));
        }
        if (requestToken != _playRequestToken) {
          try {
            await _active.stop();
          } catch (_) {}
          return;
        }
        isPlaying = true;
        _pausedForDj = false;
        _nextReady = false;

        // Ensure duration is never left at zero when we already know it from
        // catalog or InnerTube. audioplayers sometimes never fires
        // onDurationChanged for googlevideo / adaptive streams.
        final knownSecs = selectedSong['duration_seconds'] is num
            ? (selectedSong['duration_seconds'] as num).round()
            : null;
        if (knownSecs != null && knownSecs > 0 && duration.inSeconds < 1) {
          duration = Duration(seconds: knownSecs);
        }

        if (queue.isEmpty) {
          queue = [selectedSong];
          queueIndex = 0;
          if (selectedSong['is_local'] == true) {
            final local = LocalMusicService.instance.tracks;
            if (local.length > 1) {
              queue = List<Map<String, dynamic>>.from(local);
              final idx = queue.indexWhere((s) => _songKey(s) == key);
              queueIndex = idx >= 0 ? idx : 0;
            }
          } else {
            unawaited(_expandQueueAround(selectedSong, requestToken));
          }
        } else {
          final idx = queue.indexWhere((s) => _songKey(s) == key);
          if (idx >= 0) queueIndex = idx;
        }
        currentSong = Map<String, dynamic>.from(selectedSong);
        notifyListeners();
      });

      if (requestToken != _playRequestToken || !isPlaying) return;
      unawaited(_recordPlay(selectedSong));
      unawaited(_persistSession());
      // Fallback: if the player still reports 0 duration after a short settle,
      // force the known metadata value so the seek bar and time labels work.
      unawaited(Future.delayed(const Duration(milliseconds: 1200), () {
        if (requestToken != _playRequestToken) return;
        final known = currentSong?['duration_seconds'];
        final secs = known is num ? known.round() : null;
        if (secs != null && secs > 0 && duration.inSeconds < 1) {
          duration = Duration(seconds: secs);
          notifyListeners();
        }
      }));
      // YouTube: if the stream never advances (URL dead / wrong client),
      // force a fresh InnerTube resolve once and retry play.
      if (isYouTube) {
        unawaited(Future.delayed(const Duration(milliseconds: 2200), () async {
          if (requestToken != _playRequestToken) return;
          if (position.inMilliseconds > 400) return;
          try {
            final st = await _active.state;
            if (st == PlayerState.playing && position.inMilliseconds > 200) {
              return;
            }
            final vid = (selectedSong['youtube_id'] ?? '').toString();
            if (vid.length != 11) return;
            debugPrint('YouTube stream stuck at 0 — forcing re-resolve');
            final again = await YoutubeStreamService.instance
                .resolveDetailed(vid, force: true);
            if (requestToken != _playRequestToken) return;
            await _serializeAudio(() async {
              if (requestToken != _playRequestToken) return;
              await _active.stop();
              await _active.play(UrlSource(again.url));
              isPlaying = true;
              if (again.durationSeconds != null &&
                  again.durationSeconds! > 0) {
                duration = Duration(seconds: again.durationSeconds!);
                selectedSong['duration_seconds'] = again.durationSeconds;
              }
              selectedSong['audio_url'] = again.url;
              currentSong = Map<String, dynamic>.from(selectedSong);
              notifyListeners();
            });
          } catch (e) {
            debugPrint('YouTube force re-resolve failed: $e');
          }
        }));
      }
      unawaited(Future.delayed(const Duration(milliseconds: 400), () {
        if (requestToken == _playRequestToken) _preloadNext();
      }));
    } catch (error) {
      debugPrint('playSong error: $error');
      if (requestToken == _playRequestToken) {
        await _serializeAudio(() async {
          try {
            await _playerA.setVolume(0);
            await _playerB.setVolume(0);
            await _playerA.stop();
            await _playerB.stop();
            await _playerA.setVolume(1);
            await _playerB.setVolume(1);
          } catch (_) {}
        });
        currentSong = selectedSong;
        isPlaying = false;
        position = Duration.zero;
        // Keep the known duration so the UI still shows the correct length
        // even when the stream itself failed to start.
        final known = selectedSong['duration_seconds'];
        final secs = known is num ? known.round() : null;
        duration = (secs != null && secs > 0)
            ? Duration(seconds: secs)
            : Duration.zero;
        notifyListeners();
      }
    }
  }

  Future<void> _resolveAppleArtwork(
    Map<String, dynamic> song,
    int requestToken,
  ) async {
    final title = (song['title'] ?? '').toString();
    final artist = (song['artist'] ?? '').toString();
    final album = song['album']?.toString();
    final artwork = await AppleArtworkService.instance.resolve(
      title: title,
      artist: artist,
      album: album,
    );
    if (artwork == null || requestToken != _playRequestToken) return;

    final key = _songKey(song);
    song['cover_url'] = artwork;
    song['artwork_url'] = artwork;
    if (currentSong != null && _songKey(currentSong!) == key) {
      currentSong = Map<String, dynamic>.from(song);
    }
    for (var index = 0; index < queue.length; index++) {
      if (_songKey(queue[index]) == key) {
        queue[index]['cover_url'] = artwork;
        queue[index]['artwork_url'] = artwork;
      }
    }
    notifyListeners();
  }

  Future<void> _recordPlay(Map<String, dynamic> song) async {
    try {
      if (SettingsService.instance.historyLocal) {
        await ListeningHistory.instance.recordPlay(song);
      }
    } catch (_) {}
    try {
      await SupabaseService.kokoro.from('song_plays').insert({
        'song_id': (song['id'] ?? '').toString(),
        'title': (song['title'] ?? '').toString(),
        'artist': (song['artist'] ?? '').toString(),
      });
    } catch (_) {}
  }

  void attachSong(Map<String, dynamic> song) {
    final key = _songKey(song);
    if (currentSong != null && _songKey(currentSong!) == key) {
      notifyListeners();
      return;
    }
    currentSong = song;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    if (_usesNativePlayer) { await NativePlayerBridge.instance.invoke('seek', {'positionMs': position.inMilliseconds}); return; }
    await _active.seek(position);
    this.position = position;
    notifyListeners();
  }

  Future<void> toggle() async {
    if (_usesNativePlayer) { await NativePlayerBridge.instance.invoke('toggle'); return; }
    if (isPlaying) {
      _playRequestToken++;
      await _active.pause();
      isPlaying = false;
    } else {
      await _active.resume();
      isPlaying = true;
    }
    notifyListeners();
  }

  Future<void> pause() async {
    if (_usesNativePlayer) { await NativePlayerBridge.instance.invoke('pause'); return; }
    _playRequestToken++;
    await _active.pause();
    isPlaying = false;
    notifyListeners();
  }

  Future<void> resume() async {
    if (_usesNativePlayer) { await NativePlayerBridge.instance.invoke('resume'); return; }
    await _active.resume();
    isPlaying = true;
    notifyListeners();
  }

  /// Crossfade to another song using dual players (settings crossfade).
  Future<void> crossfadeTo(Map<String, dynamic> song,
      {Duration fade = const Duration(seconds: 4)}) async {
    if (_usesNativePlayer) { await playSong(song, forceRestart: true); return; }
    final provider = (song['provider'] ?? song['source'] ?? '').toString().toLowerCase();
    final url = (song['audio_url'] ?? song['stream_url'] ?? '').toString();
    if (provider == 'youtube_music' || url.isEmpty) {
      await playSong(song, forceRestart: true);
      return;
    }
    final requestToken = ++_playRequestToken;
    final incoming = _idle;
    try {
      final id = (song['id'] ?? _songKey(song)).toString();
      final local = await AudioCacheService.instance.localPathForSongId(id);
      if (requestToken != _playRequestToken) return;
      await incoming.stop();
      if (local != null) {
        await incoming.play(DeviceFileSource(local));
      } else {
        await incoming.play(UrlSource(url));
      }
      if (requestToken != _playRequestToken) {
        await incoming.stop();
        return;
      }
      await incoming.setVolume(0);
      final steps = 20;
      final ms = fade.inMilliseconds ~/ steps;
      for (var i = 1; i <= steps; i++) {
        if (requestToken != _playRequestToken) return;
        final t = i / steps;
        await _active.setVolume(1.0 - t);
        await incoming.setVolume(t);
        await Future.delayed(Duration(milliseconds: ms));
      }
      if (requestToken != _playRequestToken) return;
      await _active.stop();
      await _active.setVolume(1);
      await incoming.setVolume(1);
      _usingB = !_usingB;
      currentSong = song;
      isPlaying = true;
      _nextReady = false;
      notifyListeners();
      unawaited(_preloadNext());
    } catch (e) {
      debugPrint('crossfade: $e');
      await playSong(song, forceRestart: true);
    }
  }

  Future<void> _expandQueueAround(Map<String, dynamic> song, int requestToken) async {
    try {
      final more = await SupabaseService.getSongs(limit: 40);
      if (requestToken != _playRequestToken) return;
      final key = _songKey(song);
      final rest = more.where((s) => _songKey(s) != key).toList();
      if (rest.isEmpty) return;
      queue = [song, ...rest];
      queueIndex = 0;
      notifyListeners();
      unawaited(_preloadNext());
    } catch (e) {
      debugPrint('expandQueue: $e');
    }
  }

  Future<void> _persistSession() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = currentSong;
      if (s == null) return;
      await p.setString('session_song_json', jsonEncode(s));
      await p.setInt('session_queue_index', queueIndex);
    } catch (_) {}
  }

  Future<void> restoreSession() async {
    if (_usesNativePlayer) return; // Media3/MediaSession owns Android playback restoration.
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('session_song_json');
      if (raw == null || raw.isEmpty) return;
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      currentSong = map;
      queue = [map];
      queueIndex = 0;
      isPlaying = false;
      notifyListeners();
      unawaited(_expandQueueAround(map, _playRequestToken));
    } catch (e) {
      debugPrint('restoreSession: $e');
    }
  }
}
