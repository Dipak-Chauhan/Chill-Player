import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/audio_state.dart';
import 'smooth_art_widget.dart';

/// Measurement keys for the morphing elements. The mini-player (in the home
/// route) and the Now Playing screen (in this route) both attach these so the
/// morph layer can read their exact on-screen rects and interpolate between
/// them. There is only ever one of each on screen at a time.
final GlobalKey miniArtKey = GlobalKey(debugLabel: 'miniArt');
final GlobalKey miniTitleKey = GlobalKey(debugLabel: 'miniTitle');
final GlobalKey miniArtistKey = GlobalKey(debugLabel: 'miniArtist');
final GlobalKey npArtKey = GlobalKey(debugLabel: 'npArt');
final GlobalKey npTitleKey = GlobalKey(debugLabel: 'npTitle');
final GlobalKey npArtistKey = GlobalKey(debugLabel: 'npArtist');

// Matched text styles for the two ends of the morph.
TextStyle? expandedTitleStyle(ThemeData t) => t.textTheme.headlineMedium
    ?.copyWith(fontWeight: FontWeight.bold, color: t.colorScheme.onSurface);
TextStyle? collapsedTitleStyle(ThemeData t) =>
    t.textTheme.titleMedium?.copyWith(color: t.colorScheme.onSurface);
TextStyle? expandedArtistStyle(ThemeData t) => t.textTheme.titleMedium
    ?.copyWith(color: t.colorScheme.onSurface.withValues(alpha: 0.7));
TextStyle? collapsedArtistStyle(ThemeData t) => t.textTheme.bodySmall
    ?.copyWith(color: t.colorScheme.onSurfaceVariant.withValues(alpha: 0.7));

Rect? _rectOf(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  if (!box.attached) return null;
  final topLeft = box.localToGlobal(Offset.zero);
  return topLeft & box.size;
}

/// A transparent route that morphs the Now Playing screen to/from the
/// mini-player. The artwork, title and artist are drawn by [_PlayerMorphLayer]
/// and interpolated between the two measured layouts; the background chrome
/// cross-fades. A single controller drives all of it, and [PlayerDragToDismiss]
/// steers that controller, so the drag itself performs the morph and lands
/// exactly on the mini-player.
class ExpandPlayerRoute<T> extends PageRoute<T> {
  ExpandPlayerRoute({required this.child});

  final Widget child;

  /// Fraction of screen height a downward drag travels to fully collapse.
  static const double collapseFraction = 0.55;

  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get opaque => false;
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 380);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  AnimationController get expandController => controller!;

  static ExpandPlayerRoute? maybeOf(BuildContext context) {
    final route = ModalRoute.of(context);
    return route is ExpandPlayerRoute ? route : null;
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      child;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value.clamp(0.0, 1.0);
        // Real Now Playing content is only shown near the fully-expanded end;
        // below that the morph layer takes over so nothing is double-drawn.
        // The child stays in the tree (just invisible) so its measurement keys
        // remain laid out and the drag gesture keeps receiving events.
        final chromeOpacity = ((t - 0.86) / 0.14).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: chromeOpacity, child: child),
            _PlayerMorphLayer(t: t),
          ],
        );
      },
    );
  }
}

/// Draws the morphing artwork/title/artist over the route, interpolating their
/// geometry between the Now Playing layout (t = 1) and the mini-player
/// (t = 0). Hidden at t = 1, where the real content shows through instead.
class _PlayerMorphLayer extends ConsumerWidget {
  const _PlayerMorphLayer({required this.t});

  final double t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();

    final artExpanded = _rectOf(npArtKey);
    final artCollapsed = _rectOf(miniArtKey);
    final titleExpanded = _rectOf(npTitleKey);
    final titleCollapsed = _rectOf(miniTitleKey);
    final artistExpanded = _rectOf(npArtistKey);
    final artistCollapsed = _rectOf(miniArtistKey);

