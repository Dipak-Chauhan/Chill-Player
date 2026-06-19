import 'dart:ui';
import 'package:flutter/material.dart';

class DragToDismissWrapper extends StatefulWidget {
  final Widget Function(BuildContext context, double dismissProgress) builder;
  final VoidCallback onDismissed;
  final VoidCallback? onDragUp;
  final double? maxDragDistance;

  const DragToDismissWrapper({
    super.key,
    required this.builder,
    required this.onDismissed,
    this.onDragUp,
    this.maxDragDistance,
  });

  @override
  State<DragToDismissWrapper> createState() => _DragToDismissWrapperState();
}

class _DragToDismissWrapperState extends State<DragToDismissWrapper> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _dragOffset = 0.0;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isDismissing) return;
    if (_controller.isAnimating) _controller.stop();

    setState(() {
      _dragOffset += details.delta.dy;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isDismissing) return;
    final velocity = details.velocity.pixelsPerSecond.dy;
    
    final targetMax = widget.maxDragDistance ?? MediaQuery.of(context).size.height;

    if (_dragOffset > targetMax * 0.4 || velocity > 800) {
      _animateDismiss(targetMax);
    } else if (widget.onDragUp != null && (_dragOffset < -40 || velocity < -500)) {
      widget.onDragUp!();
      _snapBack();
    } else {
      _snapBack();
    }
  }

  /// Drives the collapse the rest of the way to [maxDist] (completing the
  /// art/controls morph so it lands exactly on the mini-player) before popping.
  /// This avoids the old behaviour of popping mid-drag, which left the route's
  /// reverse transition and the Hero flight to fight over a half-finished morph.
  void _animateDismiss(double maxDist) {
    _isDismissing = true;
    if (_controller.isAnimating) _controller.stop();

    final startOffset = _dragOffset.clamp(0.0, maxDist);
    final remaining = maxDist - startOffset;
    // Scale the finishing duration to the remaining distance so the motion
    // keeps a consistent feel whether released early or near the bottom.
    final ms = (140 + (remaining / maxDist) * 150).round().clamp(120, 300);
    _controller.duration = Duration(milliseconds: ms);

    late final VoidCallback listener;
    listener = () {
      if (!mounted) return;
      final curved = Curves.easeOutCubic.transform(_controller.value);
      setState(() {
        _dragOffset = startOffset + remaining * curved;
      });
      if (_controller.isCompleted) {
        _controller.removeListener(listener);
        widget.onDismissed();
      }
    };

    _controller.addListener(listener);
    _controller.forward(from: 0.0);
  }

  void _snapBack() {
    final startOffset = _dragOffset;
    _controller.duration = const Duration(milliseconds: 300);

    late final VoidCallback listener;
    listener = () {
      if (!mounted) return;
      final curved = Curves.easeOutCubic.transform(_controller.value);
      setState(() {
        _dragOffset = startOffset * (1.0 - curved);
      });
      if (_controller.isCompleted) {
        _controller.removeListener(listener);
      }
    };

    _controller.addListener(listener);
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    // Determine the distance required to hit the target
    final maxDist = widget.maxDragDistance ?? MediaQuery.of(context).size.height;
    
    // Clamp offset so the entire screen physically stops tracking the finger once it hits maxDist
    final clampedDrag = _dragOffset.clamp(0.0, maxDist);
    final dismissProgress = (clampedDrag / maxDist).clamp(0.0, 1.0);

    return GestureDetector(
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Transform.translate(
        offset: Offset(0, clampedDrag), // Move the screen down naturally
        child: widget.builder(context, dismissProgress),
      ),
    );
  }
}
