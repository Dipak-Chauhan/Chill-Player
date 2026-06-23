import 'package:flutter_test/flutter_test.dart';
import 'package:chill_player/utils/lrc_parser.dart';

void main() {
  group('LrcParser.parse', () {
    test('returns empty list for empty input', () {
      expect(LrcParser.parse(''), isEmpty);
    });

    test('parses synced lines and snaps end times to the next line', () {
      const lrc = '[00:12.50]Hello\n[00:15.00]World';
      final lines = LrcParser.parse(lrc);

      expect(lines.length, 2);
      expect(lines[0].text, 'Hello');
      expect(lines[0].startTime, const Duration(milliseconds: 12500));
      // First line's end snaps to the second line's start.
      expect(lines[0].endTime, const Duration(milliseconds: 15000));
      expect(lines[1].text, 'World');
      expect(lines[1].startTime, const Duration(milliseconds: 15000));
      // Last line stays active indefinitely.
      expect(lines[1].endTime, const Duration(hours: 1));
    });

    test('treats input without timestamps as plain lyrics', () {
      const plain = 'Just a line\nAnother line';
      final lines = LrcParser.parse(plain);

      expect(lines.length, 2);
      expect(lines[0].text, 'Just a line');
      expect(lines[0].startTime, Duration.zero);
      expect(lines[0].endTime, const Duration(hours: 1));
    });

    test('extracts a leading singer label', () {
      const lrc = '[00:01.00]Singer: Hello there';
      final lines = LrcParser.parse(lrc);

      expect(lines.length, 1);
      expect(lines[0].singer, 'Singer');
      expect(lines[0].text, 'Hello there');
    });
  });
}
