import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:nali/pages/browse_page.dart';
import 'package:nali/pages/home_page.dart';
import 'package:nali/pages/library_page.dart';
import 'package:nali/pages/radio.dart';
import 'package:nali/pages/search_page.dart';
import 'package:nali/widgets/liquid_glass.dart';
import 'package:nali/widgets/mini_player.dart';
import 'package:nali/widgets/headphone_banner.dart';
import 'package:nali/services/headphone_service.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/services/player_controller.dart';
import 'package:nali/services/supabase_service.dart';

class FirstPage extends StatefulWidget {
  FirstPage({super.key});

  @override
  State<FirstPage> createState() => _FirstPageState();
}

class _FirstPageState extends State<FirstPage> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isDragging = false;
  int? _hoverIndex;
  double _dragX = 0;
  double _velocity = 0;
  double _prevX = 0;
  String? _headphoneDevice;
  late Future<Map<String, dynamic>?> _desktopProfileFuture;

  bool _navCollapsed = false;
  late AnimationController _collapseCtrl;
  late AnimationController _bubbleCtrl;
  late Animation<double> _bubbleScale;

  final List<Widget> _pages = [
    HomePage(),
    BrowsePage(),
    RadioPage(),
    LibraryPage(),
    SearchPage(),
  ];

  final List<IconData> _icons = [
    Icons.home_filled,
    Icons.grid_view_rounded,
    Icons.sensors,
    Icons.subscriptions_rounded,
    Icons.search,
  ];

  final List<String> _labels = ['Home', 'Browse', 'Radio', 'Library', 'Search'];

  static const _collapsedMain = [0, 3]; // Home, Library
  static const _searchIdx = 4;

  @override
  void initState() {
    super.initState();
    _desktopProfileFuture = SupabaseService.getProfile();
    _bubbleCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _bubbleScale =
        CurvedAnimation(parent: _bubbleCtrl, curve: Curves.easeOutBack);
    _collapseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      HeadphoneService.instance.start();
      HeadphoneService.instance.onConnected.listen((name) {
        if (mounted) setState(() => _headphoneDevice = name);
      });
    }
  }

  @override
  void dispose() {
    _bubbleCtrl.dispose();
    _collapseCtrl.dispose();
    super.dispose();
  }

  void _setCollapsed(bool v) {
    if (_navCollapsed == v) return;
    final allow = SettingsService.instance.betaNavCollapseOnScroll &&
        SettingsService.instance.flag('beta_nav_collapse', def: true);
    if (!allow && v) return;
    setState(() => _navCollapsed = v);
    if (v) {
      _collapseCtrl.forward();
    } else {
      _collapseCtrl.reverse();
    }
  }

  bool _onScroll(ScrollNotification n) {
    // Only react to vertical page scroll. Horizontal carousels ("Para ti",
    // "Escuchado recientemente", etc.) must never collapse the nav / mini player.
    if (n.metrics.axis != Axis.vertical) return false;

    final playing = PlayerController.instance.current != null;
    if (!playing) {
      if (_navCollapsed) _setCollapsed(false);
      return false;
    }
    if (n is ScrollUpdateNotification) {
      final dy = n.scrollDelta ?? 0;
      if (dy > 2 && n.metrics.pixels > 24) {
        _setCollapsed(true);
      } else if (dy < -4 || n.metrics.pixels <= 8) {
        _setCollapsed(false);
      }
    } else if (n is ScrollEndNotification) {
      if (n.metrics.pixels <= 8) _setCollapsed(false);
    }
    return false;
  }

  void _onLongPressStart(LongPressStartDetails d, BoxConstraints c) {
    if (_navCollapsed) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isDragging = true;
      _dragX = d.localPosition.dx;
      _prevX = d.localPosition.dx;
      _velocity = 0;
      _hoverIndex = _indexFromX(d.localPosition.dx, c.maxWidth);
    });
    _bubbleCtrl.forward(from: 0);
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d, BoxConstraints c) {
    if (_navCollapsed) return;
    final x = d.localPosition.dx.clamp(0.0, c.maxWidth);
    final idx = _indexFromX(x, c.maxWidth);
    if (idx != _hoverIndex) HapticFeedback.selectionClick();
    setState(() {
      _velocity = (x - _prevX).clamp(-22.0, 22.0);
      _prevX = x;
      _dragX = x;
      _hoverIndex = idx;
    });
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    if (_hoverIndex != null && _hoverIndex != _selectedIndex) {
      setState(() => _selectedIndex = _hoverIndex!);
    }
    _bubbleCtrl.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isDragging = false;
          _hoverIndex = null;
          _velocity = 0;
        });
      }
    });
  }

  int _indexFromX(double x, double width) {
    final itemW = width / 5;
    return (x / itemW).floor().clamp(0, 4);
  }

  Widget _navItem(int i, {bool compact = false, bool showLabel = true}) {
    final selected = i == _selectedIndex;
    final hovering = _isDragging && i == _hoverIndex;
    final active = selected || hovering;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _selectedIndex = i);
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _icons[i],
              size: hovering ? 26 : (compact ? 22 : 24),
              color: active
                  ? const Color(0xfffc3c44)
                  : Colors.white.withOpacity(0.88),
            ),
            if (showLabel) ...[
              const SizedBox(height: 2),
              Text(
                _labels[i],
                style: TextStyle(
                  fontSize: compact ? 9 : 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? const Color(0xfffc3c44)
                      : Colors.white.withOpacity(0.72),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _desktopNavItem(int index) {
    final selected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? const Color(0x22fc3c44) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _selectedIndex = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              Icon(_icons[index], size: 20,
                  color: selected ? const Color(0xfffc3c44) : Colors.white70),
              const SizedBox(width: 13),
              Text(_labels[index], style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              )),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0c0c0e),
      body: Row(children: [
        Container(
          width: 224,
          decoration: const BoxDecoration(
            color: Color(0xff101013),
            border: Border(right: BorderSide(color: Colors.white10)),
          ),
          child: SafeArea(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(25, 25, 20, 28),
                child: Row(children: [
                  Icon(Icons.graphic_eq_rounded, color: Color(0xfffc3c44), size: 27),
                  SizedBox(width: 10),
                  Text('NALI', style: TextStyle(color: Colors.white,
                    fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 2.2)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 0, 20, 9),
                child: Text('YOUR SPACE', style: TextStyle(color: Colors.white38,
                  fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              ),
              for (final i in const [0, 4, 3, 1, 2]) _desktopNavItem(i),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Divider(color: Colors.white.withOpacity(0.08)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: const Icon(Icons.settings_outlined, color: Colors.white70),
                  title: const Text('Settings', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  onTap: () => Navigator.pushNamed(context, '/settings'),
                ),
              ),
            ],
          )),
        ),
        Expanded(child: Stack(children: [
          Positioned.fill(child: _pages[_selectedIndex]),
          Positioned(
            top: 12, right: 22,
            child: SafeArea(child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/profile_edit'),
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _desktopProfileFuture,
                builder: (context, snapshot) {
                  final avatar = snapshot.data?['avatar_url']?.toString();
                  return Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: const Color(0xff242428),
                      backgroundImage: avatar != null && avatar.isNotEmpty
                          ? NetworkImage(avatar)
                          : null,
                      child: avatar == null || avatar.isEmpty
                          ? const Icon(Icons.person_outline_rounded,
                              color: Colors.white70, size: 19)
                          : null,
                    ),
                  );
                },
              ),
            )),
          ),
          Positioned(
            left: 22, right: 22, bottom: 16,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: const MiniPlayer(compact: false),
              ),
            ),
          ),
        ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showLabels = SettingsService.instance.navLabels &&
        SettingsService.instance.flag('nav_labels', def: true);

    return LayoutBuilder(builder: (context, constraints) {
      final nativeDesktop = !kIsWeb && (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS);
      final webDesktop = kIsWeb && constraints.maxWidth >= 1100 &&
          defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS;
      if (nativeDesktop || webDesktop) return _buildDesktopLayout(context);
      return Stack(
      children: [
        Scaffold(
          extendBody: true,
          body: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: Stack(
              children: [
                _pages[_selectedIndex],
                // More gap between mini player and nav
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _navCollapsed ? 86 : 100,
                  child: MiniPlayer(compact: _navCollapsed),
                ),
              ],
            ),
          ),
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: AnimatedBuilder(
              animation: _collapseCtrl,
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_collapseCtrl.value);
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final fullW = constraints.maxWidth;
                    final barH = showLabels ? (62.0 - 4 * t) : (56.0 - 2 * t);

                    // Collapsed: short pill centered for Home+Library (~46% width)
                    // Search peels off from the RIGHT edge of that pill (not screen edge)
                    final collapsedMainW = fullW * 0.46;
                    final expandedMainW = fullW;
                    final mainW = expandedMainW + (collapsedMainW - expandedMainW) * t;
                    final mainLeft = (fullW - mainW) / 2 * t; // centers as it shrinks

                    // Search starts OVER the right side of the bar and slides out a little
                    final searchSize = 52.0;
                    final searchLeft = mainLeft + mainW - searchSize * (1 - t) - 4 * t;
                    // When fully detached: just to the right of the short pill with small gap
                    final searchLeftDetached = mainLeft + mainW + 8;
                    final searchX = searchLeft + (searchLeftDetached - searchLeft) * t;

                    return SizedBox(
                      height: barH + 6,
                      width: fullW,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // ── Main glass bar ──────────────────────────
                          Positioned(
                            left: mainLeft,
                            width: mainW,
                            top: 0,
                            child: GestureDetector(
                              onLongPressStart: (d) =>
                                  _onLongPressStart(d, constraints),
                              onLongPressMoveUpdate: (d) =>
                                  _onLongPressMove(d, constraints),
                              onLongPressEnd: _onLongPressEnd,
                              child: LiquidGlass(
                                blur: 34,
                                opacity: 0.14,
                                borderRadius:
                                    BorderRadius.circular(28 - 2 * t),
                                borderWidth: 0.85,
                                enableSpecular: true,
                                elevation: 10,
                                child: SizedBox(
                                  height: barH,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: _navCollapsed
                                        ? [
                                            for (final i in _collapsedMain)
                                              _navItem(i,
                                                  compact: true,
                                                  showLabel: showLabels),
                                          ]
                                        : List.generate(
                                            5,
                                            (i) => _navItem(i,
                                                showLabel: showLabels),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // ── Search bubble — peels from nav, not screen edge ──
                          if (t > 0.01)
                            Positioned(
                              left: searchX,
                              top: (barH - searchSize) / 2,
                              child: Opacity(
                                opacity: Curves.easeOut.transform(t),
                                child: Transform.scale(
                                  scale: 0.72 + 0.28 * t,
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      setState(
                                          () => _selectedIndex = _searchIdx);
                                    },
                                    child: LiquidGlass(
                                      blur: 28,
                                      opacity: 0.16,
                                      borderRadius:
                                          BorderRadius.circular(searchSize / 2),
                                      borderWidth: 0.8,
                                      enableSpecular: true,
                                      elevation: 8,
                                      child: SizedBox(
                                        width: searchSize,
                                        height: searchSize,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.search,
                                              size: 22,
                                              color: _selectedIndex ==
                                                      _searchIdx
                                                  ? const Color(0xfffc3c44)
                                                  : Colors.white
                                                      .withOpacity(0.9),
                                            ),
                                            if (showLabels && t > 0.6)
                                              Text(
                                                'Search',
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  color: _selectedIndex ==
                                                          _searchIdx
                                                      ? const Color(
                                                          0xfffc3c44)
                                                      : Colors.white70,
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

                          // ── Liquid bubble (full nav only) ───────────
                          if (!_navCollapsed &&
                              _isDragging &&
                              _hoverIndex != null)
                            Positioned(
                              left: mainLeft +
                                  (_dragX - 30).clamp(4.0, mainW - 64),
                              top: 6,
                              child: ScaleTransition(
                                scale: _bubbleScale,
                                child: CustomPaint(
                                  size: const Size(60, 52),
                                  painter: _LiquidBubblePainter(
                                    velocity: _velocity,
                                  ),
                                  child: SizedBox(
                                    width: 60,
                                    height: 52,
                                    child: Center(
                                      child: Icon(
                                        _icons[_hoverIndex!],
                                        size: 26,
                                        color: const Color(0xfffc3c44),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        if (_headphoneDevice != null)
          HeadphoneBanner(
            deviceName: _headphoneDevice!,
            onDone: () {
              if (mounted) setState(() => _headphoneDevice = null);
            },
          ),
      ],
    );
    });
  }
}

class _LiquidBubblePainter extends CustomPainter {
  final double velocity;

  _LiquidBubblePainter({required this.velocity});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseRx = size.width * 0.38;
    final baseRy = size.height * 0.40;

    final speed = velocity.abs();
    final stretch = (0.14 + (speed / 18.0) * 0.86).clamp(0.14, 1.0);
    final dir = velocity >= 0 ? -1.0 : 1.0;

    final path = Path();
    const steps = 56;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps * math.pi * 2;
      final egg = 1.0 + 0.09 * math.sin(t - math.pi / 2);
      final rx = baseRx * egg * (1 + stretch * 0.42);
      final ry = baseRy * egg * (1 - stretch * 0.22);
      final lag = math.cos(t) * dir * stretch * baseRx * 0.38;
      final wave = math.sin(t * 2.2) * stretch * 1.6;
      final x = cx + rx * math.cos(t) + lag;
      final y = cy + ry * math.sin(t) + wave * 0.35;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    final rect = Offset.zero & size;

    canvas.drawPath(
      path.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.28),
          Colors.white.withOpacity(0.14),
        ],
      ).createShader(rect);
    canvas.drawPath(path, fill);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withOpacity(0.48),
    );

    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.38),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.42),
            Colors.white.withOpacity(0.0),
          ],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiquidBubblePainter old) =>
      old.velocity != velocity;
}


/// Brief toast when headphones connect (Spotify-style device name).
class HeadphoneBanner extends StatefulWidget {
  final String deviceName;
  final VoidCallback onDone;
  const HeadphoneBanner({super.key, required this.deviceName, required this.onDone});

  @override
  State<HeadphoneBanner> createState() => _HeadphoneBannerState();
}

class _HeadphoneBannerState extends State<HeadphoneBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      await _c.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _c,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
              .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1DB954).withOpacity(0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.headphones, color: Color(0xFF1DB954), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1DB954),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
