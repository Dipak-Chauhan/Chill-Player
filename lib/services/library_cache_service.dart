import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class LibraryCacheService {
  static const _cacheKey = 'library_cache';

  // Background Isolates for JSON
  static String _encodeSongs(List<Song> songs) => jsonEncode(songs.map((s) => s.toJson()).toList());
  static List<Song>? _decodeSongs(String json) {
    try {
      final decoded = jsonDecode(json) as List;
      return decoded.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) { return null; }
  }

  // Async Savers
  static Future<void> saveLibrary(SharedPreferences prefs, List<Song> songs) async {
    final jsonStr = await compute(_encodeSongs, songs);
    await prefs.setString(_cacheKey, jsonStr);
  }

  // Async Loaders (prevents blocking main thread during JSON parsing)
  static Future<List<Song>?> loadLibraryAsync(SharedPreferences prefs) async {
    final cachedStr = prefs.getString(_cacheKey);
    if (cachedStr == null || cachedStr.isEmpty) return null;
    return await compute(_decodeSongs, cachedStr);
  }
}

