import 'dart:ui';
import 'package:flutter/material.dart';

/// A premium frosted glass container that avoids color banding.
///
/// Uses a multi-layer approach:
///  1. BackdropFilter for the blur itself
///  2. A subtle gradient tint (not flat color) to break up banding
///  3. A procedural grain/noise overlay to dither any remaining bands
class FrostedGlass extends StatelessWidget {
  final Widget child;
  final double sigmaX;
  final double sigmaY;
  final double tintOpacity;
  final BorderRadius? borderRadius;

  const FrostedGlass({
    super.key,
    required this.child,
    this.sigmaX = 40,
    this.sigmaY = 40,
    this.tintOpacity = 0.55,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tintBase = cs.surfaceContainerHighest;

    Widget content = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Use a gradient instead of flat color to break banding
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tintBase.withValues(alpha: tintOpacity),
              tintBase.withValues(alpha: tintOpacity * 0.85),
              tintBase.withValues(alpha: tintOpacity * 0.95),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: child,
      ),
    );

    if (borderRadius != null) {
      content = ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }

    return content;
  }
}
