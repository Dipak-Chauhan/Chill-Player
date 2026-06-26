import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/artwork_cache.dart';

class ExtractedColors {
  final Color dominant;
  final Color vibrant;
  final Color muted;
  final Color darkVibrant;

  const ExtractedColors({
    required this.dominant,
    required this.vibrant,
    required this.muted,
    required this.darkVibrant,
  });

  static const defaultColors = ExtractedColors(
    dominant: Color(0xFF3F9BAF), // App Icon's primary seed color
    vibrant: Color(0xFF00BCD4),
    muted: Color(0xFF006064),
    darkVibrant: Color(0xFF00363A),
  );
}

class ColorSchemeState {
  final ColorScheme light;
  final ColorScheme dark;
  final bool isAnimating;

  const ColorSchemeState({
    required this.light,
    required this.dark,
    required this.isAnimating,
  });
}

class ColorSchemeNotifier extends Notifier<ColorSchemeState> {
  @override
  ColorSchemeState build() {
    return _createSchemes(ExtractedColors.defaultColors.dominant, false);
  }

  ColorSchemeState _createSchemes(Color seed, bool isAnimating) {
    return ColorSchemeState(
      light: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
      dark: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      isAnimating: isAnimating,
    );
  }

  void updateSeed(Color seed) {
    if (state.light.primary.toARGB32() == ColorScheme.fromSeed(seedColor: seed).primary.toARGB32()) {
      return; // Prevent triggering an animation if the dominant color leads to the same seed base
    }

    state = _createSchemes(seed, true);
    // Reset isAnimating after typical transition duration (350ms)
    // We use a small buffer margin to allow the UI to finish its animated widget frames
    Future.delayed(const Duration(milliseconds: 360), () {
      if (ref.mounted) {
        state = _createSchemes(seed, false);
      }
    });
  }
}

final colorSchemeProvider = NotifierProvider<ColorSchemeNotifier, ColorSchemeState>(ColorSchemeNotifier.new);

class ExtractedColorsNotifier extends Notifier<ExtractedColors> {
  @override
  ExtractedColors build() => ExtractedColors.defaultColors;

  void updateColors(ExtractedColors colors) {
    state = colors;
    ref.read(colorSchemeProvider.notifier).updateSeed(colors.dominant);
  }
}

final currentExtractedColorsProvider = NotifierProvider<ExtractedColorsNotifier, ExtractedColors>(ExtractedColorsNotifier.new);

class ColorExtractor {
  static int? _lastExtractedId;

  /// Colors are computed once per song and reused everywhere, so the theme is
  /// instant and consistent across the app.
  static final Map<int, ExtractedColors> _cache = {};

  static void extractColors(WidgetRef ref, int songId) {
    if (_lastExtractedId == songId) return;

    final cached = _cache[songId];
    if (cached != null) {
      _lastExtractedId = songId;
      ref.read(currentExtractedColorsProvider.notifier).updateColors(cached);
      return;
    }
    _doExtract(ref, songId);
  }

  static Future<void> extractFromBytes(WidgetRef ref, int songId, Uint8List bytes) async {
    if (_lastExtractedId == songId) return;
    _lastExtractedId = songId;
    final colors = await FastColorExtractor.extract(bytes);
    _cache[songId] = colors;
    ref.read(currentExtractedColorsProvider.notifier).updateColors(colors);
  }

  static Future<void> _doExtract(WidgetRef ref, int songId) async {
    try {
      _lastExtractedId = songId;
      // Reuse the shared artwork cache instead of a separate device query.
      final artworkBytes = await ArtworkCache.load(songId);
      if (artworkBytes == null) {
        ref.read(currentExtractedColorsProvider.notifier).updateColors(ExtractedColors.defaultColors);
        return;
      }
      final colors = await FastColorExtractor.extract(artworkBytes);
      _cache[songId] = colors;
      // Guard against a newer song having been requested meanwhile.
      if (_lastExtractedId == songId) {
        ref.read(currentExtractedColorsProvider.notifier).updateColors(colors);
      }
    } catch (e) {
      debugPrint('Error extracting colors: $e');
      ref.read(currentExtractedColorsProvider.notifier).updateColors(ExtractedColors.defaultColors);
    }
  }
}

class FastColorExtractor {
  /// Extracts a prominent, vibrant seed color from artwork bytes.
  ///
  /// Decodes a small 48x48 sample (cheap), then builds a histogram of quantized
  /// colors weighted by vibrancy. The winning bucket is the color that is both
  /// frequent and colorful, averaged for a clean result — far more accurate
  /// than picking a single outlier pixel from an 8x8 grid.
  static Future<ExtractedColors> extract(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 48,
        targetHeight: 48,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();

      if (byteData == null) return ExtractedColors.defaultColors;
      final pixels = byteData.buffer.asUint8List();

      // key -> [count, sumR, sumG, sumB, scoreSum]
      final Map<int, List<double>> buckets = {};
      double totalR = 0, totalG = 0, totalB = 0;
      int validCount = 0;
      double bestVibrantScore = -1.0;
      Color vibrant = ExtractedColors.defaultColors.vibrant;

      for (int i = 0; i < pixels.length; i += 4) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        final a = pixels[i + 3];
        if (a < 128) continue;

        totalR += r;
        totalG += g;
        totalB += b;
        validCount++;

        final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
        // Skip near-grey / near-black / near-white for seed selection.
        if (hsl.saturation < 0.15 || hsl.lightness < 0.12 || hsl.lightness > 0.88) {
          continue;
        }

        final lightnessScore = 1.0 - (hsl.lightness - 0.5).abs() * 2.0;
        final score = hsl.saturation * lightnessScore;

        // Quantize to 4 bits per channel so similar colors group together.
        final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
        final bucket = buckets.putIfAbsent(key, () => [0, 0, 0, 0, 0]);
        bucket[0] += 1;
        bucket[1] += r;
        bucket[2] += g;
        bucket[3] += b;
        bucket[4] += score;

        if (score > bestVibrantScore) {
          bestVibrantScore = score;
          vibrant = Color.fromARGB(255, r, g, b);
        }
      }

      Color dominant;
      if (buckets.isEmpty) {
        if (validCount == 0) return ExtractedColors.defaultColors;
        dominant = Color.fromARGB(
          255,
          (totalR / validCount).round(),
          (totalG / validCount).round(),
          (totalB / validCount).round(),
        );
        vibrant = dominant;
      } else {
        // Bucket with the highest summed vibrancy = prominent AND colorful.
        List<double>? best;
        for (final bucket in buckets.values) {
          if (best == null || bucket[4] > best[4]) best = bucket;
        }
        final count = best![0];
        dominant = Color.fromARGB(
          255,
          (best[1] / count).round(),
          (best[2] / count).round(),
          (best[3] / count).round(),
        );
      }

      final hslDominant = HSLColor.fromColor(dominant);
      final muted = hslDominant
          .withSaturation((hslDominant.saturation * 0.5).clamp(0.15, 0.4))
          .withLightness(0.3)
          .toColor();
      final darkVibrant = hslDominant
          .withSaturation((hslDominant.saturation * 1.2).clamp(0.3, 0.9))
          .withLightness(0.15)
          .toColor();

      return ExtractedColors(
        dominant: dominant,
        vibrant: vibrant,
        muted: muted,
        darkVibrant: darkVibrant,
      );
    } catch (_) {
      return ExtractedColors.defaultColors;
    }
  }
}
