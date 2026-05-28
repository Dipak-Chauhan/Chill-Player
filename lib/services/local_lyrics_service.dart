import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Service for saving, loading, and managing custom/edited lyrics locally.
/// Supports LRC, plain text, and TTML/ELRC formats.
class LocalLyricsService {
  static Directory? _lyricsDir;

  /// Get the lyrics storage directory, creating it if needed.
  static Future<Directory> _getDir() async {
    if (_lyricsDir != null) return _lyricsDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _lyricsDir = Directory('${appDir.path}/custom_lyrics');
    if (!await _lyricsDir!.exists()) {
      await _lyricsDir!.create(recursive: true);
    }
    return _lyricsDir!;
  }

  /// Detect if content is TTML/ELRC format.
  /// Also handles legacy files that have LRC headers prepended to TTML XML.
  static bool isTtml(String content) {
    final trimmed = content.trimLeft();
    // Direct TTML
    if (trimmed.startsWith('<?xml') || trimmed.startsWith('<tt')) return true;
    // Legacy: LRC headers prepended before TTML XML (old save format bug)
    if (content.contains('<?xml') && content.contains('<tt')) return true;
    return false;
  }

  /// Save custom lyrics for a song.
  /// Handles both LRC/plain text and TTML/ELRC formats.
  static Future<void> saveLyrics({
    required int songId,
    required String lrcContent,
    String? title,
    String? artist,
  }) async {
    final dir = await _getDir();

    if (isTtml(lrcContent)) {
      // Save TTML as-is (no LRC headers that would corrupt the XML)
      final file = File('${dir.path}/$songId.ttml');
      await file.writeAsString(lrcContent);
      // Remove any old .lrc file for this song
      final oldLrc = File('${dir.path}/$songId.lrc');
      if (await oldLrc.exists()) await oldLrc.delete();
    } else {
      // Save LRC/plain text with metadata headers
      final file = File('${dir.path}/$songId.lrc');
      final buffer = StringBuffer();
      if (title != null) buffer.writeln('[ti:$title]');
      if (artist != null) buffer.writeln('[ar:$artist]');
      buffer.writeln('[re:Chill Player - Custom Lyrics]');
      buffer.writeln('[ve:1.0]');
      buffer.writeln();
      buffer.write(lrcContent);
      await file.writeAsString(buffer.toString());
      // Remove any old .ttml file for this song
      final oldTtml = File('${dir.path}/$songId.ttml');
      if (await oldTtml.exists()) await oldTtml.delete();
    }

    // Save metadata for quick access
    final metaFile = File('${dir.path}/$songId.meta.json');
    await metaFile.writeAsString(jsonEncode({
      'songId': songId,
      'title': title ?? '',
      'artist': artist ?? '',
      'savedAt': DateTime.now().toIso8601String(),
      'format': isTtml(lrcContent) ? 'ttml' : 'lrc',
      'hasTimestamps': _hasTimestamps(lrcContent),
    }));
  }

  /// Load custom lyrics for a song.
  /// Returns a record of (content, isTtml) or null if none exist.
  static Future<String?> loadLyrics(int songId) async {
    final dir = await _getDir();

    // Check TTML first (higher quality)
    final ttmlFile = File('${dir.path}/$songId.ttml');
    if (await ttmlFile.exists()) {
      return await ttmlFile.readAsString();
    }

    // Then check LRC
    final lrcFile = File('${dir.path}/$songId.lrc');
    if (await lrcFile.exists()) {
      final content = await lrcFile.readAsString();
      // Handle legacy: .lrc file that's actually TTML with LRC headers prepended
      if (isTtml(content) && content.contains('<?xml')) {
        final xmlStart = content.indexOf('<?xml');
        return content.substring(xmlStart);
      }
      return content;
    }

    return null;
  }

  /// Check if custom lyrics exist for a song (either format).
  static Future<bool> hasCustomLyrics(int songId) async {
    final dir = await _getDir();
    final ttmlFile = File('${dir.path}/$songId.ttml');
    final lrcFile = File('${dir.path}/$songId.lrc');
    return await ttmlFile.exists() || await lrcFile.exists();
  }

  /// Delete custom lyrics for a song (both formats).
  static Future<void> deleteLyrics(int songId) async {
    final dir = await _getDir();
    final ttmlFile = File('${dir.path}/$songId.ttml');
    final lrcFile = File('${dir.path}/$songId.lrc');
    final metaFile = File('${dir.path}/$songId.meta.json');
    if (await ttmlFile.exists()) await ttmlFile.delete();
    if (await lrcFile.exists()) await lrcFile.delete();
    if (await metaFile.exists()) await metaFile.delete();
  }

  /// List all songs that have custom lyrics. Returns list of song IDs.
  static Future<List<int>> listCustomLyrics() async {
    final dir = await _getDir();
    if (!await dir.exists()) return [];
    
    final ids = <int>{};
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        if (name.endsWith('.lrc') || name.endsWith('.ttml')) {
          final id = int.tryParse(name.split('.').first);
          if (id != null) ids.add(id);
        }
      }
    }
    return ids.toList();
  }

  /// Check if an LRC string contains timestamp tags [mm:ss.xx]
  static bool _hasTimestamps(String content) {
    return RegExp(r'\[\d{1,2}:\d{2}\.\d{2,3}\]').hasMatch(content);
  }
}
