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
  static const _kAppleEnabled = 'provider_apple_music_enabled';
  static const _kDeezerEnabled = 'provider_deezer_enabled';

  // ── State ─────────────────────────────────────────────────────────
  /// Supabase is always considered enabled. Primary music source of Nali.
  bool get supabaseEnabled => true;

  /// YouTube Music – OFF by default (mandatory).
  bool youtubeMusicEnabled = false;

  /// Spotify – user can enable/disable whether its results appear in search/home.
  /// Actual OAuth connection is handled by SpotifyService.
  bool spotifyEnabled = false;

  /// SoundCloud catalog. OAuth credentials stay on the Supabase Edge Function.
  bool soundCloudEnabled = false;
  bool appleMusicEnabled = false;
  bool deezerEnabled = false;

  bool get isLoaded => _loaded;
  bool _loaded = false;

  // ── Load / Save ───────────────────────────────────────────────────
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    youtubeMusicEnabled = prefs.getBool(_kYoutubeEnabled) ?? false; // default OFF
    spotifyEnabled = prefs.getBool(_kSpotifyEnabled) ?? false;
    soundCloudEnabled = prefs.getBool(_kSoundCloudEnabled) ?? false;
    appleMusicEnabled = prefs.getBool(_kAppleEnabled) ?? false;
    deezerEnabled = prefs.getBool(_kDeezerEnabled) ?? false;
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

  Future<void> setAppleMusicEnabled(bool value) async {
    if (appleMusicEnabled == value) return;
    appleMusicEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAppleEnabled, value);
    notifyListeners();
  }

  Future<void> setDeezerEnabled(bool value) async {
    if (deezerEnabled == value) return;
    deezerEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDeezerEnabled, value);
    notifyListeners();
  }

  Future<void> setSoundCloudEnabled(bool value) async {
    if (soundCloudEnabled == value) return;
    soundCloudEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSoundCloudEnabled, value);
    notifyListeners();
  }

  // ── Queries ───────────────────────────────────────────────────────

  /// Providers that are currently allowed to be queried.
  /// Supabase is always first.
  List<String> get activeProviders {
    final list = <String>['supabase'];
    if (youtubeMusicEnabled) list.add('youtube_music');
    if (spotifyEnabled) list.add('spotify');
    if (soundCloudEnabled) list.add('soundcloud');
    if (appleMusicEnabled) list.add('apple_music');
    if (deezerEnabled) list.add('deezer');
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
      case 'apple_music':
      case 'apple':
        return appleMusicEnabled;
      case 'deezer':
        return deezerEnabled;
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
        return soundCloudEnabled
            ? (en ? 'Enabled · public links; catalog search needs Client ID' : 'Activado · enlaces públicos; búsqueda requiere Client ID')
            : (en ? 'Disabled' : 'Desactivado');
      case 'apple_music':
      case 'apple':
        return appleMusicEnabled
            ? (en ? 'Active · official previews' : 'Activo · avances oficiales')
            : (en ? 'Disabled' : 'Desactivado');
      case 'deezer':
        return deezerEnabled
            ? (en ? 'Active · 30-second previews' : 'Activo · avances de 30 segundos')
            : (en ? 'Disabled' : 'Desactivado');
      default:
        return '';
    }
  }

  /// Quick check used by Search / Home later.
  bool get shouldQueryYoutube => youtubeMusicEnabled;
  bool get shouldQuerySpotify => spotifyEnabled;
  bool get shouldQuerySoundCloud => soundCloudEnabled;
  bool get shouldQueryAppleMusic => appleMusicEnabled;
  bool get shouldQueryDeezer => deezerEnabled;
  bool get shouldQuerySupabase => true;
}
