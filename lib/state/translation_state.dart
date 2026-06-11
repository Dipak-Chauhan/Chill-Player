import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/translation_service.dart';
import 'audio_state.dart';
import 'lyrics_provider.dart';

/// Display modes matching YouLy+'s toggle system.
enum TranslationDisplayMode { none, translate, romanize, both }

/// Current translation display mode.
class TranslationModeNotifier extends Notifier<TranslationDisplayMode> {
  @override
  TranslationDisplayMode build() => TranslationDisplayMode.none;
  @override
  set state(TranslationDisplayMode value) => super.state = value;
}

final translationModeProvider =
    NotifierProvider<TranslationModeNotifier, TranslationDisplayMode>(
        TranslationModeNotifier.new);

/// Target language code for translations (default: English).
class TargetLanguageNotifier extends Notifier<String> {
  @override
  String build() => 'en';
  @override
  set state(String value) => super.state = value;
}

final targetLanguageProvider =
    NotifierProvider<TargetLanguageNotifier, String>(TargetLanguageNotifier.new);

class TranslationFetchingNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  @override
  set state(bool value) => super.state = value;
}
final translationFetchingProvider = NotifierProvider<TranslationFetchingNotifier, bool>(TranslationFetchingNotifier.new);

class RomanizationFetchingNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  @override
  set state(bool value) => super.state = value;
}
final romanizationFetchingProvider = NotifierProvider<RomanizationFetchingNotifier, bool>(RomanizationFetchingNotifier.new);

/// Combined loading status provider.
final translationLoadingProvider = Provider<bool>((ref) {
  final tr = ref.watch(translationFetchingProvider);
  final rm = ref.watch(romanizationFetchingProvider);
  return tr || rm;
});

/// Cached translation data for current song.
class TranslationDataNotifier extends Notifier<TranslationResult?> {
  @override
  TranslationResult? build() => null;
  @override
  set state(TranslationResult? value) => super.state = value;
}

final translationDataProvider =
    NotifierProvider<TranslationDataNotifier, TranslationResult?>(
        TranslationDataNotifier.new);

/// Cached romanization data for current song.
class RomanizationDataNotifier extends Notifier<TranslationResult?> {
  @override
  TranslationResult? build() => null;
  @override
  set state(TranslationResult? value) => super.state = value;
}

final romanizationDataProvider =
    NotifierProvider<RomanizationDataNotifier, TranslationResult?>(
        RomanizationDataNotifier.new);

/// Error message if translation failed.
class TranslationErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  @override
  set state(String? value) => super.state = value;
}

final translationErrorProvider =
    NotifierProvider<TranslationErrorNotifier, String?>(
        TranslationErrorNotifier.new);

/// Helper class that orchestrates translation fetches and state updates.
class TranslationController {
  final WidgetRef ref;
  const TranslationController(this.ref);

  /// Fetches translations for the current song's lyrics.
  Future<void> fetchTranslation() async {
    final song = ref.read(currentSongProvider);
    final lyricsAsync = ref.read(lyricsProvider);
    final targetLang = ref.read(targetLanguageProvider);

    if (song == null) return;

    final lyrics = lyricsAsync.value;
    if (lyrics == null || lyrics.isEmpty) return;

    ref.read(translationFetchingProvider.notifier).state = true;
    ref.read(translationErrorProvider.notifier).state = null;

    try {
      final lineTexts = lyrics.map((l) => l.text).toList();
      final result = await TranslationService.translate(
        lines: lineTexts,
        targetLang: targetLang,
        songTitle: song.title,
        songArtist: song.artist,
      );
      ref.read(translationDataProvider.notifier).state = result;
    } catch (e) {
      ref.read(translationErrorProvider.notifier).state =
          'Translation failed. Check your connection.';
    } finally {
      ref.read(translationFetchingProvider.notifier).state = false;
    }
  }

  /// Fetches romanization for the current song's lyrics.
  Future<void> fetchRomanization() async {
    final song = ref.read(currentSongProvider);
    final lyricsAsync = ref.read(lyricsProvider);

    if (song == null) return;

    final lyrics = lyricsAsync.value;
    if (lyrics == null || lyrics.isEmpty) return;

    ref.read(romanizationFetchingProvider.notifier).state = true;
    ref.read(translationErrorProvider.notifier).state = null;

    try {
      final result = await TranslationService.romanize(
        lyrics: lyrics,
        songTitle: song.title,
        songArtist: song.artist,
      );
      ref.read(romanizationDataProvider.notifier).state = result;
    } catch (e) {
      ref.read(translationErrorProvider.notifier).state =
          'Romanization failed. Check your connection.';
    } finally {
      ref.read(romanizationFetchingProvider.notifier).state = false;
    }
  }

  /// Toggles translation on/off, fetching if needed.
  Future<void> toggleTranslation() async {
    final mode = ref.read(translationModeProvider);
    final hasTranslation =
        mode == TranslationDisplayMode.translate ||
        mode == TranslationDisplayMode.both;

    if (hasTranslation) {
      ref.read(translationModeProvider.notifier).state =
          mode == TranslationDisplayMode.both
              ? TranslationDisplayMode.romanize
              : TranslationDisplayMode.none;
    } else {
      ref.read(translationModeProvider.notifier).state =
          mode == TranslationDisplayMode.romanize
              ? TranslationDisplayMode.both
              : TranslationDisplayMode.translate;

      if (ref.read(translationDataProvider) == null) {
        await fetchTranslation();
      }
    }
  }

  /// Toggles romanization on/off, fetching if needed.
  Future<void> toggleRomanization() async {
    final mode = ref.read(translationModeProvider);
    final hasRomanization =
        mode == TranslationDisplayMode.romanize ||
        mode == TranslationDisplayMode.both;

    if (hasRomanization) {
      ref.read(translationModeProvider.notifier).state =
          mode == TranslationDisplayMode.both
              ? TranslationDisplayMode.translate
              : TranslationDisplayMode.none;
    } else {
      ref.read(translationModeProvider.notifier).state =
          mode == TranslationDisplayMode.translate
              ? TranslationDisplayMode.both
              : TranslationDisplayMode.romanize;

      if (ref.read(romanizationDataProvider) == null) {
        await fetchRomanization();
      }
    }
  }

  /// Changes target language and re-fetches translation.
  Future<void> changeLanguage(String langCode) async {
    ref.read(targetLanguageProvider.notifier).state = langCode;
    ref.read(translationDataProvider.notifier).state = null;

    final mode = ref.read(translationModeProvider);
    if (mode == TranslationDisplayMode.translate ||
        mode == TranslationDisplayMode.both) {
      await fetchTranslation();
    }
  }

  /// Clears all translation state (call on song change).
  void clearForNewSong() {
    ref.read(translationDataProvider.notifier).state = null;
    ref.read(romanizationDataProvider.notifier).state = null;
    ref.read(translationErrorProvider.notifier).state = null;
    ref.read(translationFetchingProvider.notifier).state = false;
    ref.read(romanizationFetchingProvider.notifier).state = false;
  }
}
