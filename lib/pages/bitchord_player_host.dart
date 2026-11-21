import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nali/services/lyrics_service.dart';
import 'package:nali/services/player_controller.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/widgets/karaoke_lyrics.dart';

/// Responsive Flutter host for the BitChord-style Now Playing surface on Web.
/// Android continues to use BitChordPlayerActivity; desktop Web uses the
/// dedicated desktop player instead of this phone/tablet presentation.
class BitChordPlayerHost extends StatefulWidget {
  const BitChordPlayerHost({super.key});

  @override
  State<BitChordPlayerHost> createState() => _BitChordPlayerHostState();
}

class _BitChordPlayerHostState extends State<BitChordPlayerHost>
    with TickerProviderStateMixin {
  String? _lyrics;
  String? _lyricsKey;
  bool _lyricsExpanded = false;
  bool _queueExpanded = false;
  late final AnimationController _enter = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 620),
  )..forward();

  String _key(Map<String, dynamic>? song) =>
      (song?['id'] ?? song?['title'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    PlayerController.instance.addListener(_syncLyrics);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        final pc = PlayerController.instance;
        if (_key(pc.current) != _key(args)) pc.playSong(args);
      }
      _syncLyrics();
    });
  }

  void _syncLyrics() {
    final song = PlayerController.instance.current;
    final key = _key(song);
    if (song == null || key.isEmpty || key == _lyricsKey) return;
    _lyricsKey = key;
    _lyrics = null;
    LyricsService.resolve(
      localText: song['lyrics_text']?.toString(),
      title: song['title']?.toString() ?? '',
      artist: song['artist']?.toString() ?? '',
      album: song['album']?.toString(),
      durationSeconds: (song['duration_seconds'] ?? song['duration']) is num
          ? ((song['duration_seconds'] ?? song['duration']) as num).round()
          : null,
    ).then((value) {
      if (!mounted || _lyricsKey != key) return;
      setState(() => _lyrics = value);
    });
  }

  @override
  void dispose() {
    PlayerController.instance.removeListener(_syncLyrics);
    _enter.dispose();
    super.dispose();
  }

  String _time(Duration value) =>
      '${value.inMinutes}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  Widget _cover(Map<String, dynamic> song, double size) {
    final url = (song['animated_cover_url'] ?? song['cover_url'] ?? song['artwork_url'])?.toString();
    return Hero(
      tag: 'player_cover_${song['cover_url'] ?? song['animated_cover_url'] ?? 'none'}',
      child: AnimatedScale(
        scale: PlayerController.instance.isPlaying ? 1.0 : 0.975,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeInOutCubic,
          width: size, height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.34), blurRadius: 34, offset: const Offset(0, 18))],
          ),
          clipBehavior: Clip.antiAlias,
          child: url != null && url.isNotEmpty
              ? Image.network(url, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _coverFallback())
              : _coverFallback(),
        ),
      ),
    );
  }

  Widget _coverFallback() => const ColoredBox(
    color: Color(0xff242428),
    child: Center(child: Icon(Icons.music_note_rounded, color: Colors.white38, size: 64)),
  );

  Widget _control({required IconData icon, required VoidCallback onTap,
      double size = 28, Color color = Colors.white70}) => IconButton(
    onPressed: onTap,
    icon: Icon(icon, size: size, color: color),
    splashRadius: 26,
  );

  Widget _playButton(PlayerController pc) => GestureDetector(
    onTap: pc.toggle,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 68, height: 68,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: Icon(pc.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        color: Colors.black, size: 38),
    ),
  );

  Widget _progress(PlayerController pc) {
    final duration = pc.duration.inMilliseconds > 0 ? pc.duration : const Duration(seconds: 1);
    final max = duration.inMilliseconds.toDouble();
    final value = pc.position.inMilliseconds.toDouble().clamp(0, max);
    return Column(children: [
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white24,
          thumbColor: Colors.white,
          trackHeight: 3,
          overlayColor: Colors.white12,
        ),
        child: Slider(value: value, max: max, onChanged: (v) => pc.seekTo(Duration(milliseconds: v.round()))),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_time(pc.position), style: const TextStyle(color: Colors.white54, fontSize: 11)),
          Text(_time(pc.duration), style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      ),
    ]);
  }

  Widget _transport(PlayerController pc) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _control(icon: pc.shuffleMode ? Icons.shuffle_rounded : Icons.shuffle_rounded,
        onTap: pc.toggleShuffle, color: pc.shuffleMode ? Colors.white : Colors.white54, size: 22),
      _control(icon: Icons.skip_previous_rounded, onTap: pc.playPreviousInQueue, size: 38),
      _playButton(pc),
      _control(icon: Icons.skip_next_rounded, onTap: pc.playNextInQueue, size: 38),
      _control(icon: pc.repeatMode == 2 ? Icons.repeat_one_rounded : Icons.repeat_rounded,
        onTap: pc.cycleRepeatMode, color: pc.repeatMode == 0 ? Colors.white54 : Colors.white, size: 22),
    ],
  );

  Widget _lyricsPanel(PlayerController pc, {required bool compact}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
      height: compact ? (_lyricsExpanded ? 300 : 174) : double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
          child: Row(children: [
            const Icon(Icons.lyrics_rounded, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('Letras', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            TextButton(
              onPressed: () => setState(() => _lyricsExpanded = !_lyricsExpanded),
              child: Text(_lyricsExpanded ? 'Ocultar' : 'Mostrar', style: const TextStyle(color: Colors.white70)),
            ),
          ]),
        ),
        Expanded(child: _lyrics == null
          ? const Center(child: Text('Buscando letras…', style: TextStyle(color: Colors.white38)))
          : KaraokeLyrics(lrcText: _lyrics, position: pc.position)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([PlayerController.instance, SettingsService.instance]),
      builder: (context, _) {
        final pc = PlayerController.instance;
        final song = pc.current;
        if (song == null) return const Scaffold(backgroundColor: Color(0xff09090b));
        final size = MediaQuery.sizeOf(context);
        final tablet = size.width >= 620;
        final wide = size.width >= 900;
        final coverSize = wide ? 340.0 : (tablet ? 300.0 : (size.width - 52).clamp(220.0, 360.0).toDouble());
        final cover = song['cover_url'] ?? song['animated_cover_url'];
        final background = cover?.toString();

        return Scaffold(
          backgroundColor: const Color(0xff09090b),
          body: Stack(fit: StackFit.expand, children: [
            if (background != null && background.isNotEmpty)
              Image.network(background, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            BackdropFilter(filter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
              child: ColoredBox(color: const Color(0xff09090b).withOpacity(0.78))),
            SafeArea(child: FadeTransition(
              opacity: CurvedAnimation(parent: _enter, curve: Curves.easeOut),
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, .035), end: Offset.zero)
                  .animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic)),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                    child: Row(children: [
                      IconButton(onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30)),
                      const Expanded(child: Column(children: [
                        Text('REPRODUCIENDO', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
                        Text('Ahora', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ])),
                      IconButton(onPressed: () => setState(() => _queueExpanded = !_queueExpanded),
                        icon: const Icon(Icons.queue_music_rounded, color: Colors.white70)),
                    ]),
                  ),
                  Expanded(child: tablet
                    ? Row(children: [
                        Expanded(child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 12, 18, 28),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            _cover(song, coverSize),
                            const SizedBox(height: 24),
                            _trackInfo(song),
                            const SizedBox(height: 18),
                            _progress(pc),
                            const SizedBox(height: 14),
                            _transport(pc),
                            if (_queueExpanded) _queuePanel(pc),
                          ]),
                        )),
                        if (wide || _lyricsExpanded)
                          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(8, 12, 22, 22),
                            child: _lyricsPanel(pc, compact: false))),
                      ])
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                        child: Column(children: [
                          const SizedBox(height: 10),
                          _cover(song, coverSize),
                          const SizedBox(height: 25),
                          _trackInfo(song),
                          const SizedBox(height: 18),
                          _progress(pc),
                          const SizedBox(height: 12),
                          _transport(pc),
                          const SizedBox(height: 20),
                          _lyricsPanel(pc, compact: true),
                          const SizedBox(height: 18),
                          if (_queueExpanded) _queuePanel(pc),
                        ]),
                      )),
                ]),
              ),
            )),
          ]),
        );
      },
    );
  }

  Widget _trackInfo(Map<String, dynamic> song) => Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(song['title']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 23, height: 1.08, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(song['artist']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white.withOpacity(.62), fontSize: 15)),
    ])),
    const SizedBox(width: 8),
  ]);

  Widget _queuePanel(PlayerController pc) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white.withOpacity(.06), borderRadius: BorderRadius.circular(18)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Siguiente en la cola', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      ...pc.queue.skip(pc.queueIndex + 1).take(8).map((item) => ListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        title: Text(item['title']?.toString() ?? '', style: const TextStyle(color: Colors.white)),
        subtitle: Text(item['artist']?.toString() ?? '', style: const TextStyle(color: Colors.white54)),
      )),
    ]),
  );
}
