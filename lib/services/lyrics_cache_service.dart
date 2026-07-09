import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/lyric_line.dart';
import 'translation_service.dart';

/// Local file-based caching for translation and romanization results
/// stored under the application's temporary cache directory.
class LyricsCacheService {
  static Directory? _cacheDir;

  /// Retrieves the cache directory, creating it recursively if needed.
  static Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final tempDir = await getTemporaryDirectory();
    _cacheDir = Directory('${tempDir.path}/lyrics_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  /// Sanitizes key string to be safe for filenames.
  static String _sanitizeFileName(String key) {
    return key.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }

  /// Generates a standardized cache key based on song meta.
  static String getCacheKey({
    required String title,
    required String artist,
    required String action,
    required String lang,
  }) {
    return '${title.toLowerCase()}|${artist.toLowerCase()}|$action|$lang';
  }

  /// Saves a translation or romanization result asynchronously to a cache file.
  static Future<void> save(String key, TranslationResult result) async {
    try {
      final dir = await _getCacheDir();
      final fileName = _sanitizeFileName(key);
      final file = File('${dir.path}/$fileName.json');

      final data = {
        'translations': result.translations,
        'romanizations': result.romanizations,
        'romanizedWords': result.romanizedWords,
        'detectedLanguage': result.detectedLanguage,
      };

      await file.writeAsString(jsonEncode(data));
    } catch (_) {
      // Fail silently on cache write issues so it doesn't disrupt user flow
    }
  }

  /// Cache key for a song's parsed lyrics.
  static String getLyricsKey({
    required String title,
    required String artist,
    required Duration duration,
  }) {
    return 'lyrics_${title.toLowerCase()}_${artist.toLowerCase()}_${duration.inSeconds}';
  }

  /// Persists parsed lyric lines so a song is only fetched from the network
  /// once. This keeps word-by-word lyrics reliable even when upstream APIs
  /// rate-limit after a few requests.
  static Future<void> saveLyrics(String key, List<LyricLine> lines) async {
    if (lines.isEmpty) return;
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_sanitizeFileName(key)}.json');
      await file.writeAsString(
        jsonEncode(lines.map((l) => l.toJson()).toList()),
      );
    } catch (_) {
      // Non-fatal: a failed cache write just means we refetch next time.
    }
  }

  /// Loads cached lyric lines, or null on a miss/parse error.
  static Future<List<LyricLine>?> loadLyrics(String key) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_sanitizeFileName(key)}.json');
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is! List || data.isEmpty) return null;
      return data
          .map((e) => LyricLine.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Loads a cached translation/romanization result. Returns null on a cache miss or parse error.
  static Future<TranslationResult?> load(String key) async {
    try {
      final dir = await _getCacheDir();
      final fileName = _sanitizeFileName(key);
      final file = File('${dir.path}/$fileName.json');

      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      return TranslationResult(
        translations: List<String>.from(json['translations'] ?? []),
        romanizations: List<String?>.from(json['romanizations'] ?? []),
        romanizedWords:
            (json['romanizedWords'] as List?)
                ?.map((e) => e == null ? null : List<String>.from(e as List))
                .toList() ??
            const [],
        detectedLanguage: json['detectedLanguage'] ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
