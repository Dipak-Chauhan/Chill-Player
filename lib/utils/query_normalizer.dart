/// Normalization helpers shared by the lyrics provider APIs (LRCLIB,
/// LyricsPlus, Unison) to clean track/artist names before searching.
class LyricQueryNormalizer {
  const LyricQueryNormalizer._();

  /// Strips platform tags (official video, remastered, "feat." segments) and
  /// returns a lowercased, trimmed title.
  static String cleanTrackName(String title) {
    String t = title.toLowerCase();

    t = t.replaceAll(RegExp(r'\b(official\s+(video|audio|music\s+video|lyric\s+video))\b'), '');
    t = t.replaceAll(RegExp(r'\b(lyric\s+video|music\s+video|official\s+video)\b'), '');
    t = t.replaceAll(RegExp(r'\[\s*(official\s+(video|audio|music\s+video|lyric\s+video))\s*\]'), '');
    t = t.replaceAll(RegExp(r'\b(remastered|deluxe\s+version|deluxe\s+edition|deluxe)\b'), '');
    t = t.replaceAll(RegExp(r'\[\s*(remastered|deluxe)\s*\]'), '');

    t = t.replaceAll(RegExp(r'\b(feat|ft|featuring)\b\.?\s+[\w\s\-\.\&\,]+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\(\s*(feat|ft|featuring)\b\.?\s+[\w\s\-\.\&\,]+\)', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\[\s*(feat|ft|featuring)\b\.?\s+[\w\s\-\.\&\,]+\]', caseSensitive: false), '');

    // Drop empty brackets left behind by the removals above.
    t = t.replaceAll(RegExp(r'\(\s*\)'), '');
    t = t.replaceAll(RegExp(r'\[\s*\]'), '');

    return t.trim();
  }

  /// Removes the YouTube "- Topic" suffix and keeps only the primary artist
  /// when several are joined by `/`, `,` or `&`. Returns a lowercased, trimmed name.
  static String cleanArtistName(String artist) {
    String a = artist.toLowerCase();

    a = a.replaceAll(RegExp(r'\s*-\s*topic\b'), '');

    final splitIndex = a.indexOf(RegExp(r'[\/,\&]'));
    if (splitIndex != -1) {
      a = a.substring(0, splitIndex);
    }

    return a.trim();
  }
}