    // If we can't measure (e.g. first frame before layout), draw nothing and
    // let the real content / mini-player show.
    if (artExpanded == null || artCollapsed == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final morphOpacity = (1.0 - ((t - 0.86) / 0.14)).clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(t);

    final artRect = Rect.lerp(artCollapsed, artExpanded, eased)!;
    final artRadius = lerpDouble(28.0, 18.0, eased)!;

    final children = <Widget>[
      // Backdrop scrim that fades out as the player collapses, revealing the
      // home screen + real mini-player underneath at the end of the drag.
      Positioned.fill(
        child: IgnorePointer(
          child: Opacity(
            opacity: Curves.easeIn.transform(t),
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),
        ),
      ),
      Positioned.fromRect(
        rect: artRect,
        child: SmoothArtWidget(
          id: song.id,
          size: 400,
          isMini: false,
          borderRadius: artRadius,
          iconSize: 24,
          isPlaying: false,
        ),
      ),
    ];

    if (titleExpanded != null && titleCollapsed != null) {
      final titleRect = Rect.lerp(titleCollapsed, titleExpanded, eased)!;
      children.add(_morphText(
        rect: titleRect,
        text: song.title,
        style: TextStyle.lerp(
          collapsedTitleStyle(theme),
          expandedTitleStyle(theme),
          eased,
        ),
        centered: eased > 0.5,
      ));
    }
    if (artistExpanded != null && artistCollapsed != null) {
      final artistRect = Rect.lerp(artistCollapsed, artistExpanded, eased)!;
      children.add(_morphText(
        rect: artistRect,
        text: song.artist,
        style: TextStyle.lerp(
          collapsedArtistStyle(theme),
          expandedArtistStyle(theme),
          eased,
        ),
        centered: eased > 0.5,
      ));
    }

    return IgnorePointer(
      child: Opacity(
        opacity: morphOpacity,
        child: Stack(fit: StackFit.expand, children: children),
      ),
    );
  }

  Widget _morphText({
    required Rect rect,
    required String text,
    required TextStyle? style,
    required bool centered,
  }) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Align(
        alignment: centered ? Alignment.center : Alignment.centerLeft,
        child: Text(
          text,
          style: style,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          textAlign: centered ? TextAlign.center : TextAlign.left,
        ),
      ),
    );
  }
}

/// Wraps the Now Playing content and lets a vertical drag steer the enclosing
/// [ExpandPlayerRoute] animation, so the morph tracks the finger. Releasing
/// past the threshold (or with downward velocity) pops; releasing early springs
/// back. An upward fling triggers [onDragUp].
class PlayerDragToDismiss extends StatefulWidget {
  const PlayerDragToDismiss({super.key, required this.child, this.onDragUp});

  final Widget child;
  final VoidCallback? onDragUp;

  @override
  State<PlayerDragToDismiss> createState() => _PlayerDragToDismissState();
}

class _PlayerDragToDismissState extends State<PlayerDragToDismiss> {
  double _dragDistance = 0.0;
  bool _dismissing = false;

  void _onStart(DragStartDetails details) => _dragDistance = 0.0;

  void _onUpdate(DragUpdateDetails details) {
    if (_dismissing) return;
    final controller = ExpandPlayerRoute.maybeOf(context)?.expandController;
    if (controller == null) return;

    _dragDistance += details.delta.dy;
    if (_dragDistance <= 0) {
      controller.value = 1.0;
      return;
    }
    final collapseDistance =
        MediaQuery.of(context).size.height * ExpandPlayerRoute.collapseFraction;
    controller.value =
        (1.0 - (_dragDistance / collapseDistance)).clamp(0.0, 1.0);
  }

  void _onEnd(DragEndDetails details) {
    if (_dismissing) return;
    final route = ExpandPlayerRoute.maybeOf(context);
    final controller = route?.expandController;
    if (route == null || controller == null) return;

    final velocity = details.velocity.pixelsPerSecond.dy;

    if ((_dragDistance < -40 || velocity < -500) && widget.onDragUp != null) {
      controller.value = 1.0;
      _dragDistance = 0.0;
      widget.onDragUp!();
      return;
    }

    final shouldDismiss = controller.value < 0.7 || velocity > 700;
    if (shouldDismiss) {
      _dismissing = true;
      Navigator.of(context).maybePop();
    } else {
      controller.forward();
    }
    _dragDistance = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: _onStart,
      onVerticalDragUpdate: _onUpdate,
      onVerticalDragEnd: _onEnd,
      child: widget.child,
    );
  }
}
