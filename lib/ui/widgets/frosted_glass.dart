import 'dart:ui';
import 'dart:math' as math;
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
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // Grain overlay to dither any remaining banding
            const Positioned.fill(child: _GrainOverlay()),
            child,
          ],
        ),
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

/// A subtle procedural noise overlay that breaks up color banding.
/// Uses a custom painter for minimal overhead.
class _GrainOverlay extends StatelessWidget {
  const _GrainOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GrainPainter(
          opacity: 0.04, // Very subtle—just enough to dither bands
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  final double opacity;
  final bool isDark;

  _GrainPainter({required this.opacity, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42); // Fixed seed for stable grain
    final paint = Paint();
    const step = 3.0; // Grain cell size in logical pixels

    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        final v = rng.nextDouble();
        paint.color = (isDark ? Colors.white : Colors.black)
            .withValues(alpha: v * opacity);
        canvas.drawRect(Rect.fromLTWH(x, y, step, step), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.isDark != isDark;
}
