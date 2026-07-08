import 'package:flutter_test/flutter_test.dart';
import 'package:chill_player/utils/musixmatch_parser.dart';

void main() {
  group('MusixmatchParser.parseRichsync', () {
    test('parses word-by-word chunks with absolute timing', () {
      const body =
          '[{"ts":5.33,"te":6.68,"x":"Cause I in the stars","l":['
          '{"c":"Cause","o":0},{"c":" ","o":0.19},'
          '{"c":"I","o":0.226},{"c":" ","o":0.28},'
          '{"c":"in","o":0.574},{"c":" ","o":0.65},'
          '{"c":"the","o":0.7},{"c":" ","o":0.84},'
          '{"c":"stars","o":0.941}]}]';

      final lines = MusixmatchParser.parseRichsync(body);
      expect(lines.length, 1);
      final line = lines.first;
      expect(line.startTime, const Duration(milliseconds: 5330));
      expect(line.endTime, const Duration(milliseconds: 6680));
      expect(line.text, 'Cause I in the stars');
      expect(line.words, isNotNull);
      // Whitespace chunks are dropped.
      expect(line.words!.length, 5);
      // First word starts at ts + o = 5.33s.
      expect(line.words![0].text, 'Cause');
      expect(line.words![0].startTime, const Duration(milliseconds: 5330));
      // "Cause" ends at next chunk offset (the space at 0.19) => 5.33 + 0.19.
      expect(line.words![0].endTime, const Duration(milliseconds: 5520));
      // "I" starts at 5.33 + 0.226 = 5556.
      expect(line.words![1].text, 'I');
      expect(line.words![1].startTime, const Duration(milliseconds: 5556));
      // Last word "stars" ends at te.
      expect(line.words!.last.text, 'stars');
      expect(line.words!.last.endTime, const Duration(milliseconds: 6680));
    });

    test('handles multiple lines', () {
      const body =
          '[{"ts":0,"te":2,"x":"one","l":[{"c":"one","o":0}]},'
          '{"ts":2,"te":4,"x":"two","l":[{"c":"two","o":0}]}]';
      final lines = MusixmatchParser.parseRichsync(body);
      expect(lines.length, 2);
      expect(lines[1].startTime, const Duration(seconds: 2));
      expect(lines[1].text, 'two');
    });

    test('returns empty for malformed input', () {
      expect(MusixmatchParser.parseRichsync('not json'), isEmpty);
      expect(MusixmatchParser.parseRichsync('{}'), isEmpty);
      expect(MusixmatchParser.parseRichsync('[]'), isEmpty);
    });
  });
}
