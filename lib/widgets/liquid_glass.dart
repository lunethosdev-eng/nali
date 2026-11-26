import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nali/services/settings_service.dart';

/// Apple-style Liquid Glass. Chromatic light lives *inside* the material
/// (gradient / inner glow), never as an outer outline stroke.
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
      duration: s.effectiveReduceAnimations
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: const Cubic(0.22, 1.0, 0.36, 1.0),
      builder: (context, radius, _) =>
          _buildGlass(context, s, enabled, radius ?? targetRadius),
    );
  }

  Widget _buildGlass(
    BuildContext context,
    SettingsService s,
    bool enabled,
    BorderRadius radius,
  ) {
    final tint = tintColor ?? Colors.white;
    final effectiveBlur = enabled
        ? (s.flag('ui_blur_heavy', def: false)
                ? s.effectiveGlassBlur * 1.4
                : s.effectiveGlassBlur)
            .clamp(0.0, 48.0)
            .toDouble()
        : 0.0;
    final effectiveOpacity = enabled
        ? s.glassOpacity.clamp(0.02, 0.5).toDouble()
        : opacity * 0.35;
    final specularOn = enabled &&
        s.allowExpensiveEffects &&
        enableSpecular &&
        s.flag('ui_specular', def: true);

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

    // Inner material: soft multi-stop gradient simulates light bending
    // *through* the glass (cyan→clear→magenta bias), not an outer rim.
    final glassSurface = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0x22A8E8FF), // inner cyan tint
            tint.withOpacity(effectiveOpacity),
            const Color(0x18FF8AB8), // inner magenta tint
            tint.withOpacity(effectiveOpacity * 0.85),
          ],
          stops: const [0.0, 0.28, 0.72, 1.0],
        ),
        border: Border.all(
          // Neutral soft edge only — no RGB outline
          color: Colors.white.withOpacity(0.14),
          width: borderWidth,
        ),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          if (specularOn)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 1.2,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: radius.topLeft,
                      topRight: radius.topRight,
                    ),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.0),
                        Colors.white.withOpacity(0.35),
                        Colors.white.withOpacity(0.0),
                      ],
                      stops: const [0.12, 0.5, 0.88],
                    ),
                  ),
                ),
              ),
            ),
          // Soft inner highlight (light catching inside the glass body)
          if (specularOn)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: RadialGradient(
                      center: const Alignment(-0.55, -0.7),
                      radius: 1.1,
                      colors: [
                        Colors.white.withOpacity(0.12),
                        Colors.white.withOpacity(0.0),
                      ],
                    ),
                  ),
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
                  color: Colors.black.withOpacity(0.22),
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
  Size get preferredSize =>
      Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

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
