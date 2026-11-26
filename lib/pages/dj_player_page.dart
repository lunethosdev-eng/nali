import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nali/services/dj_service.dart';
import 'package:nali/services/player_controller.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/services/supabase_service.dart';
import 'package:nali/screens/playlist_detail_screen.dart';
import 'package:nali/widgets/karaoke_lyrics.dart';
import 'package:nali/services/lyrics_service.dart';

/// Full redesigned MAI Radio / DJ player with working actions + motion.
class DjPlayerPage extends StatefulWidget {
  const DjPlayerPage({super.key});

  @override
  State<DjPlayerPage> createState() => _DjPlayerPageState();
}

class _DjPlayerPageState extends State<DjPlayerPage>
    with TickerProviderStateMixin {
  late final AnimationController _blob;
  late final AnimationController _pulse;
  late final AnimationController _btnBounce;
  late final AnimationController _speakPulse;

  bool _building = false;
  bool _voicePhase = true; // showing blob, waiting for voice to end
  StreamSubscription? _voiceSub;
  bool _showSettings = false;
  bool _liked = false;
  bool _lyricsOpen = false;
  String? _lyrics;
  double _balance = 0.5;
  bool _genreFocus = false;
  Color _blobColor = const Color(0xfffc3c44);

  String t(String es, String en) =>
      SettingsService.instance.locale == 'en' ? en : es;

  @override
  void initState() {
    super.initState();
    _blob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _btnBounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _speakPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _boot();
  }

  Future<void> _boot() async {
    final dj = DjService.instance;
    await dj.init();
    await dj.setEnabled(true);
    _balance = dj.balance;
    _genreFocus = dj.genreFocus;
    _blobColor = Color(dj.blobColor);
    _voicePhase = true;
    if (mounted) setState(() {});

    // Listen once: when voice ends → crossfade into music
    _voiceSub?.cancel();
    _voiceSub = dj.onVoiceComplete.listen((event) {
      if (!mounted) return;
      if (event == DjService.eventWelcome || event == DjService.eventBuilding) {
        unawaited(_crossfadeIntoMusic());
      }
    });

    // Build queue silently (don't start audible play yet)
    await _prepareQueue();
    // Speak welcome — song waits until voice completes
    await dj.welcome();
  }

  Future<void> _prepareQueue() async {
    if (!mounted) return;
    setState(() => _building = true);
    try {
      final songs = <Map<String, dynamic>>[];
      try {
        final recent = await SupabaseService.ukiyo
            .from('songs')
            .select()
            .order('created_at', ascending: false)
            .limit(40);
        songs.addAll(List<Map<String, dynamic>>.from(recent));
      } catch (_) {}
      if (songs.isEmpty) {
        songs.addAll(PlayerController.instance.queue);
      }
      songs.shuffle();
      final take = math.min(25, songs.length);
      if (take > 0) {
        // Load into controller queue but keep music silent until voice ends
        final pc = PlayerController.instance;
        pc.queue = List<Map<String, dynamic>>.from(songs.take(take));
        pc.queueIndex = 0;
        // Mute music players while voice speaks
        try {
          await pc.pause();
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  /// After DJ voice ends: fade voice out (already ending) and ramp music in.
  Future<void> _crossfadeIntoMusic() async {
    if (!mounted) return;
    final dj = DjService.instance;
    final xfade = dj.voiceXfade; // 3–4s typical
    final pc = PlayerController.instance;
    if (pc.queue.isEmpty) {
      setState(() => _voicePhase = false);
      return;
    }
    setState(() {
      _voicePhase = false;
      _building = true;
    });
    try {
      // Start first track
      await pc.playPlaylist(pc.queue, startIndex: pc.queueIndex);
      // Soft volume ramp on music for voiceXfade seconds
      final steps = 16;
      final stepMs = (xfade * 1000 / steps).round().clamp(40, 400);
      for (var i = 1; i <= steps; i++) {
        if (!mounted) return;
        final tNorm = i / steps;
        // voice fades if still speaking
        await dj.setVoiceVolume(1.0 - tNorm);
        await Future.delayed(Duration(milliseconds: stepMs));
      }
      await dj.setVoiceVolume(0);
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  Future<void> _buildAndPlay() async {
    // Rebuild radio: voice "building" then music
    setState(() => _voicePhase = true);
    await DjService.instance.onBuilding();
    await _prepareQueue();
    // If building clip is short/missing, onVoiceComplete still fires
  }

  @override
  void dispose() {
    _blob.dispose();
    _pulse.dispose();
    _btnBounce.dispose();
    _speakPulse.dispose();
    super.dispose();
  }

  Future<void> _tapBounce(Future<void> Function() action) async {
    HapticFeedback.lightImpact();
    await _btnBounce.forward(from: 0);
    await _btnBounce.reverse();
    await action();
  }

  Future<void> _toggleLike() async {
    setState(() => _liked = !_liked);
    if (_liked) {
      await DjService.instance.onFavorite();
    }
  }

  Future<void> _openLyrics() async {
    final song = PlayerController.instance.currentSong;
    if (song == null) return;
    setState(() => _lyricsOpen = true);
    final text = await LyricsService.resolve(
      title: (song['title'] ?? '').toString(),
      artist: (song['artist'] ?? '').toString(),
    );
    if (mounted) setState(() => _lyrics = text ?? '');
  }

  void _addToPlaylist() {
    final song = PlayerController.instance.currentSong;
    if (song == null) return;
    PlaylistActions.showAddToPlaylistSheet(context, song: song);
  }

  void _showOverflow() {
    final song = PlayerController.instance.currentSong;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded, color: Colors.white70),
              title: Text(t('Compartir', 'Share'),
                  style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.radio_rounded, color: Colors.white70),
              title: Text(t('Reconstruir radio', 'Rebuild radio'),
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _buildAndPlay();
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded, color: Colors.white70),
              title: Text(t('Ajustes de radio', 'Radio settings'),
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _showSettings = true);
              },
            ),
            if (song != null)
              ListTile(
                leading: const Icon(Icons.person_outline, color: Colors.white70),
                title: Text(t('Ir al artista', 'Go to artist'),
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pushNamed(context, '/artist',
                      arguments: song['artist']);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pc = PlayerController.instance;
    return AnimatedBuilder(
      animation: pc,
      builder: (context, _) {
        final song = pc.currentSong;
        final hasTrack = song != null;
        final title = _voicePhase
            ? (SettingsService.instance.locale == 'en' ? (DjService.instance.displayName + ' speaking…') : (DjService.instance.displayName + ' al habla…'))
            : (song?['title'] ?? (SettingsService.instance.locale == 'en' ? (DjService.instance.displayName + ' speaking…') : (DjService.instance.displayName + ' al habla…'))).toString();
        final artist = _voicePhase
            ? DjService.instance.displayName
            : (song?['artist'] ?? DjService.instance.displayName).toString();
        final cover =
            (song?['cover_url'] ?? song?['animated_cover_url'])?.toString();
        final pos = pc.position;
        final dur = pc.duration.inMilliseconds > 0
            ? pc.duration
            : const Duration(seconds: 1);
        final progress =
            (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
        final speaking = DjService.instance.isSpeaking;

        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Ambient
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(const Color(0xFF0A1628), _blobColor, 0.12)!,
                      const Color(0xFF071018),
                      const Color(0xFF05080F),
                    ],
                  ),
                ),
              ),
              if (cover != null && cover.isNotEmpty)
                Opacity(
                  opacity: 0.22,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                    child: Image.network(cover, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                ),
              // Soft radial glow tied to blob color
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.35),
                      radius: 0.9,
                      colors: [
                        _blobColor.withOpacity(0.18 + _pulse.value * 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    // Grabber
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Row(
                        children: [
                          _bounceIcon(
                            Icons.keyboard_arrow_down_rounded,
                            () => Navigator.maybePop(context),
                          ),
                          const Spacer(),
                          Text(
                            DjService.instance.displayName.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.45),
                              fontSize: 11,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          _bounceIcon(Icons.tune_rounded, () {
                            setState(() => _showSettings = true);
                          }),
                          _bounceIcon(Icons.more_horiz_rounded, _showOverflow),
                        ],
                      ),
                    ),
                    const Spacer(flex: 2),
                    // Hero orb
                    SizedBox(
                      height: 240,
                      width: 240,
                      child: (!_voicePhase && hasTrack && cover != null && cover.isNotEmpty)
                          ? _CoverOrb(
                              url: cover,
                              pulse: _pulse,
                              speak: speaking ? _speakPulse : null,
                              color: _blobColor,
                            )
                          : AnimatedBuilder(
                              animation: Listenable.merge(
                                  [_blob, _pulse, _speakPulse]),
                              builder: (_, __) => CustomPaint(
                                painter: _DjBlobPainter(
                                  t: _blob.value,
                                  pulse: _pulse.value,
                                  speak: (speaking || _voicePhase) ? _speakPulse.value : 0,
                                  color: _blobColor,
                                ),
                              ),
                            ),
                    ),
                    const Spacer(),
                    // Title row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            artist,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Progress
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          // Custom glowing progress
                          LayoutBuilder(builder: (context, box) {
                            final w = box.maxWidth;
                            return GestureDetector(
                              onTapDown: _voicePhase
                                  ? null
                                  : (d) {
                                      final v = (d.localPosition.dx / w)
                                          .clamp(0.0, 1.0);
                                      pc.seekTo(Duration(
                                          milliseconds: (v *
                                                  dur.inMilliseconds)
                                              .round()));
                                    },
                              onHorizontalDragUpdate: _voicePhase
                                  ? null
                                  : (d) {
                                      final v = (d.localPosition.dx / w)
                                          .clamp(0.0, 1.0);
                                      pc.seekTo(Duration(
                                          milliseconds: (v *
                                                  dur.inMilliseconds)
                                              .round()));
                                    },
                              child: SizedBox(
                                height: 28,
                                child: Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    // Track
                                    Container(
                                      height: 6,
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        color: Colors.white.withOpacity(0.12),
                                      ),
                                    ),
                                    // Active fill with gradient glow
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 80),
                                      width: w *
                                          (_voicePhase ? 0 : progress),
                                      height: 6,
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        gradient: LinearGradient(
                                          colors: [
                                            _blobColor.withOpacity(0.55),
                                            _blobColor,
                                            Colors.white.withOpacity(0.9),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: _blobColor
                                                .withOpacity(0.55),
                                            blurRadius: 10,
                                            spreadRadius: 0.5,
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Thumb
                                    if (!_voicePhase)
                                      Positioned(
                                        left: (w * progress - 8)
                                            .clamp(0.0, w - 16),
                                        child: Container(
                                          width: 16,
                                          height: 16,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white,
                                            boxShadow: [
                                              BoxShadow(
                                                color: _blobColor
                                                    .withOpacity(0.6),
                                                blurRadius: 12,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                  _voicePhase ? '0:00' : _fmt(pos),
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                              const Spacer(),
                              Text(
                                  _voicePhase
                                      ? t('voz', 'voice')
                                      : _fmt(dur),
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Transport
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _transportBtn(
                          Icons.skip_previous_rounded,
                          40,
                          () => _tapBounce(() async {
                            await DjService.instance.onSkip();
                            await pc.playPreviousInQueue();
                          }),
                        ),
                        const SizedBox(width: 18),
                        GestureDetector(
                          onTap: () => _tapBounce(() async {
                            if (pc.isPlaying) {
                              await DjService.instance.onPause();
                              await pc.pause();
                            } else {
                              await pc.resume();
                            }
                          }),
                          child: AnimatedBuilder(
                            animation: _btnBounce,
                            builder: (_, child) {
                              final s = 1.0 -
                                  Curves.easeOut
                                          .transform(_btnBounce.value) *
                                      0.08;
                              return Transform.scale(scale: s, child: child);
                            },
                            child: Container(
                              width: 78,
                              height: 78,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: _blobColor.withOpacity(0.35),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: _building
                                  ? Padding(
                                      padding: const EdgeInsets.all(22),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: _blobColor,
                                      ),
                                    )
                                  : Icon(
                                      pc.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 40,
                                      color: const Color(0xFF0A1220),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        _transportBtn(
                          Icons.skip_next_rounded,
                          40,
                          () => _tapBounce(() async {
                            await DjService.instance.onSkip();
                            await pc.playNextInQueue();
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Action row: heart / lyrics / add
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _actionBtn(
                          icon: _liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: _liked ? const Color(0xfffc3c44) : Colors.white70,
                          onTap: () => _tapBounce(_toggleLike),
                        ),
                        const SizedBox(width: 28),
                        _actionBtn(
                          icon: Icons.lyrics_rounded,
                          color: Colors.white70,
                          onTap: () => _tapBounce(_openLyrics),
                        ),
                        const SizedBox(width: 28),
                        _actionBtn(
                          icon: Icons.playlist_add_rounded,
                          color: Colors.white70,
                          onTap: () => _tapBounce(() async {
                            _addToPlaylist();
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
              if (_lyricsOpen) _lyricsOverlay(title, artist),
              if (_showSettings) _settingsSheet(),
            ],
          ),
        );
      },
    );
  }

  Widget _bounceIcon(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  Widget _transportBtn(IconData icon, double size, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: Colors.white, size: size),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 26),
      ),
    );
  }

  Widget _lyricsOverlay(String title, String artist) {
    final reduce = SettingsService.instance.effectiveReduceAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 380),
      curve: const Cubic(0.22, 1.0, 0.36, 1.0),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 28),
          child: child,
        ),
      ),
      child: Material(
        color: const Color(0xEE0A0A0C),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => setState(() {
                        _lyricsOpen = false;
                        _lyrics = null;
                      }),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _lyrics == null
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white38))
                    : _lyrics!.isEmpty
                        ? Center(
                            child: Text(
                              t('Sin letras', 'No lyrics'),
                              style: const TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListenableBuilder(
                            listenable: PlayerController.instance,
                            builder: (_, __) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: KaraokeLyrics(
                                  lrcText: _lyrics,
                                  position: PlayerController.instance.position,
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsSheet() {
    final weights = DjService.instance.blockWeights;
    final colors = <int>[
      0xfffc3c44,
      0xFF7C5CFF,
      0xFFFC3C44,
      0xFFFFB347,
      0xFF4FC3F7,
      0xFFFF6BCB,
    ];
    return GestureDetector(
      onTap: () => setState(() => _showSettings = false),
      child: Container(
        color: Colors.black54,
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
            decoration: BoxDecoration(
              color: const Color(0xFF141418),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  t('Configuración', 'Settings'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                Text(t('Color del orb', 'Orb color'),
                    style: const TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final c in colors)
                      GestureDetector(
                        onTap: () async {
                          setState(() => _blobColor = Color(c));
                          await DjService.instance.setBlobColor(c);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _blobColor.value == c
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(c).withOpacity(0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(t('Tipo de música', 'Music type'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                Text(
                  _balance < 0.35
                      ? t('Más música conocida', 'More familiar')
                      : _balance > 0.65
                          ? t('Descubrir nueva', 'Discover new')
                          : t('Balance equilibrado', 'Balanced'),
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
                Slider(
                  value: _balance,
                  activeColor: _blobColor,
                  onChanged: (v) {
                    setState(() => _balance = v);
                    DjService.instance.setBalance(v);
                  },
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Tops ${weights['tops']}% · Favs ${weights['favorites']}% · Discover ${weights['discovery']}%',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7), fontSize: 13),
                  ),
                ),
                Text(t('Crossfade voz → canción', 'Voice → song crossfade'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                Text(
                  '${DjService.instance.voiceXfade.toStringAsFixed(1)}s',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
                Slider(
                  value: DjService.instance.voiceXfade,
                  min: 1.5,
                  max: 6.0,
                  divisions: 9,
                  activeColor: _blobColor,
                  onChanged: (v) async {
                    await DjService.instance.setVoiceXfade(v);
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('Por géneros', 'By genres'),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                  value: _genreFocus,
                  activeColor: _blobColor,
                  onChanged: (v) {
                    setState(() => _genreFocus = v);
                    DjService.instance.setGenreFocus(v);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            setState(() => _showSettings = false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(t('Cerrar', 'Close')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() => _showSettings = false);
                          _buildAndPlay();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blobColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(t('Aplicar', 'Apply'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _CoverOrb extends StatelessWidget {
  const _CoverOrb({
    required this.url,
    required this.pulse,
    required this.color,
    this.speak,
  });
  final String url;
  final Animation<double> pulse;
  final Animation<double>? speak;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([pulse, if (speak != null) speak!]),
      builder: (_, __) {
        final speakV = speak?.value ?? 0;
        final glow = 0.3 + pulse.value * 0.2 + speakV * 0.25;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(glow * 0.55),
                blurRadius: 32 + speakV * 12,
                spreadRadius: 2 + speakV * 4,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: const Color(0xFF1A3A6E))),
          ),
        );
      },
    );
  }
}

/// Perfect circle idle; concentric wave rings + spectrum bars while speaking.
class _DjBlobPainter extends CustomPainter {
  _DjBlobPainter({
    required this.t,
    required this.pulse,
    required this.speak,
    required this.color,
  });
  final double t;
  final double pulse;
  final double speak;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final base = size.shortestSide * 0.28;

    // Soft ambient glow
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withOpacity(0.45 + speak * 0.25),
          color.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: base * 2.4));
    canvas.drawCircle(c, base * 2.2, glow);

    // Core circle (always perfect)
    final coreR = base * (1.0 + pulse * 0.04 + speak * 0.08);
    final core = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(color, Colors.white, 0.22)!,
          color,
          color.withOpacity(0.55),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: coreR));
    canvas.drawCircle(c, coreR, core);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withOpacity(0.28 + pulse * 0.12);
    canvas.drawCircle(c, coreR, rim);

    if (speak <= 0.02) return;

    // Expanding wave rings while DJ speaks
    for (var i = 0; i < 4; i++) {
      final phase = (t * 1.4 + i * 0.22) % 1.0;
      final ringR = coreR + 12 + phase * (28 + i * 18);
      final alpha = (1.0 - phase) * speak * 0.45;
      canvas.drawCircle(
        c,
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 - i * 0.2
          ..color = color.withOpacity(alpha.clamp(0.0, 0.5)),
      );
    }

    // Spectrum bars around the circle
    const bars = 32;
    for (var i = 0; i < bars; i++) {
      final a = (i / bars) * math.pi * 2 - math.pi / 2;
      final amp = 0.35 +
          0.65 *
              (0.5 +
                  0.5 *
                      math.sin(t * math.pi * 2 * 3 + i * 0.7) *
                      math.cos(t * 5 + i * 0.3));
      final len = (10 + amp * 22 * speak);
      final inner = coreR + 6;
      final p0 = Offset(c.dx + math.cos(a) * inner, c.dy + math.sin(a) * inner);
      final p1 = Offset(
        c.dx + math.cos(a) * (inner + len),
        c.dy + math.sin(a) * (inner + len),
      );
      canvas.drawLine(
        p0,
        p1,
        Paint()
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(color, Colors.white, 0.25)!
              .withOpacity(0.35 + 0.5 * speak * amp),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DjBlobPainter old) =>
      old.t != t ||
      old.pulse != pulse ||
      old.speak != speak ||
      old.color != color;
}
