import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DJ voice core. Scans `assets/dj/<dj_id>/<event>/*.mp3` and picks randomly.
class DjService {
  DjService._();
  static final DjService instance = DjService._();

  static const _prefEnabled = 'dj_enabled';
  static const _prefActive = 'dj_active_id';
  static const _prefBalance = 'dj_music_balance';
  static const _prefPlacement = 'dj_placement'; // none | home | nav
  static const _prefBlobColor = 'dj_blob_color';

  static const eventWelcome = 'welcome';
  static const eventPause = 'pause';
  static const eventSkip = 'skip';
  static const eventShuffle = 'shuffle';
  static const eventPlaylistEnd = 'playlist_end';
  static const eventLowBattery = 'low_battery';
  static const eventBuilding = 'building_playlist';
  static const eventFavorites = 'favorites';
  static const eventTransitions = 'transitions';

  final AudioPlayer _voice = AudioPlayer();
  final _rng = Random();
  bool _enabled = false;
  String _activeId = 'nugget_dj';
  double _balance = 0.5;
  bool _genreFocus = false;
  bool _ready = false;
  bool _playingVoice = false;
  String _placement = 'none'; // none | home | nav
  int _blobColor = 0xFF5CE1C5;

  final Map<String, Map<String, List<String>>> _catalog = {};

  bool get enabled => _enabled;
  String get activeId => _activeId;
  double get balance => _balance;
  bool get genreFocus => _genreFocus;
  bool get isSpeaking => _playingVoice;
  String get placement => _placement;
  int get blobColor => _blobColor;
  List<String> get availableDjs => _catalog.keys.toList()..sort();

  Map<String, dynamic> get djIdentity => {
        'id': 'dj_core_$_activeId',
        'title': _activeId.replaceAll('_', ' ').toUpperCase(),
        'artist': 'MAI Radio · DJ',
        'cover_url': null,
        'provider': 'dj',
        'is_dj_core': true,
      };

