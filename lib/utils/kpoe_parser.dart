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

    final Map<String, String> agentTypes = {};
    final metadata = data['metadata'];
    if (metadata is Map && metadata['agents'] is Map) {
      final agentsMap = metadata['agents'] as Map;
      agentsMap.forEach((key, val) {
        if (val is Map && val['type'] != null) {
          agentTypes[key.toString()] = val['type'].toString();
        }
      });
    }

    final List<String?> lineSingers = [];
    for (final item in rawLines) {
      if (item is! Map) {
        lineSingers.add(null);
        continue;
      }
      String? singer;
      final element = item['element'];
      if (element is Map && element['singer'] != null) {
        final s = element['singer'].toString().trim();
        if (s.isNotEmpty) singer = s;
      }
      lineSingers.add(singer);
    }

    final alignments = calculateLineAlignments(lineSingers, agentTypes);
    final List<LyricLine> lines = [];

    for (int idx = 0; idx < rawLines.length; idx++) {
      final item = rawLines[idx];
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();

      final int lineStartMs = _toInt(map['time']);
      final int lineDurMs = _toInt(map['duration']);
      final String? singer = lineSingers[idx];
      final String? singerSide = alignments[idx];

      final transliteration = map['transliteration'];
      List<String?>? romanizedWords;
      if (transliteration is Map) {
        final transSyllables = transliteration['syllabus'];
        if (transSyllables is List) {
          romanizedWords = transSyllables.map((s) {
            if (s is Map) {
              return (s['text'] ?? '').toString();
            }
            return null;
          }).toList();
        }
      }

      final List<LyricWord> mainWords = [];
      final List<LyricWord> bgWords = [];
      int? bgStartMs;
      int? bgEndMs;

      final syllabus = map['syllabus'];
      if (syllabus is List) {
        int mainWordIdx = 0;
        for (final s in syllabus) {
          if (s is! Map) continue;
          final text = (s['text'] ?? '').toString();
          if (text.trim().isEmpty) continue;
          final startMs = _toInt(s['time']);
          final durMs = _toInt(s['duration']);
          final endMs = startMs + (durMs > 0 ? durMs : 0);
          
          if (s['isBackground'] == true) {
            final word = LyricWord(
              startTime: Duration(milliseconds: startMs),
              endTime: Duration(milliseconds: endMs),
              text: text,
            );
            bgWords.add(word);
            bgStartMs = bgStartMs == null
                ? startMs
                : (startMs < bgStartMs ? startMs : bgStartMs);
            bgEndMs = bgEndMs == null
                ? endMs
                : (endMs > bgEndMs ? endMs : bgEndMs);
          } else {
            String? wordRoman;
            if (romanizedWords != null && mainWordIdx < romanizedWords.length) {
              wordRoman = romanizedWords[mainWordIdx];
            }
            final word = LyricWord(
              startTime: Duration(milliseconds: startMs),
              endTime: Duration(milliseconds: endMs),
              text: text,
              romanText: wordRoman,
            );
            mainWords.add(word);
            mainWordIdx++;
          }
        }
      }

      // Main text: prefer joining main syllables (keeps it in sync with the
      // word-by-word render and excludes background parentheticals); otherwise
      // fall back to the line's own text.
      String text = mainWords.isNotEmpty
          ? mainWords.map((w) => w.text).join().trim()
          : (map['text'] ?? '').toString().trim();

      final int expectedEnd = lineStartMs + (lineDurMs > 0 ? lineDurMs : 0);
      final int lastWordEnd = mainWords.isNotEmpty
          ? mainWords.last.endTime.inMilliseconds
          : lineStartMs + 3000;
      final int lineEndMs = lastWordEnd > expectedEnd ? lastWordEnd : expectedEnd;

      // Snap the final syllable/word to the end of the line if the line duration is longer
      if (mainWords.isNotEmpty) {
        final lastWord = mainWords.last;
        if (lineEndMs > lastWord.endTime.inMilliseconds) {
          mainWords[mainWords.length - 1] = LyricWord(
            startTime: lastWord.startTime,
            endTime: Duration(milliseconds: lineEndMs),
            text: lastWord.text,
          );
        }
      }

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
          singerSide: singerSide,
        ),
      );
    }

    return lines;
  }

  static List<String?> calculateLineAlignments(
    List<String?> lineSingers,
    Map<String, String> agentTypes,
  ) {
    final List<String?> assignments = List.filled(lineSingers.length, null);
    bool currentSideIsLeft = true;
    String? lastPersonSingerId;
    int rightCount = 0;
    int totalCount = 0;

    for (int i = 0; i < lineSingers.length; i++) {
      final singerId = lineSingers[i];
      String? side; // 'left' or 'right'

      if (singerId != null) {
        String? type = agentTypes[singerId];
        if (type == null) {
          if (singerId == 'v1000') {
            type = 'group';
          } else if (singerId == 'v2000') {
            type = 'other';
          } else {
            type = 'person';
          }
        }

        if (type == 'group') {
          side = 'left';
        } else {
          if (lastPersonSingerId == null) {
            if (type == 'other') {
              currentSideIsLeft = false;
            } else {
              currentSideIsLeft = true;
            }
          } else if (singerId != lastPersonSingerId) {
            currentSideIsLeft = !currentSideIsLeft;
          }

          side = currentSideIsLeft ? 'left' : 'right';
          lastPersonSingerId = singerId;
        }
      }

      if (side != null) {
        totalCount++;
        if (side == 'right') rightCount++;
      }
      assignments[i] = side;
    }

    if (totalCount > 0 && ((rightCount / totalCount) * 100).round() >= 85) {
      for (int i = 0; i < assignments.length; i++) {
        if (assignments[i] == 'left') {
          assignments[i] = 'right';
        } else if (assignments[i] == 'right') {
          assignments[i] = 'left';
        }
      }
    }

    return assignments;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return double.tryParse(v)?.round() ?? 0;
    return 0;
  }
}
