import 'package:flutter/services.dart';

/// Centralized service to manage premium, Google Pixel-like tactile haptic feedback
/// across the entire Chill Player application.
class HapticService {
  /// A light, crisp tick for letter index scroll transitions or subtle progress bar ticks.
  static Future<void> tick() async {
    await HapticFeedback.selectionClick();
  }

  /// A delicate impact for grabbing handles, sliders, or minor button focus changes.
  static Future<void> light() async {
    await HapticFeedback.lightImpact();
  }

  /// A medium-weight impact for standard button taps, toggles (like Shuffle), or tab swaps.
  static Future<void> medium() async {
    await HapticFeedback.mediumImpact();
  }

  /// A solid, high-tactility impact for major events like long-presses or dismissing playback.
  static Future<void> heavy() async {
    await HapticFeedback.heavyImpact();
  }
}
