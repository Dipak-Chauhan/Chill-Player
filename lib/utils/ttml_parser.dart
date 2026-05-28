import 'package:xml/xml.dart';
import '../models/lyric_line.dart';

class TtmlParser {
  static List<LyricLine> parse(String ttmlContent) {
    final List<LyricLine> lines = [];
    if (ttmlContent.isEmpty) return lines;

    try {
      final document = XmlDocument.parse(ttmlContent);
      final pElements = document.findAllElements('p');

      for (final pElement in pElements) {
        final beginAttr = pElement.getAttribute('begin');
        if (beginAttr == null || beginAttr.isEmpty) continue;

        final startTime = _parseTime(beginAttr);
        final List<LyricWord> words = [];

        final List<LyricLine> backgroundLines = [];

        final children = pElement.children;
        for (final node in children) {
          if (node is XmlElement && node.name.local == 'span') {
            final role = node.getAttribute('role') ?? 
                         node.getAttribute('ttm:role') ?? 
                         node.getAttribute('role', namespace: 'http://www.w3.org/ns/ttml#metadata');
                         
            if (role == 'x-translation' || role == 'x-roman') continue;

            if (role == 'x-bg') {
              final bgBeginStr = node.getAttribute('begin');
              final bgStartTime = bgBeginStr != null ? _parseTime(bgBeginStr) : startTime;
              final List<LyricWord> bgWords = [];
              
              for (final innerNode in node.children) {
                if (innerNode is XmlElement && innerNode.name.local == 'span') {
                  final innerRole = innerNode.getAttribute('role') ?? 
                         innerNode.getAttribute('ttm:role') ?? 
                         innerNode.getAttribute('role', namespace: 'http://www.w3.org/ns/ttml#metadata');
                  if (innerRole == 'x-translation' || innerRole == 'x-roman') continue;
                  
                  final innerBegin = innerNode.getAttribute('begin');
                  final innerEnd = innerNode.getAttribute('end');
                  final innerText = innerNode.innerText.trim();
                  
                  if (innerText.isNotEmpty && innerBegin != null && innerEnd != null) {
                    bgWords.add(LyricWord(
                      startTime: _parseTime(innerBegin),
                      endTime: _parseTime(innerEnd),
                      text: innerText,
                    ));
                  }
                }
              }
              
              final bgLineText = bgWords.map((e) => e.text).join(' ').trim();
              if (bgLineText.isNotEmpty) {
                 backgroundLines.add(LyricLine(
                   startTime: bgStartTime,
                   endTime: bgWords.last.endTime,
                   text: bgLineText,
                   words: bgWords,
                 ));
              }
              continue; // Processed background, move to next parent node
            }

            // Normal vocal word
            final wordBegin = node.getAttribute('begin');
            final wordEnd = node.getAttribute('end');
            final wordText = node.innerText.trim();

            if (wordText.isNotEmpty && wordBegin != null && wordEnd != null) {
              words.add(LyricWord(
                startTime: _parseTime(wordBegin),
                endTime: _parseTime(wordEnd),
                text: wordText, // TTML inherently splits by spans
              ));
            }
          } else if (node is XmlText) {
             // Standard lyric string, no syllable tagging found (unlikely in LyricsPlus, but fallback)
             final text = node.innerText.trim();
             if (text.isNotEmpty && words.isEmpty) {
                 // Raw text chunk mapping handled outside this block
             }
          }
        }

        // Amalgamate text
        final lineText = words.map((e) => e.text).join(' ').trim();
        final fallbackText = pElement.innerText.trim();

        final finalText = lineText.isNotEmpty ? lineText : fallbackText;

        if (finalText.isNotEmpty) {
           Duration calculatedEndTime;
           if (words.isNotEmpty && words.last.endTime > startTime) {
             calculatedEndTime = words.last.endTime;
           } else {
             // Approximate an end time if TTML missed word nodes. Will be snapped by the iterator later.
             calculatedEndTime = startTime + const Duration(seconds: 3); 
           }

           final role = pElement.getAttribute('ttm:role') ??
                        pElement.getAttribute('role') ??
                        pElement.getAttribute('actor') ??
                        pElement.getAttribute('ttm:agent');

           String? parsedSinger = role?.trim();
           String cleanedText = finalText;

           final singerRegex = RegExp(r'^\[([^\]]+)\]:\s*|^([^:]+):\s*|^\(([^)]+)\)\s*');
           final match = singerRegex.firstMatch(finalText);
           if (match != null) {
             final foundSinger = match.group(1) ?? match.group(2) ?? match.group(3);
             if (foundSinger != null && foundSinger.isNotEmpty) {
               parsedSinger = foundSinger.trim();
               cleanedText = finalText.substring(match.end).trim();
             }
           }

           lines.add(LyricLine(
             startTime: startTime,
             endTime: calculatedEndTime,
             text: cleanedText,
             words: words.isNotEmpty ? words : null,
             backgroundLines: backgroundLines.isNotEmpty ? backgroundLines : null,
             singer: parsedSinger?.isNotEmpty == true ? parsedSinger : null,
           ));
        }
      }

      // Snap EndTimes to next line StartTimes (cleanup)
      for (int i = 0; i < lines.length - 1; i++) {
         if (lines[i].words == null || lines[i].words!.isEmpty) {
             lines[i] = lines[i].copyWith(endTime: lines[i+1].startTime);
         }
      }
      
    } catch (e) {
       // Silently fail allowing upstream to fall back to LRCLib parsing.
    }
    return lines;
  }

  static Duration _parseTime(String timeStr) {
    try {
      if (timeStr.contains(':')) {
        final parts = timeStr.split(':');
        if (parts.length == 2) {
          final m = double.parse(parts[0]);
          final s = double.parse(parts[1]);
          return Duration(milliseconds: ((m * 60 + s) * 1000).round());
        } else if (parts.length == 3) {
          final h = double.parse(parts[0]);
          final m = double.parse(parts[1]);
          final s = double.parse(parts[2]);
          return Duration(milliseconds: ((h * 3600 + m * 60 + s) * 1000).round());
        }
      } else {
        final s = double.parse(timeStr);
        return Duration(milliseconds: (s * 1000).round());
      }
    } catch (_) {}
    return Duration.zero;
  }
}
