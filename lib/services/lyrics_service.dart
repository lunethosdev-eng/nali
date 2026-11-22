import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nali/services/custom_provider_service.dart';
import 'package:nali/services/supabase_service.dart';

/// Free lyrics sources: LRCLIB, BetterLyrics, Lyrics.ovh, and additional
/// BitChord/Tori providers proxied through Supabase (QQ, Unison, SimpMusic,
/// KuGou and YouTube Music lyrics). User APIs are the last fallback.
class LyricsService {
  static const _ua = 'Nali/1.1 (https://github.com/lunethosdev-eng/nali)';

  static bool isJunk(String? text) {
    if (text == null || text.trim().length < 12) return true;
    final lower = text.toLowerCase();
    const bad = ['termux', 'seki', 'procesado por', 'processed by', 'sticky termos',
      'server error', 'no lyrics available on server', 'lyrics not found'];
    return bad.any(lower.contains);
  }

  static Future<String?> resolve({
    String? localText, required String title, required String artist,
    String? album, int? durationSeconds, String? videoId,
  }) async {
    if (!isJunk(localText)) return localText;
    return fetch(title: title, artist: artist, album: album,
      durationSeconds: durationSeconds, videoId: videoId);
  }

  static Future<String?> fetch({
    required String title, required String artist, String? album,
    int? durationSeconds, String? videoId,
  }) async {
    final cleanTitle = title.trim();
    final cleanArtist = artist.trim();
    if (cleanTitle.isEmpty || cleanArtist.isEmpty) return null;
    final client = http.Client();
    try {
      // 1) LRCLIB: plain or line-synced lyrics, no API key.
      try {
        final uri = Uri.https('lrclib.net', '/api/search', {'q': '$cleanTitle $cleanArtist'});
        final response = await client.get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
            .timeout(const Duration(seconds: 9));
        if (response.statusCode == 200) {
          final rows = jsonDecode(response.body);
          if (rows is List && rows.isNotEmpty) {
            Map<String, dynamic>? best;
            for (final row in rows.whereType<Map>()) {
              final item = Map<String, dynamic>.from(row);
              final name = (item['trackName'] ?? item['name'] ?? '').toString().toLowerCase();
              final who = (item['artistName'] ?? '').toString().toLowerCase();
              if (name == cleanTitle.toLowerCase() && who.contains(cleanArtist.toLowerCase())) { best = item; break; }
              best ??= item;
            }
            final synced = best?['syncedLyrics']?.toString();
            if (!isJunk(synced)) return synced;
            final plain = best?['plainLyrics']?.toString();
            if (!isJunk(plain)) return plain;
          }
        }
      } catch (e) { debugPrint('LRCLIB lyrics: $e'); }

      // 2) Better Lyrics: word/syllable-synced TTML. Requires known duration.
      if (durationSeconds != null && durationSeconds > 0) {
        try {
          final uri = Uri.https('api.betterlyrics.org', '/getLyrics', {
            's': cleanTitle, 'a': cleanArtist, 'al': album?.trim().isNotEmpty == true ? album!.trim() : 'Unknown',
            'd': '$durationSeconds',
          });
          final response = await client.get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
              .timeout(const Duration(seconds: 9));
          if (response.statusCode == 200) {
            final payload = jsonDecode(response.body);
            final ttml = payload is Map ? payload['ttml']?.toString() : null;
            final lrc = ttml == null ? null : _ttmlToLrc(ttml);
            if (!isJunk(lrc)) return lrc;
          }
        } catch (e) { debugPrint('Better Lyrics: $e'); }
      }

      // 3) Lyrics.ovh: independent plain-text source, no API key.
      try {
        final uri = Uri.parse('https://api.lyrics.ovh/v1/${Uri.encodeComponent(cleanArtist)}/${Uri.encodeComponent(cleanTitle)}');
        final response = await client.get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
            .timeout(const Duration(seconds: 9));
        if (response.statusCode == 200) {
          final payload = jsonDecode(response.body);
          final lyrics = payload is Map ? payload['lyrics']?.toString() : null;
          if (!isJunk(lyrics)) return lyrics;
        }
      } catch (e) { debugPrint('Lyrics.ovh: $e'); }

      // 4) More free sources migrated from BitChord/Tori. They run behind
      // Supabase so browsers do not fail on third-party CORS restrictions:
      // BetterLyrics QQ/Portato, Unison, SimpMusic and KuGou;
      // YouTube Music's own Lyrics tab. SimpMusic is region-blocked in some
      // countries, so the server continues to the next provider on a miss.
      try {
        final response = await SupabaseService.kokoro.functions.invoke(
          'lyrics-catalog',
          body: {
            'title': cleanTitle,
            'artist': cleanArtist,
            'album': album ?? '',
            'durationSeconds': durationSeconds ?? 0,
            'videoId': videoId ?? '',
          },
        ).timeout(const Duration(seconds: 45));
        final payload = response.data;
        final lyrics = payload is Map ? payload['lyrics']?.toString() : null;
        if (!isJunk(lyrics)) {
          final source = payload is Map ? payload['provider']?.toString() : 'free fallback';
          debugPrint('Lyrics resolved by $source');
          return lyrics;
        }
      } catch (e) { debugPrint('Free lyrics provider fallback: $e'); }

      // 5) User-configured lyrics APIs, if any.
      try {
        final custom = await CustomProviderService.instance.fetchLyrics(title: cleanTitle, artist: cleanArtist);
        if (!isJunk(custom)) return custom;
      } catch (e) { debugPrint('Custom lyrics: $e'); }
    } finally { client.close(); }
    return null;
  }

  static String? _ttmlToLrc(String source) {
    final lines = <MapEntry<int, String>>[];
    final paragraph = RegExp(r'<p\b([^>]*)>([\s\S]*?)</p>', caseSensitive: false);
    for (final match in paragraph.allMatches(source)) {
      final attrs = match.group(1) ?? '';
      final begin = RegExp(r'''begin=["']([^"']+)["']''', caseSensitive: false).firstMatch(attrs)?.group(1);
      if (begin == null) continue;
      var text = (match.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), '');
      text = text.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"').replaceAll('&apos;', "'").trim();
      if (text.isEmpty) continue;
      final ms = _parseTime(begin);
      if (ms != null) lines.add(MapEntry(ms, text));
    }
    if (lines.isEmpty) return null;
    lines.sort((a, b) => a.key.compareTo(b.key));
    return lines.map((line) {
      final minutes = line.key ~/ 60000;
      final seconds = (line.key % 60000) ~/ 1000;
      final hundredths = (line.key % 1000) ~/ 10;
      return '[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}]${line.value}';
    }).join('\n');
  }

  static int? _parseTime(String value) {
    final parts = value.split(':');
    try {
      double seconds;
      if (parts.length == 3) seconds = int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60 + double.parse(parts[2]);
      else if (parts.length == 2) seconds = int.parse(parts[0]) * 60 + double.parse(parts[1]);
      else seconds = double.parse(parts[0]);
      return (seconds * 1000).round();
    } catch (_) { return null; }
  }
}
