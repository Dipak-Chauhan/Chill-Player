import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final uri = Uri.parse('https://lyricsplus.binimum.org/v1/ttml/get').replace(
    queryParameters: {
      'title': 'Sorry',
      'artist': 'Justin Bieber',
    },
  );
  try {
      final response = await http.get(uri);
      print("SUCCESS on lyricsplus.binimum.org:");
      print(response.statusCode);
      print(response.body.substring(0, 200));
  } catch (e) {
      print(e);
  }
}
