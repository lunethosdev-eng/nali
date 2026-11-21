import 'package:flutter/foundation.dart';
import 'package:nali/services/provider_service.dart';
import 'package:nali/services/supabase_service.dart';

/// SoundCloud search is proxied through Supabase so the SoundCloud client
/// secret is never shipped in the Flutter application.
class SoundCloudCatalogService {
  SoundCloudCatalogService._();
  static final SoundCloudCatalogService instance = SoundCloudCatalogService._();

  Future<List<Map<String, dynamic>>> search(String query, {int limit = 24}) async {
    if (!ProviderService.instance.soundCloudEnabled || query.trim().length < 2) {
      return const [];
    }
    try {
      final response = await SupabaseService.kokoro.functions.invoke(
        'soundcloud-catalog',
        body: {'action': 'search', 'query': query.trim(), 'limit': limit.clamp(1, 30)},
      );
      final payload = response.data;
      final rows = payload is Map ? payload['results'] : null;
      if (rows is! List) return const [];
      return rows.whereType<Map>().map((row) {
        final id = row['id']?.toString() ?? '';
        final title = row['title']?.toString() ?? 'SoundCloud track';
        final user = row['user'] is Map ? row['user'] as Map : const {};
        final artist = user['username']?.toString() ?? 'SoundCloud';
        final artwork = row['artwork_url']?.toString();
        final permalink = row['permalink_url']?.toString() ?? '';
        final stream = id.isEmpty ? null :
            '${SupabaseService.kokoroUrl}/functions/v1/soundcloud-catalog?action=stream&id=$id';
        return <String, dynamic>{
          'id': 'soundcloud:$id',
          'provider': 'soundcloud',
          'source': 'soundcloud',
          'title': title,
          'artist': artist,
          'cover_url': artwork,
          'audio_url': stream,
          'stream_url': stream,
          'permalink_url': permalink,
          'duration_ms': row['duration'],
          'downloadable': false,
        };
      }).where((song) => song['id'] != 'soundcloud:').toList();
    } catch (error, stack) {
      debugPrint('SoundCloud catalog error: $error\n$stack');
      return const [];
    }
  }
}
