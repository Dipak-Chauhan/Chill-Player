import 'dart:convert';
import '../models/lyric_line.dart';

/// Parses Musixmatch `track.richsync.get` bodies (word-by-word timing) into
/// [LyricLine]s.
///
/// The body is a JSON array of lines:
/// ```json
/// [{"ts":5.33,"te":6.68,"x":"full line","l":[{"c":"'Cause","o":0},{"c":" ","o":0.19}]}]
/// ```
/// where `ts`/`te` are the line start/end in seconds and each `l` entry is a
/// text chunk `c` with offset `o` (seconds) from `ts`. Whitespace chunks only
/// mark gaps, so they are dropped — the renderer re-derives word end times from
/// the following word's start.
class MusixmatchParser {
  static List<LyricLine> parseRichsync(String body) {
    dynamic data;
    try {
      data = json.decode(body);
    } catch (_) {
      return [];
    }
    if (data is! List) return [];

    final List<LyricLine> lines = [];
    for (final item in data) {
      if (item is! Map) continue;
      final double ts = _toDouble(item['ts']);
      final double te = _toDouble(item['te']);
      final String lineText = (item['x'] ?? '').toString().trim();

      final List<LyricWord> words = [];
      final chunks = item['l'];
      if (chunks is List) {
        for (int i = 0; i < chunks.length; i++) {
          final chunk = chunks[i];
          if (chunk is! Map) continue;
          final String c = (chunk['c'] ?? '').toString();
          if (c.trim().isEmpty) continue; // whitespace chunk → skip
          final double o = _toDouble(chunk['o']);
          final double nextO = _nextNonSpaceOffset(chunks, i + 1, te - ts);
          words.add(
            LyricWord(
              startTime: Duration(milliseconds: ((ts + o) * 1000).round()),
              endTime: Duration(milliseconds: ((ts + nextO) * 1000).round()),
              text: c.trim(),
            ),
          );
        }
      }

      if (lineText.isEmpty && words.isEmpty) continue;

      lines.add(
        LyricLine(
          startTime: Duration(milliseconds: (ts * 1000).round()),
          endTime: Duration(milliseconds: (te * 1000).round()),
          text: lineText.isNotEmpty
              ? lineText
              : words.map((w) => w.text).join(' ').trim(),
          words: words.isNotEmpty ? words : null,
        ),
      );
    }
    return lines;
  }

  /// Offset of the next chunk (used as the current word's end); falls back to
  /// [lineSpan] for the final word.
  static double _nextNonSpaceOffset(List chunks, int from, double lineSpan) {
    for (int i = from; i < chunks.length; i++) {
      final chunk = chunks[i];
      if (chunk is Map) return _toDouble(chunk['o']);
    }
    return lineSpan;
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}
