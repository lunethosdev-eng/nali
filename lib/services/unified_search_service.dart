import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nali/services/provider_service.dart';
import 'package:nali/services/supabase_service.dart';
import 'package:nali/services/youtube_catalog_service.dart';
import 'package:nali/services/soundcloud_catalog_service.dart';
import 'package:nali/services/music_discovery_service.dart';
import 'package:nali/services/custom_provider_service.dart';
import 'package:nali/services/spotify_service.dart';
import 'package:nali/services/internet_archive_catalog_service.dart';

/// Unified search for Nali (Phase 4).
///
/// Rules:
/// - Supabase is always queried (primary source).
/// - YouTube Music is queried ONLY when ProviderService.youtubeMusicEnabled.
/// - SoundCloud resolves public permalinks; global search needs a Client ID.
// - Apple/iTunes and Deezer provide official short previews when enabled.
// - Custom providers are queried only when configured by the user.
/// - The MP3 download server is deliberately excluded from catalog search.
/// - Results are tagged with `provider` / `source`.
/// - Supports autocomplete with debounce + cancellation of in-flight requests.
class UnifiedSearchService {
  UnifiedSearchService._();
  static final UnifiedSearchService instance = UnifiedSearchService._();

  int _searchToken = 0;
  Timer? _debounceTimer;

  /// Cancel any pending debounced search.
  void cancelPending() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Full search (for the main Search button / submit).
  /// Combines Supabase + YouTube (if enabled).
  Future<UnifiedSearchResult> search(
    String query, {
    int limitPerProvider = 25,
    void Function(String status)? onStatus,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return UnifiedSearchResult.empty(q);
    }

    final token = ++_searchToken;
    final ps = ProviderService.instance;

    onStatus?.call('Buscando…');

    // 1) Supabase (always)
    List<Map<String, dynamic>> supabaseResults = [];
    try {
      supabaseResults = await SupabaseService.searchSongs(q, limit: limitPerProvider);
      // Ensure provider tag
      supabaseResults = supabaseResults.map((s) {
        final m = Map<String, dynamic>.from(s);
        m['provider'] ??= 'supabase';
        m['source'] ??= 'supabase';
        return m;
      }).toList();
    } catch (e) {
      debugPrint('UnifiedSearch Supabase error: $e');
    }

    if (token != _searchToken) {
      return UnifiedSearchResult.empty(q); // cancelled
    }

    // 2) YouTube Music (only if enabled)
    List<Map<String, dynamic>> youtubeResults = [];
    if (ps.shouldQueryYoutube) {
      onStatus?.call('YouTube Music…');
      try {
        youtubeResults = await YoutubeCatalogService.instance.search(
          q,
          limit: limitPerProvider,
        );
      } catch (e) {
        debugPrint('UnifiedSearch YouTube error: $e');
      }
    }

    if (token != _searchToken) {
      return UnifiedSearchResult.empty(q);
    }

    // 3) SoundCloud (optional; separate from the Nali MP3 download server)
    List<Map<String, dynamic>> soundCloudResults = [];
    if (ps.shouldQuerySoundCloud) {
      onStatus?.call('SoundCloud…');
      try {
        soundCloudResults = await SoundCloudCatalogService.instance.search(
          q,
          limit: limitPerProvider,
        );
      } catch (e) {
        debugPrint('UnifiedSearch SoundCloud error: $e');
      }
    }

    if (token != _searchToken) {
      return UnifiedSearchResult.empty(q);
    }

    List<Map<String, dynamic>> spotifyResults = [];
    if (ps.shouldQuerySpotify) {
      onStatus?.call('Spotify…');
      spotifyResults = await SpotifyService.instance.searchTracks(q, limit: limitPerProvider);
    }
    if (token != _searchToken) return UnifiedSearchResult.empty(q);

    final discoveryFutures = <Future<List<Map<String, dynamic>>>>[];
    if (ps.shouldQueryAppleMusic) {
      onStatus?.call('Apple Music…');
      discoveryFutures.add(MusicDiscoveryService.instance.search('apple', q, limit: limitPerProvider));
    }
    if (ps.shouldQueryDeezer) {
      onStatus?.call('Deezer…');
      discoveryFutures.add(MusicDiscoveryService.instance.search('deezer', q, limit: limitPerProvider));
    }
    if (ps.shouldQueryInternetArchive) {
      onStatus?.call('Internet Archive…');
      discoveryFutures.add(InternetArchiveCatalogService.instance.search(q, limit: limitPerProvider));
    }
    List<Map<String, dynamic>> discoveryResults = [];
    if (token != _searchToken) return UnifiedSearchResult.empty(q);
    if (discoveryFutures.isNotEmpty) {
      try { discoveryResults = (await Future.wait(discoveryFutures)).expand((items) => items).toList(); }
      catch (e) { debugPrint('UnifiedSearch discovery error: $e'); }
    }
    if (token != _searchToken) return UnifiedSearchResult.empty(q);

    List<Map<String, dynamic>> customResults = [];
    try { customResults = await CustomProviderService.instance.searchMusic(q, limit: limitPerProvider); }
    catch (e) { debugPrint('UnifiedSearch custom providers error: $e'); }
    if (token != _searchToken) return UnifiedSearchResult.empty(q);

    final merged = _mergeResults([
      supabaseResults,
      youtubeResults,
      soundCloudResults,
      spotifyResults,
      discoveryResults,
      customResults,
    ]);

    return UnifiedSearchResult(
      query: q,
      all: merged,
      supabase: supabaseResults,
      youtube: youtubeResults,
      remote: [...youtubeResults, ...soundCloudResults, ...spotifyResults, ...discoveryResults, ...customResults],
    );
  }

