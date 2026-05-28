import 'dart:convert';
import 'package:http/http.dart' as http;

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
      final cleanTitle = _cleanTrackName(title);
      final cleanArtist = _cleanArtistName(artist);

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

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'ChillPlayer/1.0.0 (https://github.com/chillplayer)',
        },
      ).timeout(const Duration(seconds: 8));

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
}
