import 'dart:convert';

import '../utils/query_normalizer.dart';
import 'api_client.dart';

class LyricsPlusApi {
  static const List<String> _servers = [
    "https://lyricsplus.prjktla.my.id", // YouLy's primary working server
    "https://lyricsplus.binimum.org", // Primary working mirror
    "https://lyricsplus.atomix.one",
    "https://lyricsplus-seven.vercel.app",
    "https://lyricsplus.prjktla.workers.dev",
    "https://lyrics-plus-backend.vercel.app",
  ];

  static Future<String?> fetchTTML(
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
      if (album != null && album.isNotEmpty && album.toLowerCase() != '<unknown>') {
        queryParams['album'] = album;
      }

      final uri = Uri.parse('$server/v1/ttml/get').replace(
        queryParameters: queryParams,
      );

      try {
        final response = await ApiClient.get(uri, timeout: const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['ttml'] != null) {
            return data['ttml'] as String;
          }
        }
      } catch (e) {
        // Switch to the next fallback mirror if a community server is down.
        continue;
      }
    }

    return null; // All mirrors failed.
  }
}
