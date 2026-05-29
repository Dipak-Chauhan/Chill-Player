import 'dart:collection';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

class _ArtCache {
  static const int _maxEntries = 500;
  // Use a LinkedHashMap for O(1) LRU operations instead of a List + Map combo
  static final LinkedHashMap<String, Uint8List?> _cache = LinkedHashMap<String, Uint8List?>();


  static Uint8List? get(String key) {
    final data = _cache.remove(key); // O(1) remove from linked map
    if (data != null || _cache.containsKey(key)) {
      _cache[key] = data; // Re-insert at end (most-recently-used)
      return data;
    }
    return null;
  }

  static void put(String key, Uint8List? data) {
    _cache.remove(key); // O(1)
    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first); // Evict oldest entry O(1)
    }
    _cache[key] = data;
  }
}

class _DiskArtCache {
  static Directory? _cacheDir;

  static Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationCacheDirectory();
    _cacheDir = Directory('${appDir.path}/art_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  static Future<Uint8List?> load(String key) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/$key.png');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  static Future<void> save(String key, Uint8List data) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/$key.png');
      await file.writeAsBytes(data, flush: false);
    } catch (_) {}
  }
}

class SmoothArtWidget extends StatefulWidget {
  final int id;
  final int size;
  final double borderRadius;
  final bool isMini;
  final double? iconSize;
  final ArtworkType artworkType;
  final bool isPlaying;
  final bool isStopped;

  const SmoothArtWidget({
    super.key,
    required this.id,
    this.size = 300,
    this.borderRadius = 12.0,
    this.isMini = false,
    this.iconSize,
    this.artworkType = ArtworkType.AUDIO,
    this.isPlaying = false,
    this.isStopped = false,
  });

  @override
  State<SmoothArtWidget> createState() => _SmoothArtWidgetState();
}

class _SmoothArtWidgetState extends State<SmoothArtWidget> {
  Uint8List? _currentArt;
  bool _isLoading = true;
  bool _loadedSynchronously = false;

  String get _cacheKey => '${widget.id}_${widget.artworkType.index}_${widget.size}';

  @override
  void initState() {
    super.initState();
    final memCached = _ArtCache.get(_cacheKey);
    if (memCached != null) {
      _currentArt = memCached;
      _isLoading = false;
      _loadedSynchronously = true;
    } else {
      _isLoading = true;
      _loadedSynchronously = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) _tryLoad();
  }

  @override
  void didUpdateWidget(covariant SmoothArtWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.artworkType != widget.artworkType) {
      final memCached = _ArtCache.get(_cacheKey);
      if (memCached != null) {
        _currentArt = memCached;
        _isLoading = false;
        _loadedSynchronously = true;
      } else {
        _isLoading = true;
        _loadedSynchronously = false;
        _currentArt = null;
        _tryLoad();
      }
    }
  }

  void _tryLoad() {
    if (!_isLoading) return;

    // Fast path: already in memory
    final memCached = _ArtCache.get(_cacheKey);
    if (memCached != null) {
      _currentArt = memCached;
      _isLoading = false;
      _loadedSynchronously = true;
      return;
    }

    // Use Flutter's built-in scroll-aware deferral
    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      // Schedule a retry after the current frame
      WidgetsBinding.instance.scheduleFrameCallback((_) {
        if (mounted && _isLoading) _tryLoad();
      });
      return;
    }

    _fetchArt();
  }

  Future<void> _fetchArt() async {
    final cacheKey = _cacheKey;
    final targetId = widget.id;

    final diskCached = await _DiskArtCache.load(cacheKey);
    if (diskCached != null) {
      _ArtCache.put(cacheKey, diskCached);
      if (mounted && widget.id == targetId) {
        setState(() {
          _currentArt = diskCached;
          _isLoading = false;
          _loadedSynchronously = false;
        });
      }
      return;
    }

    final art = await OnAudioQuery().queryArtwork(
      targetId,
      widget.artworkType,
      size: widget.size,
      quality: widget.isMini ? 50 : 100,
      format: ArtworkFormat.PNG,
    );

    _ArtCache.put(cacheKey, art);
    if (art != null) {
      _DiskArtCache.save(cacheKey, art);
    }

    if (mounted && widget.id == targetId) {
      setState(() {
        _currentArt = art;
        _isLoading = false;
        _loadedSynchronously = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (_currentArt != null) {
      imageWidget = Image.memory(
        _currentArt!,
        key: ValueKey(widget.id),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        cacheWidth: widget.size,
      );
    } else {
      imageWidget = Container(
        key: const ValueKey('placeholder'),
        width: double.infinity,
        height: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.music_note, 
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5), 
            size: widget.iconSize ?? 40
          )
        ),
      );
    }

    final duration = _loadedSynchronously 
        ? Duration.zero 
        : const Duration(milliseconds: 200);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox.expand(
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
            return Stack(
              children: <Widget>[
                ...previousChildren.map((child) => SizedBox.expand(child: child)),
                if (currentChild != null) SizedBox.expand(child: currentChild),
              ],
            );
          },
          child: imageWidget,
        ),
      ),
    );
  }
}

// Emphasized Spring Curve
class SpringCurve extends Curve {
  const SpringCurve();

  @override
  double transform(double t) {
    final simulation = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 400, damping: 24),
      0, 1, 0,
    );
    // mapped roughly over 600ms duration
    return simulation.x(t * 0.6); 
  }
}
