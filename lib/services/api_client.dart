import 'package:http/http.dart' as http;

/// Thin shared wrapper around [http] for the app's REST integrations
/// (LRCLIB, LyricsPlus, Unison, Deezer).
///
/// Centralizes the default `User-Agent`, per-request timeouts and the
/// (previously duplicated) GET boilerplate so individual services only
/// describe *what* they fetch, not *how*.
class ApiClient {
  const ApiClient._();

  /// Default identifying User-Agent sent with every request unless overridden.
  static const String userAgent =
      'ChillPlayer/1.0.0 (https://github.com/chillplayer)';

  /// Performs a GET request with a sane default timeout and User-Agent.
  ///
  /// [headers] are merged on top of the default `User-Agent` header, so a
  /// caller can override or extend them as needed.
  static Future<http.Response> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
    Map<String, String>? headers,
  }) {
    final mergedHeaders = <String, String>{
      'User-Agent': userAgent,
      ...?headers,
    };
    return http.get(uri, headers: mergedHeaders).timeout(timeout);
  }
}
