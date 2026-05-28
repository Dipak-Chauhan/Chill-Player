import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../../state/audio_state.dart';
import '../../services/haptic_service.dart';

class SquigglySeekbar extends ConsumerStatefulWidget {
  const SquigglySeekbar({super.key});

  @override
  ConsumerState<SquigglySeekbar> createState() => _SquigglySeekbarState();
}

class _SquigglySeekbarState extends ConsumerState<SquigglySeekbar> with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _interactionController;
  late AnimationController _progressController;
  bool _showRemainingTime = false;
  int _lastTickedPercent = -1;
  bool _isDragging = false;
  double _dragProgress = 0.0;
  int? _currentSongId;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    // 1.0 means unpressed (full amplitude, thin thumb)
    // 0.0 means pressed (flat wave, fat thumb)
    _interactionController = AnimationController.unbounded(
      vsync: this,
      value: 1.0,
    );

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  void _animateInteraction(double target) {
    final simulation = SpringSimulation(
      const SpringDescription(mass: 1.0, stiffness: 400.0, damping: 24.0),
      _interactionController.value,
      target,
      _interactionController.velocity,
    );
    _interactionController.animateWith(simulation);
  }

  @override
  void dispose() {
    _waveController.dispose();
    _interactionController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = ref.watch(isPlayingProvider);
    final currentDuration = ref.watch(playbackPositionProvider);
    final song = ref.watch(currentSongProvider);
    
    final int maxMs = song?.duration.inMilliseconds ?? 1;
    final double safeProgress = (currentDuration.inMilliseconds / maxMs).clamp(0.0, 1.0);

    // Track active song and snap progress instantly on song switch or huge seek changes
    if (song != null) {
      if (song.id != _currentSongId) {
        _currentSongId = song.id;
        _progressController.value = safeProgress;
      } else if (!_isDragging) {
        final double diff = (safeProgress - _progressController.value).abs();
        if (diff > 0.15) {
          _progressController.value = safeProgress;
        } else {
          _progressController.animateTo(
            safeProgress,
            duration: const Duration(milliseconds: 250),
            curve: Curves.linear,
          );
        }
      }
    }

    String formatDuration(Duration d) {
      final m = d.inMinutes.toString().padLeft(2, '0');
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return "$m:$s";
    }

    if (!isPlaying) {
      _waveController.stop();
    } else if (!_waveController.isAnimating) {
      _waveController.repeat();
    }

    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
      fontWeight: FontWeight.w600,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final displayDuration = _isDragging 
            ? Duration(milliseconds: (_dragProgress * maxMs).toInt()) 
            : currentDuration;

        return Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(formatDuration(displayDuration), style: textStyle, textAlign: TextAlign.center),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, boxConstraints) {
                  void seekToLocal(Offset localPosition) {
                    final percent = (localPosition.dx / boxConstraints.maxWidth).clamp(0.0, 1.0);
                    setState(() {
                      _dragProgress = percent;
                    });
                    _progressController.value = percent; // Snap visual thumb instantly during drag
                    
                    final int targetPercentInt = (percent * 100).round();
                    if (targetPercentInt != _lastTickedPercent) {
                      _lastTickedPercent = targetPercentInt;
                      HapticService.tick();
                    }
                  }

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (details) {
                      setState(() {
                        _isDragging = true;
                      });
                      _animateInteraction(0.0); // animate to flat and fat thumb
                      HapticService.light();
                      seekToLocal(details.localPosition);
                    },
                    onPanUpdate: (details) => seekToLocal(details.localPosition),
                    onPanEnd: (_) {
                      final targetDuration = Duration(milliseconds: (_progressController.value * maxMs).toInt());
                      ref.read(audioPlayerProvider).seek(targetDuration);
                      
                      setState(() {
                        _isDragging = false;
                      });
                      _animateInteraction(1.0); // animate to squiggly and thin thumb
                      _lastTickedPercent = -1;
                    },
                    onPanCancel: () {
                      final targetDuration = Duration(milliseconds: (_progressController.value * maxMs).toInt());
                      ref.read(audioPlayerProvider).seek(targetDuration);
                      
                      setState(() {
                        _isDragging = false;
                      });
                      _animateInteraction(1.0);
                      _lastTickedPercent = -1;
                    },
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_waveController, _interactionController, _progressController]),
                      builder: (context, child) {
                        return CustomPaint(
                          size: const Size(double.infinity, 40),
                          painter: _SquigglyPainter(
                            progress: _progressController.value,
                            wavePhase: _waveController.value * 2 * math.pi * 1.0, // Perfect harmonic phase loop continuity
                            interactionValue: _interactionController.value,
                            color: theme.colorScheme.primary,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          ),
                        );
                      },
                    ),
                  );
                }
              ),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () {
                setState(() {
                  _showRemainingTime = !_showRemainingTime;
                });
              },
              child: SizedBox(
                width: 48,
                child: Text(
                  _showRemainingTime 
                      ? "-${formatDuration((song?.duration ?? Duration.zero) - displayDuration)}"
                      : formatDuration(song?.duration ?? Duration.zero), 
                  style: textStyle, 
                  textAlign: TextAlign.center
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SquigglyPainter extends CustomPainter {
  final double progress;
  final double wavePhase;
  final double interactionValue;
  final Color color;
  final Color backgroundColor;

  _SquigglyPainter({
    required this.progress,
    required this.wavePhase,
    required this.interactionValue,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1.0 = full wave, 0.0 = flat
    final amplitude = 4.0 * interactionValue;
    // Material 3 exact wavelength constraint
    final wavelength = 40.0;
    
    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final activePaint = Paint()
      ..color = color
      ..strokeWidth = ui.lerpDouble(8.0, 4.0, interactionValue)! // Slightly thicker line when flat
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final thumbPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final activeWidth = size.width * progress;

    // Draw background (straight line)
    // We start slightly inside the active length so the rounded cap doesn't poke out from under the thumb
    if (size.width - activeWidth > 0) {
      canvas.drawLine(
        Offset(activeWidth + 4, size.height / 2),
        Offset(size.width, size.height / 2),
        bgPaint,
      );
    }

    // Draw active path (squiggly or mostly flat if interactionValue ~ 0)
    final path = Path();
    
    if (activeWidth > 0 && interactionValue > 0.01) {
      path.moveTo(0, size.height / 2);
      
      // Step size for drawing sine wave (smaller = smoother)
      final step = 1.0; 
      
      for (double x = 0; x <= activeWidth; x += step) {
        // Dampen the wave right near the thumb so it meets the center perfectly
        final distanceToThumb = activeWidth - x;
        double thumbDamping = 1.0;
        final dampingZone = 32.0;
        
        if (distanceToThumb < dampingZone) {
          // Smooth cubic interpolation (smoothstep) for a flawless blend into the thumb
          final t = distanceToThumb / dampingZone;
          thumbDamping = t * t * (3 - 2 * t);
        }

        // Dampen the wave at the very start (left side) so it emanates from the center
        double startDamping = 1.0;
        final startZone = 24.0;
        if (x < startZone) {
          final t = x / startZone;
          startDamping = t * t * (3 - 2 * t);
        }

        final totalDamping = thumbDamping * startDamping;

        // Add phase. Using x + phase to flow leftwards
        final y = size.height / 2 + math.sin((x / (wavelength / (2 * math.pi))) + wavePhase) * amplitude * totalDamping;
        
        // If it's very close to thumb, literally just flatline it into the center to avoid math imprecision
        if (distanceToThumb <= step) {
           path.lineTo(activeWidth, size.height / 2);
           break;
        } else {
           path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, activePaint);
    } else if (activeWidth > 0) {
      // Very close to 0 amplitude, just draw a flat line
      canvas.drawLine(Offset(0, size.height / 2), Offset(activeWidth, size.height / 2), activePaint);
    }

    // Draw physics morphing thumb
    // Unpressed (1.0): 6x24 pill
    // Pressed (0.0): 24x24 circle
    final thumbHeight = 24.0;
    final thumbWidth = ui.lerpDouble(24.0, 6.0, interactionValue)!;
    final thumbRadius = ui.lerpDouble(12.0, 3.0, interactionValue)!;

    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(activeWidth, size.height / 2),
        width: thumbWidth,
        height: thumbHeight,
      ),
      Radius.circular(thumbRadius),
    );
    canvas.drawRRect(thumbRect, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _SquigglyPainter oldDelegate) {
    return oldDelegate.progress != progress || 
           oldDelegate.wavePhase != wavePhase ||
           oldDelegate.interactionValue != interactionValue ||
           oldDelegate.color != color ||
           oldDelegate.backgroundColor != backgroundColor;
  }
}
