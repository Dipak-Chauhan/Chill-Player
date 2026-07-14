class Song {
  final int id;
  final String title;
  final String artist;
  final String album;
  final String albumArtist; // Album-level artist (for compilations & grouping)
  final String genre;
  final String uri; // File path on the device
  final Duration duration;
  final int dateAdded; // Epoch timestamp in seconds

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist = '',
    this.genre = '',
    required this.uri,
    required this.duration,
    this.dateAdded = 0,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as int,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String,
      albumArtist: json['albumArtist'] as String? ?? '',
      genre: json['genre'] as String? ?? '',
      uri: json['uri'] as String,
      duration: Duration(milliseconds: json['durationMs'] as int),
      dateAdded: json['dateAdded'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'albumArtist': albumArtist,
      'genre': genre,
      'uri': uri,
      'durationMs': duration.inMilliseconds,
      'dateAdded': dateAdded,
    };
  }

  /// Returns the effective artist for grouping purposes.
  /// Prefers albumArtist when available, falls back to track artist.
  String get groupingArtist {
    if (albumArtist.isNotEmpty && albumArtist.toLowerCase() != '<unknown>') {
      return albumArtist;
    }
    return artist;
  }
}
