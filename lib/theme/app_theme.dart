import 'package:flutter/material.dart';
import 'package:tofu_expressive/tofu_expressive.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData buildTheme(Color seedColor, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Use TofuTheme as the base
    final base = isDark
        ? TofuTheme.dark(seedColor: seedColor)
        : TofuTheme.light(seedColor: seedColor);

    final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);

    final textTheme = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    final sourceFont = GoogleFonts.outfitTextTheme(textTheme);
    final font = sourceFont.copyWith(
      displayLarge: sourceFont.displayLarge?.copyWith(fontSize: 57, fontWeight: FontWeight.w700),
      displayMedium: sourceFont.displayMedium?.copyWith(fontSize: 45, fontWeight: FontWeight.w700),
      displaySmall: sourceFont.displaySmall?.copyWith(fontSize: 36, fontWeight: FontWeight.w600),
      headlineLarge: sourceFont.headlineLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w600),
      headlineMedium: sourceFont.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w500),
      headlineSmall: sourceFont.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w500),
      titleLarge: sourceFont.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w500),
      titleMedium: sourceFont.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
      titleSmall: sourceFont.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      bodyLarge: sourceFont.bodyLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: sourceFont.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: sourceFont.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w400),
      labelLarge: sourceFont.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium: sourceFont.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: sourceFont.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w500),
    );

    return base.copyWith(
      colorScheme: scheme,
      textTheme: font,
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        color: scheme.surfaceContainerHighest,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: font.headlineSmall?.copyWith(color: scheme.onSurface),
      ),
    );
  }
}
