import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nali/services/provider_service.dart';

/// YouTube Music catalog via InnerTube.
///
/// Ported from Tori: `YouTubeCatalogRepository.kt`
///
/// Rules (mandatory):
/// - Only performs requests when ProviderService.youtubeMusicEnabled == true.
/// - Returns empty list (does not throw) when the provider is disabled.
/// - Does NOT claim direct streaming; only metadata + videoId.
/// - Uses the same public InnerTube key and client strategy as Tori.
class YoutubeCatalogService {
  YoutubeCatalogService._();
  static final YoutubeCatalogService instance = YoutubeCatalogService._();

  // Same public InnerTube key used by YouTube Music clients (from Tori)
  static const _apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
  static const _searchUrl =
      'https://music.youtube.com/youtubei/v1/search?key=$_apiKey&prettyPrint=false';

  final http.Client _client = http.Client();

  /// Search songs on YouTube Music.
  /// Returns a list of maps compatible with Nali song model.
  /// Empty list when provider is disabled or query is blank.
  Future<List<Map<String, dynamic>>> search(
    String query, {
    int limit = 30,
  }) async {
    // Mandatory: respect the Settings → Proveedores switch
    if (!ProviderService.instance.youtubeMusicEnabled) {
      return const [];
    }
    if (query.trim().isEmpty) return const [];

    try {
      // Prefer WEB_REMIX (more stable JSON shape), fallback to ANDROID_MUSIC
      var results = await _searchWithClient(
        query: query,
        limit: limit,
        clientName: 'WEB_REMIX',
        clientVersion: '1.20241001.01.00',
        clientId: '67',
      );

      if (results.isEmpty) {
        results = await _searchWithClient(
          query: query,
          limit: limit,
          clientName: 'ANDROID_MUSIC',
          clientVersion: '7.27.52',
          clientId: '21',
        );
      }

      return results;
    } catch (e, st) {
      debugPrint('YoutubeCatalogService.search error: $e\n$st');
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _searchWithClient({
    required String query,
    required int limit,
    required String clientName,
    required String clientVersion,
    required String clientId,
  }) async {
    final body = {
      'context': {
        'client': {
          'clientName': clientName,
          'clientVersion': clientVersion,
          'hl': 'es',
          'gl': 'US',
        },
      },
      'query': query,
      // Filter: songs only
      'params': 'EgWKAQIIAWoKEAMQBBAJEAoQBQ%3D%3D',
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Origin': 'https://music.youtube.com',
      'Referer': 'https://music.youtube.com/',
      'X-YouTube-Client-Name': clientId,
      'X-YouTube-Client-Version': clientVersion,
      'User-Agent': clientName == 'ANDROID_MUSIC'
          ? 'com.google.android.apps.youtube.music/$clientVersion (Linux; U; Android 14)'
          : 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
    };

    final response = await _client
        .post(
          Uri.parse(_searchUrl),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      debugPrint('YTM search HTTP ${response.statusCode}');
      return const [];
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseSearchResponse(json, limit);
  }

  List<Map<String, dynamic>> _parseSearchResponse(
    Map<String, dynamic> root,
    int limit,
  ) {
    final results = <Map<String, dynamic>>[];

    // Walk contents looking for musicResponsiveListItemRenderer / twoColumnItemRenderer style items
    void walk(dynamic node) {
      if (results.length >= limit) return;
      if (node is Map<String, dynamic>) {
        // musicResponsiveListItemRenderer
        final item = node['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
        if (item != null) {
          final song = _parseResponsiveItem(item);
          if (song != null) results.add(song);
          return;
        }

        // twoColumnItemRenderer / musicTwoRowItemRenderer style
        final twoRow = node['musicTwoRowItemRenderer'] as Map<String, dynamic>?;
        if (twoRow != null) {
          final song = _parseTwoRow(twoRow);
          if (song != null) results.add(song);
          return;
        }

        // Continue walking
        for (final value in node.values) {
          walk(value);
          if (results.length >= limit) return;
        }
      } else if (node is List) {
        for (final e in node) {
          walk(e);
          if (results.length >= limit) return;
        }
      }
    }

    walk(root);
    return results;
  }

  Map<String, dynamic>? _parseResponsiveItem(Map<String, dynamic> item) {
    try {
      final videoId = _findVideoId(item);
      if (videoId == null) return null;

      final flex = item['flexColumns'] as List?;
      String title = 'YouTube';
      String artist = 'YouTube Music';

      if (flex != null && flex.isNotEmpty) {
        title = _extractRunText(flex[0]) ?? title;
        if (flex.length > 1) {
          artist = _extractRunText(flex[1]) ?? artist;
        }
      }

      final cover = _extractThumb(item) ??
          'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

      return _songMap(
        videoId: videoId,
        title: title,
        artist: artist,
        cover: cover,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _parseTwoRow(Map<String, dynamic> item) {
    try {
      final videoId = _findVideoId(item);
      if (videoId == null) return null;

      final title = _extractRunText(item['title']) ?? 'YouTube';
      final artist = _extractRunText(item['subtitle']) ?? 'YouTube Music';
      final cover = _extractThumb(item) ??
          'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

      return _songMap(
        videoId: videoId,
        title: title,
        artist: artist,
        cover: cover,
      );
    } catch (_) {
      return null;
    }
  }

  String? _extractRunText(dynamic node) {
    if (node == null) return null;
    if (node is Map) {
      // musicResponsiveListItemFlexColumnRenderer → text → runs
      final renderer = node['musicResponsiveListItemFlexColumnRenderer'];
      if (renderer is Map) {
        return _extractRunText(renderer['text']);
      }
      final runs = node['runs'];
      if (runs is List && runs.isNotEmpty) {
        final first = runs.first;
        if (first is Map && first['text'] is String) {
          return first['text'] as String;
        }
      }
      if (node['text'] is String) return node['text'] as String;
    }
    return null;
  }

  String? _extractThumb(Map<String, dynamic> item) {
    try {
      dynamic thumbs = item['thumbnail']?['musicThumbnailRenderer']?['thumbnail']
          ?['thumbnails'];
      thumbs ??= item['thumbnailRenderer']?['musicThumbnailRenderer']
          ?['thumbnail']?['thumbnails'];

      if (thumbs is List && thumbs.isNotEmpty) {
        final last = thumbs.last;
        if (last is Map && last['url'] is String) {
          return last['url'] as String;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Finds an 11-char videoId anywhere in the item tree (same approach as Tori).
  String? _findVideoId(Map<String, dynamic> o) {
    final str = jsonEncode(o);
    final match = RegExp(r'"videoId"\s*:\s*"([a-zA-Z0-9_-]{11})"').firstMatch(str);
    return match?.group(1);
  }

  Map<String, dynamic> _songMap({
    required String videoId,
    required String title,
    required String artist,
    required String cover,
  }) {
    return {
      'id': 'yt_$videoId',
      'title': title,
      'artist': artist,
      'album': 'YouTube Music',
      'cover_url': cover,
      'audio_url': null, // stream resolved later if needed
      'duration': 0,
      'provider': 'youtube_music',
      'youtube_id': videoId,
      'source': 'youtube_music',
    };
  }
}
