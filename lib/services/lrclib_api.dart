import 'dart:convert';

import '../utils/query_normalizer.dart';
import 'api_client.dart';

class LrcLibApi {
  static const String _baseUrl = 'https://lrclib.net/api';

  /// Fetches lyrics from LRCLIB. Returns synced lyrics if available,
  /// otherwise falls back to plain lyrics. Returns null if nothing is found.
  static Future<String?> fetchLyrics(
    String trackName,
    String artistName, {
    Duration? duration,
  }) async {
    try {
      final cleanedTrack = LyricQueryNormalizer.cleanTrackName(trackName);
      final cleanedArtist = LyricQueryNormalizer.cleanArtistName(artistName);

      // Fast path: LRCLIB's indexed/cached lookup endpoint. It responds
      // quickly, unlike /search which does slow full-text lookups and often
      // times out on weaker connections. Duration is intentionally omitted:
      // /get treats it as a strict (±2s) filter and 404s on any mismatch.
      // But we verify duration of the returned payload to reject wrong versions.
      final direct = await _directGet(
        cleanedTrack,
        cleanedArtist,
        targetDuration: duration,
      );
      if (direct != null) return direct;

      final List<dynamic>? data = await _searchApi(cleanedTrack, cleanedArtist);
      if (data != null && data.isNotEmpty) {
        dynamic bestCandidate;
        int bestScore = -9999;

        for (final item in data) {
          final candidate = item as Map<String, dynamic>;
          final score = _scoreCandidate(
            candidate,
            trackName,
            artistName,
            duration,
          );
          if (score > bestScore) {
            bestScore = score;
            bestCandidate = candidate;
          }
        }

        if (bestCandidate != null && bestScore > 0) {
          final synced = bestCandidate['syncedLyrics'] as String?;
          final plain = bestCandidate['plainLyrics'] as String?;
          if (synced != null && synced.isNotEmpty) {
            return synced;
          } else if (plain != null && plain.isNotEmpty) {
            return plain;
          }
        }
      }

      // Fallback: search just by track name if strict match fails (like Rush's strategy)
      return await _fallbackSearch(trackName, artistName, duration);
    } catch (e) {
      // ignore: avoid_print
      print('Error fetching lyrics: $e');
      return null;
    }
  }

  /// Fetches ONLY synced (timestamped) lyrics. Returns null if not available.
  static Future<String?> fetchSyncedLyrics(
    String trackName,
    String artistName, {
    Duration? duration,
  }) async {
    try {
      final cleanedTrack = LyricQueryNormalizer.cleanTrackName(trackName);
      final cleanedArtist = LyricQueryNormalizer.cleanArtistName(artistName);

      final data = await _searchApi(cleanedTrack, cleanedArtist);
      if (data == null) return null;

      dynamic bestCandidate;
      int bestScore = -9999;

      for (final item in data) {
        final candidate = item as Map<String, dynamic>;
        final synced = candidate['syncedLyrics'] as String?;
        if (synced == null || synced.isEmpty) continue;

        final score = _scoreCandidate(
          candidate,
          trackName,
          artistName,
          duration,
        );
        if (score > bestScore) {
          bestScore = score;
          bestCandidate = candidate;
        }
      }

      if (bestCandidate != null && bestScore > 0) {
        return bestCandidate['syncedLyrics'] as String;
      }
    } catch (_) {}
    return null;
  }

