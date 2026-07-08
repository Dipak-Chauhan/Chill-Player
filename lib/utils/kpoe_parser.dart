import '../models/lyric_line.dart';

/// Parses the LyricsPlus (KPOE) `/v2/lyrics/get` JSON format into [LyricLine]s.
///
/// The payload looks like:
/// ```json
/// {
///   "type": "Word" | "Line" | "Syllable" | "Plain",
///   "lyrics": [
///     {
///       "text": "full line",
///       "time": 12345,       // ms, absolute
///       "duration": 3000,    // ms
///       "syllabus": [
///         {"text": "Word ", "time": 12345, "duration": 300, "isBackground": false}
///       ],
///       "element": {"singer": "v1"}
///     }
///   ],
///   "metadata": { ... }
/// }
/// ```
/// Syllable times are absolute milliseconds (same clock as the line). Syllables
/// flagged `isBackground` are split off into a background line so the renderer
/// can show them separately.
class KpoeParser {
  static List<LyricLine> parse(Map<String, dynamic> data) {
    final rawLines = data['lyrics'];
    if (rawLines is! List || rawLines.isEmpty) return [];

    final List<LyricLine> lines = [];

    for (final item in rawLines) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();

      final int lineStartMs = _toInt(map['time']);
      final int lineDurMs = _toInt(map['duration']);

      String? singer;
      final element = map['element'];
      if (element is Map && element['singer'] != null) {
        final s = element['singer'].toString().trim();
        if (s.isNotEmpty) singer = s;
      }

      final List<LyricWord> mainWords = [];
      final List<LyricWord> bgWords = [];
      int? bgStartMs;
      int? bgEndMs;

      final syllabus = map['syllabus'];
      if (syllabus is List) {
        for (final s in syllabus) {
          if (s is! Map) continue;
          final text = (s['text'] ?? '').toString();
          if (text.trim().isEmpty) continue;
          final startMs = _toInt(s['time']);
          final durMs = _toInt(s['duration']);
          final endMs = startMs + (durMs > 0 ? durMs : 0);
          final word = LyricWord(
            startTime: Duration(milliseconds: startMs),
            endTime: Duration(milliseconds: endMs),
            text: text,
          );
          if (s['isBackground'] == true) {
            bgWords.add(word);
            bgStartMs = bgStartMs == null
                ? startMs
                : (startMs < bgStartMs ? startMs : bgStartMs);
            bgEndMs = bgEndMs == null
                ? endMs
                : (endMs > bgEndMs ? endMs : bgEndMs);
          } else {
            mainWords.add(word);
          }
        }
      }

      // Main text: prefer joining main syllables (keeps it in sync with the
      // word-by-word render and excludes background parentheticals); otherwise
      // fall back to the line's own text.
      String text = mainWords.isNotEmpty
          ? mainWords.map((w) => w.text).join().trim()
          : (map['text'] ?? '').toString().trim();

      final int lineEndMs = mainWords.isNotEmpty
          ? mainWords.last.endTime.inMilliseconds
          : lineStartMs + (lineDurMs > 0 ? lineDurMs : 3000);

      List<LyricLine>? bgLines;
      if (bgWords.isNotEmpty) {
        final bgText = bgWords.map((w) => w.text).join().trim();
        if (bgText.isNotEmpty) {
          bgLines = [
            LyricLine(
              startTime: Duration(milliseconds: bgStartMs ?? lineStartMs),
              endTime: Duration(milliseconds: bgEndMs ?? lineEndMs),
              text: bgText,
              words: bgWords,
            ),
          ];
        }
      }

      if (text.isEmpty && bgLines == null) continue;

      lines.add(
        LyricLine(
          startTime: Duration(milliseconds: lineStartMs),
          endTime: Duration(milliseconds: lineEndMs),
          text: text,
          words: mainWords.isNotEmpty ? mainWords : null,
          backgroundLines: bgLines,
          singer: singer,
        ),
      );
    }

    return lines;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return double.tryParse(v)?.round() ?? 0;
    return 0;
  }
}
