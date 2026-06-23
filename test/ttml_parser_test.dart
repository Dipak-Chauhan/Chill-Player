import 'package:flutter_test/flutter_test.dart';
import 'package:chill_player/utils/ttml_parser.dart';

void main() {
  group('TtmlParser.parse', () {
    test('returns empty list for empty input', () {
      expect(TtmlParser.parse(''), isEmpty);
    });

    test('returns empty list for malformed XML', () {
      expect(TtmlParser.parse('<tt><p>oops'), isEmpty);
    });

    test('parses word-level spans into a line', () {
      const ttml = '''
<tt xmlns="http://www.w3.org/ns/ttml">
  <body>
    <div>
      <p begin="00:01.000" end="00:03.000">
        <span begin="00:01.000" end="00:02.000">Hello</span>
        <span begin="00:02.000" end="00:03.000">World</span>
      </p>
    </div>
  </body>
</tt>''';

      final lines = TtmlParser.parse(ttml);

      expect(lines.length, 1);
      expect(lines.first.text, 'Hello World');
      expect(lines.first.startTime, const Duration(seconds: 1));
      expect(lines.first.words, isNotNull);
      expect(lines.first.words!.length, 2);
      expect(lines.first.endTime, const Duration(seconds: 3));
    });
  });
}
