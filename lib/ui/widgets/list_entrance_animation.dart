import 'package:flutter/material.dart';

class ListEntranceAnimation extends StatefulWidget {
  final Widget Function(BuildContext context, Animation<double> animation) builder;
  final Duration duration;
  final VoidCallback? onComplete;

  const ListEntranceAnimation({
    super.key,
    required this.builder,
    this.duration = const Duration(milliseconds: 550),
    this.onComplete,
  });

  @override
  State<ListEntranceAnimation> createState() => _ListEntranceAnimationState();
}

class _ListEntranceAnimationState extends State<ListEntranceAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _controller);
  }
}
