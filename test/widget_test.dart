import 'package:flutter_test/flutter_test.dart';
import 'package:chill_player/models/lyric_line.dart';

void main() {
  group('LyricLine.copyWith', () {
    const base = LyricLine(
      startTime: Duration(seconds: 1),
      endTime: Duration(seconds: 2),
      text: 'original',
    );

    test('overrides only the provided fields', () {
      final updated = base.copyWith(
        endTime: const Duration(seconds: 5),
        text: 'changed',
      );

      expect(updated.startTime, const Duration(seconds: 1));
      expect(updated.endTime, const Duration(seconds: 5));
      expect(updated.text, 'changed');
    });

    test('keeps original values when nothing is passed', () {
      final copy = base.copyWith();

      expect(copy.startTime, base.startTime);
      expect(copy.endTime, base.endTime);
      expect(copy.text, base.text);
      expect(copy.isGap, isFalse);
    });
  });
}
