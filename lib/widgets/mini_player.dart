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
/// Android opens the original Kotlin/Compose BitChordPlayerActivity. Web and
/// desktop keep the native Flutter Nali player until the shared Compose UI has
/// a real JS/Wasm target; they do not use a visual imitation of PlayerHost.
class MiniPlayer extends StatefulWidget {
  final bool compact;

  const MiniPlayer({super.key, this.compact = false});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  double _dragDx = 0;
  double _dragDy = 0;
  /// 0 = cover-only circle, 1 = play/pause+next, 2 = + previous, -1 = title+artist strip
  int _compactLevel = 0;
  String? _lyricsText;
  String? _lyricsSongKey;

  @override
  void initState() {
    super.initState();
    PlayerController.instance.addListener(_onPlayerChanged);
    _loadMiniLyrics();
  }

  @override
  void didUpdateWidget(covariant MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset expansion when leaving compact mode.
    if (!widget.compact && _compactLevel != 0) {
      _compactLevel = 0;
    }
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
        debugPrint('Native BitChord open failed: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo abrir el reproductor Kotlin: $e'),
          ));
        }
        return;
      }
    }

    // Only Android can launch the original Kotlin/Compose BitChord surface.
    // Flutter Web must not pretend that a Dart imitation is the native PlayerHost.
    if (!context.mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 460),
        reverseTransitionDuration: const Duration(milliseconds: 360),
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
      animation: Listenable.merge([
        PlayerController.instance,
        SettingsService.instance,
      ]),
      builder: (context, _) {
        final pc = PlayerController.instance;
        final song = pc.current;
        final settings = SettingsService.instance;
        if (song == null ||
            !settings.showMiniPlayer ||
            !settings.flag('ui_mini_player', def: true)) {
          return const SizedBox.shrink();
        }

        final collapse = widget.compact && settings.miniPlayerCollapseOnScroll;
        final alignment = settings.miniPlayerCollapsedSide == 'left'
            ? Alignment.centerLeft
            : Alignment.centerRight;
        final cover = song['cover_url'] ?? song['animated_cover_url'];
        final height = settings.miniPlayerShowLyrics ? 70.0 : 58.0;
        final animationDuration = settings.effectiveReduceAnimations
            ? Duration.zero
            : const Duration(milliseconds: 680);
        final title = (song['title'] ?? '').toString();
        final artist = (song['artist'] ?? '').toString();

        return LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.of(context).size.width;

            // Compact expands VERTICALLY only (never horizontal control strip).
            //  0  = circle cover
            //  1  = cover + play/pause stacked above
            //  2  = + previous / next
            // -1  = title + artist strip above the circle
            double targetWidth;
            double targetHeight;
            if (!collapse) {
              targetWidth = (availableWidth - 32).clamp(58.0, 900.0).toDouble();
              targetHeight = height;
            } else if (_compactLevel < 0) {
              targetWidth = 64;
              targetHeight = 118;
            } else if (_compactLevel >= 2) {
              targetWidth = 64;
              targetHeight = 196;
            } else if (_compactLevel == 1) {
              targetWidth = 64;
              targetHeight = 132;
            } else {
              targetWidth = 58;
              targetHeight = 58;
            }

            final compactRadius = collapse
                ? (_compactLevel == 0 ? 29.0 : 22.0)
                : 16.0;

            return AnimatedAlign(
              alignment: collapse ? alignment : Alignment.center,
              duration: animationDuration,
              curve: const Cubic(0.22, 1.0, 0.36, 1.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AnimatedContainer(
                  duration: animationDuration,
                  curve: const Cubic(0.22, 1.0, 0.36, 1.0),
                  width: targetWidth,
                  height: targetHeight,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(compactRadius),
                  ),
                  child: GestureDetector(
                    onTap: () {
                      if (collapse && _compactLevel == 0) {
                        _openFull(context, song);
                      } else if (!collapse) {
                        _openFull(context, song);
                      } else {
                        PlayerController.instance.toggle();
                      }
                    },
                    onHorizontalDragUpdate: (details) {
                      if (collapse) return; // horizontal only in expanded mini
                      _dragDx += details.delta.dx;
                    },
                    onHorizontalDragEnd: (d) {
                      if (collapse) return;
                      _onHorizontalEnd(d);
                    },
                    onVerticalDragUpdate: (details) {
                      if (!collapse) return;
                      _dragDy += details.delta.dy;
                    },
                    onVerticalDragEnd: (details) {
                      if (!collapse) return;
                      final dy = _dragDy;
                      _dragDy = 0;
                      // Swipe UP → grow control stack; DOWN → title strip / collapse
                      if (dy < -16) {
                        setState(() {
                          if (_compactLevel < 0) {
                            _compactLevel = 0;
                          } else if (_compactLevel < 2) {
                            _compactLevel += 1;
                          }
                        });
                      } else if (dy > 16) {
                        setState(() {
                          if (_compactLevel > 0) {
                            _compactLevel -= 1;
                          } else if (_compactLevel == 0) {
                            _compactLevel = -1;
                          } else {
                            _compactLevel = 0;
                          }
                        });
                      }
                    },
                    child: LiquidGlass(
                      borderRadius: BorderRadius.circular(compactRadius),
                      child: collapse
                          ? _buildCompactBody(
                              pc: pc,
                              cover: cover,
                              title: title,
                              artist: artist,
                            )
                          : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: settings.effectiveReduceAnimations
                                  ? Duration.zero
                                  : const Duration(milliseconds: 620),
                              curve: Curves.easeInOutCubic,
                              width: 44.0,
                              height: 44.0,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: cover != null &&
                                      cover.toString().isNotEmpty
                                  ? Image.network(
                                      cover.toString(),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const ColoredBox(
                                        color: Colors.white12,
                                      ),
                                    )
                                  : const ColoredBox(
                                      color: Colors.white12,
                                      child: Icon(
                                        Icons.music_note_rounded,
                                        color: Colors.white38,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 10),
                              Expanded(
                                child: ClipRect(
                                  child: AnimatedOpacity(
                                    duration:
                                        settings.effectiveReduceAnimations
                                            ? Duration.zero
                                            : const Duration(milliseconds: 220),
                                    curve: Curves.easeInOut,
                                    opacity: 1,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          song['title']?.toString() ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          song['artist']?.toString() ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.58),
                                            fontSize: 11,
                                          ),
                                        ),
                                        if (settings.miniPlayerShowLyrics &&
                                            _lyricAt(pc.position) != null)
                                          Text(
                                            _lyricAt(pc.position)!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.72),
                                              fontSize: 10,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: pc.isPlaying ? 'Pause' : 'Play',
                                icon: Icon(
                                  pc.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 25,
                                ),
                                onPressed: pc.toggle,
                              ),
                              IconButton(
                                tooltip: 'Next',
                                icon: const Icon(
                                  Icons.skip_next_rounded,
                                  color: Colors.white70,
                                  size: 24,
                                ),
                                onPressed: pc.playNextInQueue,
                              ),
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
      },
    );
  }

  Widget _buildCompactBody({
    required PlayerController pc,
    required dynamic cover,
    required String title,
    required String artist,
  }) {
    final coverWidget = cover != null && cover.toString().isNotEmpty
        ? Image.network(
            cover.toString(),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Colors.white12,
              child: Icon(Icons.music_note_rounded, color: Colors.white38),
            ),
          )
        : const ColoredBox(
            color: Colors.white12,
            child: Icon(Icons.music_note_rounded, color: Colors.white38),
          );

    // Level 0: full-bleed circular cover
    if (_compactLevel == 0) {
      return ClipOval(child: coverWidget);
    }

    // Level -1: vertical stack — title/artist above a small cover
    if (_compactLevel < 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            ClipOval(
              child: SizedBox(width: 40, height: 40, child: coverWidget),
            ),
          ],
        ),
      );
    }

    // Level 1/2: VERTICAL control stack growing upward from the cover
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        children: [
          // Controls sit ABOVE the cover
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_compactLevel >= 2)
                  _CompactIconBtn(
                    icon: Icons.skip_previous_rounded,
                    onTap: pc.playPreviousInQueue,
                  ),
                _CompactIconBtn(
                  icon: pc.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onTap: pc.toggle,
                  emphasize: true,
                ),
                _CompactIconBtn(
                  icon: Icons.skip_next_rounded,
                  onTap: pc.playNextInQueue,
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          ClipOval(
            child: SizedBox(
              width: _compactLevel >= 2 ? 44 : 48,
              height: _compactLevel >= 2 ? 44 : 48,
              child: coverWidget,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool emphasize;
  const _CompactIconBtn({
    required this.icon,
    required this.onTap,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Icon(
            icon,
            color: emphasize ? Colors.white : Colors.white70,
            size: emphasize ? 26 : 22,
          ),
        ),
      ),
    );
  }
}
