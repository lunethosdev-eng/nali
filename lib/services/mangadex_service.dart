import 'package:nali/services/supabase_service.dart';

/// Manga catalog lookup through the public Supabase proxy. MangaDex is primary;
/// the function automatically returns AniList results when MangaDex blocks egress.
class MangaDexService {
  MangaDexService._();
  static final instance = MangaDexService._();

  Future<List<Map<String, String?>>> search(String query, {int limit = 12}) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];
    final response = await SupabaseService.kokoro.functions.invoke(
      'mangadex-search',
      body: {'query': trimmed, 'limit': limit.clamp(1, 32)},
    ).timeout(const Duration(seconds: 22));
    final root = response.data;
    final data = root is Map ? root['data'] : null;
    if (data is! List) throw StateError('MangaDex/AniList no devolvió resultados.');
    return data.map<Map<String, String?>?>((item) {
      if (item is! Map) return null;
      final id = item['id']?.toString() ?? '';
      final attributes = item['attributes'];
      if (id.isEmpty || attributes is! Map) return null;
      final titles = attributes['title'];
      String title = 'Sin título';
      if (titles is Map) {
        final english = titles['en']?.toString().trim() ?? '';
        final romaji = titles['romaji']?.toString().trim() ?? '';
        title = english.isNotEmpty ? english : romaji.isNotEmpty ? romaji :
          titles.values.map((v) => v.toString()).firstWhere((v) => v.trim().isNotEmpty, orElse: () => title);
      }
      String? cover = attributes['coverUrl']?.toString();
      final relationships = item['relationships'];
      if (cover == null && relationships is List) {
        for (final relation in relationships) {
          if (relation is Map && relation['type'] == 'cover_art') {
            final file = relation['attributes'] is Map ? relation['attributes']['fileName']?.toString() : null;
            if (file?.isNotEmpty == true) { cover = 'https://uploads.mangadex.org/covers/$id/$file.256.jpg'; break; }
          }
        }
      }
      return {'id': id, 'title': title, 'cover': cover};
    }).whereType<Map<String, String?>>().toList();
  }
}
