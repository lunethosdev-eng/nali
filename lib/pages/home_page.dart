import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nali/widgets/compact_header.dart';
import 'package:nali/services/supabase_service.dart';
import 'package:nali/services/listening_history.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/services/follow_service.dart';
import 'package:nali/services/player_controller.dart';
import 'package:nali/services/notification_service.dart';
import 'package:nali/services/unified_search_service.dart';
import 'package:nali/services/provider_service.dart';
import 'package:nali/services/custom_provider_service.dart';
import 'package:nali/services/native_player_bridge.dart';

class HomePage extends StatefulWidget {
  HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scrollCtrl = ScrollController();
  bool _collapsed = false;
  List<Map<String, dynamic>> _forYou = [];
  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _discover = [];
  List<Map<String, dynamic>> _trending = [];
  List<Map<String, dynamic>> _recent = [];
  List<Map<String, dynamic>> _popular = [];
  List<Map<String, dynamic>> _followedArtists = [];
  bool _loading = true;
  String? _loadError;

  String t(String es, String en) =>
      SettingsService.instance.locale == 'en' ? en : es;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      final c = _scrollCtrl.offset > 48;
      if (c != _collapsed) setState(() => _collapsed = c);
    });
    _load();
    NotificationService.instance.load();
    NotificationService.instance.refreshFromFollows();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _loadError = null; });

    // Paint the exact same source Browse uses before awaiting history, follows,
    // or analytics. Optional endpoints must never keep a valid catalog hidden.
    List<Map<String, dynamic>> all;
    try {
      all = await SupabaseService.getSongs(limit: 100)
          .timeout(const Duration(seconds: 12));
    } catch (error) {
      if (!mounted) return;
      setState(() { _loadError = error.toString(); _loading = false; });
      return;
    }
    if (!mounted) return;
    setState(() {
      _catalog = all;
      _forYou = [];
      _loading = false;
    });

    // Home also samples the providers explicitly enabled by the user.
    // Keep the primary Supabase catalog visible even if a remote source is slow.
    final providers = ProviderService.instance;
    await CustomProviderService.instance.load();
    if (providers.youtubeMusicEnabled || providers.soundCloudEnabled ||
        providers.spotifyEnabled || providers.appleMusicEnabled || providers.deezerEnabled ||
        CustomProviderService.instance.hasMusicProviders) {
      try {
        final discovery = await UnifiedSearchService.instance.search('popular songs', limitPerProvider: 16)
            .timeout(const Duration(seconds: 28));
        if (mounted) setState(() => _discover = _dedup(discovery.all.where((s) =>
          (s['provider'] ?? s['source'] ?? 'supabase').toString() != 'supabase').toList()));
      } catch (e) { debugPrint('Home provider discovery: $e'); }
    } else if (mounted) {
      setState(() => _discover = []);
    }

    // These enrichments are deliberately isolated and bounded. A missing RLS
    // policy, empty history, or slow analytics query cannot blank the Home.
    List<Map<String, dynamic>> history = [];
    List<String> topArtists = [];
    List<Map<String, dynamic>> followed = [];
    try { history = await ListeningHistory.instance.recent(limit: 24).timeout(const Duration(seconds: 5)); } catch (_) {}
    try { topArtists = await ListeningHistory.instance.topArtistNames(limit: 10).timeout(const Duration(seconds: 5)); } catch (_) {}
    try { followed = await FollowService.list().timeout(const Duration(seconds: 5)); } catch (_) {}

    List<Map<String, dynamic>> forYou = [];
    if (topArtists.isNotEmpty) {
      for (final artist in topArtists.take(4)) {
        forYou.addAll(all.where((song) =>
          (song['artist'] ?? '').toString().toLowerCase().contains(artist.toLowerCase())));
      }
    }
    forYou = _dedup(forYou);

    final allTimeCounts = <String, int>{};
    final dailyCounts = <String, int>{};
    try {
      final rows = await SupabaseService.kokoro.from('song_plays')
          .select('song_id, created_at')
          .order('created_at', ascending: false).limit(1200)
          .timeout(const Duration(seconds: 4));
      final since = DateTime.now().subtract(const Duration(days: 1));
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final id = (row['song_id'] ?? '').toString();
        if (id.isEmpty) continue;
        allTimeCounts[id] = (allTimeCounts[id] ?? 0) + 1;
        final created = DateTime.tryParse((row['created_at'] ?? '').toString());
        if (created != null && created.isAfter(since)) dailyCounts[id] = (dailyCounts[id] ?? 0) + 1;
      }
    } catch (_) {}

    List<Map<String, dynamic>> sortByCount(Map<String, int> counts) {
      final rows = List<Map<String, dynamic>>.from(all);
      rows.sort((a, b) => (counts[(b['id'] ?? '').toString()] ?? 0)
          .compareTo(counts[(a['id'] ?? '').toString()] ?? 0));
      return rows.where((song) => (counts[(song['id'] ?? '').toString()] ?? 0) > 0).toList();
    }

    if (!mounted) return;
    setState(() {
      _catalog = all;
      _forYou = forYou;
      _trending = sortByCount(allTimeCounts);
      _recent = history;
      _popular = sortByCount(dailyCounts).take(30).toList();
      _followedArtists = followed;
    });
  }

  List<Map<String, dynamic>> _dedup(List<Map<String, dynamic>> list) {
    final seen = <String>{};
    return list.where((s) {
      final id = (s['id'] ?? s['title']).toString();
      if (seen.contains(id)) return false;
      seen.add(id);
      return true;
    }).toList();
  }

  Future<void> _play(Map<String, dynamic> song, List<Map<String, dynamic>> contextList) async {
    final provider = (song['provider'] ?? song['source'] ?? '').toString();
    final youtubeId = (song['youtube_id'] ?? '').toString();
    final audio = (song['audio_url'] ?? song['stream_url'] ?? '').toString();
    final permalink = (song['permalink_url'] ?? '').toString();
    // The browser cannot resolve YouTube's signed media stream. Open the
    // official YouTube Music track instead of opening a silent Flutter player.
    if (!NativePlayerBridge.instance.supported && provider == 'youtube_music' && youtubeId.isNotEmpty) {
      await launchUrl(Uri.https('music.youtube.com', '/watch', {'v': youtubeId}), mode: LaunchMode.externalApplication);
      return;
    }
    if (audio.isEmpty && permalink.startsWith('https://')) {
      await launchUrl(Uri.parse(permalink), mode: LaunchMode.externalApplication);
      return;
    }
    if (NativePlayerBridge.instance.supported) {
      // Resolve only the selected YouTube track before opening the Kotlin host;
      // extracting every search result first can delay the native player UI.
      await PlayerController.instance.playSong(song);
      return;
    }
    final idx = contextList.indexWhere(
        (s) => (s['id'] ?? s['title']) == (song['id'] ?? song['title']));
    await PlayerController.instance.playPlaylist(
      contextList.isEmpty ? [song] : contextList,
      startIndex: idx >= 0 ? idx : 0,
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Text(title,
          style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }

  Widget _songCard(Map<String, dynamic> s, List<Map<String, dynamic>> list) {
    final cover = s['cover_url'];
    return GestureDetector(
      onTap: () => _play(s, list),
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: cover != null
                  ? Image.network(cover.toString(),
                      width: 140, height: 140, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 140, height: 140, color: Colors.white12))
                  : Container(width: 140, height: 140, color: Colors.white12),
            ),
            const SizedBox(height: 8),
            Text(s['title'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            Text(s['artist'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _hList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: list.length.clamp(0, 24),
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _songCard(list[i], list),
      ),
    );
  }


  Widget _homeEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 54, 18, 40),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xff292126), Color(0xff151518)],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.graphic_eq_rounded, color: Color(0xfffc3c44), size: 30),
          const SizedBox(height: 18),
          Text(t('Tu música empieza aquí', 'Your music starts here'),
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            _loadError != null
              ? t('No se pudo cargar el catálogo. Comprueba tu conexión e inténtalo de nuevo.', 'The catalog could not be loaded. Check your connection and try again.')
              : t('Todavía no hay canciones para mostrar. Activa YouTube Music o SoundCloud en Ajustes, o vuelve cuando haya canciones en el catálogo de Nali.', 'There are no tracks to show yet. Enable YouTube Music or SoundCloud in Settings, or return when Nali has catalog tracks.'),
            style: TextStyle(color: Colors.white.withOpacity(0.58), height: 1.45, fontSize: 13),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(t('Actualizar Home', 'Refresh Home')),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final backgroundPath = SettingsService.instance.homeBackgroundPath;
        final hasBackground = !kIsWeb && backgroundPath != null && File(backgroundPath).existsSync();
        return Scaffold(
          backgroundColor: const Color(0xFF0C0C0E),
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (hasBackground) Image.file(File(backgroundPath!), fit: BoxFit.cover),
              if (hasBackground) const ColoredBox(color: Color(0x990C0C0E)),
              _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xfffc3c44)))
          : RefreshIndicator(
              color: const Color(0xfffc3c44),
              onRefresh: _load,
              child: CustomScrollView(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: CompactHeader(
                      collapsed: _collapsed,
                      title: t('Inicio', 'Home'),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_recent.isNotEmpty) ...[
                          _sectionTitle(t('Escuchado recientemente', 'Recently played')),
                          _hList(_recent),
                          const SizedBox(height: 22),
                        ],
                        if (_forYou.isNotEmpty) ...[
                          _sectionTitle(t('Para ti', 'Made for you')),
                          _hList(_forYou),
                          const SizedBox(height: 22),
                        ],
                        if (_popular.isNotEmpty) ...[
                          _sectionTitle(t('Más escuchadas', 'Most played')),
                          _hList(_popular),
                          const SizedBox(height: 22),
                        ],
                        if (_trending.isNotEmpty) ...[
                          _sectionTitle(t('Tendencias en Nali', 'Trending on Nali')),
                          _hList(_trending),
                          const SizedBox(height: 22),
                        ],
                        if (_discover.isNotEmpty) ...[
                          _sectionTitle(t('Descubre música', 'Discover music')),
                          _hList(_discover),
                          const SizedBox(height: 22),
                        ],
                        if (_catalog.isNotEmpty) ...[
                          _sectionTitle(t('Catálogo de Nali', 'Nali catalog')),
                          _hList(_catalog),
                          const SizedBox(height: 22),
                        ],
                        if (_catalog.isEmpty && _discover.isEmpty && _forYou.isEmpty && _recent.isEmpty && _trending.isEmpty)
                          _homeEmptyState(),
                        // Followed artists only
                        _sectionTitle(t('Artistas que sigues', 'Artists you follow')),
                        if (_followedArtists.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Text(
                              t(
                                'Sigue artistas desde el player para verlos aquí.',
                                'Follow artists from the player to see them here.',
                              ),
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.45),
                                  fontSize: 13),
                            ),
                          )
                        else
                          SizedBox(
                            height: 110,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              itemCount: _followedArtists.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 14),
                              itemBuilder: (_, i) {
                                final a = _followedArtists[i];
                                final img = a['artist_image'] ?? a['image_url'];
                                final name =
                                    (a['artist_name'] ?? a['name'] ?? '')
                                        .toString();
                                return Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 36,
                                      backgroundColor: Colors.white12,
                                      backgroundImage: img != null
                                          ? NetworkImage(img.toString())
                                          : null,
                                      child: img == null
                                          ? const Icon(Icons.person,
                                              color: Colors.white38)
                                          : null,
                                    ),
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      width: 72,
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 12),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        // Bottom padding for mini player + nav
                        const SizedBox(height: 140),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ],
          ),
        );
      },
    );
  }
}
