import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/song.dart';
import '../services/listening_stats_service.dart';
import '../services/settings_service.dart';
import '../services/playback_persistence.dart';
import 'audio_engine.dart';
import 'queue_provider.dart';

// Reactive UI Proxies (Syncs just_audio streams identically to old UI state)
class CurrentSongNotifier extends Notifier<Song?> {
  StreamSubscription? _sub;

  @override
  Song? build() {
    Song? initialSong;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final savedState = PlaybackPersistence.load(prefs);
      if (savedState != null && savedState.songJson != null) {
        initialSong = Song.fromJson(jsonDecode(savedState.songJson!) as Map<String, dynamic>);
      }
    } catch (_) {}

    final player = ref.watch(audioPlayerProvider);
    _sub?.cancel();
    _sub = player.currentIndexStream.listen((index) {
      // FIREWALL: Do not let just_audio dictate the UI during massive native playlist 15k swaps!
      if (ref.read(isSwappingPlaylistProvider)) {
        final expected = ref.read(expectedPlayerIndexProvider);
        if (expected != null && index == expected) {
          // The player has arrived at our expected index! Disengage the firewall instantly!
          ref.read(isSwappingPlaylistProvider.notifier).setSwapping(false);
          ref.read(expectedPlayerIndexProvider.notifier).clear();
        } else {
          return;
        }
      }

      final queue = ref.read(queueProvider);
      if (index != null && index >= 0 && index < queue.length) {
        final newSong = queue[index];
        if (state?.id != newSong.id) {
          state = newSong;

          // Persist playback state for app restart recovery
          _savePlaybackState(newSong, index, queue);
        }
      } else if (state != null) {
        // If index is null (which happens during the 1-2 second just_audio native boot-up phase),
        // we should NOT wipe the initial instantly-cached song unless the playlist is genuinely empty.
        if (queue.isEmpty) {
          state = null;
        }
      }
    });
    
    ref.onDispose(() => _sub?.cancel());
    return initialSong;
  }

  void forceSync() {
    final player = ref.read(audioPlayerProvider);
    final queue = ref.read(queueProvider);
    final index = player.currentIndex;
    if (index != null && index >= 0 && index < queue.length) {
      final newSong = queue[index];
      if (state?.id != newSong.id) {
         state = newSong;
      }
    }
  }

  Future<void> stop() async {
    final player = ref.read(audioPlayerProvider);
    await player.stop();
    
    // Clear queue notifier
    ref.read(queueProvider.notifier).state = [];
    
    state = null;
    
    // Clear saved playback state
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await PlaybackPersistence.clear(prefs);
    } catch (_) {}
  }

  void _savePlaybackState(Song song, int index, List<Song> queue) {
    try {
      final originalQueue = ref.read(queueProvider.notifier).originalQueue;
      PlaybackPersistence.saveSnapshot(
        prefs: ref.read(sharedPreferencesProvider),
        song: song,
        positionMs: ref.read(audioPlayerProvider).position.inMilliseconds,
        queue: queue,
        queueIndex: index,
        originalQueue: originalQueue,
      );
    } catch (e, st) {
      // Don't let persistence errors affect playback, but don't hide them either.
      debugPrint('Failed to persist playback state: $e\n$st');
    }
  }
}
final currentSongProvider = NotifierProvider<CurrentSongNotifier, Song?>(CurrentSongNotifier.new);

class IsPlayingNotifier extends Notifier<bool> {
  StreamSubscription? _sub;

  @override
  bool build() {
    final player = ref.watch(audioPlayerProvider);
    _sub?.cancel();
    _sub = player.playingStream.listen((playing) {
      if (state != playing) {
        state = playing;
        // Manage wakelock based on playback state to save battery
        if (playing) {
          WakelockPlus.enable();
        } else {
          WakelockPlus.disable();
          
          // Save playback state (including position) when paused
          final queue = ref.read(queueProvider);
          final currentSong = ref.read(currentSongProvider);
          if (currentSong != null && player.currentIndex != null) {
            try {
              final originalQueue = ref.read(queueProvider.notifier).originalQueue;
              PlaybackPersistence.saveSnapshot(
                prefs: ref.read(sharedPreferencesProvider),
                song: currentSong,
                positionMs: player.position.inMilliseconds,
                queue: queue,
                queueIndex: player.currentIndex!,
                originalQueue: originalQueue,
              );
            } catch (e, st) {
              debugPrint('Failed to persist playback state on pause: $e\n$st');
            }
          }
        }
      }
    });
    ref.onDispose(() {
      _sub?.cancel();
      WakelockPlus.disable(); // Always release on dispose
    });
    return false;
  }
  
  void play() => ref.read(audioPlayerProvider).play();
  void pause() => ref.read(audioPlayerProvider).pause();
  void toggle() => state ? pause() : play();
}
final isPlayingProvider = NotifierProvider<IsPlayingNotifier, bool>(IsPlayingNotifier.new);

class PlaybackPositionNotifier extends Notifier<Duration> {
  StreamSubscription? _posSub;
  StreamSubscription? _indexSub;
  Duration _lastPos = Duration.zero;
  Duration _lastSavePos = Duration.zero;
  bool _isCrossfading = false;

  int? _currentRecordedSongId;
  int _currentSongAccumulatedMs = 0;
  int? _lastActiveSongId;

  @override
  Duration build() {
    Duration initialPosition = Duration.zero;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final savedState = PlaybackPersistence.load(prefs);
      if (savedState != null) {
        initialPosition = Duration(milliseconds: savedState.positionMs);
        _lastPos = initialPosition;
        _lastSavePos = initialPosition;
      }
    } catch (_) {}

