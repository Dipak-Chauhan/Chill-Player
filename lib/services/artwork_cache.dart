import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

/// One cache tier (a resolution). Holds an LRU of raw bytes keyed by song id,
/// backed by disk, with concurrent-request de-duplication.
class _ArtStore {
  _ArtStore({required this.querySize, required this.suffix, required this.maxEntries});

  final int querySize;
  final String suffix; // disk filename suffix
  final int maxEntries;

  final LinkedHashMap<int, Uint8List?> _mem = LinkedHashMap<int, Uint8List?>();
  final Map<int, Future<Uint8List?>> _inflight = {};

  Uint8List? peek(int id) {
    if (!_mem.containsKey(id)) return null;
    final v = _mem.remove(id);
    _mem[id] = v; // LRU touch
    return v;
  }

  bool contains(int id) => _mem.containsKey(id);
  int get count => _mem.length;

  void clear() {
    _mem.clear();
    _inflight.clear();
  }

  void put(int id, Uint8List? bytes) {
    _mem.remove(id);
    if (_mem.length >= maxEntries) _mem.remove(_mem.keys.first);
    _mem[id] = bytes;
  }

  Future<Uint8List?> load(int id, ArtworkType type, Future<Directory> Function() dir) {
    if (_mem.containsKey(id)) return Future.value(peek(id));
    final existing = _inflight[id];
    if (existing != null) return existing;
    final future = _fetch(id, type, dir);
    _inflight[id] = future;
    return future.whenComplete(() => _inflight.remove(id));
  }

  Future<Uint8List?> _fetch(int id, ArtworkType type, Future<Directory> Function() dir) async {
    try {
      final d = await dir();
      final file = File('${d.path}/$id.$suffix');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        put(id, bytes);
        return bytes;
      }
    } catch (_) {}

    Uint8List? art;
    try {
      art = await OnAudioQuery().queryArtwork(
        id,
        type,
        size: querySize,
        quality: 85,
        format: ArtworkFormat.JPEG,
      );
    } catch (_) {}

    put(id, art);
    if (art != null) {
      final bytes = art;
      dir().then((d) {
        final path = '${d.path}/$id.$suffix';
        File(path).writeAsBytes(bytes, flush: false).catchError((_) => File(path));
      }).catchError((_) {});
    }
    return art;
  }
}

/// App-wide artwork cache with two resolution tiers:
///
/// * **thumbnail** ([thumbSize]) for lists, the mini-player and grids — small
///   and fast so fast scrolling stays instant.
/// * **full** ([fullSize]) for the Now Playing / detail screens.
///
/// Each song's artwork is read from the device once per tier, cached in memory
/// (LRU) and on disk. The whole library's thumbnails are warmed in the
/// background on load so scrolling never waits on a device query.
class ArtworkCache {
  ArtworkCache._();

  static const int thumbSize = 256;
  static const int fullSize = 720;

  static final _ArtStore _thumbs = _ArtStore(querySize: thumbSize, suffix: 't', maxEntries: 600);
  static final _ArtStore _fulls = _ArtStore(querySize: fullSize, suffix: 'f', maxEntries: 60);

  static _ArtStore _store(bool full) => full ? _fulls : _thumbs;

  static Directory? _dir;
  static Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationCacheDirectory();
    final d = Directory('${base.path}/artwork_cache');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  static Uint8List? peek(int id, {bool full = false}) => _store(full).peek(id);
  static bool contains(int id, {bool full = false}) => _store(full).contains(id);

  static Future<Uint8List?> load(int id, {bool full = false, ArtworkType type = ArtworkType.AUDIO}) =>
      _store(full).load(id, type, _cacheDir);

  /// Immediate prefetch for a small set (e.g. queue neighbours).
  static void precache(Iterable<int> ids, {bool full = false, ArtworkType type = ArtworkType.AUDIO}) {
    final store = _store(full);
    for (final id in ids) {
      if (!store.contains(id)) load(id, full: full, type: type);
    }
  }

  // Background thumbnail warm-up (e.g. the whole library), throttled so it
  // never blocks the UI.
  static final Queue<int> _warmQueue = Queue<int>();
  static final Set<int> _warmQueued = {};
  static bool _warming = false;
  static ArtworkType _warmType = ArtworkType.AUDIO;

  static void warm(Iterable<int> ids, {ArtworkType type = ArtworkType.AUDIO}) {
    _warmType = type;
    for (final id in ids) {
      if (!_thumbs.contains(id) && _warmQueued.add(id)) _warmQueue.add(id);
    }
    _pumpWarm();
  }

  static Future<void> _pumpWarm() async {
    if (_warming) return;
    _warming = true;
    const int concurrency = 8;
    while (_warmQueue.isNotEmpty) {
      final futures = <Future<void>>[];
      for (int i = 0; i < concurrency && _warmQueue.isNotEmpty; i++) {
        final id = _warmQueue.removeFirst();
        _warmQueued.remove(id);
        if (_thumbs.contains(id)) continue;
        futures.add(load(id, type: _warmType).then((_) {}));
      }
      if (futures.isNotEmpty) await Future.wait(futures);
      await Future<void>.delayed(Duration.zero); // yield to the UI
    }
    _warming = false;
  }

  @visibleForTesting
  static int get maxMemEntries => _thumbs.maxEntries;
  @visibleForTesting
  static int get debugMemCount => _thumbs.count;
  @visibleForTesting
  static void debugPut(int id, Uint8List? bytes) => _thumbs.put(id, bytes);
  @visibleForTesting
  static void debugClear() {
    _thumbs.clear();
    _fulls.clear();
    _warmQueue.clear();
    _warmQueued.clear();
    _warming = false;
  }
}
