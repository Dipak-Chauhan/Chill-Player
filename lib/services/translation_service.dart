import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/lyric_line.dart';
import 'lyrics_cache_service.dart';

/// Result of a translation/romanization operation.
class TranslationResult {
  final List<String> translations;
  final List<String?> romanizations;
  final List<List<String>?> romanizedWords;
  final String detectedLanguage;

  const TranslationResult({
    required this.translations,
    this.romanizations = const [],
    this.romanizedWords = const [],
    this.detectedLanguage = '',
  });
}

/// Supported target languages for translation.
const Map<String, String> supportedLanguages = {
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh-CN': 'Chinese',
  'hi': 'Hindi',
  'ar': 'Arabic',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'tr': 'Turkish',
  'it': 'Italian',
  'th': 'Thai',
  'vi': 'Vietnamese',
  'id': 'Indonesian',
};

/// Translation service using Google Translate free API.
/// Supports batch translation with chunking and in-memory caching.
class TranslationService {
  static final Map<String, TranslationResult> _cache = {};

  static void clearCache() => _cache.clear();

  /// Translates lyric lines to the target language.
  static Future<TranslationResult> translate({
    required List<String> lines,
    required String targetLang,
    required String songTitle,
    required String songArtist,
  }) async {
    final cacheKey = _key(songTitle, songArtist, 'tr', targetLang);
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      // Invalidate cache if it was an empty English misdetection on a non-English song
      if (targetLang == 'en' &&
          cached.detectedLanguage == 'en' &&
          !isEnglishLyrics(lines) &&
          cached.translations.every((t) => t.isEmpty)) {
        // Fall through to re-fetch
      } else {
        return cached;
      }
    }

    final persistentCached = await LyricsCacheService.load(cacheKey);
    if (persistentCached != null) {
      // Invalidate persistent cache if it was an empty English misdetection on a non-English song
      if (targetLang == 'en' &&
          persistentCached.detectedLanguage == 'en' &&
          !isEnglishLyrics(lines) &&
          persistentCached.translations.every((t) => t.isEmpty)) {
        // Fall through to re-fetch and overwrite
      } else {
        _cache[cacheKey] = persistentCached;
        return persistentCached;
      }
    }

    // Pre-detection: If target language is English and source lyrics are locally detected as English, skip
    if (targetLang == 'en' && isEnglishLyrics(lines)) {
      final out = TranslationResult(
        translations: List.filled(lines.length, ''),
        detectedLanguage: 'en',
      );
      _cache[cacheKey] = out;
      await LyricsCacheService.save(cacheKey, out);
      return out;
    }

    final indexed = _filterLines(lines);
    if (indexed.isEmpty) {
      return _empty(lines.length);
    }

    final texts = indexed.values.toList();
    final translated = await _batchTranslate(texts, targetLang);

    // Post-detection: If Google Translate detected the source language matching target language, skip.
    // For English target language, we trust our local isEnglishLyrics detection to prevent skipping mixed songs.
    final bool shouldSkip = (translated.detectedLang == targetLang) &&
        (targetLang != 'en' || isEnglishLyrics(lines));
    if (shouldSkip) {
      final out = TranslationResult(
        translations: List.filled(lines.length, ''),
        detectedLanguage: translated.detectedLang,
      );
      _cache[cacheKey] = out;
      await LyricsCacheService.save(cacheKey, out);
      return out;
    }

    final result = List<String>.filled(lines.length, '');
    final keys = indexed.keys.toList();
    for (int i = 0; i < keys.length && i < translated.lines.length; i++) {
      result[keys[i]] = translated.lines[i];
    }