  /// Fetches ONLY plain (unsynced) lyrics. Returns null if not available.
  static Future<String?> fetchPlainLyrics(
    String trackName,
    String artistName, {
    Duration? duration,
  }) async {
    try {
      final cleanedTrack = LyricQueryNormalizer.cleanTrackName(trackName);
      final cleanedArtist = LyricQueryNormalizer.cleanArtistName(artistName);

      final data = await _searchApi(cleanedTrack, cleanedArtist);
      if (data == null) return null;

      dynamic bestCandidate;
      int bestScore = -9999;

      for (final item in data) {
        final candidate = item as Map<String, dynamic>;
        final plain = candidate['plainLyrics'] as String?;
        if (plain == null || plain.isEmpty) continue;

        final score = _scoreCandidate(
          candidate,
          trackName,
          artistName,
          duration,
        );
        if (score > bestScore) {
          bestScore = score;
          bestCandidate = candidate;
        }
      }

      if (bestCandidate != null && bestScore > 0) {
        return bestCandidate['plainLyrics'] as String;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _directGet(
    String trackName,
    String artistName, {
    Duration? targetDuration,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/get').replace(
        queryParameters: {'track_name': trackName, 'artist_name': artistName},
      );
      final response = await ApiClient.get(
        uri,
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final Map<String, dynamic> obj = jsonDecode(decodedBody);
        
        if (targetDuration != null) {
          final double? candDurationSec = (obj['duration'] as num?)?.toDouble();
          if (candDurationSec != null && candDurationSec > 0.0) {
            final double tarDurationSec = targetDuration.inMilliseconds / 1000.0;
            if ((tarDurationSec - candDurationSec).abs() > 8.0) {
              return null; // Reject direct get if duration mismatch is too large
            }
          }
        }

        final synced = obj['syncedLyrics'] as String?;
        final plain = obj['plainLyrics'] as String?;
        if (synced != null && synced.isNotEmpty) {
          // ignore: avoid_print
          print('LRCLIB DIRECT MATCHED: ${obj['trackName']} by ${obj['artistName']} (synced)');
          return synced;
        }
        if (plain != null && plain.isNotEmpty) {
          // ignore: avoid_print
          print('LRCLIB DIRECT MATCHED: ${obj['trackName']} by ${obj['artistName']} (plain)');
          return plain;
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('LRCLIB /get EXCEPTION: $e');
    }
    return null;
  }

  /// Common search API call, returns decoded JSON list or null.
  static Future<List<dynamic>?> _searchApi(
    String trackName,
    String artistName,
  ) async {
    final uri = Uri.parse('$_baseUrl/search').replace(
      queryParameters: {'track_name': trackName, 'artist_name': artistName},
    );

    final response = await ApiClient.get(
      uri,
      timeout: const Duration(seconds: 10),
    );

    if (response.statusCode == 200) {
      final decodedBody = utf8.decode(response.bodyBytes);
      final List<dynamic> data = jsonDecode(decodedBody);
      if (data.isNotEmpty) return data;
    }
    return null;
  }

  static Future<String?> _fallbackSearch(
    String trackName,
    String artistName,
    Duration? duration,
  ) async {
    try {
      final cleanedTrack = LyricQueryNormalizer.cleanTrackName(trackName);
      final uri = Uri.parse(
        '$_baseUrl/search',
      ).replace(queryParameters: {'q': cleanedTrack});

      final response = await ApiClient.get(
        uri,
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final List<dynamic> data = jsonDecode(decodedBody);
        if (data.isNotEmpty) {
          dynamic bestCandidate;
          int bestScore = -9999;

          for (final item in data) {
            final candidate = item as Map<String, dynamic>;
            final score = _scoreCandidate(
              candidate,
              trackName,
              artistName,
              duration,
            );
            if (score > bestScore) {
              bestScore = score;
              bestCandidate = candidate;
            }
          }

          if (bestCandidate != null && bestScore > 0) {
            // ignore: avoid_print
            print('LRCLIB SEARCH MATCHED: ${bestCandidate['trackName']} by ${bestCandidate['artistName']} (Score: $bestScore)');
            final synced = bestCandidate['syncedLyrics'] as String?;
            final plain = bestCandidate['plainLyrics'] as String?;
            if (synced != null && synced.isNotEmpty) return synced;
            if (plain != null && plain.isNotEmpty) return plain;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Ranking Helper
  // ---------------------------------------------------------------------------

  static int _scoreCandidate(
    Map<String, dynamic> candidate,
    String targetTrack,
    String targetArtist,
    Duration? targetDuration,
  ) {
    int score = 0;

    final String candTrack = (candidate['trackName'] as String? ?? '')
        .toLowerCase()
        .trim();
    final String candArtist = (candidate['artistName'] as String? ?? '')
        .toLowerCase()
        .trim();
    final double? candDurationSec = (candidate['duration'] as num?)?.toDouble();

    final String tarTrack = targetTrack.toLowerCase().trim();
    final String tarArtist = targetArtist.toLowerCase().trim();

    // 1. DURATION MATCHING (High importance!)
    if (targetDuration != null &&
        candDurationSec != null &&
        candDurationSec > 0.0) {
      final double tarDurationSec = targetDuration.inMilliseconds / 1000.0;
      final double diff = (tarDurationSec - candDurationSec).abs();
      if (diff > 8.0) {
        return -9999; // Reject candidate if duration mismatch is > 8 seconds
      } else if (diff <= 2.0) {
        score += 80;
      } else if (diff <= 5.0) {
        score += 50;
      } else if (diff <= 8.0) {
        score += 20;
      }
    }

    // 2. TEXT CLEANING & EXACT MATCHES
    final String cleanCandTrack = LyricQueryNormalizer.cleanTrackName(
      candTrack,
    );
    final String cleanTarTrack = LyricQueryNormalizer.cleanTrackName(tarTrack);

    final String cleanCandArtist = LyricQueryNormalizer.cleanArtistName(
      candArtist,
    );
    final String cleanTarArtist = LyricQueryNormalizer.cleanArtistName(
      tarArtist,
    );

    if (cleanCandTrack == cleanTarTrack) {
      score += 100;
    } else if (cleanCandTrack.contains(cleanTarTrack) ||
        cleanTarTrack.contains(cleanCandTrack)) {
      score += 40;
    }

    if (cleanCandArtist == cleanTarArtist) {
      score += 60;
    } else if (cleanCandArtist.contains(cleanTarArtist) ||
        cleanTarArtist.contains(cleanCandArtist)) {
      score += 30;
    }

    // 3. VERSION/LANGUAGE SPECIFIC MATCHING (solves YOASOBI English/Japanese issue!)
    const versionKeywords = [
      'english',
      'eng',
      'japanese',
      'jap',
      'acoustic',
      'live',
      'cover',
      'remix',
      'instrumental',
      'tv size',
      'edit',
    ];
    for (final kw in versionKeywords) {
      final bool tarHas = tarTrack.contains(kw);
      final bool candHas = candTrack.contains(kw);
      if (tarHas && candHas) {
        score += 90; // huge bonus if they both specify this version
      } else if (!tarHas && candHas) {
        score -=
            70; // heavily penalize if candidate is a specific version but target is not
      } else if (tarHas && !candHas) {
        score -=
            70; // heavily penalize if target is a specific version but candidate does not specify it
      }
    }

    // 4. PREFER SYNCED LYRICS (Massive bonus because we are a word-by-word lyrics player!)
    final String? synced = candidate['syncedLyrics'] as String?;
    if (synced != null && synced.isNotEmpty) {
      score += 150;
    }

    return score;
  }
}
