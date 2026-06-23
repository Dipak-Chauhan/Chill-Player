import 'dart:convert';

import '../utils/query_normalizer.dart';
import 'api_client.dart';

class UnisonApi {
  static const String _baseUrl = 'https://unison.boidu.dev';

  /// Fetches lyrics from Unison API.
  /// Returns a Map with 'lyrics', 'format' ('ttml' or 'lrc'), and 'syncType' ('richsync', 'linesync', or 'plain')
  /// or null if nothing is found.
  static Future<Map<String, String>?> fetchLyrics(
    String title,
    String artist, {
    Duration? duration,
    String? album,
  }) async {
    try {
      final cleanTitle = LyricQueryNormalizer.cleanTrackName(title);
      final cleanArtist = LyricQueryNormalizer.cleanArtistName(artist);

      final queryParams = {
        'song': cleanTitle,
        'artist': cleanArtist,
      };

      if (duration != null && duration.inSeconds > 0) {
        queryParams['duration'] = duration.inSeconds.toString();
      }
      if (album != null && album.isNotEmpty && album.toLowerCase() != '<unknown>') {
        queryParams['album'] = album;
      }

      final uri = Uri.parse('$_baseUrl/lyrics').replace(queryParameters: queryParams);

      final response = await ApiClient.get(uri, timeout: const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final lyricsData = data['data'];
          final lyrics = lyricsData['lyrics'] as String?;
          final format = lyricsData['format'] as String?;
          final syncType = lyricsData['syncType'] as String?;

          if (lyrics != null && lyrics.isNotEmpty) {
            return {
              'lyrics': lyrics,
              'format': (format ?? 'plain').toLowerCase(),
              'syncType': (syncType ?? 'plain').toLowerCase(),
            };
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
