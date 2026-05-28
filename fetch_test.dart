import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final servers = [
    "https://lyricsplus-seven.vercel.app", 
    "https://lyricsplus.prjktla.workers.dev", 
    "https://lyrics-plus-backend.vercel.app", 
    "https://youlyplus.binimum.org",
  ];
  for (final server in servers) {
      final uri = Uri.parse('$server/v1/ttml/get').replace(
        queryParameters: {
          'title': 'Sorry',
          'artist': 'Justin Bieber',
        },
      );
      try {
          final response = await http.get(uri);
          if (response.statusCode == 200) {
             print("SUCCESS on $server:");
             print(response.body);
             return;
          } else {
             print("Failed on $server with status ${response.statusCode}");
          }
      } catch (e) {
          print("Failed on $server with exception");
      }
  }
}
