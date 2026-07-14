import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lyric_line.dart';
import '../models/song.dart';
import '../services/lrclib_api.dart';
import '../services/local_lyrics_service.dart';
import '../services/lyrics_cache_service.dart';
import '../utils/lrc_parser.dart';
import '../services/lyrics_plus_api.dart';
import '../services/unison_api.dart';
import '../services/binilyrics_api.dart';
import '../services/musixmatch_api.dart';
import '../utils/ttml_parser.dart';
import '../utils/kpoe_parser.dart';
import '../utils/musixmatch_parser.dart';
import 'audio_state.dart';

// Lyrics Provider
final lyricsProvider = FutureProvider<List<LyricLine>>((ref) async {
  final currentSong = ref.watch(currentSongProvider);
  if (currentSong == null) return [];

  // 0. Serve from the persistent cache when available so each song only hits
  // the network once (upstream lyric APIs rate-limit after a few requests).
  final cacheKey = LyricsCacheService.getLyricsKey(
    title: currentSong.title,
    artist: currentSong.artist,
    duration: currentSong.duration,
  );
  final cached = await LyricsCacheService.loadLyrics(cacheKey);
  if (cached != null && cached.isNotEmpty) {
    return cached;
  }

  List<LyricLine> rawLines = [];

  // 1. Try API-fetched lyrics first, isolating each fetch in its own try-catch
  // so a failure in one provider doesn't abort the search.

  // 1a. LyricsPlus (KPOE) — Apple-Music-style syllable-synced lyrics using /v2 JSON
  if (rawLines.isEmpty) {
    try {
      final kpoeData = await LyricsPlusApi.fetchKpoe(
        currentSong.title,
        currentSong.artist,
        duration: currentSong.duration,
        album: currentSong.album,
      );
      if (kpoeData != null) {
        // ignore: avoid_print
        print('LYRICSPLUS KPOE MATCHED: ${kpoeData['title']} by ${kpoeData['artist']}');
        final lines = KpoeParser.parse(kpoeData);
        if (_validateLyricsLines(lines, currentSong)) {
          rawLines = lines;
          // ignore: avoid_print
          print('LYRICS RESOLVED: LyricsPlus KPOE');
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('LyricsPlus fetch error: $e');
    }
  }

  // 1b. BiniLyrics API — cached high-fidelity syllable-synced Apple Music TTML
  if (rawLines.isEmpty) {
    try {
      final ttmlContent = await BiniLyricsApi.fetchLyrics(
        currentSong.title,
        currentSong.artist,
        duration: currentSong.duration,
        album: currentSong.album,
      );
      if (ttmlContent != null) {
        final lines = TtmlParser.parse(ttmlContent);
        if (_validateLyricsLines(lines, currentSong)) {
          rawLines = lines;
          // ignore: avoid_print
          print('LYRICS RESOLVED: BiniLyrics (TTML)');
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('BiniLyrics fetch error: $e');
    }
  }

  // 1c. Musixmatch richsync — reliable fallback word-by-word timing
  if (rawLines.isEmpty) {
    try {
      final richsync = await MusixmatchApi.fetchRichsync(
        currentSong.title,
        currentSong.artist,
        duration: currentSong.duration,
      );
      if (richsync != null) {
        final lines = MusixmatchParser.parseRichsync(richsync);
        if (lines.isNotEmpty) {
          rawLines = lines;
          // ignore: avoid_print
          print('LYRICS RESOLVED: Musixmatch Richsync');
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Musixmatch fetch error: $e');
    }
  }

  if (rawLines.isEmpty) {
    try {
      final unisonData = await UnisonApi.fetchLyrics(
        currentSong.title,
        currentSong.artist,
        duration: currentSong.duration,
        album: currentSong.album,
      );
      if (unisonData != null) {
        // ignore: avoid_print
        print('UNISON MATCHED: ${unisonData['song']} by ${unisonData['artist']}');
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

          final double songDurationSec =
              currentSong.duration.inMilliseconds / 1000.0;
          final double lyricsDurationSec =
              parsedLines.last.endTime.inMilliseconds / 1000.0;
          if ((lyricsDurationSec - songDurationSec) > 8.0 ||
              (songDurationSec - lyricsDurationSec) > 60.0) {
            isUnisonValid = false;
          }

          if (isUnisonValid) {
            rawLines = parsedLines;
            // ignore: avoid_print
            print('LYRICS RESOLVED: Unison');
          }
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Unison fetch error: $e');
    }
  }

  if (rawLines.isEmpty) {
    try {
      final rawLyrics = await LrcLibApi.fetchLyrics(
        currentSong.title,
        currentSong.artist,
        duration: currentSong.duration,
      );
      if (rawLyrics != null && rawLyrics.isNotEmpty) {
        rawLines = LrcParser.parse(rawLyrics);
        // ignore: avoid_print
        print('LYRICS RESOLVED: LRCLib Synced');
      }
    } catch (e) {
      // ignore: avoid_print
      print('LRCLib fetch error: $e');
    }
  }

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
    if (lowerText == '$cleanTitle - $cleanArtist' ||
        lowerText == '$cleanArtist - $cleanTitle' ||
        lowerText == '$cleanTitle by $cleanArtist') {
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
        withGaps.add(
          LyricLine(
            startTime: currentEnd,
            endTime: nextStart,
            text: '• • •',
            isGap: true,
          ),
        );
      }
    }
  }

  // 4. Duet / Singer Dual-Side Layout Assignment
  final individualSingers = <String>{};
  for (final line in withGaps) {
    if (line.isGap || line.singer == null) continue;
    final s = line.singer!.toLowerCase();
    if (s.contains('group') ||
        s.contains('all') ||
        s.contains('both') ||
        s.contains('chorus')) {
      continue;
    }
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
        if (sLower.contains('group') ||
            sLower.contains('all') ||
            sLower.contains('both') ||
            sLower.contains('chorus')) {
          assigned.add(line.copyWith(singerSide: 'center'));
        } else {
          if (!singerSideMap.containsKey(singer)) {
            currentSide = (currentSide == 'left') ? 'right' : 'left';
            singerSideMap[singer] = currentSide;
          }
          final side = singerSideMap[singer]!;
          assigned.add(line.copyWith(singerSide: side));
          if (side == 'left') {
            leftCount++;
          } else {
            rightCount++;
          }
          totalDuetLines++;
        }
      }
    }

    List<LyricLine> result = assigned;
    if (totalDuetLines > 0) {
      final double leftRatio = leftCount / totalDuetLines;
      final double rightRatio = rightCount / totalDuetLines;
      if (leftRatio >= 0.85 || rightRatio >= 0.85) {
        result = withGaps;
      }
    }
    await LyricsCacheService.saveLyrics(cacheKey, result);
    return result;
  }

  await LyricsCacheService.saveLyrics(cacheKey, withGaps);
  return withGaps;
});

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

bool _validateLyricsLines(List<LyricLine> lines, Song currentSong) {
  if (lines.isEmpty) return false;

  // 1. Duration verification (reject if lyrics exceed song duration by > 8s or are shorter by > 60s)
  final double songDurationSec = currentSong.duration.inMilliseconds / 1000.0;
  final double lyricsDurationSec = lines.last.endTime.inMilliseconds / 1000.0;
  if ((lyricsDurationSec - songDurationSec) > 8.0 ||
      (songDurationSec - lyricsDurationSec) > 60.0) {
    return false;
  }

  // 2. Language/version verification (Japanese CJK character checks for English tracks)
  final bool playingIsEnglish = currentSong.title
      .toLowerCase()
      .contains(RegExp(r'\b(english|eng)\b'));
  int cjkCount = 0;
  final int checkLimit = math.min(lines.length, 15);
  for (int i = 0; i < checkLimit; i++) {
    if (_hasCJKCharacters(lines[i].text)) {
      cjkCount++;
    }
  }
  if (playingIsEnglish && cjkCount > 2) {
    return false;
  }

  return true;
}
