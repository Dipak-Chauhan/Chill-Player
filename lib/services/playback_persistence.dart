import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import 'settings_service.dart';

/// Persists the last playback state (song ID, position, queue) so the app
/// can restore where the user left off when reopened.
class PlaybackPersistence {
  static const _lastSongIdKey = 'last_song_id';
  static const _lastPositionKey = 'last_position_ms';
  static const _lastQueueKey = 'last_queue_ids';
  static const _lastQueueIndexKey = 'last_queue_index';
  static const _lastSongJsonKey = 'last_song_json';
  static const _lastOriginalQueueKey = 'last_original_queue_ids';

  /// Save the current playback state.
  static Future<void> save({
    required SharedPreferences prefs,
    required int songId,
    required int positionMs,
    required List<int> queueIds,
    required int queueIndex,
    String? songJson,
    List<int>? originalQueueIds,
  }) async {
    await prefs.setInt(_lastSongIdKey, songId);
    await prefs.setInt(_lastPositionKey, positionMs);
    await prefs.setString(_lastQueueKey, jsonEncode(queueIds));
    await prefs.setInt(_lastQueueIndexKey, queueIndex);
    if (songJson != null) await prefs.setString(_lastSongJsonKey, songJson);
    if (originalQueueIds != null) {
      await prefs.setString(_lastOriginalQueueKey, jsonEncode(originalQueueIds));
    } else {
      await prefs.remove(_lastOriginalQueueKey);
    }
  }

  /// Convenience save that derives the persisted fields from the domain
  /// objects, so callers don't have to repeat the queue-id / song-json
  /// mapping (and can't accidentally drop the song JSON snapshot).
  static Future<void> saveSnapshot({
    required SharedPreferences prefs,
    required Song song,
    required int positionMs,
    required List<Song> queue,
    required int queueIndex,
    List<Song>? originalQueue,
  }) {
    return save(
      prefs: prefs,
      songId: song.id,
      positionMs: positionMs,
      queueIds: queue.map((s) => s.id).toList(),
      queueIndex: queueIndex,
      songJson: jsonEncode(song.toJson()),
      originalQueueIds: originalQueue?.map((s) => s.id).toList(),
    );
  }

  /// Load the last playback state. Returns null if none saved.
  static PlaybackState? load(SharedPreferences prefs) {
    final songId = prefs.getInt(_lastSongIdKey);
    if (songId == null) return null;

    final positionMs = prefs.getInt(_lastPositionKey) ?? 0;
    final queueRaw = prefs.getString(_lastQueueKey);
    final queueIndex = prefs.getInt(_lastQueueIndexKey) ?? 0;
    final originalQueueRaw = prefs.getString(_lastOriginalQueueKey);

    List<int> queueIds = [];
    if (queueRaw != null) {
      try {
        queueIds = (jsonDecode(queueRaw) as List).cast<int>();
      } catch (_) {}
    }

    List<int> originalQueueIds = [];
    if (originalQueueRaw != null) {
      try {
        originalQueueIds = (jsonDecode(originalQueueRaw) as List).cast<int>();
      } catch (_) {}
    }

    return PlaybackState(
      songId: songId,
      positionMs: positionMs,
      queueIds: queueIds,
      queueIndex: queueIndex,
      songJson: prefs.getString(_lastSongJsonKey),
      originalQueueIds: originalQueueIds,
    );
  }

  /// Clear saved playback state.
  static Future<void> clear(SharedPreferences prefs) async {
    await prefs.remove(_lastSongIdKey);
    await prefs.remove(_lastPositionKey);
    await prefs.remove(_lastQueueKey);
    await prefs.remove(_lastQueueIndexKey);
    await prefs.remove(_lastSongJsonKey);
    await prefs.remove(_lastOriginalQueueKey);
  }
}

class PlaybackState {
  final int songId;
  final int positionMs;
  final List<int> queueIds;
  final int queueIndex;
  final String? songJson;
  final List<int> originalQueueIds;

  PlaybackState({
    required this.songId,
    required this.positionMs,
    required this.queueIds,
    required this.queueIndex,
    this.songJson,
    this.originalQueueIds = const [],
  });
}

/// Provider that exposes the last saved playback state.
final lastPlaybackStateProvider = Provider<PlaybackState?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PlaybackPersistence.load(prefs);
});
