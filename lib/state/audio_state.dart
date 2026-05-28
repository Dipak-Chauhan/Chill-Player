import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/song.dart';
import 'package:audio_service/audio_service.dart';
import '../services/audio_handler.dart';
import '../models/lyric_line.dart';
import '../services/lrclib_api.dart';
import '../services/local_lyrics_service.dart';
import '../utils/lrc_parser.dart';
import '../services/lyrics_plus_api.dart';
import '../services/unison_api.dart';
import '../utils/ttml_parser.dart';
import '../services/listening_stats_service.dart';
import '../services/settings_service.dart';
import '../services/playback_persistence.dart';

// ---------------------------------------------------------------------------
// Core Audio Engine & Handler
// ---------------------------------------------------------------------------
final audioHandlerProvider = Provider<AudioHandler>((ref) => throw UnimplementedError());

final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final handler = ref.watch(audioHandlerProvider) as ChillAudioHandler;
  return handler.player;
});

final androidEqualizerProvider = Provider<AndroidEqualizer>((ref) {
  final handler = ref.watch(audioHandlerProvider) as ChillAudioHandler;
  return handler.equalizer;
});

// ---------------------------------------------------------------------------
// Queue Management
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

/// Firewall provider to temporarily mask transient just_audio ExoPlayer stream emissions 
class IsSwappingPlaylistNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void setSwapping(bool val) => state = val;
}
final isSwappingPlaylistProvider = NotifierProvider<IsSwappingPlaylistNotifier, bool>(IsSwappingPlaylistNotifier.new);

class QueueNotifier extends Notifier<List<Song>> {
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

  Future<void> setQueue(List<Song> songs, {int? initialIndex, Duration? initialPosition}) async {
    ref.read(isSwappingPlaylistProvider.notifier).setSwapping(true);
    state = songs;
    final player = ref.read(audioPlayerProvider);
    
    // Create ConcatenatingAudioSource for gapless playback & immediate skip
    final playlist = ConcatenatingAudioSource(
      children: songs.map((song) => AudioSource.uri(
        Uri.file(song.uri),
        tag: MediaItem(
          id: song.id.toString(),
          album: song.album,
          title: song.title,
          artist: song.artist,
          duration: song.duration,
          artUri: Uri.parse('content://media/external/audio/media/${song.id}/albumart'),
        ),
      )).toList(),
    );
    
    await player.setAudioSource(
      playlist,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );
    
    // Once explicitly verified and mounted, drop the firewall firewall and force the UI sync
    ref.read(isSwappingPlaylistProvider.notifier).setSwapping(false);
    ref.read(currentSongProvider.notifier).forceSync();
  }

  /// Reorder a song in the queue from oldIndex to newIndex
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final list = List<Song>.from(state);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex < oldIndex ? newIndex : newIndex, item);
    state = list;

    // Also reorder in the audio player's concatenating source
    final player = ref.read(audioPlayerProvider);
    if (player.audioSource is ConcatenatingAudioSource) {
      (player.audioSource as ConcatenatingAudioSource).move(oldIndex, newIndex);
    }
  }

  /// Remove a song from the queue
  void removeAt(int index) {
    final list = List<Song>.from(state);
    list.removeAt(index);
    state = list;

    final player = ref.read(audioPlayerProvider);
    if (player.audioSource is ConcatenatingAudioSource) {
      (player.audioSource as ConcatenatingAudioSource).removeAt(index);
    }
  }
}
final queueProvider = NotifierProvider<QueueNotifier, List<Song>>(QueueNotifier.new);

