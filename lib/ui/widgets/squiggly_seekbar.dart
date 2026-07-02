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
  late AnimationController _amplitudeController;
  late AnimationController _progressController;
  bool _showRemainingTime = false;
  int _lastTickedPercent = -1;
  bool _isDragging = false;
  double _dragProgress = 0.0;
  int? _currentSongId;
  bool? _wasPlaying;
  // The wave only starts scrolling after the open transition settles, so the
  // Now Playing screen stays a static (cacheable) layer during the morph.
  bool _waveReady = false;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    
    // Handle morph: 1.0 = idle (thin pill), 0.0 = scrubbing (round handle).
    _interactionController = AnimationController.unbounded(
      vsync: this,
      value: 1.0,
    );

    // Wave amplitude: 1.0 = wavy (playing), 0.0 = flat (paused or scrubbing).
    final bool playing = ref.read(isPlayingProvider);
    _wasPlaying = playing;
    _amplitudeController = AnimationController.unbounded(
      vsync: this,
      value: playing ? 1.0 : 0.0,
    );

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _waveReady = true);
    });
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

  void _animateAmplitude(double target) {
    final simulation = SpringSimulation(
      const SpringDescription(mass: 1.0, stiffness: 300.0, damping: 26.0),
      _amplitudeController.value,
      target,
      _amplitudeController.velocity,
    );
    _amplitudeController.animateWith(simulation);
  }

  @override
  void dispose() {
    _waveController.dispose();
    _interactionController.dispose();
    _amplitudeController.dispose();
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

    if (!isPlaying || !_waveReady) {
      _waveController.stop();
    } else if (!_waveController.isAnimating) {
      _waveController.repeat();
    }

    // Flatten the wave when paused, restore it when playing (Material 3
    // expressive behaviour). The handle morph is unaffected by play state.
    if (!_isDragging && _wasPlaying != isPlaying) {
      _wasPlaying = isPlaying;
      _animateAmplitude(isPlaying ? 1.0 : 0.0);
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
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
                      _animateInteraction(0.0); // grow handle
                      _animateAmplitude(0.0); // flatten while scrubbing
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
                      _animateInteraction(1.0); // shrink handle back to pill
                      _animateAmplitude(isPlaying ? 1.0 : 0.0); // wavy only if playing
                      _lastTickedPercent = -1;
                    },
                    onPanCancel: () {
                      final targetDuration = Duration(milliseconds: (_progressController.value * maxMs).toInt());
                      ref.read(audioPlayerProvider).seek(targetDuration);
                      
                      setState(() {
                        _isDragging = false;
                      });
                      _animateInteraction(1.0);
                      _animateAmplitude(isPlaying ? 1.0 : 0.0);
                      _lastTickedPercent = -1;
                    },
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                      animation: Listenable.merge([_waveController, _interactionController, _amplitudeController, _progressController]),
                      builder: (context, child) {
                        return CustomPaint(
                          size: const Size(double.infinity, 40),
                          painter: _SquigglyPainter(
                            progress: _progressController.value,
                            wavePhase: _waveController.value * 2 * math.pi * 1.0, // Perfect harmonic phase loop continuity
                            interactionValue: _interactionController.value,
                            amplitudeValue: _amplitudeController.value,
                            color: theme.colorScheme.primary,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          ),
                        );
                      },
                      ),
                    ),
                  );
                }
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(displayDuration), style: textStyle),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showRemainingTime = !_showRemainingTime;
                    });
                  },
                  child: Text(
                    _showRemainingTime
                        ? "-${formatDuration((song?.duration ?? Duration.zero) - displayDuration)}"
                        : formatDuration(song?.duration ?? Duration.zero),
                    style: textStyle,
                  ),
                ),
              ],
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
  final double amplitudeValue;
  final Color color;
  final Color backgroundColor;

  _SquigglyPainter({
    required this.progress,
    required this.wavePhase,
    required this.interactionValue,
    required this.amplitudeValue,
    required this.color,
    required this.backgroundColor,
  });

  // Material 3 wavy linear progress indicator spec.
  static const double _trackStroke = 4.0; // active + inactive track thickness
  static const double _waveAmplitude = 3.0; // peak wave height from centre
  static const double _wavelength = 40.0; // determinate wavelength
  static const double _trackGap = 6.0; // gap between active/inactive and handle
  static const double _startRamp = 8.0; // wave eases up from the left edge

  @override
  void paint(Canvas canvas, Size size) {
    final double centerY = size.height / 2;
    final double handleX = (size.width * progress).clamp(0.0, size.width);
    // Wave amplitude is driven only by play/scrub state, not the handle.
    final double amplitude = _waveAmplitude * amplitudeValue.clamp(0.0, 1.0);

    final Paint inactivePaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = _trackStroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final Paint activePaint = Paint()
      ..color = color
      ..strokeWidth = _trackStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final Paint handlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Inactive track: straight line from after the handle to the end.
    final double inactiveStart = (handleX + _trackGap).clamp(0.0, size.width);
    final double inactiveEnd = size.width - _trackStroke / 2;
    if (inactiveEnd > inactiveStart) {
      canvas.drawLine(
        Offset(inactiveStart, centerY),
        Offset(inactiveEnd, centerY),
        inactivePaint,
      );
    }

    // Active track: wavy line from the left edge, connected right up to the handle.
    final double waveEnd = handleX;
    if (waveEnd > 0) {
      if (amplitude < 0.05) {
        canvas.drawLine(Offset(0, centerY), Offset(waveEnd, centerY), activePaint);
      } else {
        final path = Path();
        const double step = 1.0;
        path.moveTo(0, centerY);
        for (double x = 0; x <= waveEnd; x += step) {
          // Ease the wave up from flat over the first few px so it emanates
          // cleanly from the left edge.
          double ramp = 1.0;
          if (x < _startRamp) {
            final double t = x / _startRamp;
            ramp = t * t * (3 - 2 * t); // smoothstep
          }
          final double y = centerY +
              math.sin((x / (_wavelength / (2 * math.pi))) + wavePhase) * amplitude * ramp;
          path.lineTo(x, y);
        }
        canvas.drawPath(path, activePaint);
      }
    }

    // Handle: thin vertical pill at rest, growing to a circle while scrubbing.
    final double handleHeight = 22.0;
    final double handleWidth = ui.lerpDouble(22.0, 4.0, interactionValue)!;
    final double handleRadius = ui.lerpDouble(11.0, 2.0, interactionValue)!;

    final RRect handleRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(handleX, centerY),
        width: handleWidth,
        height: handleHeight,
      ),
      Radius.circular(handleRadius),
    );
    canvas.drawRRect(handleRect, handlePaint);
  }

  @override
  bool shouldRepaint(covariant _SquigglyPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.wavePhase != wavePhase ||
        oldDelegate.interactionValue != interactionValue ||
        oldDelegate.amplitudeValue != amplitudeValue ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
