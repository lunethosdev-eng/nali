import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nali/services/supabase_service.dart';

/// MangaDex title search for profile favorites. Uses an authenticated Edge proxy first, then the public endpoint fallback.
class MangaDexService {
  MangaDexService._();
  static final instance = MangaDexService._();

  Future<List<Map<String, String?>>> search(String query, {int limit = 12}) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];
    final uri = Uri.https('api.mangadex.org', '/manga', {
      'title': trimmed,
      'limit': '${limit.clamp(1, 32)}',
      'includes[]': 'cover_art',
      'order[relevance]': 'desc',
      'contentRating[]': 'safe',
    });
    dynamic root;
    // Signed-in users try the same-origin-friendly Edge proxy first. If it is
    // not deployed yet, fall back to the public API for platforms where CORS allows it.
    try {
      final proxy = await SupabaseService.kokoro.functions.invoke('mangadex-search', body: {'query': trimmed, 'limit': limit.clamp(1, 32)});
      root = proxy.data;
      if (root is! Map || root['data'] is! List) throw StateError('Unexpected MangaDex proxy response');
    } catch (_) {
      final response = await http.get(uri, headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('MangaDex HTTP ${response.statusCode}. El proveedor rechazó la solicitud; intenta más tarde.');
      root = jsonDecode(response.body);
    }
    final data = root is Map ? root['data'] : null;
    if (data is! List) return const [];
    return data.map<Map<String, String?>?>((item) {
      if (item is! Map) return null;
      final id = item['id']?.toString() ?? '';
      final attributes = item['attributes'];
      if (id.isEmpty || attributes is! Map) return null;
      final titles = attributes['title'];
      String title = 'Sin título';
      if (titles is Map) {
        title = (titles['en']?.toString().trim().isNotEmpty == true)
            ? titles['en'].toString()
            : titles.values.firstWhere((v) => v.toString().trim().isNotEmpty, orElse: () => title).toString();
      }
      String? coverFile;
      final relationships = item['relationships'];
      if (relationships is List) {
        for (final relation in relationships) {
          if (relation is Map && relation['type'] == 'cover_art') {
            final file = (relation['attributes'] is Map)
                ? relation['attributes']['fileName']?.toString()
                : null;
            if (file?.isNotEmpty == true) { coverFile = file; break; }
          }
        }
      }
      return {
        'id': id,
        'title': title,
        'cover': coverFile == null ? null : 'https://uploads.mangadex.org/covers/$id/$coverFile.256.jpg',
      };
    }).whereType<Map<String, String?>>().toList();
  }
}
