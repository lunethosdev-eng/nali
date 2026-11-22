import 'package:flutter/foundation.dart';
import 'package:nali/services/provider_service.dart';
import 'package:nali/services/supabase_service.dart';

/// YouTube Music catalog routed through Supabase Edge Functions so Web does
/// not make cross-origin InnerTube requests directly.
class YoutubeCatalogService {
  YoutubeCatalogService._();
  static final YoutubeCatalogService instance = YoutubeCatalogService._();

  Future<List<Map<String, dynamic>>> search(String query, {int limit = 30}) async {
    if (!ProviderService.instance.youtubeMusicEnabled || query.trim().length < 2) {
      return const [];
    }
    try {
      final response = await SupabaseService.kokoro.functions.invoke(
        'youtube-music-catalog',
        body: {'query': query.trim(), 'limit': limit.clamp(1, 30)},
      ).timeout(const Duration(seconds: 25));
      final payload = response.data;
      final rows = payload is Map ? payload['results'] : null;
      if (rows is! List) {
        debugPrint('YouTube Music returned an unexpected payload: $payload');
        return const [];
      }
      final songs = rows.whereType<Map>().map((row) {
        final item = Map<String, dynamic>.from(row);
        final id = (item['youtube_id'] ?? item['videoId'] ?? '').toString();
        final videoId = id.isNotEmpty ? id : (item['id'] ?? '').toString().replaceFirst('yt_', '');
        if (videoId.length != 11) return <String, dynamic>{};
        final title = (item['title'] ?? '').toString().trim();
        final artist = (item['artist'] ?? '').toString().trim();
        final cover = (item['cover_url'] ?? item['thumbnail_url'] ?? '').toString();
        return <String, dynamic>{
          ...item,
          'id': 'yt_$videoId',
          'youtube_id': videoId,
          'title': title.isEmpty ? 'YouTube Music' : title,
          'artist': artist.isEmpty ? 'YouTube Music' : artist,
          'album': item['album'] ?? 'YouTube Music',
          'cover_url': cover.isEmpty ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg' : cover,
          'audio_url': null,
          'provider': 'youtube_music',
          'source': 'youtube_music',
          'downloadable': false,
        };
      }).where((song) => song.isNotEmpty).take(limit).toList();
      debugPrint('YouTube Music InnerTube catalog: ${songs.length} results for "$query"');
      return songs;
    } catch (error, stack) {
      debugPrint('YouTube Music Edge Function error: $error\n$stack');
      return const [];
    }
  }
}
