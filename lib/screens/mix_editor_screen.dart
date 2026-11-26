import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/services/supabase_service.dart';

/// TikTok-style dual-waveform mix editor (A/B, playhead, crossfade curves).
class MixEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? initialA;
  final Map<String, dynamic>? initialB;

  const MixEditorScreen({super.key, this.initialA, this.initialB});

  @override
  State<MixEditorScreen> createState() => _MixEditorScreenState();
}

class _MixEditorScreenState extends State<MixEditorScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? trackA;
  Map<String, dynamic>? trackB;
  final AudioPlayer _playerA = AudioPlayer();
  final AudioPlayer _playerB = AudioPlayer();
  Duration _durA = const Duration(seconds: 180);
  Duration _durB = const Duration(seconds: 180);
  Duration _pos = Duration.zero;
  bool _playing = false;
  double _cutSec = 40;
  double _xfadeSec = 6;
  bool _bStarted = false;
  StreamSubscription? _posSub;

  /// Horizontal scroll/offset of each lane (0..1 of total view)
  double _offsetA = 0.0;
  double _offsetB = 0.18;
  String _stemModeA = 'full';
  String _stemModeB = 'full';
  double _muteFrom = 0;
  double _muteTo = 30;
  String _mixMode = 'crossfade'; // crossfade | dual
  int _bars = 16;
  late AnimationController _playheadPulse;

  // Seeded pseudo-waveforms (stable per track id)
  List<double> _waveA = [];
  List<double> _waveB = [];

  String t(String es, String en) =>
      SettingsService.instance.locale == 'en' ? en : es;

  @override
  void initState() {
    super.initState();
    _playheadPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    trackA = widget.initialA;
    trackB = widget.initialB;
    _regenWaves();
    _playerA.onDurationChanged.listen((d) {
      if (mounted) setState(() => _durA = d);
    });
    _playerB.onDurationChanged.listen((d) {
      if (mounted) setState(() => _durB = d);
    });
    _posSub = _playerA.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _pos = p);
      _tickCrossfade(p);
    });
    if (trackA != null) _prep(trackA!, true);
    if (trackB != null) _prep(trackB!, false);
  }

  void _regenWaves() {
    _waveA = _fakeWave(trackA?['id']?.toString() ?? 'a', 180);
    _waveB = _fakeWave(trackB?['id']?.toString() ?? 'b', 180);
  }

  List<double> _fakeWave(String seed, int n) {
    final r = math.Random(seed.hashCode);
    final out = <double>[];
    double v = 0.3;
    for (var i = 0; i < n; i++) {
      v += (r.nextDouble() - 0.5) * 0.35;
      v = v.clamp(0.08, 1.0);
      // Beat emphasis every ~4 bars of samples
      final beat = (i % 8 == 0) ? 0.25 : 0.0;
      out.add((v + beat).clamp(0.05, 1.0));
    }
    return out;
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _playheadPulse.dispose();
    _playerA.dispose();
    _playerB.dispose();
    super.dispose();
  }

  Future<void> _prep(Map<String, dynamic> song, bool isA) async {
    final url = (song['audio_url'] ?? song['stream_url'] ?? '').toString();
    if (url.isEmpty) return;
    try {
      final p = isA ? _playerA : _playerB;
      await p.setSourceUrl(url);
      final d = await p.getDuration();
      if (mounted && d != null) {
        setState(() {
          if (isA) {
            _durA = d;
            _cutSec = (d.inSeconds * 0.45).clamp(5, d.inSeconds - 5.0);
          } else {
            _durB = d;
          }
          _regenWaves();
        });
      }
    } catch (_) {}
  }

  void _tickCrossfade(Duration posA) {
    if (!_playing || trackB == null) return;
    if (_mixMode == 'dual') {
      _playerA.setVolume(0.85);
      _playerB.setVolume(0.85);
      if (!_bStarted) {
        _bStarted = true;
        final url =
            (trackB!['audio_url'] ?? trackB!['stream_url'] ?? '').toString();
        if (url.isNotEmpty) _playerB.play(UrlSource(url));
      }
      return;
    }
    final startMs = (_cutSec * 1000).round();
    final fadeMs = (_xfadeSec * 1000).round().clamp(300, 30000);
    if (posA.inMilliseconds < startMs) {
      _playerA.setVolume(1);
      _playerB.setVolume(0);
      return;
    }
    final elapsed = posA.inMilliseconds - startMs;
    final tNorm = (elapsed / fadeMs).clamp(0.0, 1.0);
    _playerA.setVolume(1.0 - tNorm);
    _playerB.setVolume(tNorm);
    if (!_bStarted) {
      _bStarted = true;
      final url =
          (trackB!['audio_url'] ?? trackB!['stream_url'] ?? '').toString();
      if (url.isNotEmpty) _playerB.play(UrlSource(url));
    }
  }

  Future<void> _togglePlay() async {
    HapticFeedback.selectionClick();
    if (_playing) {
      await _playerA.pause();
      await _playerB.pause();
      setState(() => _playing = false);
      return;
    }
    if (trackA == null) return;
    final urlA =
        (trackA!['audio_url'] ?? trackA!['stream_url'] ?? '').toString();
    if (urlA.isEmpty) return;
    _bStarted = false;
    await _playerA.play(UrlSource(urlA));
    if (_mixMode == 'dual' && trackB != null) {
      final urlB =
          (trackB!['audio_url'] ?? trackB!['stream_url'] ?? '').toString();
      if (urlB.isNotEmpty) {
        await _playerB.play(UrlSource(urlB));
        _bStarted = true;
      }
    }
    setState(() => _playing = true);
  }

  Future<void> _pickTrack(bool isA) async {
    try {
      final rows = await SupabaseService.ukiyo
          .from('songs')
          .select()
          .order('created_at', ascending: false)
          .limit(40);
      final list = List<Map<String, dynamic>>.from(rows);
      if (!mounted) return;
      final picked = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: const Color(0xFF121214),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final s = list[i];
              return ListTile(
                leading: _coverThumb(s, 40),
                title: Text((s['title'] ?? '').toString(),
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text((s['artist'] ?? '').toString(),
                    style: const TextStyle(color: Colors.white54)),
                onTap: () => Navigator.pop(ctx, s),
              );
            },
          ),
        ),
      );
      if (picked == null) return;
      setState(() {
        if (isA) {
          trackA = picked;
        } else {
          trackB = picked;
        }
        _regenWaves();
      });
      await _prep(picked, isA);
    } catch (e) {
      debugPrint('pick track: $e');
    }
  }

  Future<void> _save() async {
    // Persist mix intent in a simple payload (backend can expand later)
    final payload = {
      'a_id': trackA?['id'],
      'b_id': trackB?['id'],
      'cut_sec': _cutSec,
      'xfade_sec': _xfadeSec,
      'mix_mode': _mixMode,
      'stem_a': _stemModeA,
      'stem_b': _stemModeB,
      'mute_from': _muteFrom,
      'mute_to': _muteTo,
      'bars': _bars,
      'offset_a': _offsetA,
      'offset_b': _offsetB,
    };
    debugPrint('mix saved $payload');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('Mezcla guardada', 'Mix saved')),
        backgroundColor: const Color(0xfffc3c44),
      ),
    );
    Navigator.maybePop(context);
  }

  int _guessBpm(Map<String, dynamic>? song) {
    final v = song?['bpm'];
    if (v is num && v > 40 && v < 240) return v.round();
    // Stable pseudo from id
    final h = (song?['id'] ?? song?['title'] ?? 'x').toString().hashCode;
    return 90 + (h.abs() % 70);
  }

  String _keyLabel(Map<String, dynamic>? song, bool a) {
    final keys = ['1A', '2A', '3A', '4A', '5A', '6A', '7A', '8A', '9A', '10A', '11A', '12A',
      '1B', '2B', '3B', '4B', '5B', '6B', '7B', '8B', '9B', '10B', '11B', '12B'];
    final h = (song?['id'] ?? (a ? 'a' : 'b')).toString().hashCode.abs();
    return keys[h % keys.length];
  }

  @override
  Widget build(BuildContext context) {
    final bpmA = _guessBpm(trackA);
    final bpmB = _guessBpm(trackB);
    final totalSec = math.max(_durA.inSeconds, 1).toDouble();
    final progress = (_pos.inMilliseconds / (_durA.inMilliseconds.clamp(1, 1 << 30)))
        .clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                  ),
                  Expanded(
                    child: Text(
                      t('Editor de Mezcla', 'Mix Editor'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _togglePlay,
                    icon: Icon(
                      _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  TextButton(
                    onPressed: (trackA != null && trackB != null) ? _save : null,
                    child: Text(
                      t('Guardar', 'Save'),
                      style: TextStyle(
                        color: (trackA != null && trackB != null)
                            ? const Color(0xfffc3c44)
                            : Colors.white24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Track A header
            _trackHeader(
              isA: true,
              song: trackA,
              bpm: bpmA,
              keyLabel: _keyLabel(trackA, true),
              dur: _durA,
              onTap: () => _pickTrack(true),
            ),
            // Dual waveform canvas
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: LayoutBuilder(
                  builder: (context, box) {
                    return GestureDetector(
                      onHorizontalDragUpdate: (d) {
                        // Dragging moves both offsets slightly for alignment
                        setState(() {
                          _offsetB = (_offsetB + d.delta.dx / box.maxWidth)
                              .clamp(-0.2, 0.6);
                        });
                      },
                      onTapDown: (d) {
                        final x = d.localPosition.dx / box.maxWidth;
                        final sec = x * totalSec;
                        setState(() => _cutSec = sec.clamp(1, totalSec - 1));
                        _playerA.seek(Duration(milliseconds: (sec * 1000).round()));
                      },
                      child: AnimatedBuilder(
                        animation: _playheadPulse,
                        builder: (_, __) {
                          return CustomPaint(
                            size: Size(box.maxWidth, box.maxHeight),
                            painter: _DualWavePainter(
                              waveA: _waveA,
                              waveB: _waveB,
                              offsetA: _offsetA,
                              offsetB: _offsetB,
                              progress: progress,
                              cutRatio: (_cutSec / totalSec).clamp(0.0, 1.0),
                              xfadeRatio:
                                  (_xfadeSec / totalSec).clamp(0.02, 0.4),
                              pulse: _playheadPulse.value,
                              bars: _bars,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            // Bars chip
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    const opts = [8, 16, 32];
                    final i = opts.indexOf(_bars);
                    _bars = opts[(i + 1) % opts.length];
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_bars ${t('barras', 'bars')}',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ),
              ),
            ),
            // Track B header
            _trackHeader(
              isA: false,
              song: trackB,
              bpm: bpmB,
              keyLabel: _keyLabel(trackB, false),
              dur: _durB,
              onTap: () => _pickTrack(false),
            ),
            // Controls strip
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(t('Corte', 'Cut'),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _cutSec.clamp(1, totalSec - 1),
                          min: 1,
                          max: (totalSec - 1).clamp(2, 9999),
                          activeColor: const Color(0xFF4ADE80),
                          onChanged: (v) => setState(() => _cutSec = v),
                        ),
                      ),
                      Text('${_cutSec.toStringAsFixed(0)}s',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                  Row(
                    children: [
                      Text(t('Crossfade', 'Crossfade'),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _xfadeSec.clamp(0.5, 20),
                          min: 0.5,
                          max: 20,
                          activeColor: const Color(0xFF60A5FA),
                          onChanged: (v) => setState(() => _xfadeSec = v),
                        ),
                      ),
                      Text('${_xfadeSec.toStringAsFixed(1)}s',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _modeChip('crossfade', t('Crossfade', 'Crossfade')),
                      const SizedBox(width: 8),
                      _modeChip('dual', t('Ambas a la vez', 'Both at once')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(t('Voces / instrumental', 'Vocals / instrumental'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  const SizedBox(height: 6),
                  _stemRow(t('Pista A', 'Track A'), _stemModeA,
                      (v) => setState(() => _stemModeA = v)),
                  const SizedBox(height: 4),
                  _stemRow(t('Pista B', 'Track B'), _stemModeB,
                      (v) => setState(() => _stemModeB = v)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(String id, String label) {
    final on = _mixMode == id;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      selectedColor: const Color(0xfffc3c44),
      labelStyle:
          TextStyle(color: on ? Colors.white : Colors.white70, fontSize: 12),
      backgroundColor: Colors.white10,
      onSelected: (_) => setState(() => _mixMode = id),
    );
  }

  Widget _stemRow(String label, String mode, ValueChanged<String> onChanged) {
    Widget chip(String id, String text) {
      final on = mode == id;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(text, style: const TextStyle(fontSize: 11)),
          selected: on,
          selectedColor: const Color(0xfffc3c44),
          labelStyle: TextStyle(color: on ? Colors.white : Colors.white70),
          backgroundColor: Colors.white10,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onChanged(id),
        ),
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip('full', t('Completo', 'Full')),
                chip('no_voice', t('Sin voz', 'No voice')),
                chip('voice_only', t('Solo voz', 'Voice only')),
                chip('mute_range', t('Mute rango', 'Mute range')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _trackHeader({
    required bool isA,
    required Map<String, dynamic>? song,
    required int bpm,
    required String keyLabel,
    required Duration dur,
    required VoidCallback onTap,
  }) {
    final title = (song?['title'] ?? t('Toca para elegir', 'Tap to pick')).toString();
    final artist = (song?['artist'] ?? '').toString();
    final mins = dur.inMinutes;
    final secs = (dur.inSeconds % 60).toString().padLeft(2, '0');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            _coverThumb(song, 48),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  Text(artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    const Icon(Icons.arrow_upward, size: 12, color: Colors.white38),
                    Text('$bpm bpm',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                Text('$keyLabel  $mins:$secs',
                    style: TextStyle(
                        color: isA
                            ? const Color(0xFFE879F9)
                            : const Color(0xFF34D399),
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverThumb(Map<String, dynamic>? song, double size) {
    final url = (song?['cover_url'] ?? song?['animated_cover_url'] ?? '').toString();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFF1C1C22),
        child: url.isEmpty
            ? Icon(Icons.music_note, color: Colors.white24, size: size * 0.45)
            : Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.music_note, color: Colors.white24, size: size * 0.45)),
      ),
    );
  }
}

class _DualWavePainter extends CustomPainter {
  _DualWavePainter({
    required this.waveA,
    required this.waveB,
    required this.offsetA,
    required this.offsetB,
    required this.progress,
    required this.cutRatio,
    required this.xfadeRatio,
    required this.pulse,
    required this.bars,
  });

  final List<double> waveA;
  final List<double> waveB;
  final double offsetA;
  final double offsetB;
  final double progress;
  final double cutRatio;
  final double xfadeRatio;
  final double pulse;
  final int bars;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height * 0.5;
    final laneH = size.height * 0.38;

    // Background grid bars
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1;
    for (var i = 0; i <= bars; i++) {
      final x = size.width * (i / bars);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    // Wave A (top)
    _drawWave(
      canvas,
      size,
      waveA,
      offsetA,
      top: mid - laneH - 6,
      height: laneH,
      colorHi: const Color(0xFFFBBF24),
      colorLo: const Color(0xFF60A5FA),
    );

    // Wave B (bottom)
    _drawWave(
      canvas,
      size,
      waveB,
      offsetB,
      top: mid + 6,
      height: laneH,
      colorHi: const Color(0xFFFBBF24),
      colorLo: const Color(0xFF3B82F6),
    );

    // Crossfade region box + curves (blue like TikTok)
    final cutX = size.width * cutRatio;
    final fadeW = size.width * xfadeRatio;
    final fadeRect = Rect.fromLTWH(cutX, 8, fadeW, size.height - 16);
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF60A5FA).withOpacity(0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fadeRect, const Radius.circular(6)),
      boxPaint,
    );

    // Diagonal fade curves
    final curve = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF93C5FD);
    final p1 = Path()
      ..moveTo(cutX, mid - laneH)
      ..lineTo(cutX + fadeW, mid - 8);
    final p2 = Path()
      ..moveTo(cutX, mid + laneH)
      ..lineTo(cutX + fadeW, mid + 8);
    canvas.drawPath(p1, curve);
    canvas.drawPath(p2, curve);

    // Green playhead
    final playX = size.width * progress;
    final head = Paint()
      ..color = const Color(0xFF4ADE80)
      ..strokeWidth = 2.2;
    canvas.drawLine(Offset(playX, 0), Offset(playX, size.height), head);
    // Glow
    final glow = Paint()
      ..color = const Color(0xFF4ADE80).withOpacity(0.25 + pulse * 0.2)
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawLine(Offset(playX, 0), Offset(playX, size.height), glow);

    // Center play button shadow circle (visual only)
    final cx = size.width / 2;
    final cy = mid;
    canvas.drawCircle(
      Offset(cx, cy),
      18,
      Paint()..color = Colors.black.withOpacity(0.45),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white24,
    );
  }

  void _drawWave(
    Canvas canvas,
    Size size,
    List<double> wave,
    double offset, {
    required double top,
    required double height,
    required Color colorHi,
    required Color colorLo,
  }) {
    if (wave.isEmpty) return;
    final n = wave.length;
    final barW = size.width / n;
    final shift = offset * size.width;
    for (var i = 0; i < n; i++) {
      final x = i * barW + shift;
      if (x < -barW || x > size.width + barW) continue;
      final amp = wave[i] * height * 0.92;
      final cy = top + height / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barW * 0.5, cy),
          width: math.max(1.5, barW * 0.7),
          height: amp,
        ),
        const Radius.circular(1.5),
      );
      final t = i / n;
      final col = Color.lerp(colorHi, colorLo, t)!;
      canvas.drawRRect(rect, Paint()..color = col.withOpacity(0.9));
    }
  }

  @override
  bool shouldRepaint(covariant _DualWavePainter old) =>
      old.progress != progress ||
      old.cutRatio != cutRatio ||
      old.xfadeRatio != xfadeRatio ||
      old.offsetA != offsetA ||
      old.offsetB != offsetB ||
      old.pulse != pulse ||
      old.bars != bars;
}
