import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DJ voice core. Scans folders under `assets/dj/<dj_id>/<event>/`.
///
/// Layout (add as many clips as you want — random pick each time):
/// ```
/// assets/dj/nugget_dj/
///   welcome/
///   pause/
///   skip/
///   shuffle/
///   playlist_end/
///   low_battery/
///   building_playlist/
///   favorites/
///   transitions/
/// ```
class DjService {
  DjService._();
  static final DjService instance = DjService._();

  static const _prefEnabled = 'dj_enabled';
  static const _prefActive = 'dj_active_id';
  static const _prefBalance = 'dj_music_balance';

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

  /// djId → event → asset paths
  final Map<String, Map<String, List<String>>> _catalog = {};

  bool get enabled => _enabled;
  String get activeId => _activeId;
  double get balance => _balance;
  bool get genreFocus => _genreFocus;
  bool get isSpeaking => _playingVoice;
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

  void setGenreFocus(bool v) => _genreFocus = v;

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
        // assets/dj/<dj_id>/<event>/file.ext
        final parts = path.split('/');
        if (parts.length < 5) continue;
        final djId = parts[2];
        final event = parts[3];
        _catalog
            .putIfAbsent(djId, () => {})
            .putIfAbsent(event, () => [])
            .add(path);
      }
    } catch (e) {
      debugPrint('DjService scan: $e');
    }
    _catalog.putIfAbsent('nugget_dj', () => {});
    for (final e in [
      eventWelcome,
      eventPause,
      eventSkip,
      eventShuffle,
      eventPlaylistEnd,
      eventLowBattery,
      eventBuilding,
      eventFavorites,
      eventTransitions,
    ]) {
      _catalog['nugget_dj']!.putIfAbsent(e, () => []);
    }
    debugPrint(
      'DjService catalog: ${_catalog.map((k, v) => MapEntry(k, v.map((e, files) => MapEntry(e, files.length))))}',
    );
  }

  Future<void> rescan() => _scanAssets();

  List<String> clipsFor(String event) {
    final dj = _catalog[_activeId] ?? const {};
    return List<String>.from(dj[event] ?? const []);
  }

  String? _randomClip(String event) {
    final list = clipsFor(event);
    if (list.isEmpty) return null;
    return list[_rng.nextInt(list.length)];
  }

  Future<void> playEvent(String event) async {
    if (!_enabled) return;
    await init();
    final path = _randomClip(event);
    if (path == null) {
      debugPrint('DjService: no clips in $_activeId/$event');
      return;
    }
    try {
      _playingVoice = true;
      await _voice.stop();
      final relative =
          path.startsWith('assets/') ? path.substring('assets/'.length) : path;
      await _voice.play(AssetSource(relative));
      _voice.onPlayerComplete.first.then((_) {
        _playingVoice = false;
      });
    } catch (e) {
      _playingVoice = false;
      debugPrint('DjService play $event: $e');
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
