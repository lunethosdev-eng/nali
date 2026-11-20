import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nali/services/spotify_service.dart';

/// Centralized music providers manager for Nali.
///
/// Phase 2 – Full providers system.
///
/// Mandatory rules:
/// - Supabase is ALWAYS the primary / default backend. It cannot be disabled.
/// - YouTube Music starts DISABLED by default.
/// - YouTube Music is only used after the user enables it in Settings → Proveedores.
/// - Spotify toggle is independent of the OAuth link (user can enable/disable catalog use).
/// - Preferences are persisted.
class ProviderService extends ChangeNotifier {
  ProviderService._();
  static final ProviderService instance = ProviderService._();

  // ── Persistence keys ──────────────────────────────────────────────
  static const _kYoutubeEnabled = 'provider_youtube_music_enabled';
  static const _kSpotifyEnabled = 'provider_spotify_enabled';
  static const _kSoundCloudEnabled = 'provider_soundcloud_enabled';

  // ── State ─────────────────────────────────────────────────────────
  /// Supabase is always considered enabled. Primary music source of Nali.
  bool get supabaseEnabled => true;

  /// YouTube Music – OFF by default (mandatory).
  bool youtubeMusicEnabled = false;

  /// Spotify – user can enable/disable whether its results appear in search/home.
  /// Actual OAuth connection is handled by SpotifyService.
  bool spotifyEnabled = false;

  /// SoundCloud – prepared for future (always false for now).
  bool soundCloudEnabled = false;

  bool get isLoaded => _loaded;
  bool _loaded = false;

  // ── Load / Save ───────────────────────────────────────────────────
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    youtubeMusicEnabled = prefs.getBool(_kYoutubeEnabled) ?? false; // default OFF
    spotifyEnabled = prefs.getBool(_kSpotifyEnabled) ?? false;
    soundCloudEnabled = prefs.getBool(_kSoundCloudEnabled) ?? false;
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

  Future<void> setSoundCloudEnabled(bool value) async {
    // Not available yet
    soundCloudEnabled = false;
    notifyListeners();
  }

  // ── Queries ───────────────────────────────────────────────────────

  /// Providers that are currently allowed to be queried.
  /// Supabase is always first.
  List<String> get activeProviders {
    final list = <String>['supabase'];
    if (youtubeMusicEnabled) list.add('youtube_music');
    if (spotifyEnabled) list.add('spotify');
    // soundCloud later
    return list;
  }

  /// Whether a specific provider should be queried right now.
  bool isEnabled(String providerId) {
    switch (providerId.toLowerCase()) {
      case 'supabase':
      case 'nali':
      case 'primary':
        return true;
      case 'youtube_music':
      case 'youtube':
      case 'ytm':
        return youtubeMusicEnabled;
      case 'spotify':
        return spotifyEnabled;
      case 'soundcloud':
        return soundCloudEnabled;
      default:
        return false;
    }
  }

  /// Human readable status for Settings UI.
  String statusText(String providerId, {String locale = 'es'}) {
    final en = locale == 'en';
    switch (providerId.toLowerCase()) {
      case 'supabase':
        return en ? 'Primary · always active' : 'Principal · siempre activo';
      case 'youtube_music':
      case 'youtube':
        if (youtubeMusicEnabled) {
          return en
              ? 'Active · results included in search'
              : 'Activo · resultados incluidos en búsqueda';
        }
        return en
            ? 'Disabled · catalog is not queried'
            : 'Desactivado · no se consulta su catálogo';
      case 'spotify':
        final linked = SpotifyService.instance.isLinked;
        if (spotifyEnabled && linked) {
          return en ? 'Active · connected' : 'Activo · conectado';
        }
        if (spotifyEnabled && !linked) {
          return en
              ? 'Enabled but not connected'
              : 'Activado pero no conectado';
        }
        if (!spotifyEnabled && linked) {
          return en
              ? 'Connected · catalog disabled'
              : 'Conectado · catálogo desactivado';
        }
        return en ? 'Disabled' : 'Desactivado';
      case 'soundcloud':
        return en ? 'Coming soon' : 'Próximamente';
      default:
        return '';
    }
  }

  /// Quick check used by Search / Home later.
  bool get shouldQueryYoutube => youtubeMusicEnabled;
  bool get shouldQuerySpotify => spotifyEnabled;
  bool get shouldQuerySupabase => true;
}
