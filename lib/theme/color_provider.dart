import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';

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

  static void extractColors(WidgetRef ref, int songId) {
    if (_lastExtractedId == songId) return;
    _doExtract(ref, songId);
  }

  static Future<void> extractFromBytes(WidgetRef ref, int songId, Uint8List bytes) async {
    if (_lastExtractedId == songId) return;
    _lastExtractedId = songId;
    await _generateAndApply(ref, bytes);
  }

  static Future<void> _doExtract(WidgetRef ref, int songId) async {
    try {
      _lastExtractedId = songId;
      final artworkBytes = await OnAudioQuery().queryArtwork(songId, ArtworkType.AUDIO, size: 100);
      if (artworkBytes == null) {
        ref.read(currentExtractedColorsProvider.notifier).updateColors(ExtractedColors.defaultColors);
        return;
      }
      await _generateAndApply(ref, artworkBytes);
    } catch (e) {
      debugPrint('Error extracting colors: $e');
      ref.read(currentExtractedColorsProvider.notifier).updateColors(ExtractedColors.defaultColors);
    }
  }

  static Future<void> _generateAndApply(WidgetRef ref, Uint8List artworkBytes) async {
    final colors = await FastColorExtractor.extract(artworkBytes);
    ref.read(currentExtractedColorsProvider.notifier).updateColors(colors);
  }
}

class FastColorExtractor {
  static Future<ExtractedColors> extract(Uint8List bytes) async {
    try {
      // 1. Natively downsample the image bytes to a tiny 8x8 grid in C++
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 8,
        targetHeight: 8,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose(); // Instantly free native resource to prevent any GPU memory leak
      
      if (byteData == null) return ExtractedColors.defaultColors;
      final pixels = byteData.buffer.asUint8List();
      
      double maxScore = -1.0;
      Color bestColor = ExtractedColors.defaultColors.dominant;
      
      double totalR = 0;
      double totalG = 0;
      double totalB = 0;
      int validPixelCount = 0;

      // 2. Loop over the 64 pixels to score their color vibrancy and lightness
      for (int i = 0; i < pixels.length; i += 4) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        final a = pixels[i + 3];
        
        if (a < 128) continue; // Ignore transparent pixels
        
        totalR += r;
        totalG += g;
        totalB += b;
        validPixelCount++;
        
        final color = Color.fromARGB(255, r, g, b);
        final hsl = HSLColor.fromColor(color);
        
        // Exclude dull shades (grey, black, white) for dynamic theme seed matching
        if (hsl.saturation < 0.15 || hsl.lightness < 0.12 || hsl.lightness > 0.88) {
          continue;
        }
        
        // High scores are given to highly-saturated, centered-lightness colors
        final lightnessScore = 1.0 - (hsl.lightness - 0.5).abs() * 2.0;
        final score = hsl.saturation * lightnessScore;
        
        if (score > maxScore) {
          maxScore = score;
          bestColor = color;
        }
      }
      
      Color dominantColor;
      if (validPixelCount > 0 && maxScore < 0.0) {
        // Fallback: use average color if no colorful pixels were found
        final avgR = (totalR / validPixelCount).round();
        final avgG = (totalG / validPixelCount).round();
        final avgB = (totalB / validPixelCount).round();
        dominantColor = Color.fromARGB(255, avgR, avgG, avgB);
        bestColor = dominantColor;
      } else {
        dominantColor = bestColor;
      }
      
      // 3. Derive gorgeous complementary palette levels instantly using HSL shifts
      final hslDominant = HSLColor.fromColor(dominantColor);
      final muted = hslDominant.withSaturation((hslDominant.saturation * 0.5).clamp(0.15, 0.4)).withLightness(0.3).toColor();
      final darkVibrant = hslDominant.withSaturation((hslDominant.saturation * 1.2).clamp(0.3, 0.9)).withLightness(0.15).toColor();
      
      return ExtractedColors(
        dominant: dominantColor,
        vibrant: bestColor,
        muted: muted,
        darkVibrant: darkVibrant,
      );
    } catch (_) {
      return ExtractedColors.defaultColors;
    }
  }
}
