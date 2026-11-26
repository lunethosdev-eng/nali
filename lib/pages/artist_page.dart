import 'package:flutter/material.dart';
import 'package:nali/services/supabase_service.dart';
import 'package:nali/services/artist_image_service.dart';
import 'package:nali/services/follow_service.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/services/player_controller.dart';
import 'package:nali/services/nali_links.dart';
import 'package:nali/widgets/liquid_glass.dart';
import 'package:nali/widgets/context_menu.dart';

class ArtistPage extends StatefulWidget {
  ArtistPage({super.key});

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  String _name = '';
  String? _imageUrl;
  List<Map<String, dynamic>> _songs = [];
  bool _loading = true;
  bool _following = false;
  String? _bio;
  bool _bioExpanded = false;

  String t(String es, String en) =>
      SettingsService.instance.locale == 'en' ? en : es;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_name.isNotEmpty) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _name = (args['name'] ?? args['artist'] ?? '').toString();
      _imageUrl =
          args['image_url']?.toString() ?? args['artist_img']?.toString();
      _load();
    } else if (args is String) {
      _name = args;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final songs = await SupabaseService.ukiyo
          .from('songs')
          .select()
          .ilike('artist', _name)
          .order('created_at', ascending: false)
          .limit(80);
      _songs = List<Map<String, dynamic>>.from(songs);
      if (_songs.isEmpty && _name.isNotEmpty) {
        final all = await SupabaseService.ukiyo
            .from('songs')
            .select()
            .order('created_at', ascending: false)
            .limit(400);
        final q = _name.toLowerCase();
        _songs = List<Map<String, dynamic>>.from(all)
            .where((s) =>
                (s['artist'] ?? '').toString().toLowerCase().contains(q))
            .toList();
      }
      if ((_imageUrl == null || _imageUrl!.isEmpty) && _songs.isNotEmpty) {
        _imageUrl = _songs.first['cover_url']?.toString();
      }
      if (_imageUrl == null || _imageUrl!.isEmpty) {
        _imageUrl = await ArtistImageService.imageFor(_name);
      }
      _following = await FollowService.isFollowing(_name);
      try {
        final bioRes = await SupabaseService.kokoro.functions
            .invoke('artist-bio', body: {'artist': _name})
            .timeout(const Duration(seconds: 14));
        final payload = bioRes.data;
        if (payload is Map) {
          final text = (payload['bio'] ?? '').toString().trim();
          if (text.isNotEmpty) {
            _bio = text;
            final thumb = payload['thumbnail']?.toString();
            if ((_imageUrl == null || _imageUrl!.isEmpty) &&
                thumb != null &&
                thumb.startsWith('http')) {
              _imageUrl = thumb;
            }
          }
        }
      } catch (_) {}
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleFollow() async {
    final v = await FollowService.toggle(_name, imageUrl: _imageUrl);
    if (mounted) setState(() => _following = v);
  }

  Future<void> _playAll() async {
    if (_songs.isEmpty) return;
    await PlayerController.instance.playPlaylist(_songs, startIndex: 0);
  }

  Future<void> _playSong(int index) async {
    if (index < 0 || index >= _songs.length) return;
    await PlayerController.instance.playPlaylist(_songs, startIndex: index);
  }

  void _songMenu(Map<String, dynamic> song, int index) {
    showPokkeContextMenu(
      context: context,
      items: [
        ContextMenuItem(
          icon: Icons.play_arrow_rounded,
          label: t('Reproducir', 'Play'),
          onTap: () => _playSong(index),
        ),
        ContextMenuItem(
          icon: Icons.queue_music_rounded,
          label: t('Reproducir desde aquí', 'Play from here'),
          onTap: () => _playSong(index),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xfffc3c44)))
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  expandedHeight: 340,
                  pinned: true,
                  stretch: true,
                  backgroundColor: const Color(0xFF0A0A0C),
                  elevation: 0,
                  leading: Padding(
                    padding: const EdgeInsets.all(8),
                    child: LiquidGlass(
                      borderRadius: BorderRadius.circular(20),
                      blur: 18,
                      opacity: 0.18,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: LiquidGlass(
                        borderRadius: BorderRadius.circular(20),
                        blur: 18,
                        opacity: 0.18,
                        child: IconButton(
                          icon: const Icon(Icons.more_horiz_rounded,
                              color: Colors.white, size: 20),
                          onPressed: () {
                            showPokkeContextMenu(
                              context: context,
                              items: [
                                ContextMenuItem(
                                  icon: Icons.share_rounded,
                                  label: t(
                                      'Compartir artista', 'Share artist'),
                                  onTap: () {
                                    NaliLinks.share(
                                      _name,
                                      NaliLinks.artist(_name),
                                      description: t(
                                          'Escucha en Nali',
                                          'Listen on Nali'),
                                    );
                                  },
                                ),
                                ContextMenuItem(
                                  icon: _following
                                      ? Icons.person_remove_rounded
                                      : Icons.person_add_rounded,
                                  label: _following
                                      ? t('Dejar de seguir', 'Unfollow')
                                      : t('Seguir', 'Follow'),
                                  onTap: _toggleFollow,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    stretchModes: const [
                      StretchMode.zoomBackground,
                      StretchMode.blurBackground,
                    ],
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_imageUrl != null)
                          Image.network(
                            _imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: const Color(0xFF1A1A1E)),
                          )
                        else
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF2A1520),
                                  Color(0xFF0A0A0C)
                                ],
                              ),
                            ),
                          ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.0, 0.35, 0.7, 1.0],
                              colors: [
                                Colors.black.withOpacity(0.15),
                                Colors.black.withOpacity(0.35),
                                const Color(0xFF0A0A0C).withOpacity(0.92),
                                const Color(0xFF0A0A0C),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: -40,
                          bottom: 40,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  const Color(0xfffc3c44).withOpacity(0.28),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.35),
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.45),
                                      blurRadius: 24,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: _imageUrl != null
                                      ? Image.network(
                                          _imageUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const ColoredBox(
                                            color: Color(0xFF2A2A2E),
                                            child: Icon(Icons.person_rounded,
                                                color: Colors.white38,
                                                size: 40),
                                          ),
                                        )
                                      : const ColoredBox(
                                          color: Color(0xFF2A2A2E),
                                          child: Icon(Icons.person_rounded,
                                              color: Colors.white38,
                                              size: 40),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.6,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: _toggleFollow,
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 280),
                                      curve: Curves.easeOutCubic,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _following
                                            ? Colors.white.withOpacity(0.12)
                                            : const Color(0xfffc3c44),
                                        borderRadius:
                                            BorderRadius.circular(22),
                                        border: _following
                                            ? Border.all(
                                                color: Colors.white24)
                                            : null,
                                      ),
                                      child: Text(
                                        _following
                                            ? t('Siguiendo', 'Following')
                                            : t('Seguir', 'Follow'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${_songs.length} ${t('canciones', 'songs')}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.55),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_songs.isNotEmpty)
                                    GestureDetector(
                                      onTap: _playAll,
                                      child: Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.white
                                                  .withOpacity(0.25),
                                              blurRadius: 18,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.black,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_bio != null && _bio!.isNotEmpty)
                  consecutive(
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: LiquidGlass(
                          blur: 20,
                          opacity: 0.12,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => setState(
                                () => _bioExpanded = !_bioExpanded),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 14),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: Color(0xfffc3c44),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        t('Sobre el artista',
                                            'About the artist'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const Spacer(),
                                      Icon(
                                        _bioExpanded
                                            ? Icons.expand_less_rounded
                                            : Icons.expand_more_rounded,
                                        color: Colors.white38,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  AnimatedCrossFade(
                                    firstChild: Text(
                                      _bio!,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withOpacity(0.72),
                                        height: 1.45,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    secondChild: Text(
                                      _bio!,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withOpacity(0.78),
                                        height: 1.45,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    crossFadeState: _bioExpanded
                                        ? CrossFadeState.showSecond
                                        : CrossFadeState.showFirst,
                                    duration:
                                        const Duration(milliseconds: 240),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    t('Fuente: Wikipedia',
                                        'Source: Wikipedia'),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.32),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Text(
                      t('Canciones', 'Songs'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),

                if (_songs.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'Sin canciones de este artista',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
                    sliver: consecutive(
                      consecutive(
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) {
                              final s = _songs[i];
                              final cover = (s['cover_url'] ??
                                      s['animated_cover_url'] ??
                                      '')
                                  .toString();
                              final title =
                                  (s['title'] ?? 'Track').toString();
                              final album =
                                  (s['album'] ?? s['type'] ?? 'Single')
                                      .toString();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => _playSong(i),
                                    onLongPress: () => _songMenu(s, i),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 26,
                                            child: Text(
                                              '${i + 1}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withOpacity(0.35),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: SizedBox(
                                              width: 52,
                                              height: 52,
                                              child: cover.isNotEmpty
                                                  ? Image.network(
                                                      cover,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __,
                                                              ___) =>
                                                          const ColoredBox(
                                                        color: Color(
                                                            0xFF222226),
                                                        child: Icon(
                                                            Icons
                                                                .music_note_rounded,
                                                            color: Colors
                                                                .white24,
                                                            size: 22),
                                                      ),
                                                    )
                                                  : const ColoredBox(
                                                      color:
                                                          Color(0xFF222226),
                                                      child: Icon(
                                                          Icons
                                                              .music_note_rounded,
                                                          color:
                                                              Colors.white24,
                                                          size: 22),
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  album,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.45),
                                                    fontSize: 12.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.more_horiz_rounded,
                                              color: Colors.white
                                                  .withOpacity(0.4),
                                            ),
                                            onPressed: () =>
                                                _songMenu(s, i),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                            childCount: _songs.length,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

T consecutive<T>(T value) => value;


class _ScaleButton extends StatefulWidget {
  const _ScaleButton({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  State<_ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<_ScaleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _c.forward(),
      onTapUp: (_) async {
        await _c.reverse();
        widget.onTap();
      },
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final s = 1.0 - Curves.easeOut.transform(_c.value) * 0.08;
          return Transform.scale(scale: s, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
