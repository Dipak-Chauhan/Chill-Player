import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_player/utils/kpoe_parser.dart';

void main() {
  group('KpoeParser', () {
    test('parses word-by-word syllables with absolute timing', () {
      final data =
          jsonDecode('''
      {
        "type": "Word",
        "lyrics": [
          {
            "text": "Hello world",
            "time": 1000,
            "duration": 1500,
            "element": {"singer": "v1"},
            "syllabus": [
              {"text": "Hello ", "time": 1000, "duration": 500, "isBackground": false},
              {"text": "world", "time": 1500, "duration": 1000, "isBackground": false}
            ]
          }
        ],
        "metadata": {"source": "test"}
      }
      ''')
              as Map<String, dynamic>;

      final lines = KpoeParser.parse(data);
      expect(lines.length, 1);
      final line = lines.first;
      expect(line.startTime, const Duration(milliseconds: 1000));
      // End time snaps to the last main syllable end (1500 + 1000).
      expect(line.endTime, const Duration(milliseconds: 2500));
      expect(line.singer, 'v1');
      expect(line.words, isNotNull);
      expect(line.words!.length, 2);
      expect(line.words![0].text, 'Hello ');
      expect(line.words![0].startTime, const Duration(milliseconds: 1000));
      expect(line.words![0].endTime, const Duration(milliseconds: 1500));
      expect(line.words![1].startTime, const Duration(milliseconds: 1500));
      expect(line.words![1].endTime, const Duration(milliseconds: 2500));
      // Main text is rebuilt from main syllables.
      expect(line.text, 'Hello world');
    });

    test('splits background syllables into a background line', () {
      final data =
          jsonDecode('''
      {
        "type": "Word",
        "lyrics": [
          {
            "text": "Main line",
            "time": 0,
            "duration": 2000,
            "syllabus": [
              {"text": "Main ", "time": 0, "duration": 500, "isBackground": false},
              {"text": "line", "time": 500, "duration": 500, "isBackground": false},
              {"text": "ooh", "time": 1200, "duration": 800, "isBackground": true}
            ]
          }
        ],
        "metadata": {"source": "test"}
      }
      ''')
              as Map<String, dynamic>;

      final lines = KpoeParser.parse(data);
      expect(lines.length, 1);
      final line = lines.first;
      expect(line.words!.length, 2); // background excluded from main
      expect(line.backgroundLines, isNotNull);
      expect(line.backgroundLines!.length, 1);
      final bg = line.backgroundLines!.first;
      expect(bg.text, 'ooh');
      expect(bg.words!.single.startTime, const Duration(milliseconds: 1200));
      expect(bg.words!.single.endTime, const Duration(milliseconds: 2000));
    });

    test('handles line-synced (no syllabus) entries', () {
      final data =
          jsonDecode('''
      {
        "type": "Line",
        "lyrics": [
          {"text": "Just a line", "time": 5000, "duration": 3000}
        ],
        "metadata": {"source": "test"}
      }
      ''')
              as Map<String, dynamic>;

      final lines = KpoeParser.parse(data);
      expect(lines.length, 1);
      expect(lines.first.words, isNull);
      expect(lines.first.text, 'Just a line');
      expect(lines.first.startTime, const Duration(milliseconds: 5000));
      expect(lines.first.endTime, const Duration(milliseconds: 8000));
    });

    test('returns empty list for malformed or empty payloads', () {
      expect(KpoeParser.parse({}), isEmpty);
      expect(KpoeParser.parse({'lyrics': []}), isEmpty);
      expect(KpoeParser.parse({'lyrics': 'nope'}), isEmpty);
    });
  });
}
