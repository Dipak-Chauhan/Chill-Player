import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

/// App-wide artwork cache keyed by song id.
///
/// Each song's artwork is read from the device once (a slow native MediaStore
/// call) at a canonical resolution, then served instantly from memory and
/// persisted to disk across launches. Every widget shares the same cached
/// bytes, so artwork appears instantly throughout the app and swiping the
/// queue no longer triggers a fresh device query mid-gesture.
class ArtworkCache {
  ArtworkCache._();

  /// Single resolution fetched from the device. Small widgets downscale on the
  /// GPU; full-screen art stays acceptably crisp on phones.
  static const int canonicalSize = 600;

  static const int _maxMemEntries = 400;
  static final LinkedHashMap<int, Uint8List?> _mem = LinkedHashMap<int, Uint8List?>();
  static final Map<int, Future<Uint8List?>> _inflight = {};
  static Directory? _dir;

  /// Returns cached bytes synchronously if present in memory, else null.
  static Uint8List? peek(int id) {
    if (!_mem.containsKey(id)) return null;
    final v = _mem.remove(id);
    _mem[id] = v; // LRU touch
    return v;
  }

  /// Whether [id] has been resolved (value may be null if the song has no art).
  static bool contains(int id) => _mem.containsKey(id);

  static void _put(int id, Uint8List? bytes) {
    _mem.remove(id);
    if (_mem.length >= _maxMemEntries) {
      _mem.remove(_mem.keys.first);
    }
    _mem[id] = bytes;
  }

  static Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationCacheDirectory();
    final d = Directory('${base.path}/artwork_cache');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  /// Resolves artwork for [id] (memory -> disk -> device). Concurrent requests
  /// for the same id share one in-flight future. Cached for future calls.
  static Future<Uint8List?> load(int id, {ArtworkType type = ArtworkType.AUDIO}) {
    if (_mem.containsKey(id)) return Future.value(peek(id));
    final existing = _inflight[id];
    if (existing != null) return existing;
    final future = _fetch(id, type);
    _inflight[id] = future;
    return future.whenComplete(() => _inflight.remove(id));
  }

  static Future<Uint8List?> _fetch(int id, ArtworkType type) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/$id.img');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        _put(id, bytes);
        return bytes;
      }
    } catch (_) {}

    Uint8List? art;
    try {
      art = await OnAudioQuery().queryArtwork(
        id,
        type,
        size: canonicalSize,
        quality: 100,
        format: ArtworkFormat.JPEG,
      );
    } catch (_) {}

    _put(id, art);
    if (art != null) {
      final bytes = art;
      _cacheDir().then((dir) {
        File('${dir.path}/$id.img').writeAsBytes(bytes, flush: false).catchError((_) => File('${dir.path}/$id.img'));
      }).catchError((_) {});
    }
    return art;
  }

  /// Warms the cache for several ids (e.g. queue neighbours). Fire-and-forget;
  /// skips ids already cached or being fetched.
  static void precache(Iterable<int> ids, {ArtworkType type = ArtworkType.AUDIO}) {
    for (final id in ids) {
      if (!_mem.containsKey(id) && !_inflight.containsKey(id)) {
        load(id, type: type);
      }
    }
  }

  @visibleForTesting
  static int get maxMemEntries => _maxMemEntries;

  @visibleForTesting
  static int get debugMemCount => _mem.length;

  @visibleForTesting
  static void debugPut(int id, Uint8List? bytes) => _put(id, bytes);

  @visibleForTesting
  static void debugClear() {
    _mem.clear();
    _inflight.clear();
  }
}
