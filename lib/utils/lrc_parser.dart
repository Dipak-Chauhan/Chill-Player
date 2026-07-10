import '../models/lyric_line.dart';

class LrcParser {
  /// Parses standard LRC formatting: [mm:ss.xx] Lyrics Text
  static List<LyricLine> parse(String lyricsString) {
    if (lyricsString.isEmpty) return [];

    final lines = lyricsString.split('\n');
    final List<LyricLine> result = [];
    final RegExp timeRegex = RegExp(r'\[(\d+):(\d+\.\d+)\]');
    final RegExp offsetRegex = RegExp(r'\[offset:\s*(-?\d+)\s*\]');
    int globalOffsetMs = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final offsetMatch = offsetRegex.firstMatch(line);
      if (offsetMatch != null) {
        globalOffsetMs = int.tryParse(offsetMatch.group(1)!) ?? 0;
        continue;
      }

      final match = timeRegex.firstMatch(line);
      if (match != null) {
        // It's synced!
        final minutes = int.parse(match.group(1)!);
        final secondsAndMillis = double.parse(match.group(2)!);
        
        final totalMilliseconds = (minutes * 60 + secondsAndMillis) * 1000 + globalOffsetMs;
        final int finalMs = totalMilliseconds.toInt();
        final startTime = Duration(milliseconds: finalMs < 0 ? 0 : finalMs);
        
        final text = line.replaceFirst(match.group(0)!, '').trim();
        
        // Don't add completely empty lines that have sync tags, or do we? 
        // We can add them to retain beat timing pauses!
        if (text.isNotEmpty) {
           String? parsedSinger;
           String cleanedText = text;

           final singerRegex = RegExp(r'^\[([^\]]+)\]:\s*|^([^:]+):\s*|^\(([^)]+)\)\s*');
           final singerMatch = singerRegex.firstMatch(text);
           if (singerMatch != null) {
             final foundSinger = singerMatch.group(1) ?? singerMatch.group(2) ?? singerMatch.group(3);
             if (foundSinger != null && foundSinger.isNotEmpty) {
               parsedSinger = foundSinger.trim();
               cleanedText = text.substring(singerMatch.end).trim();
             }
           }

           result.add(LyricLine(
            text: cleanedText,
            startTime: startTime,
            // Assuming endTime is the start of the next line (handled logically later or defaulted)
            endTime: startTime + const Duration(seconds: 5), // Temporary buffer until next line overrides
            singer: parsedSinger?.isNotEmpty == true ? parsedSinger : null,
          ));
        }
      }
    }

    if (result.isEmpty) {
      // It's probably a plain lyrics string without [mm:ss] tags.
      // We can create a non-sync block.
      return lines.where((l) => l.trim().isNotEmpty).map((l) {
        return LyricLine(text: l, startTime: Duration.zero, endTime: const Duration(hours: 1));
      }).toList();
    }

    // Pass 2: Dynamically fix the endTimes of synced lines to perfectly snap to the next line's start time.
    for (int i = 0; i < result.length - 1; i++) {
       final current = result[i];
       final next = result[i + 1];
       result[i] = current.copyWith(endTime: next.startTime);
    }
    
    // Set the very last line to stay active indefinitely
    if (result.isNotEmpty) {
      result[result.length - 1] = result.last.copyWith(endTime: const Duration(hours: 1));
    }

    return result;
  }
}
