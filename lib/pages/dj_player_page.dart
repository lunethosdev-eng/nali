import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nali/services/dj_service.dart';
import 'package:nali/services/player_controller.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/services/supabase_service.dart';
import 'package:nali/services/follow_service.dart';

/// Dedicated DJ radio UI (MAI-style blob + voice overlays).
class DjPlayerPage extends StatefulWidget {
  const DjPlayerPage({super.key});

  @override
  State<DjPlayerPage> createState() => _DjPlayerPageState();
}

class _DjPlayerPageState extends State<DjPlayerPage>
    with TickerProviderStateMixin {
  late final AnimationController _blob;
  late final AnimationController _pulse;
  bool _building = false;
  bool _showSettings = false;
  double _balance = 0.5;
  bool _genreFocus = false;

  String t(String es, String en) =>
      SettingsService.instance.locale == 'en' ? en : es;

  @override
  void initState() {
    super.initState();
    _blob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _boot();
  }

  Future<void> _boot() async {
    final dj = DjService.instance;
    await dj.init();
    await dj.setEnabled(true);
    _balance = dj.balance;
    _genreFocus = dj.genreFocus;
    setState(() {});
    await dj.welcome();
    await _buildAndPlay();
  }

  Future<void> _buildAndPlay() async {
    setState(() => _building = true);
    await DjService.instance.onBuilding();
    try {
      final weights = DjService.instance.blockWeights;
      final songs = <Map<String, dynamic>>[];
      // Favorites / recent from ukiyo
      try {
        final recent = await SupabaseService.ukiyo
            .from('songs')
            .select()
            .order('created_at', ascending: false)
            .limit(40);
        songs.addAll(List<Map<String, dynamic>>.from(recent));
      } catch (_) {}
      if (songs.isEmpty) {
        // Fall back to whatever is in the player queue
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pc = PlayerController.instance;
    return AnimatedBuilder(
      animation: pc,
      builder: (context, _) {
        final song = pc.currentSong;
        final hasTrack = song != null;
        final title = (song?['title'] ?? 'MAI al habla…').toString();
        final artist = (song?['artist'] ?? 'MAI Radio').toString();
        final cover = (song?['cover_url'] ?? song?['animated_cover_url'])
            ?.toString();
        final pos = pc.position;
        final dur = pc.duration.inMilliseconds > 0
            ? pc.duration
            : const Duration(seconds: 1);
        final progress =
            (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);

        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Ambient gradient
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF1A3A6E),
                      const Color(0xFF0D2244),
                      const Color(0xFF071428),
                    ],
                  ),
                ),
              ),
              // Soft blurred cover behind
              if (cover != null && cover.isNotEmpty)
                Opacity(
                  opacity: 0.25,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Image.network(cover, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                ),
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(flex: 2),
                    // Blob or cover
                    SizedBox(
                      height: 220,
                      width: 220,
                      child: hasTrack && cover != null && cover.isNotEmpty
                          ? _CoverOrb(url: cover, pulse: _pulse)
                          : AnimatedBuilder(
                              animation: Listenable.merge([_blob, _pulse]),
                              builder: (_, __) => CustomPaint(
                                painter: _DjBlobPainter(
                                  t: _blob.value,
                                  pulse: _pulse.value,
                                ),
                              ),
                            ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Row(
                        children: [
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
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  artist,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.65),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _roundIcon(Icons.tune_rounded, () {
                            setState(() => _showSettings = true);
                          }),
                          const SizedBox(width: 8),
                          _roundIcon(Icons.more_horiz_rounded, () {
                            _showMore();
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14),
                              activeTrackColor: const Color(0xFF5CE1C5),
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: progress,
                              onChanged: (v) {
                                pc.seek(Duration(
                                    milliseconds:
                                        (v * dur.inMilliseconds).round()));
                              },
                            ),
                          ),
                          Row(
                            children: [
                              Text(_fmt(pos),
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                              const Spacer(),
                              Text('MAI RADIO',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.35),
                                      fontSize: 11,
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.w600)),
                              const Spacer(),
                              Text(_fmt(dur),
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 36,
                          color: Colors.white,
                          onPressed: () async {
                            await DjService.instance.onSkip();
                            await pc.playPreviousInQueue();
                          },
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () async {
                            if (pc.isPlaying) {
                              await DjService.instance.onPause();
                              await pc.pause();
                            } else {
                              await pc.resume();
                            }
                          },
                          child: Container(
                            width: 72,
                            height: 72,
                            alignment: Alignment.center,
                            child: _building
                                ? const SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 3,
                                    ),
                                  )
                                : Icon(
                                    pc.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 56,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          iconSize: 36,
                          color: Colors.white,
                          onPressed: () async {
                            await DjService.instance.onSkip();
                            await pc.playNextInQueue();
                          },
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (hasTrack)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            color: Colors.white70,
                            onPressed: () {},
                            icon: const Icon(Icons.favorite_border_rounded),
                          ),
                          IconButton(
                            color: Colors.white70,
                            onPressed: () {},
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                          ),
                          IconButton(
                            color: Colors.white70,
                            onPressed: () {},
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      )
                    else
                      IconButton(
                        color: Colors.white38,
                        onPressed: () {},
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              if (_showSettings) _settingsSheet(),
            ],
          ),
        );
      },
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withOpacity(0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  void _showMore() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.tune_rounded, color: Colors.white),
              title: Text(t('Ajustes', 'Settings'),
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _showSettings = true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded, color: Colors.white),
              title: Text(t('Reconstruir radio', 'Rebuild radio'),
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _buildAndPlay();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsSheet() {
    final weights = DjService.instance.blockWeights;
    return GestureDetector(
      onTap: () => setState(() => _showSettings = false),
      child: Container(
        color: Colors.black54,
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: BoxDecoration(
              color: const Color(0xFF1B3A6E),
              borderRadius: BorderRadius.circular(22),
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Text(t('Tipo de música', 'Music type'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                Text(
                  _balance < 0.35
                      ? t('Más música conocida', 'More familiar music')
                      : _balance > 0.65
                          ? t('Descubrir nueva música', 'Discover new music')
                          : t('Balance equilibrado', 'Balanced'),
                  style: TextStyle(color: Colors.white.withOpacity(0.55)),
                ),
                Row(
                  children: [
                    Icon(Icons.favorite_border,
                        size: 16, color: Colors.white.withOpacity(0.5)),
                    Expanded(
                      child: Slider(
                        value: _balance,
                        activeColor: const Color(0xFF5CE1C5),
                        onChanged: (v) {
                          setState(() => _balance = v);
                          DjService.instance.setBalance(v);
                        },
                      ),
                    ),
                    Icon(Icons.explore_outlined,
                        size: 16, color: Colors.white.withOpacity(0.5)),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${t('Distribución de bloques', 'Block distribution')}:\n'
                    'Top canciones: ${weights['tops']}%\n'
                    'Canciones favoritas: ${weights['favorites']}%\n'
                    'Descubrimiento: ${weights['discovery']}%',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.75), height: 1.4),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('Exploración por géneros', 'Genre exploration'),
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(
                    t(
                      'Enfoca MAI en tus géneros favoritos en lugar de tus artistas más escuchados.',
                      'Focus MAI on favorite genres instead of most-played artists.',
                    ),
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                  value: _genreFocus,
                  activeColor: const Color(0xFF5CE1C5),
                  onChanged: (v) {
                    setState(() => _genreFocus = v);
                    DjService.instance.setGenreFocus(v);
                  },
                ),
                const SizedBox(height: 12),
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
                        child: Text(t('Cancelar', 'Cancel')),
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
                          backgroundColor: const Color(0xFF5CE1C5),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(t('Aplicar', 'Apply'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
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
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _CoverOrb extends StatelessWidget {
  const _CoverOrb({required this.url, required this.pulse});
  final String url;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) {
        final glow = 0.35 + pulse.value * 0.25;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5CE1C5).withOpacity(glow * 0.5),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
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
  _DjBlobPainter({required this.t, required this.pulse});
  final double t;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * (0.34 + pulse * 0.03);
    final path = Path();
    const n = 64;
    for (var i = 0; i <= n; i++) {
      final a = (i / n) * math.pi * 2;
      final wobble = 1 +
          0.12 * math.sin(a * 3 + t * math.pi * 2) +
          0.08 * math.cos(a * 5 - t * math.pi * 2 * 1.3);
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
          Color.lerp(const Color(0xFF4FE0C0), const Color(0xFF3BA7E8), pulse)!,
          const Color(0xFF1A6BB5).withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r * 1.6));
    canvas.drawPath(path, paint);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white.withOpacity(0.35 + pulse * 0.2);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DjBlobPainter old) =>
      old.t != t || old.pulse != pulse;
}
