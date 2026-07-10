import 'dart:convert';
import '../utils/query_normalizer.dart';
import 'api_client.dart';

class BiniLyricsApi {
  static const String _baseUrl = 'https://lyrics-api.binimum.org';

  /// Fetches lyrics from BiniLyrics database.
  /// Returns the raw TTML XML string or null if nothing is found.
  static Future<String?> fetchLyrics(
    String title,
    String artist, {
    Duration? duration,
    String? album,
  }) async {
    try {
      final cleanTitle = LyricQueryNormalizer.cleanTrackName(title);
      final cleanArtist = LyricQueryNormalizer.cleanArtistName(artist);

      final queryParams = {
        'track': cleanTitle,
        'artist': cleanArtist,
      };

      if (duration != null && duration.inSeconds > 0) {
        queryParams['duration'] = duration.inSeconds.toString();
      }
      if (album != null && album.isNotEmpty && album.toLowerCase() != '<unknown>') {
        queryParams['album'] = album;
      }

      final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);
      final response = await ApiClient.get(uri, timeout: const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final data = json.decode(decodedBody);
        if (data['results'] is List && (data['results'] as List).isNotEmpty) {
          final result = (data['results'] as List)[0];
          final lyricsUrl = result['lyricsUrl'] as String?;
          if (lyricsUrl != null && lyricsUrl.isNotEmpty) {
            final fileUri = Uri.parse(lyricsUrl);
            final fileResponse = await ApiClient.get(fileUri, timeout: const Duration(seconds: 8));
            if (fileResponse.statusCode == 200) {
              final content = utf8.decode(fileResponse.bodyBytes);
              if (content.isNotEmpty) {
                // ignore: avoid_print
                print('BINILYRICS MATCHED: ${result['track'] ?? title} by ${result['artist'] ?? artist}');
                return content;
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }
}