import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../services/artwork_cache.dart';

class SmoothArtWidget extends StatefulWidget {
  final int id;
  final int size;
  final double borderRadius;
  final bool isMini;
  final double? iconSize;
  final ArtworkType artworkType;
  final bool isPlaying;
  final bool isStopped;

  const SmoothArtWidget({
    super.key,
    required this.id,
    this.size = 300,
    this.borderRadius = 12.0,
    this.isMini = false,
    this.iconSize,
    this.artworkType = ArtworkType.AUDIO,
    this.isPlaying = false,
    this.isStopped = false,
  });

  @override
  State<SmoothArtWidget> createState() => _SmoothArtWidgetState();
}

class _SmoothArtWidgetState extends State<SmoothArtWidget> {
  Uint8List? _art;

  @override
  void initState() {
    super.initState();
    _resolve(initial: true);
  }

  @override
  void didUpdateWidget(covariant SmoothArtWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.artworkType != widget.artworkType) {
      _resolve(initial: false);
    }
  }

  // Full-resolution tier only for large displays (player / detail screens);
  // everything else uses the fast small thumbnail tier.
  bool get _full => widget.size > 400;
  int get _decodeWidth => _full ? ArtworkCache.fullSize : ArtworkCache.thumbSize;

  void _resolve({required bool initial}) {
    // Instant hit from the shared cache — no async gap.
    if (ArtworkCache.contains(widget.id, full: _full)) {
      _art = ArtworkCache.peek(widget.id, full: _full);
      if (!initial && mounted) setState(() {});
      return;
    }

    // On id change keep showing the previous art until the new one resolves.
    if (initial) _art = null;

    final int targetId = widget.id;
    ArtworkCache.load(widget.id, full: _full, type: widget.artworkType).then((bytes) {
      if (mounted && widget.id == targetId) {
        setState(() => _art = bytes);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (_art != null) {
      imageWidget = Image.memory(
        _art!,
        key: ValueKey(widget.id),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        cacheWidth: _decodeWidth,
      );
    } else {
      imageWidget = Container(
        key: const ValueKey('placeholder'),
        width: double.infinity,
        height: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.music_note,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            size: widget.iconSize ?? 40,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      // Fast fade-in whenever artwork first appears (cached or freshly loaded).
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
        child: SizedBox.expand(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
              return Stack(
                children: <Widget>[
                  ...previousChildren.map((child) => SizedBox.expand(child: child)),
                  if (currentChild != null) SizedBox.expand(child: currentChild),
                ],
              );
            },
            child: imageWidget,
          ),
        ),
      ),
    );
  }
}

// Emphasized Spring Curve
class SpringCurve extends Curve {
  const SpringCurve();

  @override
  double transform(double t) {
    final simulation = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 400, damping: 24),
      0, 1, 0,
    );
    // mapped roughly over 600ms duration
    return simulation.x(t * 0.6);
  }
}
