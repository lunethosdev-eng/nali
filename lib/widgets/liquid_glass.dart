import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nali/services/settings_service.dart';

/// Liquid Glass effect inspired by Apple's iOS 26 Liquid Glass design system.
/// Uses high-quality BackdropFilter blur, subtle specular highlights,
/// soft borders and translucent fills to achieve a fluid, glass-like appearance.
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? tintColor;
  final double borderWidth;
  final bool enableSpecular;
  final double elevation;

  const LiquidGlass({
    super.key,
    required this.child,
    this.blur = 24.0,
    this.opacity = 0.12,
    this.borderRadius,
    this.padding,
    this.margin,
    this.tintColor,
    this.borderWidth = 0.8,
    this.enableSpecular = true,
    this.elevation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final s = SettingsService.instance;
    final enabled = s.liquidGlassEnabled && s.flag('ui_liquid_glass', def: true);
    final targetRadius = borderRadius ?? BorderRadius.circular(20);
    return TweenAnimationBuilder<BorderRadius?>(
      tween: BorderRadiusTween(end: targetRadius),
      duration: s.effectiveReduceAnimations ? Duration.zero : const Duration(milliseconds: 460),
      curve: Curves.easeInOutCubic,
      builder: (context, radius, _) => _buildGlass(context, s, enabled, radius ?? targetRadius),
    );
  }

  Widget _buildGlass(BuildContext context, SettingsService s, bool enabled, BorderRadius radius) {
    final tint = tintColor ?? Colors.white;
    final effectiveBlur = enabled
        ? (s.flag('ui_blur_heavy', def: false)
            ? s.effectiveGlassBlur * 1.4
            : s.effectiveGlassBlur).clamp(0.0, 48.0).toDouble()
        : 0.0;
    final effectiveOpacity = enabled
        ? s.glassOpacity.clamp(0.02, 0.5).toDouble()
        : opacity * 0.35;
    final specularOn = enabled && s.allowExpensiveEffects &&
        enableSpecular && s.flag('ui_specular', def: true);

    if (!enabled) {
      return Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: const Color(0xFF1A1A1E).withOpacity(0.92),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: child,
      );
    }

    final glassSurface = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: tint.withOpacity(effectiveOpacity),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tint.withOpacity(effectiveOpacity * 1.4),
            tint.withOpacity(effectiveOpacity * 0.6),
            tint.withOpacity(effectiveOpacity * 0.9),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
          width: borderWidth,
        ),
      ),
      child: Stack(
        children: [
          if (specularOn)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 1.5,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: radius.topLeft,
                    topRight: radius.topRight,
                  ),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.0),
                      Colors.white.withOpacity(0.45),
                      Colors.white.withOpacity(0.0),
                    ],
                    stops: const [0.1, 0.5, 0.9],
                  ),
                ),
              ),
            ),
          // Chromatic refraction rim (liquid light fringe)
          if (enabled)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RefractionRimPainter(radius: radius),
                ),
              ),
            ),
          child,
        ],
      ),
    );

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: elevation > 0
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: elevation * 2,
                  offset: Offset(0, elevation / 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: effectiveBlur <= 0
            ? glassSurface
            : BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: effectiveBlur,
                  sigmaY: effectiveBlur,
                ),
                child: glassSurface,
              ),
      ),
    );
  }
}

/// Convenience wrapper for AppBar-style liquid glass bars
class LiquidGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final double height;
  final PreferredSizeWidget? bottom;

  const LiquidGlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.height = 90,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      blur: 28,
      opacity: 0.08,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      borderWidth: 0.6,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height - MediaQuery.of(context).padding.top,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  if (title != null) Expanded(child: title!),
                  if (actions != null) ...actions!,
                  const SizedBox(width: 8),
                ],
              ),
            ),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }
}


/// Soft RGB fringe along the glass edge — light bending through liquid.
class _RefractionRimPainter extends CustomPainter {
  _RefractionRimPainter({required this.radius});
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    // Soft liquid edge only — no heavy RGB outline.
    final rrect = radius.toRRect(Offset.zero & size);
    final inset = rrect.deflate(0.8);

    final gloss = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.18),
          Colors.white.withOpacity(0.04),
          Colors.white.withOpacity(0.0),
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    canvas.drawRRect(inset, gloss);

    // Very light inner highlight (top edge)
    final top = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = Colors.white.withOpacity(0.12);
    canvas.drawRRect(rrect.deflate(0.3), top);
  }

  @override
  bool shouldRepaint(covariant _RefractionRimPainter old) =>
      old.radius != radius;
}
