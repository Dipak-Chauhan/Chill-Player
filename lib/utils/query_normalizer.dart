/// Shared normalization helpers for lyrics-provider search queries.
///
/// The LRCLIB, LyricsPlus and Unison services all need to strip platform
/// "fluff" (e.g. "Official Video", "feat. ...", "- Topic") from track and
/// artist names before searching. This logic used to be duplicated verbatim
/// in each service; it now lives here so there is a single source of truth.
class LyricQueryNormalizer {
  const LyricQueryNormalizer._();

  /// Normalizes a track title for lyrics lookup.
  ///
  /// Removes common platform tags (official video/audio, lyric video,
  /// remastered/deluxe), `feat.`/`ft.`/`featuring` segments, and any empty
  /// brackets/parentheses left behind. Always returns a lowercased, trimmed
  /// string.
  static String cleanTrackName(String title) {
    String t = title.toLowerCase();

    // Remove common YouTube/platform fluff
    t = t.replaceAll(RegExp(r'\b(official\s+(video|audio|music\s+video|lyric\s+video))\b'), '');
    t = t.replaceAll(RegExp(r'\b(lyric\s+video|music\s+video|official\s+video)\b'), '');
    t = t.replaceAll(RegExp(r'\[\s*(official\s+(video|audio|music\s+video|lyric\s+video))\s*\]'), '');
    t = t.replaceAll(RegExp(r'\b(remastered|deluxe\s+version|deluxe\s+edition|deluxe)\b'), '');
    t = t.replaceAll(RegExp(r'\[\s*(remastered|deluxe)\s*\]'), '');

    // Remove "feat. ...", "ft. ...", "featuring ..." both in parentheses and brackets or bare
    t = t.replaceAll(RegExp(r'\b(feat|ft|featuring)\b\.?\s+[\w\s\-\.\&\,]+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\(\s*(feat|ft|featuring)\b\.?\s+[\w\s\-\.\&\,]+\)', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\[\s*(feat|ft|featuring)\b\.?\s+[\w\s\-\.\&\,]+\]', caseSensitive: false), '');

    // Clean up empty parentheses/brackets left behind
    t = t.replaceAll(RegExp(r'\(\s*\)'), '');
    t = t.replaceAll(RegExp(r'\[\s*\]'), '');

    return t.trim();
  }

  /// Normalizes an artist name for lyrics lookup.
  ///
  /// Strips the YouTube "- Topic" suffix and keeps only the primary artist
  /// when the name contains multiple artists separated by `/`, `,` or `&`.
  /// Always returns a lowercased, trimmed string.
  static String cleanArtistName(String artist) {
    String a = artist.toLowerCase();

    // Remove "- Topic" (YouTube auto-generated channels, e.g. "Adele - Topic").
    // Handles spaced ("artist - topic") and unspaced ("artist-topic") dashes.
    a = a.replaceAll(RegExp(r'\s*-\s*topic\b'), '');

    // Keep only the primary artist if split by slash, comma, or ampersand
    final splitIndex = a.indexOf(RegExp(r'[\/,\&]'));
    if (splitIndex != -1) {
      a = a.substring(0, splitIndex);
    }

    return a.trim();
  }
}
