import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nali/services/supabase_service.dart';
import 'package:nali/services/lyrics_service.dart';

/// Discord profile-card integration through the user's POLIC service.
/// The Discord client secret stays on POLIC; Nali only sends the signed-in
/// Supabase access token and the current user's public playback metadata.
class DiscordConnectorService extends ChangeNotifier {
  DiscordConnectorService._();
  static final DiscordConnectorService instance = DiscordConnectorService._();
  static const _base = 'https://polic.onrender.com';
  static const _syncKey = 'polic_discord_now_playing_enabled';
  bool syncEnabled = false;
  bool busy = false;
  String? lastError;
  String? _lastSongKey;

  String? get _userId => SupabaseService.currentUser?.id;
  String? get _token => SupabaseService.kokoro.auth.currentSession?.accessToken;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    syncEnabled = prefs.getBool(_syncKey) ?? false;
    notifyListeners();
  }

  Future<void> setSyncEnabled(bool value) async {
    syncEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_syncKey, value);
    notifyListeners();
  }

  Future<void> connectDiscord() async {
    final userId = _userId;
    if (userId == null) throw StateError('Inicia sesión en Nali antes de conectar Discord.');
    busy = true; lastError = null; notifyListeners();
    try {
      final uri = Uri.parse('$_base/api/auth/discord').replace(
        queryParameters: {'userId': userId},
      );
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No se pudo abrir el inicio de sesión de Discord.');
      }
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally { busy = false; notifyListeners(); }
  }

  Future<void> openCustomize() async {
    final userId = _userId;
    if (userId == null) throw StateError('Inicia sesión en Nali.');
    final uri = Uri.parse('$_base/customize').replace(queryParameters: {'userId': userId});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) throw StateError('No se pudo abrir el personalizador.');
  }

  Future<List<Map<String, dynamic>>> availableThemes() async {
    final response = await http.get(Uri.parse('$_base/api/themes/available')).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError('POLIC respondió HTTP ${response.statusCode}.');
    final data = jsonDecode(response.body);
    final rows = data is List ? data : data is Map ? (data['themes'] ?? data['results']) : null;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
  }

  Future<Map<String, dynamic>?> getNowPlaying() async {
    final id = _userId;
    if (id == null) return null;
    final response = await http.get(Uri.parse('$_base/api/users/$id/now-playing'), headers: _authHeaders).timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('POLIC respondió HTTP ${response.statusCode}.');
    final data = jsonDecode(response.body);
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  Future<Map<String, dynamic>?> getTheme() async {
    final id = _userId;
    if (id == null) return null;
    final response = await http.get(Uri.parse('$_base/api/users/$id/theme'), headers: _authHeaders).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('POLIC respondió HTTP ${response.statusCode}.');
    final data = jsonDecode(response.body);
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  Future<void> updateTheme(Map<String, dynamic> theme) async {
    final id = _userId;
    if (id == null) throw StateError('Inicia sesión en Nali.');
    final response = await http.put(Uri.parse('$_base/api/users/$id/theme'), headers: {..._authHeaders, 'Content-Type': 'application/json'}, body: jsonEncode(theme)).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('POLIC respondió HTTP ${response.statusCode}.');
  }

  Map<String, String> get _authHeaders => {
    if (_token != null) 'Authorization': 'Bearer $_token',
    'Accept': 'application/json',
  };

  Future<void> publishNowPlaying(Map<String, dynamic> song, {String? lyrics}) async {
    if (!syncEnabled || _userId == null || _token == null) return;
    final songKey = (song['id'] ?? song['title'] ?? '').toString();
    if (songKey.isEmpty || songKey == _lastSongKey) return;
    _lastSongKey = songKey;
    final id = _userId!;
    try {
      final lyricText = lyrics ?? song['lyrics_text']?.toString() ?? await LyricsService.resolve(
        localText: null,
        title: song['title']?.toString() ?? '',
        artist: song['artist']?.toString() ?? '',
        album: song['album']?.toString(),
        durationSeconds: (song['duration_seconds'] ?? song['duration']) is num
            ? ((song['duration_seconds'] ?? song['duration']) as num).round() : null,
      ) ?? '';
      final response = await http.post(Uri.parse('$_base/api/users/$id/now-playing'),
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'song': (song['title'] ?? '').toString(),
          'artist': (song['artist'] ?? '').toString(),
          'lyrics': lyricText,
          'albumArt': (song['cover_url'] ?? song['animated_cover_url'] ?? '').toString(),
        })).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('POLIC now-playing HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) { debugPrint('POLIC now-playing sync: $e'); }
  }
}
