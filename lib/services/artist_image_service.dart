import 'package:flutter/foundation.dart';
import 'package:nali/services/supabase_service.dart';

/// Artist photo lookup via Kokoro Edge Function → Deezer.
/// Direct browser calls to api.deezer.com fail CORS on web; the function does not.
class ArtistImageService {
  static final Map<String, String?> _cache = {};

  static Future<String?> imageFor(String artistName) async {
    final key = artistName.trim().toLowerCase();
    if (key.isEmpty) return null;
    if (_cache.containsKey(key)) return _cache[key];

    try {
      final response = await SupabaseService.kokoro.functions
          .invoke(
            'artist-image',
            body: {'artist': artistName.trim()},
          )
          .timeout(const Duration(seconds: 12));
      final payload = response.data;
      final url =
          payload is Map ? (payload['image_url'] ?? '').toString() : '';
      if (url.startsWith('http')) {
        _cache[key] = url;
        return url;
      }
    } catch (e) {
      debugPrint('ArtistImageService: $e');
    }
    _cache[key] = null;
    return null;
  }
}