  /// Autocomplete / suggestions while typing.
  /// Uses debounce. Cancels previous in-flight work via token.
  ///
  /// [onResults] is called with the latest suggestions.
  void autocomplete(
    String query, {
    required void Function(List<Map<String, dynamic>> suggestions) onResults,
    Duration debounce = const Duration(milliseconds: 350),
    int limit = 12,
  }) {
    cancelPending();
    final q = query.trim();
    if (q.length < 2) {
      onResults(const []);
      return;
    }

    _debounceTimer = Timer(debounce, () async {
      final token = ++_searchToken;
      final suggestions = <Map<String, dynamic>>[];

      // Local / Supabase first (fast)
      try {
        final local = await SupabaseService.searchSongs(q, limit: limit);
        for (final s in local) {
          final m = Map<String, dynamic>.from(s);
          m['provider'] ??= 'supabase';
          m['source'] ??= 'supabase';
          suggestions.add(m);
        }
      } catch (_) {}

      if (token != _searchToken) return;

      // YouTube only if enabled and we still need more
      if (ProviderService.instance.shouldQueryYoutube &&
          suggestions.length < limit) {
        try {
          final yt = await YoutubeCatalogService.instance.search(
            q,
            limit: limit - suggestions.length,
          );
          suggestions.addAll(yt);
        } catch (_) {}
      }

      if (token != _searchToken) return;
      if (ProviderService.instance.shouldQuerySoundCloud && suggestions.length < limit) {
        try {
          final sc = await SoundCloudCatalogService.instance.search(
            q,
            limit: limit - suggestions.length,
          );
          suggestions.addAll(sc);
        } catch (_) {}
      }
      if (token != _searchToken) return;
      if (ProviderService.instance.shouldQuerySpotify && suggestions.length < limit) {
        try { suggestions.addAll(await SpotifyService.instance.searchTracks(q, limit: limit - suggestions.length)); } catch (_) {}
      }
      if (token != _searchToken) return;
      if (ProviderService.instance.shouldQueryAppleMusic && suggestions.length < limit) {
        try { suggestions.addAll(await MusicDiscoveryService.instance.search('apple', q, limit: limit - suggestions.length)); } catch (_) {}
      }
      if (token != _searchToken) return;
      if (ProviderService.instance.shouldQueryDeezer && suggestions.length < limit) {
        try { suggestions.addAll(await MusicDiscoveryService.instance.search('deezer', q, limit: limit - suggestions.length)); } catch (_) {}
      }
      if (token != _searchToken) return;
      if (ProviderService.instance.shouldQueryInternetArchive && suggestions.length < limit) {
        try { suggestions.addAll(await InternetArchiveCatalogService.instance.search(q, limit: limit - suggestions.length)); } catch (_) {}
      }
      if (token != _searchToken) return;
      onResults(suggestions.take(limit).toList());
    });
  }

  /// Simple merge that prefers earlier lists and skips obvious duplicates.
  List<Map<String, dynamic>> _mergeResults(
    List<List<Map<String, dynamic>>> groups,
  ) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];

    String key(Map<String, dynamic> s) {
      final title = (s['title'] ?? '').toString().toLowerCase().trim();
      final artist = (s['artist'] ?? '').toString().toLowerCase().trim();
      return '$title|$artist';
    }

    for (final group in groups) {
      for (final s in group) {
        final k = key(s);
        if (k == '|' || seen.contains(k)) continue;
        seen.add(k);
        out.add(s);
      }
    }
    return out;
  }
}

/// Result of a unified search.
class UnifiedSearchResult {
  final String query;
  final List<Map<String, dynamic>> all;
  final List<Map<String, dynamic>> supabase;
  final List<Map<String, dynamic>> youtube;
  final List<Map<String, dynamic>> remote;

  const UnifiedSearchResult({
    required this.query,
    required this.all,
    required this.supabase,
    required this.youtube,
    required this.remote,
  });

  factory UnifiedSearchResult.empty(String query) => UnifiedSearchResult(
        query: query,
        all: const [],
        supabase: const [],
        youtube: const [],
        remote: const [],
      );

  bool get isEmpty => all.isEmpty;
  bool get isNotEmpty => all.isNotEmpty;
}
