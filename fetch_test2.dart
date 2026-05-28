import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final uri = Uri.parse('https://lrclib.net/api/search').replace(queryParameters: {
    'track_name': 'Die With A Smile',
    'artist_name': 'Lady Gaga',
  });
  
  final response = await http.get(uri);
  final data = json.decode(response.body);
  if (data is List && data.isNotEmpty) {
     final synced = data[0]['syncedLyrics'];
     print('Found synced lyrics:');
     print(synced.toString().substring(0, 500));
  } else {
     print('No results.');
  }
}
