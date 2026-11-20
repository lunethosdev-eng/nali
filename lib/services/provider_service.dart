import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized music providers manager for Nali (Phase 1 skeleton).
///
/// Rules (mandatory):
/// - Supabase is always the default / primary backend. It cannot be turned off.
/// - YouTube Music starts DISABLED by default.
/// - YouTube Music only becomes active after the user turns it on in
///   Settings → Proveedores.
/// - Other providers (Spotify, SoundCloud...) can be added later.
class ProviderService extends ChangeNotifier {
  ProviderService._();
  static final ProviderService instance = ProviderService._();

  static const _kYoutubeEnabled = 'provider_youtube_music_enabled';
  static const _kSpotifyEnabled = 'provider_spotify_enabled';

  /// Supabase is always considered enabled. It is the primary music source.
  bool get supabaseEnabled => true;

  /// YouTube Music – OFF by default (mandatory rule).
  bool youtubeMusicEnabled = false;

  /// Spotify – respects existing SpotifyService connection state later.
  bool spotifyEnabled = false;

  bool get isLoaded => _loaded;
  bool _loaded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    youtubeMusicEnabled = prefs.getBool(_kYoutubeEnabled) ?? false; // default OFF
    spotifyEnabled = prefs.getBool(_kSpotifyEnabled) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setYoutubeMusicEnabled(bool value) async {
    if (youtubeMusicEnabled == value) return;
    youtubeMusicEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kYoutubeEnabled, value);
    notifyListeners();
  }

  Future<void> setSpotifyEnabled(bool value) async {
    if (spotifyEnabled == value) return;
    spotifyEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSpotifyEnabled, value);
    notifyListeners();
  }

  /// List of currently active providers (for search / home).
  /// Supabase is always first.
  List<String> get activeProviders {
    final list = <String>['supabase'];
    if (youtubeMusicEnabled) list.add('youtube_music');
    if (spotifyEnabled) list.add('spotify');
    return list;
  }

  /// Whether a specific provider should be queried right now.
  bool isEnabled(String providerId) {
    switch (providerId) {
      case 'supabase':
        return true;
      case 'youtube_music':
      case 'youtube':
        return youtubeMusicEnabled;
      case 'spotify':
        return spotifyEnabled;
      default:
        return false;
    }
  }
}
