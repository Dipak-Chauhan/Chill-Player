import 'package:flutter_test/flutter_test.dart';
import 'package:chill_player/models/song.dart';

void main() {
  group('Song', () {
    const song = Song(
      id: 1,
      title: 'Title',
      artist: 'Artist',
      album: 'Album',
      albumArtist: 'Album Artist',
      genre: 'Pop',
      uri: '/music/title.mp3',
      duration: Duration(seconds: 200),
    );

    test('toJson/fromJson round-trips all fields', () {
      final json = song.toJson();
      final restored = Song.fromJson(json);

      expect(restored.id, song.id);
      expect(restored.title, song.title);
      expect(restored.artist, song.artist);
      expect(restored.album, song.album);
      expect(restored.albumArtist, song.albumArtist);
      expect(restored.genre, song.genre);
      expect(restored.uri, song.uri);
      expect(restored.duration, song.duration);
    });

    test('fromJson applies defaults for optional fields', () {
      final restored = Song.fromJson({
        'id': 2,
        'title': 'T',
        'artist': 'A',
        'album': 'Al',
        'uri': '/x.mp3',
        'durationMs': 1000,
      });

      expect(restored.albumArtist, '');
      expect(restored.genre, '');
      expect(restored.duration, const Duration(seconds: 1));
    });

    test('groupingArtist prefers a valid albumArtist', () {
      expect(song.groupingArtist, 'Album Artist');
    });

    test('groupingArtist falls back to artist when albumArtist is empty', () {
      const s = Song(
        id: 3,
        title: 'T',
        artist: 'Track Artist',
        album: 'Al',
        uri: '/x.mp3',
        duration: Duration.zero,
      );
      expect(s.groupingArtist, 'Track Artist');
    });

    test('groupingArtist falls back to artist when albumArtist is <unknown>', () {
      const s = Song(
        id: 4,
        title: 'T',
        artist: 'Track Artist',
        album: 'Al',
        albumArtist: '<unknown>',
        uri: '/x.mp3',
        duration: Duration.zero,
      );
      expect(s.groupingArtist, 'Track Artist');
    });
  });
}
