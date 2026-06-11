import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';

// ---------------------------------------------------------------------------
// Library & Sorting
// ---------------------------------------------------------------------------
enum LibrarySortType { title, artist, album, duration }

class GlobalLibraryNotifier extends Notifier<List<Song>> {
  @override
  List<Song> build() => [];

  void setLibrary(List<Song> songs) {
    state = songs;
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
