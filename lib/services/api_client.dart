import 'package:http/http.dart' as http;

/// Shared HTTP GET helper for the app's REST integrations, applying a default
/// User-Agent and timeout.
class ApiClient {
  const ApiClient._();

  static const String userAgent =
      'ChillPlayer/1.0.0 (https://github.com/chillplayer)';

  /// GET [uri] with a default [timeout]. [headers] override or extend the
  /// default User-Agent.
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
