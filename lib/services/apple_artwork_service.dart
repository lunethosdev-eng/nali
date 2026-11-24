import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Resolves full-resolution album artwork from Apple's public iTunes catalogue.
/// YouTube thumbnails are only used as a fallback when Apple has no exact match.
class AppleArtworkService {
  AppleArtworkService._();

  static final instance = AppleArtworkService._();
  final Map<String, String> _cache = <String, String>{};
  final Map<String, Future<String?>> _pending = <String, Future<String?>>{};

  Future<String?> resolve({
    required String title,
    required String artist,
    String? album,
  }) {
    final cleanTitle = title.trim();
    final cleanArtist = artist.trim();
    if (cleanTitle.isEmpty || cleanArtist.isEmpty) return Future.value(null);

    final key = '${_normalize(cleanArtist)}|${_normalize(cleanTitle)}|${_normalize(album ?? '')}';
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(key, () {
      final future = _lookup(cleanTitle, cleanArtist, album)
          .whenComplete(() { _pending.remove(key); });
      return future;
    });
  }

  Future<String?> _lookup(String title, String artist, String? album) async {
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': '$artist $title',
        'entity': 'song',
        'media': 'music',
        'limit': '10',
        'country': 'US',
      });
      final response = await http.get(uri, headers: const {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['results'] is! List) return null;
      final wantedTitle = _normalize(title);
      final wantedArtist = _normalize(artist);
      final wantedAlbum = _normalize(album ?? '');
      String? bestUrl;
      var bestScore = 0;

      for (final item in decoded['results'] as List) {
        if (item is! Map) continue;
        final track = _normalize(item['trackName']?.toString() ?? '');
        final performer = _normalize(item['artistName']?.toString() ?? '');
        final collection = _normalize(item['collectionName']?.toString() ?? '');
        if (track.isEmpty || performer.isEmpty) continue;

        final titleMatch = track == wantedTitle ||
            track.startsWith(wantedTitle) ||
            wantedTitle.startsWith(track);
        final artistMatch = performer == wantedArtist ||
            performer.contains(wantedArtist) ||
            wantedArtist.contains(performer);
        if (!titleMatch || !artistMatch) continue;

        var score = 4;
        if (track == wantedTitle) score += 3;
        if (performer == wantedArtist) score += 3;
        if (wantedAlbum.isNotEmpty && collection == wantedAlbum) score += 2;

        final rawArtwork = item['artworkUrl100']?.toString() ?? '';
        if (rawArtwork.isEmpty || rawArtwork == 'null') continue;
        final artwork = rawArtwork
            .replaceAll(RegExp(r'\d+x\d+bb'), '1200x1200bb')
            .replaceAll('100x100', '1200x1200');
        if (score > bestScore) {
          bestScore = score;
          bestUrl = artwork;
        }
      }

      if (bestUrl != null) {
        _cache['${_normalize(artist)}|${_normalize(title)}|${_normalize(album ?? '')}'] = bestUrl;
      }
      return bestUrl;
    } catch (error) {
      debugPrint('Apple artwork lookup failed: $error');
      return null;
    }
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)|\[[^]]*\]'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}
