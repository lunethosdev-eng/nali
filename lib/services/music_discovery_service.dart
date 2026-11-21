import 'package:flutter/foundation.dart';
import 'package:nali/services/supabase_service.dart';

/// Public catalog providers. Apple/iTunes and Deezer return official short
/// previews, not full-track streams; the UI labels them as previews.
class MusicDiscoveryService {
  MusicDiscoveryService._();
  static final instance = MusicDiscoveryService._();

  Future<List<Map<String, dynamic>>> search(String provider, String query, {int limit = 25}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      final response = await SupabaseService.kokoro.functions.invoke(
        'music-discovery',
        body: {'provider': provider, 'query': q, 'limit': limit.clamp(1, 30)},
      ).timeout(const Duration(seconds: 18));
      final data = response.data;
      final rows = data is Map ? data['results'] : null;
      if (rows is! List) return const [];
      return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row))
          .where((row) => (row['audio_url'] ?? '').toString().startsWith('https://'))
          .toList();
    } catch (error, stack) {
      debugPrint('$provider discovery error: $error\n$stack');
      return const [];
    }
  }
}
