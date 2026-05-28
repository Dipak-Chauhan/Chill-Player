import 'dart:convert';
import 'package:http/http.dart' as http;

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
    final cleanTitle = _cleanTrackName(title);
    final cleanArtist = _cleanArtistName(artist);

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
        final response = await http.get(uri).timeout(const Duration(seconds: 5));
        
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

  // ---------------------------------------------------------------------------
  // Query Normalization Helpers
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
}
