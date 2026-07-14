import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_service.dart';

/// Tracks listening statistics: play counts, total time listened, history.
class ListeningStats {
  final Map<int, int> playCounts; // songId → count
  final Map<int, int> lastPlayed; // songId → timestamp (ms since epoch)
  final int totalListenedMs;
  final int totalSongsPlayed;

  const ListeningStats({
    this.playCounts = const {},
    this.lastPlayed = const {},
    this.totalListenedMs = 0,
    this.totalSongsPlayed = 0,
  });

  ListeningStats copyWith({
    Map<int, int>? playCounts,
    Map<int, int>? lastPlayed,
    int? totalListenedMs,
    int? totalSongsPlayed,
  }) =>
      ListeningStats(
        playCounts: playCounts ?? this.playCounts,
        lastPlayed: lastPlayed ?? this.lastPlayed,
        totalListenedMs: totalListenedMs ?? this.totalListenedMs,
        totalSongsPlayed: totalSongsPlayed ?? this.totalSongsPlayed,
      );

  Map<String, dynamic> toJson() => {
    'playCounts': playCounts.map((k, v) => MapEntry(k.toString(), v)),
    'lastPlayed': lastPlayed.map((k, v) => MapEntry(k.toString(), v)),
    'totalListenedMs': totalListenedMs,
    'totalSongsPlayed': totalSongsPlayed,
  };

  factory ListeningStats.fromJson(Map<String, dynamic> json) {
    return ListeningStats(
      playCounts: (json['playCounts'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(int.parse(k), v as int)) ??
          {},
      lastPlayed: (json['lastPlayed'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(int.parse(k), v as int)) ??
          {},
      totalListenedMs: json['totalListenedMs'] as int? ?? 0,
      totalSongsPlayed: json['totalSongsPlayed'] as int? ?? 0,
    );
  }

  /// Get the top N most played song IDs
  List<int> topPlayed({int limit = 20}) {
    final sorted = playCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }

  /// Get recently played song IDs (most recent first)
  List<int> recentlyPlayed({int limit = 20}) {
    final sorted = lastPlayed.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }

  String get totalListenedFormatted {
    final hours = totalListenedMs ~/ 3600000;
    final minutes = (totalListenedMs % 3600000) ~/ 60000;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

class ListeningStatsNotifier extends Notifier<ListeningStats> {
  static const _storageKey = 'listening_stats';

  @override
  ListeningStats build() {
    _loadFromDisk();
    return const ListeningStats();
  }

  Future<void> _loadFromDisk() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        state = ListeningStats.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
  }

  Future<void> _saveToDisk() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_storageKey, jsonEncode(state.toJson()));
  }

  /// Record a song play event
  void recordPlay(int songId) {
    final newCounts = Map<int, int>.from(state.playCounts);
    newCounts[songId] = (newCounts[songId] ?? 0) + 1;

    final newLastPlayed = Map<int, int>.from(state.lastPlayed);
    newLastPlayed[songId] = DateTime.now().millisecondsSinceEpoch;

    state = state.copyWith(
      playCounts: newCounts,
      lastPlayed: newLastPlayed,
      totalSongsPlayed: state.totalSongsPlayed + 1,
    );
    _saveToDisk();
  }

  /// Add listening time without incrementing play count (for partial listens)
  void addListeningTime(int durationMs) {
    if (durationMs <= 0) return;
    state = state.copyWith(totalListenedMs: state.totalListenedMs + durationMs);
    // Debounce disk writes — only save every 30 seconds of accumulated time
    if (durationMs > 30000) _saveToDisk();
  }

  int getPlayCount(int songId) => state.playCounts[songId] ?? 0;
}

final listeningStatsProvider =
    NotifierProvider<ListeningStatsNotifier, ListeningStats>(ListeningStatsNotifier.new);
