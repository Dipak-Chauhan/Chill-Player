import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_player/services/artwork_cache.dart';

void main() {
  Uint8List bytes(int n) => Uint8List.fromList([n, n, n]);

  group('ArtworkCache memory cache', () {
    setUp(ArtworkCache.debugClear);

    test('peek returns null and contains is false when empty', () {
      expect(ArtworkCache.peek(1), isNull);
      expect(ArtworkCache.contains(1), isFalse);
    });

    test('stores and retrieves bytes by id', () {
      final b = bytes(7);
      ArtworkCache.debugPut(7, b);
      expect(ArtworkCache.contains(7), isTrue);
      expect(ArtworkCache.peek(7), same(b));
    });

    test('caches a null result (song with no artwork) as resolved', () {
      ArtworkCache.debugPut(9, null);
      expect(ArtworkCache.contains(9), isTrue);
      expect(ArtworkCache.peek(9), isNull);
    });

    test('evicts the least-recently-used entry past the cap', () {
      final max = ArtworkCache.maxMemEntries;
      for (int i = 0; i < max; i++) {
        ArtworkCache.debugPut(i, bytes(i % 256));
      }
      expect(ArtworkCache.debugMemCount, max);

      // Touch id 0 so it is no longer the oldest.
      ArtworkCache.peek(0);
      // Insert one more -> the new oldest (id 1) should be evicted, not id 0.
      ArtworkCache.debugPut(9999, bytes(1));

      expect(ArtworkCache.debugMemCount, max);
      expect(ArtworkCache.contains(0), isTrue);
      expect(ArtworkCache.contains(1), isFalse);
      expect(ArtworkCache.contains(9999), isTrue);
    });
  });
}
