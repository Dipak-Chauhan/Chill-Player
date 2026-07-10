import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../services/artwork_cache.dart';

// Library & Sorting
enum LibrarySortType { title, artist, album, duration }

class GlobalLibraryNotifier extends Notifier<List<Song>> {
  @override
  List<Song> build() => [];

  void setLibrary(List<Song> songs) {
    state = songs;
    // Warm artwork in the background so library scrolling shows art instantly.
    ArtworkCache.warm(songs.map((s) => s.id));
  }
}
final globalLibraryProvider = NotifierProvider<GlobalLibraryNotifier, List<Song>>(GlobalLibraryNotifier.new);

class SongSortTypeNotifier extends Notifier<LibrarySortType> {
  @override
  LibrarySortType build() => LibrarySortType.title;
  void setType(LibrarySortType val) => state = val;
}
final songSortTypeProvider = NotifierProvider<SongSortTypeNotifier, LibrarySortType>(SongSortTypeNotifier.new);

class SongSortAscendingNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void toggle() => state = !state;
  void setAscending(bool val) => state = val;
}
final songSortAscendingProvider = NotifierProvider<SongSortAscendingNotifier, bool>(SongSortAscendingNotifier.new);
