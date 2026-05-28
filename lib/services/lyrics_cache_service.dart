import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
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
        romanizedWords: (json['romanizedWords'] as List?)
            ?.map((e) => e == null ? null : List<String>.from(e as List))
            .toList() ?? const [],
        detectedLanguage: json['detectedLanguage'] ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
