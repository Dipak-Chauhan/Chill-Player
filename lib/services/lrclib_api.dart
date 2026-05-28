import 'dart:convert';
import 'package:http/http.dart' as http;

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
      final cleanedTrack = _cleanTrackName(trackName);
      final cleanedArtist = _cleanArtistName(artistName);

      final List<dynamic>? data = await _searchApi(cleanedTrack, cleanedArtist);
      if (data != null && data.isNotEmpty) {
        dynamic bestCandidate;
        int bestScore = -9999;
        
        for (final item in data) {
          final candidate = item as Map<String, dynamic>;
          final score = _scoreCandidate(candidate, trackName, artistName, duration);
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
      final cleanedTrack = _cleanTrackName(trackName);
      final cleanedArtist = _cleanArtistName(artistName);

      final data = await _searchApi(cleanedTrack, cleanedArtist);
      if (data == null) return null;

      dynamic bestCandidate;
      int bestScore = -9999;
      
      for (final item in data) {
        final candidate = item as Map<String, dynamic>;
        final synced = candidate['syncedLyrics'] as String?;
        if (synced == null || synced.isEmpty) continue;

        final score = _scoreCandidate(candidate, trackName, artistName, duration);
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
      final cleanedTrack = _cleanTrackName(trackName);
      final cleanedArtist = _cleanArtistName(artistName);

      final data = await _searchApi(cleanedTrack, cleanedArtist);
      if (data == null) return null;

      dynamic bestCandidate;
      int bestScore = -9999;
      
      for (final item in data) {
        final candidate = item as Map<String, dynamic>;
        final plain = candidate['plainLyrics'] as String?;
        if (plain == null || plain.isEmpty) continue;

        final score = _scoreCandidate(candidate, trackName, artistName, duration);
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

  /// Common search API call, returns decoded JSON list or null.
  static Future<List<dynamic>?> _searchApi(String trackName, String artistName) async {
    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'track_name': trackName,
      'artist_name': artistName,
    });

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': 'ChillPlayer/1.0.0 (https://github.com/chillplayer)',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
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
      final cleanedTrack = _cleanTrackName(trackName);
      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
        'q': cleanedTrack,
      });

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'ChillPlayer/1.0.0 (https://github.com/chillplayer)',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          dynamic bestCandidate;
          int bestScore = -9999;
          
          for (final item in data) {
            final candidate = item as Map<String, dynamic>;
            final score = _scoreCandidate(candidate, trackName, artistName, duration);
            if (score > bestScore) {
              bestScore = score;
              bestCandidate = candidate;
            }
          }

          if (bestCandidate != null && bestScore > 0) {
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
  // Query Normalization & Ranking Helpers
  // ---------------------------------------------------------------------------

  static String _cleanTrackName(String title) {
    String t = title.toLowerCase();
    
    // Remove common YouTube/platform fluff
    t = t.replaceAll(RegExp(r'\b(official\s+(video|audio|music\s+video|lyric\s+video))\b'), '');
    t = t.replaceAll(RegExp(r'\b(lyric\s+video|music\s+video|official\s+video)\b'), '');
    t = t.replaceAll(RegExp(r'\[\s*(official\s+(video|audio|music\s+video|lyric\s+video))\s*\]'), '');
    t = t.replaceAll(RegExp(r'\b(remastered|deluxe\s+version|deluxe\s+edition|deluxe)\b'), '');
    t = t.replaceAll(RegExp(r'\[\s*(remastered|deluxe)\s*\]'), '');
    
    // Remove "feat. ...", "ft. ...", "featuring ..." both in parentheses and brackets or bare
    t = t.replaceAll(RegExp(r'\b(feat|ft|featuring)\b\.?\s+[\w\s\-\.\&\,]+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\(\s*(feat|ft|featuring)\b\.?\s+[\w\s\-\.\&\,]+\)', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\[\s*(feat|ft|featuring)\b\.?\s+[\w\s\-\.\&\,]+\]', caseSensitive: false), '');
    
    // Clean up empty parentheses/brackets left behind
    t = t.replaceAll(RegExp(r'\(\s*\)'), '');
    t = t.replaceAll(RegExp(r'\[\s*\]'), '');
    
    return t.trim();
  }

  static String _cleanArtistName(String artist) {
    String a = artist.toLowerCase();
    
    // Remove "- Topic"
    a = a.replaceAll(RegExp(r'\b-\s*topic\b'), '');
    
    // Keep only the primary artist if split by slash, comma, or ampersand
    final splitIndex = a.indexOf(RegExp(r'[\/,\&]'));
    if (splitIndex != -1) {
      a = a.substring(0, splitIndex);
    }
    
    return a.trim();
  }

  static int _scoreCandidate(
    Map<String, dynamic> candidate,
    String targetTrack,
    String targetArtist,
    Duration? targetDuration,
  ) {
    int score = 0;

    final String candTrack = (candidate['trackName'] as String? ?? '').toLowerCase().trim();
    final String candArtist = (candidate['artistName'] as String? ?? '').toLowerCase().trim();
    final double? candDurationSec = (candidate['duration'] as num?)?.toDouble();

    final String tarTrack = targetTrack.toLowerCase().trim();
    final String tarArtist = targetArtist.toLowerCase().trim();

    // 1. DURATION MATCHING (High importance!)
    if (targetDuration != null && candDurationSec != null && candDurationSec > 0.0) {
      final double tarDurationSec = targetDuration.inMilliseconds / 1000.0;
      final double diff = (tarDurationSec - candDurationSec).abs();
      if (diff <= 2.0) {
        score += 80;
      } else if (diff <= 5.0) {
        score += 50;
      } else if (diff <= 10.0) {
        score += 20;
      } else if (diff > 20.0) {
        score -= 50; // heavily penalize severe duration mismatches
      }
    }

    // 2. TEXT CLEANING & EXACT MATCHES
    final String cleanCandTrack = _cleanTrackName(candTrack);
    final String cleanTarTrack = _cleanTrackName(tarTrack);
    
    final String cleanCandArtist = _cleanArtistName(candArtist);
    final String cleanTarArtist = _cleanArtistName(tarArtist);

    if (cleanCandTrack == cleanTarTrack) {
      score += 100;
    } else if (cleanCandTrack.contains(cleanTarTrack) || cleanTarTrack.contains(cleanCandTrack)) {
      score += 40;
    }

    if (cleanCandArtist == cleanTarArtist) {
      score += 60;
    } else if (cleanCandArtist.contains(cleanTarArtist) || cleanTarArtist.contains(cleanCandArtist)) {
      score += 30;
    }

    // 3. VERSION/LANGUAGE SPECIFIC MATCHING (solves YOASOBI English/Japanese issue!)
    const versionKeywords = ['english', 'eng', 'japanese', 'jap', 'acoustic', 'live', 'cover', 'remix', 'instrumental', 'tv size', 'edit'];
    for (final kw in versionKeywords) {
      final bool tarHas = tarTrack.contains(kw);
      final bool candHas = candTrack.contains(kw);
      if (tarHas && candHas) {
        score += 90; // huge bonus if they both specify this version
      } else if (!tarHas && candHas) {
        score -= 70; // heavily penalize if candidate is a specific version but target is not
      } else if (tarHas && !candHas) {
        score -= 70; // heavily penalize if target is a specific version but candidate does not specify it
      }
    }

    // 4. PREFER SYNCED LYRICS
    final String? synced = candidate['syncedLyrics'] as String?;
    if (synced != null && synced.isNotEmpty) {
      score += 15;
    }

    return score;
  }
}