  Future<void> init() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefEnabled) ?? false;
    _activeId = prefs.getString(_prefActive) ?? 'nugget_dj';
    _balance = prefs.getDouble(_prefBalance) ?? 0.5;
    _placement = prefs.getString(_prefPlacement) ?? 'none';
    _blobColor = prefs.getInt(_prefBlobColor) ?? 0xFF5CE1C5;
    try {
      await _voice.setReleaseMode(ReleaseMode.stop);
      await _voice.setPlayerMode(PlayerMode.mediaPlayer);
      await _voice.setVolume(1.0);
    } catch (e) {
      debugPrint('DjService player setup: $e');
    }
    await _scanAssets();
    _ready = true;
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, v);
  }

  Future<void> setActiveDj(String id) async {
    _activeId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefActive, id);
  }

  Future<void> setBalance(double v) async {
    _balance = v.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefBalance, _balance);
  }

  Future<void> setPlacement(String v) async {
    if (!const ['none', 'home', 'nav'].contains(v)) return;
    _placement = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPlacement, v);
  }

  Future<void> setBlobColor(int color) async {
    _blobColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefBlobColor, color);
  }

  void setGenreFocus(bool v) => _genreFocus = v;

  /// Bundled fallback when AssetManifest is empty (web/hot-reload edge cases).
  static const Map<String, List<String>> _fallback = {
    'welcome': [
      'dj/nugget_dj/welcome/welcome_01.mp3',
      'dj/nugget_dj/welcome/welcome_02.mp3',
      'dj/nugget_dj/welcome/welcome_03.mp3',
      'dj/nugget_dj/welcome/welcome_04.mp3',
    ],
    'pause': [
      'dj/nugget_dj/pause/pause_01.mp3',
      'dj/nugget_dj/pause/pause_02.mp3',
    ],
    'skip': [
      'dj/nugget_dj/skip/skip_01.mp3',
      'dj/nugget_dj/skip/skip_02.mp3',
      'dj/nugget_dj/skip/skip_03.mp3',
    ],
    'shuffle': [
      'dj/nugget_dj/shuffle/shuffle_01.mp3',
      'dj/nugget_dj/shuffle/shuffle_02.mp3',
    ],
    'playlist_end': [
      'dj/nugget_dj/playlist_end/playlist_end_01.mp3',
      'dj/nugget_dj/playlist_end/playlist_end_02.mp3',
    ],
    'low_battery': [
      'dj/nugget_dj/low_battery/low_battery_01.mp3',
      'dj/nugget_dj/low_battery/low_battery_02.mp3',
    ],
    'building_playlist': [
      'dj/nugget_dj/building_playlist/building_01.mp3',
      'dj/nugget_dj/building_playlist/building_02.mp3',
    ],
    'favorites': [
      'dj/nugget_dj/favorites/favorites_01.mp3',
      'dj/nugget_dj/favorites/favorites_02.mp3',
      'dj/nugget_dj/favorites/favorites_03.mp3',
    ],
    'transitions': [
      'dj/nugget_dj/transitions/transition_01.mp3',
    ],
  };

  Future<void> _scanAssets() async {
    _catalog.clear();
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest = json.decode(manifestJson);
      for (final path in manifest.keys) {
        if (!path.startsWith('assets/dj/')) continue;
        final lower = path.toLowerCase();
        if (!(lower.endsWith('.mp3') ||
            lower.endsWith('.m4a') ||
            lower.endsWith('.wav') ||
            lower.endsWith('.ogg') ||
            lower.endsWith('.mp4'))) {
          continue;
        }
        final parts = path.split('/');
        if (parts.length < 5) continue;
        final djId = parts[2];
        final event = parts[3];
        final relative =
            path.startsWith('assets/') ? path.substring(7) : path;
        _catalog
            .putIfAbsent(djId, () => {})
            .putIfAbsent(event, () => [])
            .add(relative);
      }
    } catch (e) {
      debugPrint('DjService scan: $e');
    }
    _catalog.putIfAbsent('nugget_dj', () => {});
    // Merge fallbacks so voice always has something to play
    for (final e in _fallback.entries) {
      final list = _catalog['nugget_dj']!.putIfAbsent(e.key, () => []);
      if (list.isEmpty) list.addAll(e.value);
    }
    debugPrint(
      'DjService ready: ${_catalog['nugget_dj']!.map((k, v) => MapEntry(k, v.length))}',
    );
  }

  Future<void> rescan() => _scanAssets();

  List<String> clipsFor(String event) {
    final dj = _catalog[_activeId] ?? const {};
    final list = List<String>.from(dj[event] ?? const []);
    if (list.isEmpty && _activeId == 'nugget_dj') {
      return List<String>.from(_fallback[event] ?? const []);
    }
    return list;
  }

  String? _randomClip(String event) {
    final list = clipsFor(event);
    if (list.isEmpty) return null;
    return list[_rng.nextInt(list.length)];
  }

  Future<void> playEvent(String event) async {
    await init();
    if (!_enabled) {
      debugPrint('DjService: disabled, skip $event');
      return;
    }
    final path = _randomClip(event);
    if (path == null) {
      debugPrint('DjService: no clips for $event');
      return;
    }
    try {
      _playingVoice = true;
      await _voice.stop();
      // path is already relative to assets/ (e.g. dj/nugget_dj/welcome/…)
      final relative =
          path.startsWith('assets/') ? path.substring(7) : path;
      debugPrint('DjService playing AssetSource($relative)');
      await _voice.play(AssetSource(relative));
      _voice.onPlayerComplete.first.then((_) {
        _playingVoice = false;
      });
    } catch (e) {
      _playingVoice = false;
      debugPrint('DjService play $event ERROR: $e');
      // Retry alternate path form
      try {
        final alt = path.startsWith('dj/') ? path : 'dj/$_activeId/$event/${path.split('/').last}';
        await _voice.play(AssetSource(alt));
        _playingVoice = true;
      } catch (e2) {
        debugPrint('DjService retry failed: $e2');
      }
    }
  }

  Future<void> welcome() => playEvent(eventWelcome);
  Future<void> onPause() => playEvent(eventPause);
  Future<void> onSkip() => playEvent(eventSkip);
  Future<void> onShuffle() => playEvent(eventShuffle);
  Future<void> onPlaylistEnd() => playEvent(eventPlaylistEnd);
  Future<void> onBuilding() => playEvent(eventBuilding);
  Future<void> onLowBattery() => playEvent(eventLowBattery);
  Future<void> onFavorite() => playEvent(eventFavorites);
  Future<void> onTransition() => playEvent(eventTransitions);

  Map<String, int> get blockWeights {
    final discover = (_balance * 50).round();
    final known = 50 - discover;
    return {
      'tops': 30,
      'favorites': known.clamp(10, 40),
      'discovery': (20 + discover).clamp(20, 60),
    };
  }
}
