import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final servers = [
    "https://lyricsplus.atomix.one",
    "https://lyricsplus-seven.vercel.app", 
    "https://lyricsplus.prjktla.workers.dev", 
    "https://lyrics-plus-backend.vercel.app", 
    "https://youlyplus.binimum.org",
  ];
  for (final server in servers) {
      final uri = Uri.parse('$server/v2/lyrics/get').replace(
        queryParameters: {
          'title': 'Sorry',
          'artist': 'Justin Bieber',
        },
      );
      try {
          final response = await http.get(uri);
          print("SUCCESS on $server/v2:");
          print(response.statusCode);
      } catch (e) {
      }
  }
}
