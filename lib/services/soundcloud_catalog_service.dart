import 'package:flutter/foundation.dart';
import 'package:nali/services/provider_service.dart';
import 'package:nali/services/supabase_service.dart';

/// SoundCloud public mode supports official oEmbed for a known permalink.
/// Catalog search requires a registered SoundCloud Client ID and is not
/// falsely presented as available when no credential has been configured.
class SoundCloudCatalogService {
  SoundCloudCatalogService._();
  static final instance = SoundCloudCatalogService._();

  Future<List<Map<String, dynamic>>> search(String query, {int limit = 24}) async {
    if (!ProviderService.instance.soundCloudEnabled) return const [];
    final uri = Uri.tryParse(query.trim());
    final isTrackUrl = uri != null && uri.scheme == 'https' &&
        (uri.host == 'soundcloud.com' || uri.host.endsWith('.soundcloud.com'));
    if (!isTrackUrl) {
      debugPrint('SoundCloud global search is unavailable without an official Client ID; no-key mode only resolves a known permalink.');
      return const [];
    }
    try {
      final response = await SupabaseService.kokoro.functions.invoke(
        'soundcloud-catalog', body: {'url': uri.toString()},
      ).timeout(const Duration(seconds: 15));
      final row = response.data;
      if (row is! Map) return const [];
      final item = Map<String, dynamic>.from(row);
      return [{
        'id': 'soundcloud:${uri.toString()}', 'provider': 'soundcloud', 'source': 'soundcloud',
        'title': item['title'] ?? 'SoundCloud track', 'artist': item['artist'] ?? 'SoundCloud',
        'cover_url': item['thumbnail_url'], 'audio_url': null,
        'permalink_url': item['url'] ?? uri.toString(), 'embed_url': item['embed_url'],
        'downloadable': false,
      }];
    } catch (error, stack) {
      debugPrint('SoundCloud oEmbed error: $error\n$stack');
      return const [];
    }
  }
}