    final player = ref.watch(audioPlayerProvider);
    _posSub?.cancel();
    _indexSub?.cancel();

    // Listen for track changes to reset volume after crossfade
    _indexSub = player.currentIndexStream.listen((_) {
      if (_isCrossfading) {
        player.setVolume(1.0);
        _isCrossfading = false;
      }
    });

    _posSub = player.positionStream.listen((pos) {
      final currentSong = ref.read(currentSongProvider);
      if (currentSong != null) {
        if (_lastActiveSongId != currentSong.id) {
          _lastActiveSongId = currentSong.id;
          _currentSongAccumulatedMs = 0;
        }
      }

      // Reset record status if the user seeks backwards significantly or song loops
      if (pos < _lastPos - const Duration(seconds: 5)) {
        _currentRecordedSongId = null;
        _currentSongAccumulatedMs = 0;
      }

      // Calculate delta for listening stats
      if (pos > _lastPos) {
        final deltaMs = (pos - _lastPos).inMilliseconds;
        // Ignore giant jumps (seeking) — only count natural playback (<2s delta)
        if (deltaMs > 0 && deltaMs < 2000) {
          ref.read(listeningStatsProvider.notifier).addListeningTime(deltaMs);

          if (currentSong != null && _currentRecordedSongId != currentSong.id) {
            _currentSongAccumulatedMs += deltaMs;
            final thresholdMs = (currentSong.duration.inMilliseconds / 2).clamp(0, 30000).toInt();
            if (_currentSongAccumulatedMs >= thresholdMs) {
              ref.read(listeningStatsProvider.notifier).recordPlay(currentSong.id);
              _currentRecordedSongId = currentSong.id;
            }
          }
        }
      }
      _lastPos = pos;
      state = pos;

      // Periodically save state (every 5 seconds) to handle app kills/swipes
      final deltaSave = (pos - _lastSavePos).inSeconds.abs();
      if (deltaSave >= 5) {
        _lastSavePos = pos;
        final currentSong = ref.read(currentSongProvider);
        if (currentSong != null && player.currentIndex != null) {
          try {
            final queue = ref.read(queueProvider);
            final originalQueue = ref.read(queueProvider.notifier).originalQueue;
            PlaybackPersistence.saveSnapshot(
              prefs: ref.read(sharedPreferencesProvider),
              song: currentSong,
              positionMs: pos.inMilliseconds,
              queue: queue,
              queueIndex: player.currentIndex!,
              originalQueue: originalQueue,
            );
          } catch (e, st) {
            debugPrint('Failed to persist playback position: $e\n$st');
          }
        }
      }

      // Crossfade logic — fade volume near end of track
      _handleCrossfade(player, pos);
    });
    ref.onDispose(() {
      _posSub?.cancel();
      _indexSub?.cancel();
    });
    return initialPosition;
  }

  void _handleCrossfade(AudioPlayer player, Duration pos) {
    final crossfadeSecs = ref.read(crossfadeDurationProvider);
    if (crossfadeSecs <= 0) return; // Disabled

    final duration = player.duration;
    if (duration == null || duration.inSeconds < crossfadeSecs + 5) return; // Too short

    final remaining = duration - pos;
    final fadeZone = Duration(seconds: crossfadeSecs);

    if (remaining <= fadeZone && remaining > Duration.zero) {
      // Calculate fade progress (1.0 at start of zone → 0.05 at end)
      final progress = remaining.inMilliseconds / fadeZone.inMilliseconds;
      final volume = (progress * 0.95 + 0.05).clamp(0.05, 1.0);
      player.setVolume(volume);
      _isCrossfading = true;
    } else if (_isCrossfading && remaining > fadeZone) {
      // User seeked back out of crossfade zone
      player.setVolume(1.0);
      _isCrossfading = false;
    }
  }
}
final playbackPositionProvider = NotifierProvider<PlaybackPositionNotifier, Duration>(PlaybackPositionNotifier.new);

class LoopModeNotifier extends Notifier<LoopMode> {
  StreamSubscription? _sub;

  @override
  LoopMode build() {
    final player = ref.watch(audioPlayerProvider);
    final prefs = ref.watch(sharedPreferencesProvider);

    final savedModeStr = prefs.getString('loop_mode') ?? 'off';
    final initialMode = LoopMode.values.firstWhere(
      (m) => m.name == savedModeStr,
      orElse: () => LoopMode.off,
    );

    // Apply the saved loop mode to the player asynchronously
    player.setLoopMode(initialMode);

    _sub?.cancel();
    _sub = player.loopModeStream.listen((loopMode) {
      if (state != loopMode) {
        state = loopMode;
        prefs.setString('loop_mode', loopMode.name);
      }
    });
    ref.onDispose(() => _sub?.cancel());
    return initialMode;
  }

  void toggle() {
    final player = ref.read(audioPlayerProvider);
    final current = state;
    LoopMode next;
    if (current == LoopMode.off) {
      next = LoopMode.all;
    } else if (current == LoopMode.all) {
      next = LoopMode.one;
    } else {
      next = LoopMode.off;
    }
    player.setLoopMode(next);
    
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString('loop_mode', next.name);
  }
}
final loopModeProvider = NotifierProvider<LoopModeNotifier, LoopMode>(LoopModeNotifier.new);

// Now Playing screen AMOLED toggle (transient, not persisted)
class NowPlayingAmoledNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}
final nowPlayingAmoledProvider = NotifierProvider<NowPlayingAmoledNotifier, bool>(NowPlayingAmoledNotifier.new);

class IsScrollingNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void setScrolling(bool val) => state = val;
}
final isScrollingProvider = NotifierProvider<IsScrollingNotifier, bool>(IsScrollingNotifier.new);
