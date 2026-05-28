// Smart Library: Intelligent parsing & grouping for artists and albums
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import 'audio_state.dart';

// ---------------------------------------------------------------------------
// Smart Artist Model
// ---------------------------------------------------------------------------
class SmartArtist {
  final String name;
  final List<Song> songs;
  final int fallbackImageId; // ID of the first song to fetch SOME artwork
  final Set<String> albumNames;
  final bool isAlbumArtist; // Whether this came from albumArtist tag

  SmartArtist({
    required this.name,
    required this.songs,
    required this.fallbackImageId,
    required this.albumNames,
    this.isAlbumArtist = false,
  });

  /// Total play time of all songs
  Duration get totalDuration =>
      songs.fold(Duration.zero, (sum, s) => sum + s.duration);
}

// ---------------------------------------------------------------------------
// Smart Album Model (for album artist grouping)
// ---------------------------------------------------------------------------
class SmartAlbum {
  final String name;
  final String albumArtist; // The effective album artist
  final List<Song> songs;
  final int fallbackImageId;

  SmartAlbum({
    required this.name,
    required this.albumArtist,
    required this.songs,
    required this.fallbackImageId,
  });

  Duration get totalDuration =>
      songs.fold(Duration.zero, (sum, s) => sum + s.duration);
}

// ---------------------------------------------------------------------------
// Artist Name Splitter — Handles all common separator patterns
// ---------------------------------------------------------------------------
class ArtistParser {
  // Ordered by specificity: longer patterns first to avoid partial matches.
  // Handles: feat., ft., with, and, &, x, ;, /  plus comma
  static final RegExp _separatorRegex = RegExp(
    r'\s+(?:feat\.?|ft\.?|featuring)\s+'  // feat / ft / featuring
    r'|\s+(?:with)\s+'                     // with
    r'|\s*[,;]\s*'                         // comma, semicolon
    r'|\s+&\s+'                            // ampersand (space-padded)
    r'|\s+(?:and)\s+'                      // and
    r'|\s+[xX]\s+',                        // x (common in EDM/hip-hop)
    caseSensitive: false,
  );

  /// Split a raw artist string into individual artist names.
  /// Trims whitespace and filters empty results.
  static List<String> split(String rawArtist) {
    if (rawArtist.trim().isEmpty || rawArtist.toLowerCase() == '<unknown>') {
      return ['Unknown'];
    }

    final splits = rawArtist.split(_separatorRegex);
    final result = <String>[];

    for (final part in splits) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty) {
        result.add(trimmed);
      }
    }

    return result.isEmpty ? ['Unknown'] : result;
  }

  /// Normalize an artist name for case-insensitive deduplication.
  /// Preserves the first-seen casing variant as the canonical name.
  static String normalizeKey(String name) => name.trim().toLowerCase();
}

// ---------------------------------------------------------------------------
// Smart Artist Provider — Splits & deduplicates artists
// ---------------------------------------------------------------------------
class SmartArtistLibraryNotifier extends Notifier<List<SmartArtist>> {
  @override
  List<SmartArtist> build() {
    final library = ref.watch(globalLibraryProvider);
    if (library.isEmpty) return [];

    // canonicalKey → (displayName, songs)
    final Map<String, String> canonicalNames = {};
    final Map<String, List<Song>> artistMap = {};

    for (final song in library) {
      // Use both track artist AND albumArtist for comprehensive coverage
      final trackArtists = ArtistParser.split(song.artist);
      final albumArtists = song.albumArtist.isNotEmpty
          ? ArtistParser.split(song.albumArtist)
          : <String>[];

      // Merge both lists, deduplicating by normalized key
      final allArtists = <String>{};
      for (final name in [...trackArtists, ...albumArtists]) {
        final key = ArtistParser.normalizeKey(name);
        if (allArtists.add(key)) {
          // First time seeing this key for this song
          canonicalNames.putIfAbsent(key, () => name); // Keep first-seen casing
          artistMap.putIfAbsent(key, () => []).add(song);
        }
      }
    }

    final smartArtists = artistMap.entries.map((e) {
      final songs = e.value;
      final displayName = canonicalNames[e.key] ?? e.key;
      final Set<String> albums = {};
      for (var s in songs) {
        if (s.album.isNotEmpty) albums.add(s.album);
      }
      return SmartArtist(
        name: displayName,
        songs: songs,
        fallbackImageId: songs.first.id,
        albumNames: albums,
      );
    }).toList();

    // Sort alphabetically, case-insensitive
    smartArtists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return smartArtists;
  }
}

final smartArtistProvider = NotifierProvider<SmartArtistLibraryNotifier, List<SmartArtist>>(
  SmartArtistLibraryNotifier.new,
);

// ---------------------------------------------------------------------------
// Smart Album Provider — Groups albums by albumArtist for proper grouping
// ---------------------------------------------------------------------------
class SmartAlbumLibraryNotifier extends Notifier<List<SmartAlbum>> {
  @override
  List<SmartAlbum> build() {
    final library = ref.watch(globalLibraryProvider);
    if (library.isEmpty) return [];

    // Group by (albumName, effectiveAlbumArtist)
    final Map<String, SmartAlbum> albumMap = {};

    for (final song in library) {
      final albumName = song.album.isNotEmpty ? song.album : 'Unknown Album';
      final albumArtist = song.groupingArtist;
      final key = '${albumName.toLowerCase()}|||${albumArtist.toLowerCase()}';

      if (albumMap.containsKey(key)) {
        albumMap[key]!.songs.add(song);
      } else {
        albumMap[key] = SmartAlbum(
          name: albumName,
          albumArtist: albumArtist,
          songs: [song],
          fallbackImageId: song.id,
        );
      }
    }

    final albums = albumMap.values.toList();
    // Sort by album name
    albums.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return albums;
  }
}

final smartAlbumProvider = NotifierProvider<SmartAlbumLibraryNotifier, List<SmartAlbum>>(
  SmartAlbumLibraryNotifier.new,
);
