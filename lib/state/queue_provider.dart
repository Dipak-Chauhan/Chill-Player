import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../services/settings_service.dart';
import '../services/playback_persistence.dart';
import 'audio_engine.dart';
import 'playback_status.dart';

// ---------------------------------------------------------------------------
// Playback "firewall" — temporarily masks transient just_audio ExoPlayer
// stream emissions during large native playlist swaps so the UI doesn't flicker
// through intermediate indices.
// ---------------------------------------------------------------------------
class IsSwappingPlaylistNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void setSwapping(bool val) => state = val;
}
final isSwappingPlaylistProvider = NotifierProvider<IsSwappingPlaylistNotifier, bool>(IsSwappingPlaylistNotifier.new);

class ExpectedPlayerIndexNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void setExpected(int? val) => state = val;
  void clear() => state = null;
}
final expectedPlayerIndexProvider = NotifierProvider<ExpectedPlayerIndexNotifier, int?>(ExpectedPlayerIndexNotifier.new);

// ---------------------------------------------------------------------------
// Queue Management
// ---------------------------------------------------------------------------
class QueueNotifier extends Notifier<List<Song>> {
  List<Song> _originalQueue = [];

  @override
  List<Song> build() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final savedState = PlaybackPersistence.load(prefs);
      if (savedState != null && savedState.songJson != null) {
        final lastSong = Song.fromJson(jsonDecode(savedState.songJson!) as Map<String, dynamic>);
        return [lastSong];
      }
    } catch (_) {}
    return [];
  }

  /// Builds the just_audio sources (with media notification metadata) for a
  /// list of songs. Shared by setQueue / enableShuffle / disableShuffle.
  List<AudioSource> _buildSources(List<Song> songs) {
    return songs
        .map((song) => AudioSource.uri(
              Uri.file(song.uri),
              tag: MediaItem(
                id: song.id.toString(),
                album: song.album,
                title: song.title,
                artist: song.artist,
                duration: song.duration,
                artUri: Uri.parse('content://media/external/audio/media/${song.id}/albumart'),
              ),
            ))
        .toList();
  }

  Future<void> setQueue(List<Song> songs, {int? initialIndex, Duration? initialPosition}) async {
    ref.read(isSwappingPlaylistProvider.notifier).setSwapping(true);
    
    final isShuffle = ref.read(shuffleModeProvider);
    List<Song> finalSongs = List<Song>.from(songs);
    int finalInitialIndex = initialIndex ?? 0;
    ref.read(expectedPlayerIndexProvider.notifier).setExpected(finalInitialIndex);
    
    if (isShuffle) {
      _originalQueue = List<Song>.from(songs);
      
      // Shuffle list while keeping the initial index song active
      if (finalSongs.isNotEmpty) {
        final targetSong = finalSongs.removeAt(finalInitialIndex);
        finalSongs.shuffle(math.Random());
        finalSongs.insert(0, targetSong);
        finalInitialIndex = 0;
      }
    } else {
      _originalQueue = [];
    }

    state = finalSongs;
    final player = ref.read(audioPlayerProvider);

    await player.setAudioSources(
      _buildSources(finalSongs),
      initialIndex: finalInitialIndex,
      initialPosition: initialPosition,
    );
    
    // Once explicitly verified and mounted, drop the firewall firewall and force the UI sync
    ref.read(isSwappingPlaylistProvider.notifier).setSwapping(false);
    ref.read(expectedPlayerIndexProvider.notifier).clear();
    ref.read(currentSongProvider.notifier).forceSync();
  }

  Future<void> enableShuffle() async {
    if (state.isEmpty) return;
    
    ref.read(isSwappingPlaylistProvider.notifier).setSwapping(true);
    ref.read(expectedPlayerIndexProvider.notifier).setExpected(0);
    
    // Save current state as original
    _originalQueue = List<Song>.from(state);
    
    final currentSong = ref.read(currentSongProvider);
    final currentSongId = currentSong?.id;
    
    final listToShuffle = List<Song>.from(state);
    Song? activeSong;
    if (currentSongId != null) {
      final activeIndex = listToShuffle.indexWhere((s) => s.id == currentSongId);
      if (activeIndex >= 0) {
        activeSong = listToShuffle.removeAt(activeIndex);
      }
    }
    
    listToShuffle.shuffle(math.Random());
    
    final shuffledList = <Song>[];
    if (activeSong != null) {
      shuffledList.add(activeSong);
    }
    shuffledList.addAll(listToShuffle);
    
    state = shuffledList;
    
    final player = ref.read(audioPlayerProvider);
    final currentPosition = player.position;
    await player.setAudioSources(
      _buildSources(shuffledList),
      initialIndex: 0,
      initialPosition: currentPosition,
    );
    
    ref.read(isSwappingPlaylistProvider.notifier).setSwapping(false);
    ref.read(expectedPlayerIndexProvider.notifier).clear();
    ref.read(currentSongProvider.notifier).forceSync();
  }

  Future<void> disableShuffle() async {
    if (_originalQueue.isEmpty) return;
    
    ref.read(isSwappingPlaylistProvider.notifier).setSwapping(true);
    
    final currentSong = ref.read(currentSongProvider);
    final currentSongId = currentSong?.id;
    
    int targetIndex = 0;
    if (currentSongId != null) {
      final idx = _originalQueue.indexWhere((s) => s.id == currentSongId);
      if (idx >= 0) {
        targetIndex = idx;
      }
    }
    ref.read(expectedPlayerIndexProvider.notifier).setExpected(targetIndex);
    
    final restoredList = List<Song>.from(_originalQueue);
    state = restoredList;
    _originalQueue = [];
    
    final player = ref.read(audioPlayerProvider);
    final currentPosition = player.position;
    await player.setAudioSources(
      _buildSources(restoredList),
      initialIndex: targetIndex,
      initialPosition: currentPosition,
    );
    
    ref.read(isSwappingPlaylistProvider.notifier).setSwapping(false);
    ref.read(expectedPlayerIndexProvider.notifier).clear();
    ref.read(currentSongProvider.notifier).forceSync();
  }

  /// Reorder a song in the queue from oldIndex to newIndex
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    
    // Activate firewall to prevent player from emitting intermediate mismatched indices
    ref.read(isSwappingPlaylistProvider.notifier).setSwapping(true);
    
    final player = ref.read(audioPlayerProvider);
    final currentIndex = player.currentIndex;
    
    if (currentIndex != null) {
      int expectedIndex = currentIndex;
      if (currentIndex == oldIndex) {
        expectedIndex = newIndex;
      } else if (oldIndex < currentIndex && currentIndex <= newIndex) {
        expectedIndex = currentIndex - 1;
      } else if (newIndex <= currentIndex && currentIndex < oldIndex) {
        expectedIndex = currentIndex + 1;
      }
      ref.read(expectedPlayerIndexProvider.notifier).setExpected(expectedIndex);
    }
    
    final list = List<Song>.from(state);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = list;

    // Also reorder in the audio player's playlist
    if (oldIndex < player.sequence.length && newIndex < player.sequence.length) {
      player.moveAudioSource(oldIndex, newIndex);
    }
    
    // Fallback: in case player.currentIndex doesn't emit or the event is lost, 
    // release the firewall after 200ms
    Future.delayed(const Duration(milliseconds: 200), () {
      if (ref.read(isSwappingPlaylistProvider)) {
        ref.read(isSwappingPlaylistProvider.notifier).setSwapping(false);
        ref.read(expectedPlayerIndexProvider.notifier).clear();
      }
    });
  }

  /// Remove a song from the queue
  void removeAt(int index) {
    final list = List<Song>.from(state);
    final removedSong = list.removeAt(index);
    state = list;

    final player = ref.read(audioPlayerProvider);
    if (index < player.sequence.length) {
      player.removeAudioSourceAt(index);
    }
    
    if (_originalQueue.isNotEmpty) {
      _originalQueue.removeWhere((s) => s.id == removedSong.id);
    }
  }
}
final queueProvider = NotifierProvider<QueueNotifier, List<Song>>(QueueNotifier.new);

// ---------------------------------------------------------------------------
// Shuffle (drives the queue's enable/disable shuffle reordering)
// ---------------------------------------------------------------------------
class ShuffleModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  Future<void> setShuffle(bool val) async {
    if (state != val) {
      state = val;
      
      final queueNotifier = ref.read(queueProvider.notifier);
      if (val) {
        await queueNotifier.enableShuffle();
      } else {
        await queueNotifier.disableShuffle();
      }
    }
  }

  Future<void> toggle() async {
    await setShuffle(!state);
  }
}
final shuffleModeProvider = NotifierProvider<ShuffleModeNotifier, bool>(ShuffleModeNotifier.new);
