import 'package:flutter/foundation.dart';
import 'package:nali/services/supabase_service.dart';

/// Global / catalog tops from song_plays when available, else play-count fields.
class TopsService {
  TopsService._();
  static final instance = TopsService._();

  List<Map<String, dynamic>> _cache = [];
  DateTime? _fetchedAt;

  Future<List<Map<String, dynamic>>> topSongs({int limit = 20}) async {
    if (_cache.isNotEmpty &&
        _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < const Duration(minutes: 8)) {
      return _cache.take(limit).toList();
    }
    try {
      // Prefer aggregated plays table if it exists.
      try {
        final plays = await SupabaseService.kokoro
            .from('song_plays')
            .select('song_id, title, artist')
            .limit(400);
        final counts = <String, Map<String, dynamic>>{};
        for (final row in List<Map<String, dynamic>>.from(plays as List)) {
          final id = (row['song_id'] ?? row['title'] ?? '').toString();
          if (id.isEmpty) continue;
          final entry = counts.putIfAbsent(id, () => {
                'id': id,
                'title': row['title'] ?? 'Track',
                'artist': row['artist'] ?? '',
                'play_count': 0,
              });
          entry['play_count'] = (entry['play_count'] as int) + 1;
        }
        final ranked = counts.values.toList()
          ..sort((a, b) =>
              (b['play_count'] as int).compareTo(a['play_count'] as int));
        if (ranked.isNotEmpty) {
          // Merge covers from catalog when possible.
          final catalog = await SupabaseService.getSongs(limit: 120);
          final byId = {
            for (final s in catalog) (s['id'] ?? '').toString(): s,
          };
          final byTitle = {
            for (final s in catalog)
              '${s['title']}|${s['artist']}'.toLowerCase(): s,
          };
          for (final r in ranked) {
            final match = byId[r['id']?.toString()] ??
                byTitle['${r['title']}|${r['artist']}'.toLowerCase()];
            if (match != null) {
              r['cover_url'] = match['cover_url'];
              r['audio_url'] = match['audio_url'];
              r['provider'] = match['provider'] ?? match['source'] ?? 'supabase';
              r.addAll(Map<String, dynamic>.from(match)
                ..removeWhere((k, _) => r.containsKey(k) && r[k] != null));
            }
          }
          _cache = ranked;
          _fetchedAt = DateTime.now();
          return ranked.take(limit).toList();
        }
      } catch (e) {
        debugPrint('TopsService song_plays: $e');
      }

      final songs = await SupabaseService.getSongs(limit: 100);
      songs.sort((a, b) {
        final pa = (a['play_count'] is num)
            ? (a['play_count'] as num).toInt()
            : int.tryParse('${a['play_count'] ?? 0}') ?? 0;
        final pb = (b['play_count'] is num)
            ? (b['play_count'] as num).toInt()
            : int.tryParse('${b['play_count'] ?? 0}') ?? 0;
        return pb.compareTo(pa);
      });
      _cache = songs;
      _fetchedAt = DateTime.now();
      return songs.take(limit).toList();
    } catch (e) {
      debugPrint('TopsService: $e');
      return const [];
    }
  }
}
