import 'package:flutter/foundation.dart';
import 'package:nali/services/provider_service.dart';
import 'package:nali/services/supabase_service.dart';

/// Search for openly licensed/public-domain audio on Internet Archive.
/// Unlike Apple/Deezer previews, returned tracks have a direct playable file.
class InternetArchiveCatalogService {
  InternetArchiveCatalogService._();
  static final instance = InternetArchiveCatalogService._();

  Future<List<Map<String, dynamic>>> search(String query, {int limit = 20}) async {
    if (!ProviderService.instance.internetArchiveEnabled || query.trim().length < 2) {
      return const [];
    }
    try {
      final response = await SupabaseService.kokoro.functions.invoke(
        'internet-archive-catalog',
        body: {'query': query.trim(), 'limit': limit.clamp(1, 20)},
      ).timeout(const Duration(seconds: 25));
      final payload = response.data;
      final rows = payload is Map ? payload['results'] : null;
      if (rows is! List) return const [];
      return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row))
          .where((row) => (row['audio_url'] ?? '').toString().startsWith('https://'))
          .toList();
    } catch (error, stack) {
      debugPrint('Internet Archive search error: $error\n$stack');
      return const [];
    }
  }
}
