import 'package:flutter/material.dart';

// Layout keys kept for potential measurement use; harmless if unused.
final GlobalKey miniArtKey = GlobalKey(debugLabel: 'miniArt');
final GlobalKey miniTitleKey = GlobalKey(debugLabel: 'miniTitle');
final GlobalKey miniArtistKey = GlobalKey(debugLabel: 'miniArtist');
final GlobalKey npArtKey = GlobalKey(debugLabel: 'npArt');
final GlobalKey npTitleKey = GlobalKey(debugLabel: 'npTitle');
final GlobalKey npArtistKey = GlobalKey(debugLabel: 'npArtist');

/// Wraps the Now Playing content. A downward fling pops the screen (the
/// container transform then collapses it back into the mini-player); an upward
/// fling triggers [onDragUp].
class PlayerDragToDismiss extends StatefulWidget {
  const PlayerDragToDismiss({super.key, required this.child, this.onDragUp});

  final Widget child;
  final VoidCallback? onDragUp;

  @override
  State<PlayerDragToDismiss> createState() => _PlayerDragToDismissState();
}

class _PlayerDragToDismissState extends State<PlayerDragToDismiss> {
  void _onEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (velocity < -300 && widget.onDragUp != null) {
      widget.onDragUp!();
    } else if (velocity > 300) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: _onEnd,
      child: widget.child,
    );
  }
}
