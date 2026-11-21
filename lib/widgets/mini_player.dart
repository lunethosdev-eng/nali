import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nali/services/native_player_bridge.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/widgets/liquid_glass.dart';
import 'package:nali/services/player_controller.dart';
import 'package:nali/pages/music_player.dart';
import 'package:nali/services/lyrics_service.dart';

/// Thin floating mini player above the bottom nav.
///
/// Phase 1 rule (mandatory):
/// On Android the Mini Player MUST open the native BitChord player
/// (BitChordPlayerActivity → BitChordNowPlayingHost).
/// It must NOT open the Flutter Full Player (MusicPlayer).
class MiniPlayer extends StatefulWidget {
  final bool compact;

  const MiniPlayer({super.key, this.compact = false});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  double _dragDx = 0;
  String? _lyricsText;
  String? _lyricsSongKey;

  @override
  void initState() {
    super.initState();
    PlayerController.instance.addListener(_onPlayerChanged);
    _loadMiniLyrics();
  }

  @override
  void dispose() {
    PlayerController.instance.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() {
    final song = PlayerController.instance.current;
    final key = (song?['id'] ?? song?['title'] ?? '').toString();
    if (key.isNotEmpty && key != _lyricsSongKey) _loadMiniLyrics();
  }

  Future<void> _loadMiniLyrics() async {
    final song = PlayerController.instance.current;
    if (song == null) return;
    final key = (song['id'] ?? song['title'] ?? '').toString();
    _lyricsSongKey = key;
    if (mounted) setState(() => _lyricsText = null);
    final text = await LyricsService.resolve(
      localText: song['lyrics_text']?.toString(),
      title: song['title']?.toString() ?? '',
      artist: song['artist']?.toString() ?? '',
      album: song['album']?.toString(),
      durationSeconds: (song['duration'] is num) ? (song['duration'] as num).round() : null,
    );
    if (!mounted || _lyricsSongKey != key) return;
    setState(() => _lyricsText = text);
  }

  String? _lyricAt(Duration position) {
    final raw = _lyricsText;
    if (raw == null || raw.isEmpty) return null;
    final lines = <MapEntry<int, String>>[];
    final re = RegExp(r'^\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)$');
    for (final line in raw.split('\n')) {
      final m = re.firstMatch(line.trim());
      if (m == null) continue;
      final ms = (int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) * 1000 +
          int.parse((m.group(3) ?? '0').padRight(3, '0').substring(0, 3));
      lines.add(MapEntry(ms, m.group(4)!.trim()));
    }
    if (lines.isEmpty) return null;
    String? current;
    for (final line in lines) {
      if (line.key <= position.inMilliseconds) current = line.value;
      else break;
    }
    return current?.isEmpty == true ? null : current;
  }

  /// Opens the native BitChord player on Android.
  /// Falls back to Flutter MusicPlayer only on non-Android platforms
  /// or if the native call fails.
  Future<void> _openFull(BuildContext context, Map<String, dynamic> song) async {
    // ── Mandatory: prefer native BitChord on Android ────────────────
    if (NativePlayerBridge.instance.supported) {
      try {
        await NativePlayerBridge.instance.invoke('openNativePlayer');
        return; // Success → do not open Flutter player
      } catch (e) {
        debugPrint('Native BitChord open failed, falling back to Flutter: $e');
        // Only fall through to Flutter if native truly failed
      }
    }

    // Fallback (iOS / Web / native failure)
    if (!context.mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => MusicPlayer(),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(
              opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.0, 0.65),
                ),
              ),
              child: child,
            ),
          );
        },
        settings: RouteSettings(name: '/player', arguments: song),
      ),
    );
  }

  void _onHorizontalEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final pc = PlayerController.instance;
    // Swipe left (negative) → next; swipe right (positive) → previous
    if (v < -400 || _dragDx < -48) {
      HapticFeedback.selectionClick();
      pc.playNextInQueue();
    } else if (v > 400 || _dragDx > 48) {
      HapticFeedback.selectionClick();
      pc.playPreviousInQueue();
    }
    setState(() => _dragDx = 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([PlayerController.instance, SettingsService.instance]),
      builder: (context, _) {
        final pc = PlayerController.instance;
        if (pc.current == null) return const SizedBox.shrink();
        final settings = SettingsService.instance;
        if (!settings.showMiniPlayer ||
            !settings.flag('ui_mini_player', def: true)) {
          return const SizedBox.shrink();
        }

        final s = pc.current!;
        final cover = s['cover_url'];
        final compact = widget.compact;
        final h = compact ? 50.0 : (settings.miniPlayerShowLyrics ? 70.0 : 58.0);
        final coverSize = compact ? 38.0 : 44.0;

        if (compact && settings.miniPlayerCollapseOnScroll) {
          final side = settings.miniPlayerCollapsedSide == 'left'
              ? Alignment.centerLeft : Alignment.centerRight;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 340),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.84, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: Align(
              key: const ValueKey('mini-player-circle'),
              alignment: side,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AnimatedScale(
                scale: 1,
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutBack,
                child: GestureDetector(
                  onTap: () => _openFull(context, s),
                  onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
                  onHorizontalDragEnd: _onHorizontalEnd,
                  child: LiquidGlass(
                    borderRadius: BorderRadius.circular(30),
                    child: SizedBox(
                      width: 56, height: 56,
                      child: Stack(alignment: Alignment.center, children: [
                        ClipOval(child: cover != null && cover.toString().isNotEmpty
                          ? Image.network(cover.toString(), width: 48, height: 48, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.white12))
                          : const SizedBox(width: 48, height: 48, child: ColoredBox(color: Colors.white12))),
                        Positioned(right: 0, bottom: 0, child: Container(
                          width: 22, height: 22,
                          decoration: const BoxDecoration(color: Color(0xfffc3c44), shape: BoxShape.circle),
                          child: Icon(pc.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white, size: 15),
                        )),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          );
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 340),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: AnimatedContainer(
            key: const ValueKey('mini-player-bar'),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 14),
          child: GestureDetector(
            onTap: () => _openFull(context, s),
            onVerticalDragUpdate: (d) {
              // Optional: drag up to open player
            },
            onHorizontalDragUpdate: (d) {
              setState(() => _dragDx += d.delta.dx);
            },
            onHorizontalDragEnd: _onHorizontalEnd,
            child: LiquidGlass(
              borderRadius: BorderRadius.circular(compact ? 14 : 16),
              child: SizedBox(
                height: h,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: cover != null && cover.toString().isNotEmpty
                            ? Image.network(
                                cover.toString(),
                                width: coverSize,
                                height: coverSize,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: coverSize,
                                  height: coverSize,
                                  color: Colors.white12,
                                  child: const Icon(Icons.music_note,
                                      color: Colors.white38, size: 18),
                                ),
                              )
                            : Container(
                                width: coverSize,
                                height: coverSize,
                                color: Colors.white12,
                                child: const Icon(Icons.music_note,
                                    color: Colors.white38, size: 18),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s['title'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: compact ? 13 : 14,
                              ),
                            ),
                            Text(
                              s['artist'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: compact ? 11 : 12,
                              ),
                            ),
                            if (settings.miniPlayerShowLyrics && _lyricAt(pc.position) != null)
                              Text(
                                _lyricAt(pc.position)!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white.withOpacity(0.68), fontSize: 10),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          pc.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: compact ? 24 : 28,
                        ),
                        onPressed: pc.toggle,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.skip_next_rounded,
                          color: Colors.white70,
                          size: compact ? 22 : 26,
                        ),
                        onPressed: () => pc.playNextInQueue(),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}