    final out = TranslationResult(
      translations: result,
      detectedLanguage: translated.detectedLang,
    );
    _cache[cacheKey] = out;
    await LyricsCacheService.save(cacheKey, out);
    return out;
  }

  /// Romanizes lyric lines and provides word-synced syllable mapping.
  static Future<TranslationResult> romanize({
    required List<LyricLine> lyrics,
    required String songTitle,
    required String songArtist,
  }) async {
    final cacheKey = _key(songTitle, songArtist, 'rm', '');
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    final persistentCached = await LyricsCacheService.load(cacheKey);
    if (persistentCached != null) {
      _cache[cacheKey] = persistentCached;
      return persistentCached;
    }

    final textsToFetch = <String>[];
    final lineIndices = <int, int>{};
    final wordIndices = <int, List<int>>{};

    // Extract all translatable lines and syllables
    for (int i = 0; i < lyrics.length; i++) {
      final line = lyrics[i];
      final t = line.text.trim();
      
      if (t.isNotEmpty && !line.isGap && !_isPurelyLatin(t)) {
        lineIndices[i] = textsToFetch.length;
        textsToFetch.add(t);
        
        final words = line.words;
        if (words != null && words.isNotEmpty) {
           final wInd = <int>[];
           for (final word in words) {
             final wText = word.text.trim();
             if (wText.isNotEmpty) {
               wInd.add(textsToFetch.length);
               textsToFetch.add(wText);
             } else {
               wInd.add(-1);
             }
           }
           wordIndices[i] = wInd;
        }
      }
    }

    if (textsToFetch.isEmpty) {
      return _empty(lyrics.length);
    }

    final romanized = await _batchRomanize(textsToFetch);
    final fetched = romanized.lines;

    final resultLines = List<String?>.filled(lyrics.length, null);
    final resultWords = List<List<String>?>.filled(lyrics.length, null);

    // Repack and align structurally
    for (int i = 0; i < lyrics.length; i++) {
       final lIndex = lineIndices[i];
       if (lIndex != null && lIndex < fetched.length) {
          final fullRom = fetched[lIndex].trim();
          if (fullRom.isNotEmpty) resultLines[i] = fullRom;
          
          final wInds = wordIndices[i];
          if (wInds != null) {
             final isolated = <String>[];
             for (final win in wInds) {
                if (win == -1 || win >= fetched.length) {
                   isolated.add("");
                } else {
                   isolated.add(fetched[win].trim());
                }
             }
             resultWords[i] = _alignRomanizationAnchors(fullRom, isolated, lyrics[i].words!);
          }
       }
    }

    final out = TranslationResult(
      translations: List.filled(lyrics.length, ''),
      romanizations: resultLines,
      romanizedWords: resultWords,
      detectedLanguage: romanized.detectedLang,
    );
    _cache[cacheKey] = out;
    await LyricsCacheService.save(cacheKey, out);
    return out;
  }

  /// Detects if lyrics are primarily English using common stop words and script script checks.
  static bool isEnglishLyrics(List<String> lines) {
    if (lines.isEmpty) return false;

    // 1. Calculate Latin character ratio to avoid misclassifying space-less scripts like Japanese/Chinese
    int latinChars = 0;
    int totalChars = 0;

    for (final line in lines) {
      for (final char in line.runes) {
        // Skip whitespace in character count to avoid padding bias
        if (char == 0x0020 || char == 0x000A || char == 0x000D) {
          continue;
        }
        totalChars++;
        if ((char >= 0x0000 && char <= 0x024F) || char == 0x2019 || char == 0x2018) {
          latinChars++;
        }
      }
    }

    if (totalChars == 0) return false;
    final latinRatio = latinChars / totalChars;

    // If it is not primarily Latin script characters, it is definitely not an English song.
    if (latinRatio < 0.85) return false;

    // 2. Check English stop words ratio among space-separated words.
    final englishWords = {
      'the', 'and', 'you', 'i', 'to', 'a', 'me', 'my', 'it', 'in', 'is', 'of',
      'that', 'this', 'on', 'with', 'we', 'your', 'love', 'know', 'like', 'so',
      'oh', 'was', 'for', 'but', 'what', 'all', 'dont', 'do', 'are', 'just',
      'can', 'cant', 'will', 'no', 'yes', 'he', 'she', 'they', 'them'
    };

    int englishWordCount = 0;
    int totalWords = 0;

    for (final line in lines) {
      final words = line
          .toLowerCase()
          .replaceAll(RegExp(r"[^a-z\s']"), '')
          .split(RegExp(r'\s+'));
      for (final word in words) {
        if (word.isEmpty) continue;
        totalWords++;
        if (englishWords.contains(word)) {
          englishWordCount++;
        }
      }
    }

    if (totalWords == 0) return false;
    final ratio = englishWordCount / totalWords;
    return ratio > 0.08;
  }

  // Private helpers

  static String _key(String title, String artist, String action, String lang) =>
      '${title.toLowerCase()}|${artist.toLowerCase()}|$action|$lang';

  static TranslationResult _empty(int len) => TranslationResult(
        translations: List.filled(len, ''),
        romanizations: List.filled(len, null),
        romanizedWords: List.filled(len, null),
      );

  static Map<int, String> _filterLines(List<String> lines) {
    final map = <int, String>{};
    for (int i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.isNotEmpty && t != '• • •') map[i] = t;
    }
    return map;
  }

  static bool _isPurelyLatin(String text) {
    for (final c in text.runes) {
      if (c > 0x024F &&
          c != 0x0027 &&
          c != 0x2019 &&
          !(c >= 0x0020 && c <= 0x007E) &&
          !(c >= 0x00C0 && c <= 0x024F)) {
        return false;
      }
    }
    return true;
  }

  /// Detects if text is RTL (Arabic, Hebrew, Farsi, Urdu, etc.)
  static bool isRtlText(String text) {
    for (final c in text.runes) {
      if ((c >= 0x0590 && c <= 0x05FF) || // Hebrew
          (c >= 0x0600 && c <= 0x06FF) || // Arabic
          (c >= 0x0700 && c <= 0x074F) || // Syriac
          (c >= 0xFB50 && c <= 0xFDFF) || // Arabic Presentation A
          (c >= 0xFE70 && c <= 0xFEFF)) { // Arabic Presentation B
        return true;
      }
    }
    return false;
  }

  static int _levenshteinDistance(String s, String t) {
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.filled(t.length + 1, 0);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < v0.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        int min1 = v1[j] + 1;
        int min2 = v0[j + 1] + 1;
        int min3 = v0[j] + cost;
        int min = min1 < min2 ? min1 : min2;
        v1[j + 1] = min < min3 ? min : min3;
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }

  static double _calculateMatchCost(String candidate, String guide, bool isLatin) {
    final cTrim = candidate.trim();
    final gTrim = guide.trim();

    if (cTrim.isEmpty && gTrim.isNotEmpty) return 50.0;

    final cLower = cTrim.toLowerCase();
    final gLower = gTrim.toLowerCase();
    final dist = _levenshteinDistance(cLower, gLower).toDouble();

    if (isLatin) {
      // High penalty for Latin mismatches to keep strict alignment
      return dist * 50.0 + ((candidate.length - guide.length).abs() * 0.5);
    }

    final lenDiff = (cTrim.length - gTrim.length).abs().toDouble();
    final hasTrailingSpace = candidate.endsWith(" ");
    final bonus = hasTrailingSpace ? -0.5 : 0.0;

    return dist + (lenDiff * 0.8) + bonus;
  }

  static List<String> _alignRomanizationAnchors(String fullText, List<String> guides, List<LyricWord> originalWords) {
    final target = fullText;
    final int N = target.length;
    final int M = guides.length;

    if (M == 0) return [];
    if (N == 0) return List<String>.filled(M, "");

    const double maxCost = 1000000.0; // Avoid overflow
    final dp = List.generate(M + 1, (_) => List.filled(N + 1, maxCost));
    final path = List.generate(M + 1, (_) => List.filled(N + 1, -1));

    dp[0][0] = 0.0;

    for (int i = 1; i <= M; i++) {
        final guideRom = guides[i - 1];
        final isLatin = _isPurelyLatin(originalWords[i - 1].text);
        final guideLen = guideRom.length;

        final int minLen = isLatin ? math.max(1, guideLen - 1) : 1;
        final int maxLen = isLatin ? guideLen + 3 : math.max(guideLen * 3 + 3, 15);

        for (int j = 1; j <= N; j++) {
            double bestLocalCost = maxCost;
            int bestPrevJ = -1;

            for (int len = minLen; len <= maxLen; len++) {
                final int k = j - len;
                if (k < 0) break;
                if (dp[i - 1][k] >= maxCost) continue;

                final candidate = target.substring(k, j);
                final segmentCost = _calculateMatchCost(candidate, guideRom, isLatin);
                final totalCost = dp[i - 1][k] + segmentCost;

                if (totalCost < bestLocalCost) {
                    bestLocalCost = totalCost;
                    bestPrevJ = k;
                }
            }
            dp[i][j] = bestLocalCost;
            path[i][j] = bestPrevJ;
        }
    }

    final results = List<String>.filled(M, "");
    int currJ = N;

    if (dp[M][N] >= maxCost) {
        double minEndCost = maxCost;
        for (int k = N; k >= 0; k--) {
            if (dp[M][k] < minEndCost) {
                minEndCost = dp[M][k];
                currJ = k;
            }
        }
    }

    for (int i = M; i > 0; i--) {
        final int prevJ = path[i][currJ];
        if (prevJ == -1) {
            results[i - 1] = "";
        } else {
            results[i - 1] = target.substring(prevJ, currJ);
            currJ = prevJ;
        }
    }

    if (currJ > 0 && results.isNotEmpty) {
        results[0] = target.substring(0, currJ) + results[0];
    }
    final totalLen = results.join("").length;
    if (totalLen < N && results.isNotEmpty) {
        results[results.length - 1] += target.substring(totalLen);
    }

    return results;
  }

  // Google Translate API

  static Future<_BatchResult> _batchTranslate(List<String> texts, String targetLang) async {
    final chunks = _chunk(texts, 1200);
    final allLines = <String>[];
    String detectedLang = '';

    for (final chunk in chunks) {
      final batch = chunk.join('\n');
      final resp = await _callApi(batch, targetLang);
      allLines.addAll(resp.lines);
      if (detectedLang.isEmpty) detectedLang = resp.detectedLang;
    }

    return _BatchResult(lines: allLines, detectedLang: detectedLang);
  }

  static Future<_BatchResult> _batchRomanize(List<String> texts) async {
    final allLines = <String>[];
    String detectedLang = '';

    // Process in batches of 50 to avoid rate limits
    for (int i = 0; i < texts.length; i += 50) {
      final end = (i + 50 > texts.length) ? texts.length : i + 50;
      final batch = texts.sublist(i, end);
      
      final batchText = batch.join(' | ');
      
      try {
        final resp = await _callApiWithRomanization(batchText);
        if (detectedLang.isEmpty) detectedLang = resp.detectedLang;
        
        final rawStr = resp.lines.join('');
        // API may insert spaces: "hello | world | test"
        final parts = rawStr.replaceAll(RegExp(r'\s*\|\s*'), '|').split('|');
        
        for (int b = 0; b < batch.length; b++) {
           if (b < parts.length && parts[b].isNotEmpty && parts[b] != 'null') {
              allLines.add(parts[b].trim());
           } else {
              allLines.add(batch[b]);
           }
        }
      } catch (e) {
        // Fallback on error
        allLines.addAll(batch);
      }
      
      await Future.delayed(const Duration(milliseconds: 200));
    }

    return _BatchResult(lines: allLines, detectedLang: detectedLang);
  }

  static List<List<String>> _chunk(List<String> lines, int maxChars) {
    final chunks = <List<String>>[];
    var current = <String>[];
    int len = 0;
    for (final line in lines) {
      if (len + line.length + 1 > maxChars && current.isNotEmpty) {
        chunks.add(current);
        current = [];
        len = 0;
      }
      current.add(line);
      len += line.length + 1;
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  /// Calls Google Translate free API for translation.
  static Future<_BatchResult> _callApi(String text, String targetLang) async {
    final uri = Uri.parse(
      'https://translate.googleapis.com/translate_a/single'
      '?client=gtx&sl=auto&tl=$targetLang&dt=t'
      '&q=${Uri.encodeComponent(text)}',
    );

    final response = await http
        .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Translation failed: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    final buf = StringBuffer();

    if (data is List && data.isNotEmpty && data[0] is List) {
      for (final seg in data[0]) {
        if (seg is List && seg.isNotEmpty && seg[0] is String) {
          buf.write(seg[0]);
        }
      }
    }

    final lines = buf.toString().split('\n').map((l) => l.trim()).toList();
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }

    final lang = (data is List && data.length > 2 && data[2] is String)
        ? data[2] as String
        : '';

    return _BatchResult(lines: lines, detectedLang: lang);
  }

  /// Calls Google Translate with romanization (dt=rm) to get src_translit.
  static Future<_BatchResult> _callApiWithRomanization(String text) async {
    final uri = Uri.parse(
      'https://translate.googleapis.com/translate_a/single'
      '?client=gtx&sl=auto&tl=en&dt=rm'
      '&q=${Uri.encodeComponent(text)}',
    );

    final response = await http
        .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Romanization failed: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    String detectedLang = '';

    if (data is List && data.length > 2 && data[2] is String) {
      detectedLang = data[2] as String;
    }

    // Try to extract romanization from the response array.
    // With dt=rm, romanization may appear at various indices.
    // Common positions: data[0] segments may contain it in index [3],
    // or it appears as a separate element in the outer array.
    final romanLines = <String>[];

    // Method 1: Check data[0] segments for romanized source text (index 3 or fallback to index 0)
    if (data is List && data.isNotEmpty && data[0] is List) {
      final buf = StringBuffer();
      bool found = false;
      for (final seg in data[0]) {
        if (seg is List && seg.isNotEmpty) {
          final s3 = (seg.length > 3 && seg[3] is String) ? seg[3] : null;
          final s0 = (seg[0] is String) ? seg[0] : null;
          final val = s3 ?? s0 ?? '';
          buf.write(val);
          found = true;
        }
      }
      if (found) {
        romanLines.addAll(buf.toString().split('\n').map((l) => l.trim()));
      }
    }

    // Fallback: if no romanization found, return empty
    while (romanLines.isNotEmpty && romanLines.last.isEmpty) {
      romanLines.removeLast();
    }

    return _BatchResult(lines: romanLines, detectedLang: detectedLang);
  }
}

class _BatchResult {
  final List<String> lines;
  final String detectedLang;
  const _BatchResult({required this.lines, required this.detectedLang});
}
