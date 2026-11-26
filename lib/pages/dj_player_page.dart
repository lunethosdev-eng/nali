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
  bool _showSettings = false;
  bool _liked = false;
  bool _lyricsOpen = false;
  String? _lyrics;
  double _balance = 0.5;
  bool _genreFocus = false;
  Color _blobColor = const Color(0xFF5CE1C5);

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
    if (mounted) setState(() {});
    // Voice first — before queue build
    await dj.welcome();
    await Future.delayed(const Duration(milliseconds: 400));
    await _buildAndPlay();
  }

  Future<void> _buildAndPlay() async {
    if (!mounted) return;
    setState(() => _building = true);
    await DjService.instance.onBuilding();
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
        await PlayerController.instance
            .playPlaylist(songs.take(take).toList(), startIndex: 0);
      }
    } finally {
      if (mounted) setState(() => _building = false);
    }
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
        final title =
            (song?['title'] ?? t('MAI al habla…', 'MAI speaking…')).toString();
        final artist =
            (song?['artist'] ?? 'MAI Radio').toString();
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
                            'MAI RADIO',
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
                      child: hasTrack && cover != null && cover.isNotEmpty
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
                                  speak: speaking ? _speakPulse.value : 0,
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
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3.5,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 16),
                              activeTrackColor: _blobColor,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: progress,
                              onChanged: (v) {
                                pc.seekTo(Duration(
                                    milliseconds:
                                        (v * dur.inMilliseconds).round()));
                              },
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              children: [
                                Text(_fmt(pos),
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 11)),
                                const Spacer(),
                                Text(_fmt(dur),
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 11)),
                              ],
                            ),
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
    return Container(
      color: Colors.black.withOpacity(0.92),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() {
                    _lyricsOpen = false;
                    _lyrics = null;
                  }),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            Expanded(
              child: _lyrics == null
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white54))
                  : _lyrics!.isEmpty
                      ? Center(
                          child: Text(
                            t('Sin letras', 'No lyrics'),
                            style: const TextStyle(color: Colors.white54),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _lyrics!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              height: 1.7,
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsSheet() {
    final weights = DjService.instance.blockWeights;
    final colors = <int>[
      0xFF5CE1C5,
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
              color: const Color(0xFF142038),
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
                  t('Configuración MAI Radio', 'MAI Radio settings'),
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
    final r = size.shortestSide * (0.34 + pulse * 0.03 + speak * 0.05);
    final path = Path();
    const n = 72;
    for (var i = 0; i <= n; i++) {
      final a = (i / n) * math.pi * 2;
      final wobble = 1 +
          0.14 * math.sin(a * 3 + t * math.pi * 2) +
          0.09 * math.cos(a * 5 - t * math.pi * 2 * 1.3) +
          speak * 0.06 * math.sin(a * 7 + t * 8);
      final p = Offset(
        c.dx + math.cos(a) * r * wobble,
        c.dy + math.sin(a) * r * wobble,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(color, Colors.white, 0.15 + speak * 0.1)!,
          color.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r * 1.7));
    canvas.drawPath(path, paint);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = Colors.white.withOpacity(0.35 + pulse * 0.2 + speak * 0.15);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DjBlobPainter old) =>
      old.t != t ||
      old.pulse != pulse ||
      old.speak != speak ||
      old.color != color;
}
