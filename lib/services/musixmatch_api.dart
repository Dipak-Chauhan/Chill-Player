import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/query_normalizer.dart';

/// Client for Musixmatch's public desktop API, used to fetch word-by-word
/// (richsync) lyrics without a browser/Turnstile flow.
///
/// Flow: obtain a short-lived user token, match the track to a
/// `commontrack_id`, and — when the track advertises `has_richsync` — pull the
/// richsync body (per-word timing). Tokens are cached in memory and refreshed
/// on expiry. All requests use a browser-like User-Agent + guid cookie, which
/// Musixmatch requires to avoid a captcha response.
class MusixmatchApi {
  const MusixmatchApi._();

  static const String _base = 'https://apic-desktop.musixmatch.com/ws/1.1';
  static const String _appId = 'web-desktop-app-v1.0';

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
    'Cookie': 'x-mxm-token-guid=',
  };

  static String? _token;
  static DateTime? _tokenFetchedAt;
  static const Duration _tokenTtl = Duration(minutes: 10);

  static Future<http.Response> _get(Uri uri) {
    return http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
  }

  static Future<String?> _getToken() async {
    final cached = _token;
    final at = _tokenFetchedAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _tokenTtl) {
      return cached;
    }
    // token.get is occasionally throttled or returns a captcha sentinel, so
    // try a couple of times before giving up.
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.parse(
          '$_base/token.get',
        ).replace(queryParameters: {'app_id': _appId, 'format': 'json'});
        final resp = await _get(uri);
        if (resp.statusCode == 200) {
          final body = json.decode(resp.body);
          final token = body?['message']?['body']?['user_token'] as String?;
          // Musixmatch returns this sentinel when it wants an upgrade/captcha.
          if (token != null &&
              token.isNotEmpty &&
              !token.startsWith('UpgradeOnly')) {
            _token = token;
            _tokenFetchedAt = DateTime.now();
            return token;
          }
        }
      } catch (_) {}
      if (attempt == 0) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return null;
  }

  /// Returns the raw richsync body (JSON string of per-word timing) for the
  /// track, or null if no word-by-word lyrics are available.
  static Future<String?> fetchRichsync(
    String title,
    String artist, {
    Duration? duration,
  }) async {
    final token = await _getToken();
    if (token == null) return null;

    // Clean platform tags (feat., remaster, "official video", extra artists)
    // so the matcher picks the right recording instead of a random version.
    final cleanTitle = LyricQueryNormalizer.cleanTrackName(title);
    final cleanArtist = LyricQueryNormalizer.cleanArtistName(artist);

    try {
      final matcherParams = <String, String>{
        'q_track': cleanTitle.isNotEmpty ? cleanTitle : title,
        'q_artist': cleanArtist.isNotEmpty ? cleanArtist : artist,
        'usertoken': token,
        'app_id': _appId,
        'format': 'json',
      };
      if (duration != null && duration.inSeconds > 0) {
        matcherParams['q_duration'] = duration.inSeconds.toString();
      }
      final matcherUri = Uri.parse(
        '$_base/matcher.track.get',
      ).replace(queryParameters: matcherParams);
      final mResp = await _get(matcherUri);
      if (mResp.statusCode != 200) return null;

      final mBody = json.decode(mResp.body);
      final track = mBody?['message']?['body']?['track'];
      if (track is! Map) return null;
      if (track['has_richsync'] != 1) return null;
      final commontrackId = track['commontrack_id'];
      if (commontrackId == null) return null;

      // Reject wrong-version matches: if the matched track's length differs
      // from the playing file by more than 8s, its word timing won't line up,
      // so fall back to line-synced lyrics instead of showing bad sync.
      if (duration != null && duration.inSeconds > 0) {
        final trackLen = (track['track_length'] as num?)?.toDouble();
        if (trackLen != null &&
            trackLen > 0 &&
            (trackLen - duration.inSeconds).abs() > 8) {
          return null;
        }
      }

      final richUri = Uri.parse('$_base/track.richsync.get').replace(
        queryParameters: {
          'commontrack_id': commontrackId.toString(),
          'usertoken': token,
          'app_id': _appId,
          'format': 'json',
        },
      );
      final rResp = await _get(richUri);
      if (rResp.statusCode != 200) return null;

      final rBody = json.decode(rResp.body);
      final richsync =
          rBody?['message']?['body']?['richsync']?['richsync_body'];
      if (richsync is String && richsync.isNotEmpty) {
        return richsync;
      }
    } catch (_) {}
    return null;
  }
}
