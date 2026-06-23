import 'package:flutter_test/flutter_test.dart';
import 'package:chill_player/utils/query_normalizer.dart';

void main() {
  group('LyricQueryNormalizer.cleanTrackName', () {
    test('lowercases and trims', () {
      expect(LyricQueryNormalizer.cleanTrackName('  Hello World  '), 'hello world');
    });

    test('strips "(Official Video)" fluff', () {
      expect(LyricQueryNormalizer.cleanTrackName('Song (Official Video)'), 'song');
    });

    test('strips "feat." segment', () {
      expect(LyricQueryNormalizer.cleanTrackName('Title feat. Someone'), 'title');
    });

    test('strips remastered/deluxe tags', () {
      expect(LyricQueryNormalizer.cleanTrackName('Track Remastered'), 'track');
    });

    test('leaves a clean title unchanged', () {
      expect(LyricQueryNormalizer.cleanTrackName('Bohemian Rhapsody'), 'bohemian rhapsody');
    });
  });

  group('LyricQueryNormalizer.cleanArtistName', () {
    test('removes "- Topic" suffix', () {
      expect(LyricQueryNormalizer.cleanArtistName('Adele - Topic'), 'adele');
    });

    test('keeps only the primary artist before an ampersand', () {
      expect(LyricQueryNormalizer.cleanArtistName('A & B'), 'a');
    });

    test('keeps only the primary artist before a comma', () {
      expect(LyricQueryNormalizer.cleanArtistName('Artist1, Artist2'), 'artist1');
    });

    test('keeps only the primary artist before a slash', () {
      expect(LyricQueryNormalizer.cleanArtistName('Artist1/Artist2'), 'artist1');
    });

    test('lowercases and trims a simple name', () {
      expect(LyricQueryNormalizer.cleanArtistName('  Queen  '), 'queen');
    });
  });
}
