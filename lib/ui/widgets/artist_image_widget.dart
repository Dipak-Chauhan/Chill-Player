import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/deezer_api.dart';

/// A widget that displays a Deezer artist image with fallback to local album art.
/// Uses a progressive loading pattern:
///   1. Show local art immediately (from SmoothArtWidget)
///   2. Async load Deezer image in background
///   3. Crossfade to Deezer image once loaded
class ArtistImageWidget extends ConsumerWidget {
  final String artistName;
  final int fallbackId; // Song/artist ID for local art fallback
  final double borderRadius;
  final double? iconSize;
  final BoxFit fit;

  const ArtistImageWidget({
    super.key,
    required this.artistName,
    required this.fallbackId,
    this.borderRadius = 12.0,
    this.iconSize,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deezerImage = ref.watch(deezerArtistImageProvider(artistName));

    final Widget child = deezerImage.when(
      data: (bytes) {
        if (bytes != null && bytes.isNotEmpty) {
          return _DeezerImage(
            key: ValueKey('deezer_${artistName}_${bytes.hashCode}'),
            bytes: bytes,
            fit: fit,
          );
        }
        return _GeneratedAvatar(
          key: ValueKey('avatar_$artistName'),
          name: artistName,
          iconSize: iconSize,
        );
      },
      loading: () {
        return _GeneratedAvatar(
          key: ValueKey('avatar_$artistName'),
          name: artistName,
          iconSize: iconSize,
        );
      },
      error: (err, stack) {
        return _GeneratedAvatar(
          key: ValueKey('avatar_$artistName'),
          name: artistName,
          iconSize: iconSize,
        );
      },
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: child,
      ),
    );
  }
}

/// Internal widget for smoothly displaying a Deezer image.
class _DeezerImage extends StatelessWidget {
  final Uint8List bytes;
  final BoxFit fit;

  const _DeezerImage({super.key, required this.bytes, required this.fit});

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      bytes,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.person,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          size: 40,
        ),
      ),
    );
  }
}

class _GeneratedAvatar extends StatelessWidget {
  final String name;
  final double? iconSize;

  const _GeneratedAvatar({super.key, required this.name, this.iconSize});

  @override
  Widget build(BuildContext context) {
    final seed = name.trim().isEmpty ? '?' : name.trim();
    final letter = seed[0].toUpperCase();

    // Deterministic hue, vibrant saturation 0.6, lightness 0.6 for text
    final hue = (seed.hashCode.abs() % 360).toDouble();
    final color = HSLColor.fromAHSL(1.0, hue, 0.6, 0.6).toColor();
    final bg = HSLColor.fromAHSL(1.0, hue, 0.4, 0.2).toColor();

    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: iconSize ?? 50,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
