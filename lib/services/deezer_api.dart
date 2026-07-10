import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';

/// Deezer API service for fetching artist artwork.
/// Uses Deezer's free public search API — no API key required.
class DeezerApi {
  static const String _baseUrl = 'https://api.deezer.com';
  static const Duration _timeout = Duration(seconds: 10);

  /// Search for an artist and return their image URLs.
  /// Returns a map with 'small', 'medium', 'big', 'xl' image URLs,
  /// or null if not found.
  static Future<Map<String, String>?> searchArtist(String artistName) async {
    if (artistName.isEmpty || artistName.toLowerCase() == 'unknown') {
      return null;
    }

    try {
      final uri = Uri.parse('$_baseUrl/search/artist').replace(
        queryParameters: {'q': artistName, 'limit': '1'},
      );

      final response = await ApiClient.get(uri, timeout: _timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List results = data['data'] ?? [];

        if (results.isNotEmpty) {
          final artist = results[0];
          return {
            'small': artist['picture_small'] ?? '',
            'medium': artist['picture_medium'] ?? '',
            'big': artist['picture_big'] ?? '',
            'xl': artist['picture_xl'] ?? '',
            'name': artist['name'] ?? artistName,
          };
        }
      }
    } catch (_) {}

    return null;
  }
}

// Persistent disk cache for Deezer artist images
class _DeezerImageCache {
  static Directory? _cacheDir;

  static Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationCacheDirectory();
    _cacheDir = Directory('${appDir.path}/deezer_artist_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  /// Returns the cached image bytes for a given artist name, or null.
  static Future<Uint8List?> load(String artistKey) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/$artistKey.jpg');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  /// Save image bytes to disk cache.
  static Future<void> save(String artistKey, Uint8List data) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/$artistKey.jpg');
      await file.writeAsBytes(data, flush: false);
    } catch (_) {}
  }

  /// Check if a "not found" marker exists so we don't re-query Deezer.
  static Future<bool> isMarkedNotFound(String artistKey) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/$artistKey.notfound');
      return await file.exists();
    } catch (_) {}
    return false;
  }

  /// Mark this artist as "not found" to avoid repeated API calls.
  static Future<void> markNotFound(String artistKey) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/$artistKey.notfound');
      await file.writeAsString(DateTime.now().toIso8601String());
    } catch (_) {}
  }
}

// In-memory LRU cache for artist images (avoids disk reads on scroll)
class _MemoryArtistCache {
  static const int _maxEntries = 80;
  static final Map<String, Uint8List?> _cache = {};
  static final List<String> _accessOrder = [];

  static Uint8List? get(String key) {
    final data = _cache[key];
    if (data != null) {
      _accessOrder.remove(key);
      _accessOrder.add(key);
    }
    return data;
  }

  static void put(String key, Uint8List? data) {
    if (_cache.containsKey(key)) {
      _accessOrder.remove(key);
    } else if (_cache.length >= _maxEntries) {
      final evictKey = _accessOrder.removeAt(0);
      _cache.remove(evictKey);
    }
    _cache[key] = data;
    _accessOrder.add(key);
  }

  static bool containsKey(String key) => _cache.containsKey(key);
}

// Riverpod provider for fetching artist images with full caching pipeline

/// Normalize artist name to a safe filesystem key
String _toSafeKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

/// FutureProvider.family that fetches and caches artist images.
/// Returns image bytes or null.
final deezerArtistImageProvider =
    FutureProvider.family<Uint8List?, String>((ref, artistName) async {
  final key = _toSafeKey(artistName);

  if (_MemoryArtistCache.containsKey(key)) {
    return _MemoryArtistCache.get(key);
  }

  final diskCached = await _DeezerImageCache.load(key);
  if (diskCached != null) {
    _MemoryArtistCache.put(key, diskCached);
    return diskCached;
  }

  if (await _DeezerImageCache.isMarkedNotFound(key)) {
    _MemoryArtistCache.put(key, null);
    return null;
  }

  final artistData = await DeezerApi.searchArtist(artistName);
  if (artistData == null) {
    _DeezerImageCache.markNotFound(key);
    _MemoryArtistCache.put(key, null);
    return null;
  }

  final imageUrl = artistData['big'] ?? artistData['medium'] ?? '';
  if (imageUrl.isEmpty) {
    _DeezerImageCache.markNotFound(key);
    _MemoryArtistCache.put(key, null);
    return null;
  }

  try {
    final imgResponse =
        await ApiClient.get(Uri.parse(imageUrl), timeout: const Duration(seconds: 15));
    if (imgResponse.statusCode == 200 && imgResponse.bodyBytes.isNotEmpty) {
      final bytes = imgResponse.bodyBytes;
      _MemoryArtistCache.put(key, bytes);
      _DeezerImageCache.save(key, bytes); // Fire-and-forget
      return bytes;
    }
  } catch (_) {}

  _DeezerImageCache.markNotFound(key);
  _MemoryArtistCache.put(key, null);
  return null;
});
