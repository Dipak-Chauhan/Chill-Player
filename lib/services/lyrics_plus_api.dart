import 'dart:convert';

import '../utils/query_normalizer.dart';
import 'api_client.dart';

/// Client for the LyricsPlus (KPOE) backend, the source of Apple-Music-style
/// syllable-synced (word-by-word) lyrics used by YouLy+.
class LyricsPlusApi {
  // Community-hosted LyricsPlus mirrors. These are best-effort: they go up and
  // down and may be rate-limited, so the provider always falls back to
  // line-synced LRCLIB when none respond. Dead hosts (unresolvable DNS /
  // invalid TLS) are kept out so a fetch fails fast.
  static const List<String> _servers = [
    "https://lyricsplus.prjktla.my.id", // official primary
    "https://lyricsplus.prjktla.workers.dev", // Cloudflare Worker mirror
  ];

  /// Fetches lyrics from the `/v2/lyrics/get` endpoint, which returns a JSON
  /// KPOE document with per-syllable (word-by-word) timing. Returns the decoded
  /// map (with a non-empty `lyrics` list) or null if no mirror responds.
  static Future<Map<String, dynamic>?> fetchKpoe(
    String title,
    String artist, {
    Duration? duration,
    String? album,
  }) async {
    final cleanTitle = LyricQueryNormalizer.cleanTrackName(title);
    final cleanArtist = LyricQueryNormalizer.cleanArtistName(artist);

    for (final server in _servers) {
      final Map<String, String> queryParams = {
        'title': cleanTitle,
        'artist': cleanArtist,
      };

      if (duration != null && duration.inSeconds > 0) {
        queryParams['duration'] = duration.inSeconds.toString();
      }
      if (album != null &&
          album.isNotEmpty &&
          album.toLowerCase() != '<unknown>') {
        queryParams['album'] = album;
      }

      final base = server.endsWith('/')
          ? server.substring(0, server.length - 1)
          : server;
      final uri = Uri.parse(
        '$base/v2/lyrics/get',
      ).replace(queryParameters: queryParams);

      try {
        final response = await ApiClient.get(
          uri,
          timeout: const Duration(seconds: 4),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data is Map<String, dynamic> &&
              data['lyrics'] is List &&
              (data['lyrics'] as List).isNotEmpty) {
            return data;
          }
        }
      } catch (_) {
        // Switch to the next fallback mirror if a community server is down.
        continue;
      }
    }

    return null; // All mirrors failed.
  }
}