// ---------------------------------------------------------------------------
// Reactive UI Proxies (Syncs just_audio streams identically to old UI state)
// ---------------------------------------------------------------------------
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
      if (ref.read(isSwappingPlaylistProvider)) return;

      final queue = ref.read(queueProvider);
      if (index != null && index >= 0 && index < queue.length) {
        final newSong = queue[index];
        if (state?.id != newSong.id) {
          // Record play stat
          ref.read(listeningStatsProvider.notifier).recordPlay(
            newSong.id,
            durationMs: newSong.duration.inMilliseconds,
          );
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
      final prefs = ref.read(sharedPreferencesProvider);
      PlaybackPersistence.save(
        prefs: prefs,
        songId: song.id,
        positionMs: ref.read(audioPlayerProvider).position.inMilliseconds,
        queueIds: queue.map((s) => s.id).toList(),
        queueIndex: index,
        songJson: jsonEncode(song.toJson()),
      );
    } catch (_) {} // Don't let persistence errors affect playback
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
              final prefs = ref.read(sharedPreferencesProvider);
              PlaybackPersistence.save(
                prefs: prefs,
                songId: currentSong.id,
                positionMs: player.position.inMilliseconds,
                queueIds: queue.map((s) => s.id).toList(),
                queueIndex: player.currentIndex!,
              );
            } catch (_) {}
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
  
  // Expose methods to UI
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
      // Calculate delta for listening stats
      if (pos > _lastPos) {
        final deltaMs = (pos - _lastPos).inMilliseconds;
        // Ignore giant jumps (seeking) — only count natural playback (<2s delta)
        if (deltaMs > 0 && deltaMs < 2000) {
          ref.read(listeningStatsProvider.notifier).addListeningTime(deltaMs);
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
            PlaybackPersistence.save(
              prefs: ref.read(sharedPreferencesProvider),
              songId: currentSong.id,
              positionMs: pos.inMilliseconds,
              queueIds: queue.map((s) => s.id).toList(),
              queueIndex: player.currentIndex!,
              songJson: jsonEncode(currentSong.toJson()),
            );
          } catch (_) {}
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

class ShuffleModeNotifier extends Notifier<bool> {
  StreamSubscription? _sub;

  @override
  bool build() {
    final player = ref.watch(audioPlayerProvider);
    _sub?.cancel();
    _sub = player.shuffleModeEnabledStream.listen((shuffle) {
      if (state != shuffle) state = shuffle;
    });
    ref.onDispose(() => _sub?.cancel());
    return false;
  }

  void toggle() {
    final player = ref.read(audioPlayerProvider);
    player.setShuffleModeEnabled(!state);
  }
}
final shuffleModeProvider = NotifierProvider<ShuffleModeNotifier, bool>(ShuffleModeNotifier.new);

class LoopModeNotifier extends Notifier<LoopMode> {
  StreamSubscription? _sub;

  @override
  LoopMode build() {
    final player = ref.watch(audioPlayerProvider);
    _sub?.cancel();
    _sub = player.loopModeStream.listen((loopMode) {
      if (state != loopMode) state = loopMode;
    });
    ref.onDispose(() => _sub?.cancel());
    return LoopMode.off;
  }

  void toggle() {
    final player = ref.read(audioPlayerProvider);
    final current = state;
    if (current == LoopMode.off) {
      player.setLoopMode(LoopMode.all);
    } else if (current == LoopMode.all) {
      player.setLoopMode(LoopMode.one);
    } else {
      player.setLoopMode(LoopMode.off);
    }
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

// ---------------------------------------------------------------------------
// Lyrics Provider
// ---------------------------------------------------------------------------
final lyricsProvider = FutureProvider<List<LyricLine>>((ref) async {
  final currentSong = ref.watch(currentSongProvider);
  if (currentSong == null) return [];

  List<LyricLine> rawLines = [];

  // 1. Try API-fetched lyrics first (default)
  try {
    // 1a. Attempt Apple Music Style Syllable Synced TTML from LyricsPlus
    final ttmlData = await LyricsPlusApi.fetchTTML(
      currentSong.title,
      currentSong.artist,
      duration: currentSong.duration,
      album: currentSong.album,
    );
    if (ttmlData != null && ttmlData.isNotEmpty) {
      final lines = TtmlParser.parse(ttmlData);
      if (lines.isNotEmpty) {
        bool isTtmlValid = true;
        
        // 1. Duration verification (relax to allow for outros: reject only if lyrics exceed song duration by > 20s or are shorter by > 90s)
        final double songDurationSec = currentSong.duration.inMilliseconds / 1000.0;
        final double lyricsDurationSec = lines.last.endTime.inMilliseconds / 1000.0;
        if ((lyricsDurationSec - songDurationSec) > 20.0 || (songDurationSec - lyricsDurationSec) > 90.0) {
          isTtmlValid = false;
        }

        // 2. Language/version verification (Japanese CJK character checks for English tracks)
        if (isTtmlValid) {
          final bool playingIsEnglish = currentSong.title.toLowerCase().contains(RegExp(r'\b(english|eng)\b'));
          int cjkCount = 0;
          final int checkLimit = math.min(lines.length, 15);
          for (int i = 0; i < checkLimit; i++) {
            if (_hasCJKCharacters(lines[i].text)) {
              cjkCount++;
            }
          }
          if (playingIsEnglish && cjkCount > 2) {
            isTtmlValid = false;
          }
        }

        if (isTtmlValid) {
          rawLines = lines;
        }
      }
    }

    // 1b. Fallback: Attempt synced/syllable/line lyrics from Unison API
    if (rawLines.isEmpty) {
      final unisonData = await UnisonApi.fetchLyrics(
        currentSong.title,
        currentSong.artist,
        duration: currentSong.duration,
        album: currentSong.album,
      );
      if (unisonData != null) {
        final lyrics = unisonData['lyrics']!;
        final format = unisonData['format']!;
        
        List<LyricLine> parsedLines = [];
        if (format == 'ttml') {
          parsedLines = TtmlParser.parse(lyrics);
        } else if (format == 'lrc') {
          parsedLines = LrcParser.parse(lyrics);
        }

        if (parsedLines.isNotEmpty) {
          bool isUnisonValid = true;
          
          final double songDurationSec = currentSong.duration.inMilliseconds / 1000.0;
          final double lyricsDurationSec = parsedLines.last.endTime.inMilliseconds / 1000.0;
          if ((lyricsDurationSec - songDurationSec) > 20.0 || (songDurationSec - lyricsDurationSec) > 90.0) {
            isUnisonValid = false;
          }

          if (isUnisonValid) {
            rawLines = parsedLines;
          }
        }
      }
    }

    // 1c. Fallback to standard line-by-line synced LRC from LRCLib
    if (rawLines.isEmpty) {
      final rawLyrics = await LrcLibApi.fetchLyrics(
        currentSong.title,
        currentSong.artist,
        duration: currentSong.duration,
      );
      if (rawLyrics != null && rawLyrics.isNotEmpty) {
        rawLines = LrcParser.parse(rawLyrics);
      }
    }
  } catch (_) {
    // API failed (no internet, timeout, etc.) — will fall through to local
  }

  // 2. Fallback: Use locally saved custom lyrics if API didn't return anything
  if (rawLines.isEmpty) {
    final localLyrics = await LocalLyricsService.loadLyrics(currentSong.id);
    if (localLyrics != null && localLyrics.isNotEmpty) {
      if (LocalLyricsService.isTtml(localLyrics)) {
        // Local TTML/ELRC — parse with TTML parser for syllable sync
        rawLines = TtmlParser.parse(localLyrics);
      } else {
        // Local LRC or plain text
        rawLines = LrcParser.parse(localLyrics);
      }
    }
  }

  if (rawLines.isEmpty) return [];

  // 2.5. Post-process: Filter out prefixed credits & metadata from the start
  final metadataRegex = RegExp(
    r'^(?:(?:.*?(?:Song)?Writers?|.*?Producers?|.*?Vocals?|.*?Singers?|Music|Lyrics|Composition|Publisher|Album|Title|Artist|Sync(?:hronized)?|LRC|Track|Release)\s*:|'
    r'(?:Written|Produced|Composed|Arranged|Translated|Mixed|Mastered|Performed|Sync(?:hronized)?|Provided|Lyrics?|Music)\s+by\b)',
    caseSensitive: false,
  );

  final cleanTitle = currentSong.title.toLowerCase().trim();
  final cleanArtist = currentSong.artist.toLowerCase().trim();

  int firstRealIdx = 0;
  for (int i = 0; i < rawLines.length; i++) {
    final text = rawLines[i].text.trim();
    final lowerText = text.toLowerCase();

    if (text.isEmpty || metadataRegex.hasMatch(text)) {
      continue; // skip metadata blocks
    }

    // Skip unstructured injections of the song title or artist name itself
    if (lowerText == cleanTitle || lowerText == cleanArtist) {
      continue;
    }
    // Skip compound injections "Artist - Title"
    if (lowerText == '$cleanTitle - $cleanArtist' || lowerText == '$cleanArtist - $cleanTitle' || lowerText == '$cleanTitle by $cleanArtist') {
      continue;
    }

    firstRealIdx = i;
    break; // found the first actual lyric
  }

  if (firstRealIdx > 0 && firstRealIdx < rawLines.length) {
    rawLines = rawLines.sublist(firstRealIdx);
  }

  // 3. Post-process: inject instrumental gap markers (≥ 4s silence → bouncing dots)
  const gapThreshold = Duration(seconds: 4);
  final List<LyricLine> withGaps = [];
  for (int i = 0; i < rawLines.length; i++) {
    withGaps.add(rawLines[i]);
    if (i < rawLines.length - 1) {
      final currentEnd = rawLines[i].endTime;
      final nextStart = rawLines[i + 1].startTime;
      if (nextStart - currentEnd >= gapThreshold) {
        withGaps.add(LyricLine(
          startTime: currentEnd,
          endTime: nextStart,
          text: '• • •',
          isGap: true,
        ));
      }
    }
  }

  // 4. Duet / Singer Dual-Side Layout Assignment
  final individualSingers = <String>{};
  for (final line in withGaps) {
    if (line.isGap || line.singer == null) continue;
    final s = line.singer!.toLowerCase();
    if (s.contains('group') || s.contains('all') || s.contains('both') || s.contains('chorus')) continue;
    individualSingers.add(line.singer!);
  }

  if (individualSingers.length >= 2) {
    final Map<String, String> singerSideMap = {};
    String currentSide = 'left';
    int leftCount = 0;
    int rightCount = 0;
    int totalDuetLines = 0;

    final List<LyricLine> assigned = [];
    for (var line in withGaps) {
      if (line.isGap) {
        assigned.add(line);
        continue;
      }
      final singer = line.singer;
      if (singer == null) {
        assigned.add(line.copyWith(singerSide: 'left'));
        leftCount++;
        totalDuetLines++;
      } else {
        final sLower = singer.toLowerCase();
        if (sLower.contains('group') || sLower.contains('all') || sLower.contains('both') || sLower.contains('chorus')) {
          assigned.add(line.copyWith(singerSide: 'center'));
        } else {
          if (!singerSideMap.containsKey(singer)) {
            currentSide = (currentSide == 'left') ? 'right' : 'left';
            singerSideMap[singer] = currentSide;
          }
          final side = singerSideMap[singer]!;
          assigned.add(line.copyWith(singerSide: side));
          if (side == 'left') leftCount++; else rightCount++;
          totalDuetLines++;
        }
      }
    }

    if (totalDuetLines > 0) {
      final double leftRatio = leftCount / totalDuetLines;
      final double rightRatio = rightCount / totalDuetLines;
      if (leftRatio >= 0.85 || rightRatio >= 0.85) {
        return withGaps;
      }
    }
    return assigned;
  }

  return withGaps;
});

class IsScrollingNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void setScrolling(bool val) => state = val;
}
final isScrollingProvider = NotifierProvider<IsScrollingNotifier, bool>(IsScrollingNotifier.new);

bool _hasCJKCharacters(String text) {
  for (int i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if ((code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3040 && code <= 0x309F) ||
        (code >= 0x30A0 && code <= 0x30FF) ||
        (code >= 0xAC00 && code <= 0xD7A3)) {
      return true;
    }
  }
  return false;
}

