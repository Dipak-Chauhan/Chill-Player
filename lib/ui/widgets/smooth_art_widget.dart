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
  bool _loadedSynchronously = false;

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

  void _resolve({required bool initial}) {
    // Instant hit from the shared cache — no flash, no async gap.
    if (ArtworkCache.contains(widget.id)) {
      _art = ArtworkCache.peek(widget.id);
      _loadedSynchronously = true;
      if (!initial && mounted) setState(() {});
      return;
    }

    _loadedSynchronously = false;
    if (initial) {
      _art = null;
    } else {
      // Keep showing the previous art until the new one resolves (no blink).
    }

    final int targetId = widget.id;
    ArtworkCache.load(widget.id, type: widget.artworkType).then((bytes) {
      if (mounted && widget.id == targetId) {
        setState(() {
          _art = bytes;
          _loadedSynchronously = false;
        });
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
        cacheWidth: widget.size,
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

    final duration = _loadedSynchronously ? Duration.zero : const Duration(milliseconds: 200);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox.expand(
        child: AnimatedSwitcher(
          duration: duration,
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
