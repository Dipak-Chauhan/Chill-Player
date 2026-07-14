import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../models/song.dart';
import '../../models/lyric_line.dart';
import '../widgets/smooth_art_widget.dart';
import '../widgets/m3_loading_indicator.dart';
import '../widgets/spring_button.dart';
import 'dart:async';
import '../../state/audio_state.dart';
import '../../services/settings_service.dart';
import '../../state/lyrics_provider.dart';
import '../../state/translation_state.dart';
import '../../services/translation_service.dart';
import '../../theme/color_provider.dart';
import 'lyrics_editor_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../widgets/drag_to_dismiss_wrapper.dart';

// Design constants — sourced from YouLy+ CSS analysis
const double _kFontMain = 30.0;
const double _kFontSub = 17.0;
const double _kBlurFar = 3.0; // distant lines
const double _kBlurNear = 1.5; // adjacent lines
const double _kScaleOff = 0.93; // inactive line scale

// LYRICS SCREEN — full opaque modal (opened from NowPlayingScreen)
// Background: album art blurred + dark overlay (like Apple Music / YouLy+)
// Timing: Rush model — anchor on positionStream, interpolate with speed×elapsed at 60fps
// Wipe: YouLy+ dual-layer soft gradient, pure math from position (no ctrl per word)

class LyricsScreen extends ConsumerStatefulWidget {
  final Song song;
  final EdgeInsets systemPadding;
  const LyricsScreen({
    super.key,
    required this.song,
    required this.systemPadding,
  });

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen>
    with TickerProviderStateMixin {
  // Scroll
  late final ScrollController _scroll;
  bool _userScrolling = false;
  Timer? _scrollLockTimer;
  List<GlobalKey> _lineKeys = [];
  bool _initialScrollDone = false;
  bool _isSeeking = false;
  // Predictive auto-scroll: the line we've most recently scrolled toward.
  int _lastScrollTargetIdx = -1;
  // Manual sync offset (ms) applied to the playback clock for lyric timing.
  int _lyricsOffsetMs = 0;
  final GlobalKey _columnKey = GlobalKey();

  // Position
  late Ticker _ticker;
  final ValueNotifier<int> _posMs = ValueNotifier(0);

  // Interpolation anchors for 60fps sub-frame timing
  Duration _lastPosition = Duration.zero;
  int _lastPositionTime = 0;
  bool _lastPlaying = false;

  // Active line
  final ValueNotifier<int> _activeIdxNotifier = ValueNotifier(-1);

  // Song change tracking
  List<LyricLine>? _currentLyrics;

  // Testing Features
  bool _isAmoledMode = false;
  int _artDisplayMode = 0; // 0=Norm, 1=Dim, 2=B&W

  late final _player = ref.read(audioPlayerProvider);

  // Local caching of player state
  Duration _cachedPosition = Duration.zero;
  bool _cachedPlaying = false;
  double _cachedSpeed = 1.0;
  StreamSubscription? _posSubscription;
  StreamSubscription? _playSubscription;
  StreamSubscription? _speedSubscription;
  int _lastTickTime = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Prevent screen timeout while lyrics are open
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    ); // Hide status bar + full screen
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );

    _scroll = ScrollController();

    // Initialize local cached player values
    _cachedPosition = _player.position;
    _cachedPlaying = _player.playing;
    _cachedSpeed = _player.speed;

    _lastPosition = _cachedPosition;
    _lastPositionTime = DateTime.now().millisecondsSinceEpoch;
    _lastPlaying = _cachedPlaying;

    // Listen to player streams to keep local cache updated
    _posSubscription = _player.positionStream.listen((pos) {
      _cachedPosition = pos;
      _lastPosition = pos;
      _lastPositionTime = DateTime.now().millisecondsSinceEpoch;
    });
    _playSubscription = _player.playingStream.listen((playing) {
      _cachedPlaying = playing;
      _lastPlaying = playing;
      _lastPositionTime = DateTime.now().millisecondsSinceEpoch;
    });
    _speedSubscription = _player.speedStream.listen((speed) {
      _cachedSpeed = speed;
    });

    // 60fps sub-frame position interpolator
    _ticker = createTicker((_) {
      if (!mounted) return;

      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        // Update at up to ~120fps so the word-by-word wipe tracks high-refresh
        // displays smoothly. Only the currently animating word rebuilds per
        // frame, so the extra cost is small.
        if (now - _lastTickTime < 8) {
          return;
        }
        _lastTickTime = now;

        if (!_isSeeking) {
          final rawPos = _cachedPosition;
          final playing = _cachedPlaying;

          if (rawPos != _lastPosition || playing != _lastPlaying) {
            _lastPosition = rawPos;
            _lastPositionTime = now;
            _lastPlaying = playing;
          }

          int posMs = rawPos.inMilliseconds;
          if (playing) {
            final elapsed = now - _lastPositionTime;
            // Limit interpolation to 2000ms to avoid runaway drift during buffering/lag
            if (elapsed >= 0 && elapsed < 2000) {
              final speed = _cachedSpeed;
              posMs = (rawPos.inMilliseconds + elapsed * speed).round();
            }
          }

          // Apply the manual sync offset (compensates audio-output latency).
          posMs += _lyricsOffsetMs;

          _posMs.value = posMs;

          final lines = _currentLyrics;
          if (lines != null && lines.isNotEmpty) {
            final newActive = _calculateActiveIndex(posMs, lines);
            if (newActive != _activeIdxNotifier.value) {
              _activeIdxNotifier.value = newActive;
            }

            // Predictive auto-scroll: aim at the line that will be active a
            // little ahead of now, so it's already settled at the anchor by
            // the time it's sung (matches Apple Music / YouLy+ behaviour).
            final lookahead = _scrollLookaheadMs(posMs, lines);
            final scrollIdx = _calculateActiveIndex(posMs + lookahead, lines);
            if (scrollIdx >= 0 && scrollIdx != _lastScrollTargetIdx) {
              _lastScrollTargetIdx = scrollIdx;
              _scrollToLine(scrollIdx);
            }
          }
        }
      } catch (e, stack) {
        debugPrint('Lyrics Ticker error: $e\n$stack');
      }
    })..start();
    _showControls = true;
    _resetControlsTimer();
  }

  void _handleUserScroll() {
    _userScrolling = true;
    _scrollLockTimer?.cancel();
    _scrollLockTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _userScrolling = false;
        });
        _animateToActiveLine();
      }
    });
  }

  void _animateToActiveLine() => _scrollToLine(_activeIdxNotifier.value);

  /// Glides the viewport so line [index] sits at the anchor. The first call
  /// after a (re)load jumps instantly; subsequent calls animate.
  void _scrollToLine(int index) {
    if (!mounted || _userScrolling || !_scroll.hasClients || index < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userScrolling || !_scroll.hasClients) return;
      final double? targetOffset = _getScrollOffsetFor(index);
      if (targetOffset != null) {
        if (!_initialScrollDone) {
          _scroll.jumpTo(targetOffset);
          _initialScrollDone = true;
        } else {
          _scroll.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 800),
            curve: const DampedSpringCurve(
              mass: 1.0,
              stiffness: 100.0,
              damping: 15.0,
            ),
          );
        }
      }
    });
  }

  /// Look-ahead window for predictive scrolling: the gap to the next line,
  /// clamped to 350–500ms (YouLy+ heuristic).
  int _scrollLookaheadMs(int posMs, List<LyricLine> lines) {
    final cur = _calculateActiveIndex(posMs, lines);
    if (cur >= 0 && cur + 1 < lines.length) {
      final gap =
          lines[cur + 1].startTime.inMilliseconds -
          lines[cur].endTime.inMilliseconds;
      return gap.clamp(350, 500);
    }
    return 350;
  }

  double? _getScrollOffsetFor(int index) {
    try {
      if (index < 0 || index >= _lineKeys.length) return null;
      final key = _lineKeys[index];
      final lineContext = key.currentContext;
      if (lineContext == null) return null;
      final box = lineContext.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) return null;
      final scrollable = Scrollable.maybeOf(lineContext);
      if (scrollable == null) return null;
      final scrollableBox = scrollable.context.findRenderObject() as RenderBox?;
      if (scrollableBox == null ||
          !scrollableBox.hasSize ||
          !scrollableBox.attached) {
        return null;
      }

      final double lineHeight = box.size.height;
      final double viewportHeight = scrollableBox.size.height;

      // Calculate local offset of the child relative to the scrollable viewport RenderBox
      final localOffset = box.localToGlobal(
        Offset.zero,
        ancestor: scrollableBox,
      );

      // Target scroll offset to center the line
      final double targetOffset =
          _scroll.offset +
          localOffset.dy +
          (lineHeight / 2) -
          (viewportHeight / 2);

      // Clamp between 0 and maxScrollExtent
      final double maxScroll = _scroll.position.maxScrollExtent;
      return targetOffset.clamp(0.0, maxScroll);
    } catch (e, stack) {
      debugPrint('Error in _getScrollOffsetFor: $e\n$stack');
      return null;
    }
  }

  int _calculateActiveIndex(int posMs, List<LyricLine> lines) {
    int newActive = -1;
    for (int i = lines.length - 1; i >= 0; i--) {
      if (posMs >= lines[i].startTime.inMilliseconds) {
        newActive = i;
        break;
      }
    }
    return newActive;
  }

  bool _isSongPurelyLatin() {
    final lyrics = _currentLyrics;
    if (lyrics == null || lyrics.isEmpty) return true;
    for (final line in lyrics) {
      final text = line.text.trim();
      if (text.isEmpty || line.isGap) continue;
      for (final char in text.runes) {
        if (char > 0x024F &&
            char != 0x0027 &&
            char != 0x2019 &&
            !(char >= 0x0020 && char <= 0x007E) &&
            !(char >= 0x00C0 && char <= 0x024F)) {
          return false;
        }
      }
    }
    return true;
  }

  // Overlay Controls
  bool _showControls = true;
  Timer? _controlsTimer;

  bool _showAlbumArtControls = false;
  Timer? _albumArtControlsTimer;

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (!_showControls) {
      setState(() {
        _showControls = true;
      });
    }
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _resetAlbumArtControlsTimer() {
    _albumArtControlsTimer?.cancel();
    if (!_showAlbumArtControls) {
      setState(() {
        _showAlbumArtControls = true;
      });
    }
    _albumArtControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showAlbumArtControls = false;
        });
      }
    });
  }

  void _toggleAlbumArtControls() {
    _resetControlsTimer();
    if (_showAlbumArtControls) {
      setState(() {
        _showAlbumArtControls = false;
      });
      _albumArtControlsTimer?.cancel();
    } else {
      _resetAlbumArtControlsTimer();
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _albumArtControlsTimer?.cancel();
    _scrollLockTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    ); // Restore status bar
    WakelockPlus.disable(); // Allow screen to sleep again when user leaves
    _posSubscription?.cancel();
    _playSubscription?.cancel();
    _speedSubscription?.cancel();
    _ticker.dispose();
    _posMs.dispose();
    _activeIdxNotifier.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Bottom sheet to nudge the lyric sync offset. Positive = lyrics earlier,
  /// negative = later. Compensates for audio-output latency.
  void _showSyncOffsetSheet() {
    _controlsTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xE6141414), // Frosted translucent background
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Consumer(
              builder: (ctx, ref, child) {
                final currentSong = ref.watch(currentSongProvider);
                if (currentSong == null) return const SizedBox.shrink();
                final offset = ref.watch(songLyricsOffsetProvider(currentSong.id));
                void setOffset(int value) {
                  ref.read(songLyricsOffsetProvider(currentSong.id).notifier).update(value);
                }

                String label(int ms) {
                  if (ms == 0) return 'In sync';
                  final sign = ms > 0 ? '+' : '';
                  return '$sign${(ms / 1000).toStringAsFixed(2)}s '
                      '(${ms > 0 ? 'earlier' : 'later'})';
                }

                return SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Lyrics Sync',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Adjust if lyrics run ahead of or behind the audio.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _offsetButton(
                            icon: Icons.remove,
                            onTap: () => setOffset(offset - 100),
                          ),
                          Column(
                            children: [
                              Text(
                                label(offset),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (offset != 0)
                                TextButton(
                                  onPressed: () => setOffset(0),
                                  child: const Text('Reset'),
                                ),
                            ],
                          ),
                          _offsetButton(
                            icon: Icons.add,
                            onTap: () => setOffset(offset + 100),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    ).then((_) {
      if (mounted) _resetControlsTimer();
    });
  }

  Widget _offsetButton({required IconData icon, required VoidCallback onTap}) {
    return InkResponse(
      onTap: onTap,
      radius: 36,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  void _showTranslationMenu() {
    final mode = ref.read(translationModeProvider);
    final hasT =
        mode == TranslationDisplayMode.translate ||
        mode == TranslationDisplayMode.both;
    final hasR =
        mode == TranslationDisplayMode.romanize ||
        mode == TranslationDisplayMode.both;
    final lang = ref.read(targetLanguageProvider);
    final ctrl = TranslationController(ref);

    _controlsTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      builder: (ctx) => _TranslationSheet(
        currentLang: lang,
        hasTranslation: hasT,
        hasRomanization: hasR,
        isRomanizationSupported: !_isSongPurelyLatin(),
        onToggleTranslation: () {
          Navigator.pop(ctx);
          ctrl.toggleTranslation();
        },
        onToggleRomanization: () {
          Navigator.pop(ctx);
          ctrl.toggleRomanization();
        },
        onLanguageSelect: (l) {
          Navigator.pop(ctx);
          ctrl.changeLanguage(l);
        },
      ),
    ).then((_) {
      if (mounted) _resetControlsTimer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQueryData.fromView(View.of(context)).padding;

    final currentSong = ref.watch(currentSongProvider);
    final globalOffset = ref.watch(lyricsOffsetProvider);
    final songSpecificOffset = currentSong != null
        ? ref.watch(songLyricsOffsetProvider(currentSong.id))
        : 0;
    _lyricsOffsetMs = globalOffset + songSpecificOffset;

    // Show floating snackbar on translation/romanization errors
    ref.listen<String?>(translationErrorProvider, (previous, next) {
      if (next != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    // Track song changes cleanly using Riverpod listener
    ref.listen<Song?>(currentSongProvider, (previous, next) {
      if (next != previous) {
        _initialScrollDone = false;
        _lastScrollTargetIdx = -1;
        setState(() {
          _lineKeys = [];
        });
        TranslationController(ref).clearForNewSong();
      }
    });

    // Reactively fetch translations and sync keys/active-index when lyrics finish loading
    ref.listen<AsyncValue<List<LyricLine>>>(lyricsProvider, (previous, next) {
      if (next.hasValue && !next.isLoading) {
        final lines = next.value ?? [];
        if (lines.isNotEmpty) {
          setState(() {
            _lineKeys = List.generate(lines.length, (_) => GlobalKey());
          });

          // Synchronize active index immediately on data load
          final currentPos = _player.position.inMilliseconds;
          final initialActive = _calculateActiveIndex(currentPos, lines);
          if (_activeIdxNotifier.value != initialActive) {
            _activeIdxNotifier.value = initialActive;
          }

          final mode = ref.read(translationModeProvider);
          if (mode != TranslationDisplayMode.none) {
            final ctrl = TranslationController(ref);
            if ((mode == TranslationDisplayMode.translate ||
                    mode == TranslationDisplayMode.both) &&
                ref.read(translationDataProvider) == null) {
              ctrl.fetchTranslation();
            }
            if ((mode == TranslationDisplayMode.romanize ||
                    mode == TranslationDisplayMode.both ||
                    ref.read(onlyShowRomanizationProvider)) &&
                ref.read(romanizationDataProvider) == null) {
              ctrl.fetchRomanization();
            }
          }
        }
      }
    });

    ref.listen<bool>(onlyShowRomanizationProvider, (previous, next) {
      if (next && ref.read(romanizationDataProvider) == null) {
        TranslationController(ref).fetchRomanization();
      }
    });

    final mode = ref.watch(translationModeProvider);
    final transData = ref.watch(translationDataProvider);
    final romanData = ref.watch(romanizationDataProvider);
    final lyricsAsync = ref.watch(lyricsProvider);
    _currentLyrics = lyricsAsync.value;
    final activeSong = ref.watch(currentSongProvider) ?? widget.song;
    final isTranslating = ref.watch(translationLoadingProvider);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final hideArt = ref.watch(hideLandscapeArtProvider);
    final centerLyrics = isLandscape && hideArt;

    Widget foregroundContent;
    if (isLandscape) {
      foregroundContent = Padding(
        padding: EdgeInsets.only(
          left: safePadding.left > 0 ? safePadding.left : 16.0,
          right: safePadding.right > 0 ? safePadding.right : 16.0,
        ),
        child: Row(
          children: [
            if (!hideArt)
              Expanded(
                flex: 4,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: GestureDetector(
                      onTap: _toggleAlbumArtControls,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Stack(
                            fit: StackFit.expand,
                            alignment: Alignment.center,
                            children: [
                              _isAmoledMode
                                  ? Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        ColorFiltered(
                                          colorFilter: _artDisplayMode == 2
                                              ? const ColorFilter.matrix(<double>[
                                                  0.2126,
                                                  0.7152,
                                                  0.0722,
                                                  0,
                                                  0,
                                                  0.2126,
                                                  0.7152,
                                                  0.0722,
                                                  0,
                                                  0,
                                                  0.2126,
                                                  0.7152,
                                                  0.0722,
                                                  0,
                                                  0,
                                                  0,
                                                  0,
                                                  0,
                                                  1,
                                                  0,
                                                ])
                                              : const ColorFilter.mode(
                                                  Colors.transparent,
                                                  BlendMode.dst,
                                                ),
                                          child: SmoothArtWidget(
                                            id: activeSong.id,
                                            size: 800,
                                            borderRadius: 32,
                                          ),
                                        ),
                                        AnimatedOpacity(
                                          opacity: _artDisplayMode == 1 ? 1.0 : 0.0,
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.85,
                                              ),
                                              borderRadius: BorderRadius.circular(
                                                32,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Container(
                                      decoration: BoxDecoration(
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.5,
                                            ),
                                            blurRadius: 40,
                                            spreadRadius: 10,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      child: SmoothArtWidget(
                                        id: activeSong.id,
                                        size: 800,
                                        borderRadius: 32,
                                      ),
                                    ),

                              Positioned.fill(
                                child: IgnorePointer(
                                  ignoring: !_showAlbumArtControls,
                                  child: AnimatedOpacity(
                                    opacity: _showAlbumArtControls ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 300),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.55),
                                        borderRadius: BorderRadius.circular(32),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        children: [
                                          SpringButton(
                                            onTap: () {
                                              ref
                                                  .read(audioPlayerProvider)
                                                  .seekToPrevious();
                                              _resetAlbumArtControlsTimer();
                                              _resetControlsTimer();
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                                    .withValues(alpha: 0.5),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.skip_previous,
                                                size: 28,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                          Consumer(
                                            builder: (context, ref, child) {
                                              final isPlaying = ref.watch(
                                                isPlayingProvider,
                                              );
                                              return SpringButton(
                                                onTap: () {
                                                  ref
                                                      .read(
                                                        isPlayingProvider.notifier,
                                                      )
                                                      .toggle();
                                                  _resetAlbumArtControlsTimer();
                                                  _resetControlsTimer();
                                                },
                                                child: AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 300,
                                                  ),
                                                  curve: Curves.elasticOut,
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: isPlaying ? 24 : 28,
                                                    vertical: 16,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.primaryContainer,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          isPlaying ? 24 : 40,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    isPlaying
                                                        ? Icons.pause
                                                        : Icons.play_arrow,
                                                    size: 32,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onPrimaryContainer,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                          SpringButton(
                                            onTap: () {
                                              ref
                                                  .read(audioPlayerProvider)
                                                  .seekToNext();
                                              _resetAlbumArtControlsTimer();
                                              _resetControlsTimer();
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                                    .withValues(alpha: 0.5),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.skip_next,
                                                size: 28,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              flex: hideArt ? 1 : 6,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: hideArt ? 600 : double.infinity),
                  child: lyricsAsync.when(
                    loading: () => const Center(
                      child: M3LoadingIndicator(size: 40, color: Colors.white38),
                    ),
                    error: (e, _) => Center(
                      child: Text(
                        '$e',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ),
                    data: (lines) => _buildList(lines, mode, transData, romanData, centerLyrics),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      foregroundContent = lyricsAsync.when(
        loading: () => const Center(
          child: M3LoadingIndicator(size: 40, color: Colors.white38),
        ),
        error: (e, _) => Center(
          child: Text('$e', style: const TextStyle(color: Colors.white54)),
        ),
        data: (lines) => _buildList(lines, mode, transData, romanData, centerLyrics),
      );
    }

    Widget contentStack = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetControlsTimer(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background: album art blurred + dark overlay (Apple Music style)
          if (!_isAmoledMode) _BlurredBackground(songId: activeSong.id),

          // The Foreground Content
          foregroundContent,

          // Top fade gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: widget.systemPadding.top + 80,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Bottom fade gradient
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 180,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.90),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Mini Translucent Controls & Song Info (Portrait)
          if (!isLandscape)
            Positioned(
              bottom: safePadding.bottom + 24,
              left: 24,
              right: 24,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        activeSong.title,
                        style: TextStyle(
                          color: _isAmoledMode
                              ? Colors.white.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.8),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        activeSong.artist,
                        style: TextStyle(
                          color: _isAmoledMode
                              ? Colors.white.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SpringButton(
                            onTap: () =>
                                ref.read(audioPlayerProvider).seekToPrevious(),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _isAmoledMode
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.skip_previous,
                                size: 24,
                                color: _isAmoledMode
                                    ? Colors.white.withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Consumer(
                            builder: (context, ref, child) {
                              final isPlaying = ref.watch(isPlayingProvider);
                              return SpringButton(
                                onTap: () =>
                                    ref.read(isPlayingProvider.notifier).toggle(),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.elasticOut,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isPlaying ? 32 : 16,
                                    vertical: 16,
                                  ),
                                  decoration: ShapeDecoration(
                                    color: _isAmoledMode
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                              .withValues(alpha: 0.5),
                                    shape: isPlaying
                                        ? const StadiumBorder()
                                        : ContinuousRectangleBorder(
                                            borderRadius: BorderRadius.circular(40),
                                          ),
                                  ),
                                  child: Icon(
                                    isPlaying ? Icons.pause : Icons.play_arrow,
                                    size: 28,
                                    color: _isAmoledMode
                                        ? Colors.white.withValues(alpha: 0.8)
                                        : Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer
                                              .withValues(alpha: 0.9),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 24),
                          SpringButton(
                            onTap: () => ref.read(audioPlayerProvider).seekToNext(),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _isAmoledMode
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.skip_next,
                                size: 24,
                                color: _isAmoledMode
                                    ? Colors.white.withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_showControls,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16 + (isLandscape ? safePadding.left : 0),
                    safePadding.top + 8,
                    4 + (isLandscape ? safePadding.right : 0),
                    0,
                  ),
                  child: Row(
                    children: [
                      if (!isLandscape)
                        const Text(
                          'Lyrics',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                      const Spacer(),
                      if (isLandscape && _isAmoledMode)
                        IconButton(
                          icon: Icon(
                            _artDisplayMode == 0
                                ? Icons.brightness_auto
                                : _artDisplayMode == 1
                                ? Icons.brightness_3
                                : Icons.tonality,
                            color: _artDisplayMode != 0
                                ? Colors.white
                                : Colors.white70,
                            size: 22,
                          ),
                          tooltip: 'Art Display Mode',
                          onPressed: () {
                            setState(() {
                              _artDisplayMode = (_artDisplayMode + 1) % 3;
                            });
                          },
                        ),
                      IconButton(
                        icon: Icon(
                          _isAmoledMode ? Icons.dark_mode : Icons.dark_mode_outlined,
                          color: _isAmoledMode ? Colors.white : Colors.white70,
                          size: 22,
                        ),
                        tooltip: 'Toggle AMOLED Mode',
                        onPressed: () {
                          setState(() {
                            _isAmoledMode = !_isAmoledMode;
                            if (!_isAmoledMode) {
                              _artDisplayMode =
                                  0; // reset dimming when leaving amoled
                            }
                          });
                        },
                      ),
                      if (isLandscape)
                        IconButton(
                          icon: Icon(
                            hideArt ? Icons.image_not_supported_outlined : Icons.image_outlined,
                            color: Colors.white70,
                            size: 22,
                          ),
                          tooltip: hideArt ? 'Show Album Art' : 'Hide Album Art',
                          onPressed: () {
                            ref.read(hideLandscapeArtProvider.notifier).update(!hideArt);
                          },
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.av_timer,
                          color: Colors.white70,
                          size: 22,
                        ),
                        tooltip: 'Lyrics Sync',
                        onPressed: _showSyncOffsetSheet,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.refresh,
                          color: Colors.white70,
                          size: 24,
                        ),
                        tooltip: 'Refresh Lyrics',
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Refreshing Lyrics...'),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          ref.invalidate(lyricsProvider);
                          TranslationController(ref).clearForNewSong();
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit_note,
                          color: Colors.white70,
                          size: 24,
                        ),
                        tooltip: 'Edit Lyrics',
                        onPressed: () async {
                          final song = ref.read(currentSongProvider);
                          if (song != null) {
                            _controlsTimer?.cancel();
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LyricsEditorScreen(song: song),
                              ),
                            );
                            if (mounted) _resetControlsTimer();
                          }
                        },
                      ),
                      isTranslating
                          ? const SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(
                                Icons.translate,
                                color: Colors.white70,
                                size: 22,
                              ),
                              onPressed: _showTranslationMenu,
                            ),
                      IconButton(
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white70,
                          size: 28,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return DragToDismissWrapper(
      onDismissed: () => Navigator.of(context).pop(),
      maxDragDistance: MediaQuery.sizeOf(context).height * 0.8,
      builder: (context, dismissProgress) {
        final scale = 1.0 - (dismissProgress * 0.1);
        final opacity = (1.0 - dismissProgress).clamp(0.0, 1.0);

        Widget result;
        if (isLandscape) {
          result = Material(
            color: Colors.black,
            child: SizedBox.expand(child: contentStack),
          );
        } else {
          result = Material(
            color: Colors.black,
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height,
              child: contentStack,
            ),
          );
        }

        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: result,
          ),
        );
      },
    );
  }

  static String _cleanForCompare(String s) {
    return s
        .toLowerCase()
        .replaceAll(
          RegExp(
            r"[.,\/#!$%\^&\*;:{}=\-_`~()?'"
            '"]',
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  Widget _buildList(
    List<LyricLine> lyrics,
    TranslationDisplayMode mode,
    TranslationResult? trans,
    TranslationResult? roman,
    bool centerLyrics,
  ) {
    if (lyrics.isEmpty) {
      return const Center(
        child: Text(
          'No synced lyrics found',
          style: TextStyle(color: Colors.white54, fontSize: 17),
        ),
      );
    }

    // Synchronize our layout keys list to exactly match the lyrics array size
    if (_lineKeys.length != lyrics.length) {
      _lineKeys = List.generate(lyrics.length, (_) => GlobalKey());
    }

    final double vh = MediaQuery.sizeOf(context).height;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          if (notification.direction != ScrollDirection.idle) {
            _handleUserScroll();
          }
        } else if (notification is ScrollUpdateNotification) {
          if (notification.dragDetails != null) {
            _handleUserScroll();
          }
        }
        return false;
      },
      child: RepaintBoundary(
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            20,
            vh *
                0.50, // 50% clearance so the first line starts exactly at vertical center
            20,
            vh *
                0.50, // 50% clearance so the last line can end exactly at vertical center
          ),
          child: Column(
            key: _columnKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(lyrics.length, (i) {
              final line = lyrics[i];
              final onlyShowRomanization = ref.watch(onlyShowRomanizationProvider);
              final String? transTextRaw =
                  (mode == TranslationDisplayMode.translate ||
                          mode == TranslationDisplayMode.both) &&
                      trans != null &&
                      i < trans.translations.length &&
                      trans.translations[i].isNotEmpty
                  ? trans.translations[i]
                  : null;
              final String? transText =
                  onlyShowRomanization
                      ? null
                      : (transTextRaw != null &&
                          _cleanForCompare(transTextRaw) !=
                              _cleanForCompare(line.text)
                      ? transTextRaw
                      : null);
              final isPureLatin = _isSongPurelyLatin();
              final String? romanTextRaw =
                  (!isPureLatin &&
                      (mode == TranslationDisplayMode.romanize ||
                          mode == TranslationDisplayMode.both ||
                          onlyShowRomanization) &&
                      roman != null &&
                      i < roman.romanizations.length)
                  ? roman.romanizations[i]
                  : null;
              final String? romanText =
                  romanTextRaw != null &&
                          _cleanForCompare(romanTextRaw) !=
                              _cleanForCompare(line.text)
                      ? romanTextRaw
                      : null;
              final List<String>? romanWordsList =
                  romanText != null &&
                      roman != null &&
                      i < roman.romanizedWords.length
                  ? roman.romanizedWords[i]
                  : null;

              final swapRomanization = ref.watch(swapRomanizationProvider);
              final LyricLine activeLine;
              final String? activeRomanText;
              final List<String>? activeRomanWords;

              if (onlyShowRomanization && romanText != null) {
                final List<LyricWord>? swappedWords = line.words != null
                    ? List.generate(line.words!.length, (wIdx) {
                        final word = line.words![wIdx];
                        final String wordRoman = (romanWordsList != null && wIdx < romanWordsList.length)
                            ? romanWordsList[wIdx]
                            : (word.romanText ?? word.text);
                        return LyricWord(
                          startTime: word.startTime,
                          endTime: word.endTime,
                          text: wordRoman,
                          romanText: null,
                        );
                      })
                    : null;

                final List<LyricLine>? swappedBgLines = line.backgroundLines?.map((bg) {
                  final bgSwappedWords = bg.words?.map((word) {
                    if (word.romanText != null) {
                      return LyricWord(
                        startTime: word.startTime,
                        endTime: word.endTime,
                        text: word.romanText!,
                        romanText: null,
                      );
                    }
                    return word;
                  }).toList();
                  
                  return LyricLine(
                    startTime: bg.startTime,
                    endTime: bg.endTime,
                    text: bgSwappedWords != null
                        ? bgSwappedWords.map((w) => w.text).join(' ')
                        : bg.text,
                    words: bgSwappedWords,
                    isGap: bg.isGap,
                    singer: bg.singer,
                    singerSide: bg.singerSide,
                  );
                }).toList();

                activeLine = LyricLine(
                  startTime: line.startTime,
                  endTime: line.endTime,
                  text: romanText,
                  words: swappedWords,
                  backgroundLines: swappedBgLines,
                  isGap: line.isGap,
                  singer: line.singer,
                  singerSide: line.singerSide,
                );
                
                activeRomanText = null;
                activeRomanWords = null;
              } else if (swapRomanization && romanText != null) {
                activeRomanText = line.text;
                
                final List<LyricWord>? swappedWords = line.words != null
                    ? List.generate(line.words!.length, (wIdx) {
                        final word = line.words![wIdx];
                        final String wordRoman = (romanWordsList != null && wIdx < romanWordsList.length)
                            ? romanWordsList[wIdx]
                            : (word.romanText ?? word.text);
                        return LyricWord(
                          startTime: word.startTime,
                          endTime: word.endTime,
                          text: wordRoman,
                          romanText: word.text,
                        );
                      })
                    : null;

                final List<LyricLine>? swappedBgLines = line.backgroundLines?.map((bg) {
                  final bgSwappedWords = bg.words?.map((word) {
                    if (word.romanText != null) {
                      return LyricWord(
                        startTime: word.startTime,
                        endTime: word.endTime,
                        text: word.romanText!,
                        romanText: word.text,
                      );
                    }
                    return word;
                  }).toList();
                  
                  return LyricLine(
                    startTime: bg.startTime,
                    endTime: bg.endTime,
                    text: bgSwappedWords != null
                        ? bgSwappedWords.map((w) => w.text).join(' ')
                        : bg.text,
                    words: bgSwappedWords,
                    isGap: bg.isGap,
                    singer: bg.singer,
                    singerSide: bg.singerSide,
                  );
                }).toList();

                activeLine = LyricLine(
                  startTime: line.startTime,
                  endTime: line.endTime,
                  text: romanText,
                  words: swappedWords,
                  backgroundLines: swappedBgLines,
                  isGap: line.isGap,
                  singer: line.singer,
                  singerSide: line.singerSide,
                );
                
                activeRomanWords = line.words?.map((w) => w.text).toList();
              } else {
                activeLine = line;
                activeRomanText = romanText;
                activeRomanWords = romanWordsList;
              }

              return RepaintBoundary(
                child: _LyricLineWrapper(
                  key: _lineKeys[i],
                  index: i,
                  activeIdxNotifier: _activeIdxNotifier,
                  line: activeLine,
                  posMs: _posMs,
                  transText: transText,
                  romanText: activeRomanText,
                  romanWords: activeRomanWords,
                  onTap: () {
                    setState(() {
                      _isSeeking = true;
                    });
                    _posMs.value = line.startTime.inMilliseconds;
                    _activeIdxNotifier.value = i;
                    try {
                      _player.seek(line.startTime);
                    } catch (_) {}
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted) {
                        setState(() {
                          _isSeeking = false;
                        });
                      }
                    });
                  },
                  lineKey: _lineKeys[i],
                  centerLyrics: centerLyrics,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _LyricLineWrapper extends StatefulWidget {
  final int index;
  final ValueNotifier<int> activeIdxNotifier;
  final LyricLine line;
  final ValueNotifier<int> posMs;
  final String? transText;
  final String? romanText;
  final List<String>? romanWords;
  final VoidCallback onTap;
  final GlobalKey lineKey;
  final bool centerLyrics;

  const _LyricLineWrapper({
    super.key,
    required this.index,
    required this.activeIdxNotifier,
    required this.line,
    required this.posMs,
    this.transText,
    this.romanText,
    this.romanWords,
    required this.onTap,
    required this.lineKey,
    required this.centerLyrics,
  });

  @override
  State<_LyricLineWrapper> createState() => _LyricLineWrapperState();
}

class _LyricLineWrapperState extends State<_LyricLineWrapper> {
  late bool _isActive;
  late double _blur;
  late double _opacity;
  Timer? _staggerTimer;

  @override
  void initState() {
    super.initState();
    _updateVisualState(widget.activeIdxNotifier.value, init: true);
    widget.activeIdxNotifier.addListener(_handleActiveIdxChange);
  }

  @override
  void didUpdateWidget(_LyricLineWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIdxNotifier != widget.activeIdxNotifier) {
      oldWidget.activeIdxNotifier.removeListener(_handleActiveIdxChange);
      widget.activeIdxNotifier.addListener(_handleActiveIdxChange);
      _updateVisualState(widget.activeIdxNotifier.value);
    }
  }

  @override
  void dispose() {
    _staggerTimer?.cancel();
    widget.activeIdxNotifier.removeListener(_handleActiveIdxChange);
    super.dispose();
  }

  void _handleActiveIdxChange() {
    if (mounted) {
      _updateVisualState(widget.activeIdxNotifier.value);
    }
  }

  void _updateVisualState(int activeIdx, {bool init = false}) {
    final isActive = widget.index == activeIdx;
    final dist = (widget.index - activeIdx).abs();
    final double blur = isActive ? 0.0 : (dist <= 1 ? _kBlurNear : _kBlurFar);
    final double opacity = isActive ? 1.0 : (dist <= 1 ? 0.55 : 0.30);

    if (init) {
      _isActive = isActive;
      _blur = blur;
      _opacity = opacity;
    } else {
      _staggerTimer?.cancel();
      // Gorgeous cascading ripple effect delay based on distance to active line
      final delayMs = dist == 0 ? 0 : math.min(dist * 35, 120);

      _staggerTimer = Timer(Duration(milliseconds: delayMs), () {
        if (mounted && widget.activeIdxNotifier.value == activeIdx) {
          if (_isActive != isActive || _blur != blur || _opacity != opacity) {
            setState(() {
              _isActive = isActive;
              _blur = blur;
              _opacity = opacity;
            });
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: _LyricLineWidget(
        line: widget.line,
        isActive: _isActive,
        blur: _blur,
        opacity: _opacity,
        posMs: widget.posMs,
        transText: widget.transText,
        romanText: widget.romanText,
        romanWords: widget.romanWords,
        onTap: widget.onTap,
        centerLyrics: widget.centerLyrics,
      ),
    );
  }
}

// BLURRED BACKGROUND — album art + dark overlay
class _BlurredBackground extends StatelessWidget {
  final int songId;
  const _BlurredBackground({required this.songId});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: 1.15,
            child: QueryArtworkWidget(
              id: songId,
              type: ArtworkType.AUDIO,
              quality: 50,
              size: 500,
              artworkFit: BoxFit.cover,
              artworkWidth: double.infinity,
              artworkHeight: double.infinity,
              nullArtworkWidget: Container(color: const Color(0xFF1A1A1A)),
              keepOldArtwork: true,
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

// LYRIC LINE WIDGET — handles scale animation, blur, opacity
class _LyricLineWidget extends StatefulWidget {
  final LyricLine line;
  final bool isActive;
  final double blur;
  final double opacity;
  final ValueNotifier<int> posMs;
  final String? transText;
  final String? romanText;
  final List<String>? romanWords;
  final VoidCallback onTap;
  final bool centerLyrics;

  const _LyricLineWidget({
    required this.line,
    required this.isActive,
    required this.blur,
    required this.opacity,
    required this.posMs,
    this.transText,
    this.romanText,
    this.romanWords,
    required this.onTap,
    this.centerLyrics = false,
  });

  @override
  State<_LyricLineWidget> createState() => _LyricLineWidgetState();
}

class _LyricLineWidgetState extends State<_LyricLineWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      lowerBound: -double.infinity,
      upperBound: double.infinity,
    );
    _scaleCtrl.value = widget.isActive ? 1.0 : 0.0;
  }

  @override
  void didUpdateWidget(_LyricLineWidget old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      final sim = SpringSimulation(
        const SpringDescription(mass: 1.0, stiffness: 100.0, damping: 20.0),
        _scaleCtrl.value,
        1.0,
        _scaleCtrl.velocity,
      );
      _scaleCtrl.animateWith(sim);
    }
    if (!widget.isActive && old.isActive) {
      final sim = SpringSimulation(
        const SpringDescription(mass: 1.0, stiffness: 100.0, damping: 20.0),
        _scaleCtrl.value,
        0.0,
        _scaleCtrl.velocity,
      );
      _scaleCtrl.animateWith(sim);
    }
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final side = widget.centerLyrics ? 'center' : widget.line.singerSide;
    if (widget.line.isGap) {
      return _GapIndicator(
        line: widget.line,
        isActive: widget.isActive,
        posMs: widget.posMs,
      );
    }
    final vWidth = MediaQuery.sizeOf(context).width;

    final crossAlign = side == 'right'
        ? CrossAxisAlignment.end
        : (side == 'center'
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start);

    final scaleAlignment = side == 'right'
        ? Alignment.centerRight
        : (side == 'center' ? Alignment.center : Alignment.centerLeft);

    final bool isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final padding = isLandscape
        ? const EdgeInsets.symmetric(horizontal: 16)
        : (side == 'right'
            ? EdgeInsets.only(left: vWidth * 0.22, right: 8)
            : (side == 'left'
                ? EdgeInsets.only(right: vWidth * 0.22, left: 8)
                : const EdgeInsets.symmetric(horizontal: 8)));

    Widget core = GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: padding.add(const EdgeInsets.symmetric(vertical: 14)),
        child: AnimatedBuilder(
          animation: _scaleCtrl,
          builder: (ctx, child) {
            final t = _scaleCtrl.value;
            final scale = _kScaleOff + (_kScaleActive - _kScaleOff) * t;
            final translateY = -4.0 * t;
            return Transform.translate(
              offset: Offset(0.0, translateY),
              child: Transform.scale(
                alignment: scaleAlignment,
                scale: scale,
                child: child,
              ),
            );
          },
          child: _buildContent(crossAlign),
        ),
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: widget.blur, end: widget.blur),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, blurValue, child) {
        Widget result = child!;
        if (blurValue > 0.05) {
          result = ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: blurValue,
              sigmaY: blurValue,
              tileMode: TileMode.decal,
            ),
            child: result,
          );
        }
        return result;
      },
      child: AnimatedOpacity(
        opacity: widget.opacity,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: core,
      ),
    );
  }

  static const double _kScaleActive = 1.0;

  Widget _buildContent(CrossAxisAlignment crossAlign) {
    final side = widget.line.singerSide;
    final wrapAlign = side == 'right'
        ? WrapAlignment.end
        : (side == 'center' ? WrapAlignment.center : WrapAlignment.start);

    final textAlign = side == 'right'
        ? TextAlign.right
        : (side == 'center' ? TextAlign.center : TextAlign.left);

    return Column(
      crossAxisAlignment: crossAlign,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.line.words?.isNotEmpty ?? false)
          _WordByWordLine(
            line: widget.line,
            posMs: widget.posMs,
            isBackground: false,
            romanWords: widget.romanWords,
            alignment: wrapAlign,
            isActive: widget.isActive,
          )
        else
          _StaticText(
            text: widget.line.text,
            isBackground: false,
            isActive: widget.isActive,
            textAlign: textAlign,
          ),

        if (widget.line.backgroundLines != null)
          Opacity(
            opacity: 0.70,
            child: Column(
              crossAxisAlignment: crossAlign,
              children: [
                for (final bg in widget.line.backgroundLines!)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: (bg.words?.isNotEmpty ?? false)
                        ? _WordByWordLine(
                            line: bg,
                            posMs: widget.posMs,
                            isBackground: true,
                            alignment: wrapAlign,
                          )
                        : _StaticText(
                            text: bg.text,
                            isBackground: true,
                            isActive: widget.isActive,
                            textAlign: textAlign,
                          ),
                  ),
              ],
            ),
          ),

        if (widget.romanText != null &&
            !(widget.line.words?.isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.romanText!,
              textAlign: textAlign,
              style: TextStyle(
                color: Colors.white.withValues(
                  alpha: widget.isActive ? 0.72 : 0.40,
                ),
                fontSize: _kFontSub,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),

        if (widget.transText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.transText!,
              textAlign: textAlign,
              style: TextStyle(
                color: Colors.white.withValues(
                  alpha: widget.isActive ? 0.62 : 0.35,
                ),
                fontSize: _kFontSub,
                fontWeight: FontWeight.w400,
                height: 1.3,
              ),
            ),
          ),
      ],
    );
  }
}

// STATIC TEXT — used for inactive lines, or line-synced LRC active lines
class _StaticText extends StatelessWidget {
  final String text;
  final bool isBackground;
  final bool isActive;
  final TextAlign textAlign;

  const _StaticText({
    required this.text,
    required this.isBackground,
    this.isActive = false,
    this.textAlign = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle baseStyle = TextStyle(
      color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.35),
      fontSize: isBackground ? _kFontMain * 0.60 : _kFontMain,
      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
      fontStyle: isBackground ? FontStyle.italic : FontStyle.normal,
      height: 1.2,
      letterSpacing: -0.2,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedOpacity(
          opacity: isActive ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 2.0,
              sigmaY: 2.0,
              tileMode: TileMode.decal,
            ),
            child: Text(
              text,
              textAlign: textAlign,
              style: baseStyle.copyWith(color: Colors.white38),
            ),
          ),
        ),
        AnimatedOpacity(
          opacity: isActive ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 5.0,
              sigmaY: 5.0,
              tileMode: TileMode.decal,
            ),
            child: Text(
              text,
              textAlign: textAlign,
              style: baseStyle.copyWith(color: Colors.white24),
            ),
          ),
        ),
        Text(
          text,
          textAlign: textAlign,
          style: baseStyle.copyWith(
            color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }
}

// GAP INDICATOR — instrumental break 🎶 icon
class _GapIndicator extends StatelessWidget {
  final LyricLine line;
  final bool isActive;
  final ValueNotifier<int> posMs;

  const _GapIndicator({
    required this.line,
    required this.isActive,
    required this.posMs,
  });

  Widget _buildDoubleNote(TextStyle style) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Left smaller note (tilted left, slightly lower)
        Transform.translate(
          offset: const Offset(-10.0, 4.0),
          child: Transform.rotate(
            angle: -0.15,
            child: Text(
              String.fromCharCode(Icons.music_note_rounded.codePoint),
              style: style.copyWith(fontSize: 30.0),
            ),
          ),
        ),
        // Right larger note (tilted right, slightly higher)
        Transform.translate(
          offset: const Offset(10.0, -4.0),
          child: Transform.rotate(
            angle: 0.10,
            child: Text(
              String.fromCharCode(Icons.music_note_rounded.codePoint),
              style: style.copyWith(fontSize: 40.0),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      clipBehavior: Clip.none,
      child: SizedBox(
        height: isActive ? 80.0 : 0.0,
        child: isActive
            ? Center(
                child: ValueListenableBuilder<int>(
                  valueListenable: posMs,
                  builder: (ctx, ms, _) {
                    final startMs = line.startTime.inMilliseconds;
                    final endMs = line.endTime.inMilliseconds;
                    final durMs = endMs - startMs;
                    if (durMs <= 0) return const SizedBox.shrink();

                    final double progress = ((ms - startMs) / durMs).clamp(
                      0.0,
                      1.0,
                    );
                    final double exitScale = progress > 0.90
                        ? (1.0 - (progress - 0.90) / 0.10).clamp(0.0, 1.0)
                        : 1.0;

                    final baseStyle = TextStyle(
                      fontFamily: Icons.music_note_rounded.fontFamily,
                      package: Icons.music_note_rounded.fontPackage,
                      color: Colors.white,
                    );

                    // Bottom layer: inactive/dim double-notes
                    final bottomStyle = baseStyle.copyWith(
                      color: Colors.white.withValues(alpha: 0.22),
                      shadows: const [],
                    );

                    // Top layer: active/glowing double-notes
                    final topStyle = baseStyle.copyWith(
                      color: Colors.white,
                      shadows: const [
                        Shadow(color: Colors.white, blurRadius: 10.0),
                        Shadow(color: Colors.white70, blurRadius: 20.0),
                      ],
                    );

                    return Opacity(
                      opacity: exitScale,
                      child: Transform.scale(
                        scale: exitScale,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            // 1. Bottom inactive/dim layer (always fully visible under)
                            _buildDoubleNote(bottomStyle),

                            // 2. Top active/glowing layer (sweeps left-to-right with a super-soft feathered mask)
                            ShaderMask(
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: const [
                                    Colors.white,
                                    Colors.white,
                                    Colors.transparent,
                                  ],
                                  stops: [
                                    0.0,
                                    progress,
                                    (progress + 0.20).clamp(0.0, 1.0),
                                  ],
                                ).createShader(bounds);
                              },
                              blendMode: BlendMode.dstIn,
                              child: SizedBox(
                                width: 140.0,
                                height: 80.0,
                                child: Center(
                                  child: _buildDoubleNote(topStyle),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

// WORD-BY-WORD LINE
// Design: YouLy+ dual-layer gradient wipe
//   Layer 1 (dim):    always visible, alpha ~0.25
//   Layer 2 (bright): ShaderMask LinearGradient sweeps left→right
//   Completed words:  full bright + glow shadows
// Timing: Pure math from posMs (0 controllers for words, as documented)
//   wordProgress = (posMs - startMs) / durationMs  clamped [0,1]
//   → directly used as gradient stop position
// Rush influence: endMs snapped to NEXT word's startMs (eliminates inter-word gaps)
class _WordByWordLine extends StatefulWidget {
  final LyricLine line;
  final ValueNotifier<int> posMs;
  final bool isBackground;
  final List<String>? romanWords;
  final WrapAlignment alignment;
  final bool isActive;

  const _WordByWordLine({
    required this.line,
    required this.posMs,
    required this.isBackground,
    this.romanWords,
    this.alignment = WrapAlignment.start,
    this.isActive = true,
  });

  @override
  State<_WordByWordLine> createState() => _WordByWordLineState();
}

class _WordByWordLineState extends State<_WordByWordLine> {
  late List<LyricWord> _words;

  @override
  void initState() {
    super.initState();
    _initWords();
  }

  @override
  void didUpdateWidget(_WordByWordLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line != widget.line) {
      _initWords();
    }
  }

  void _initWords() {
    final raw = widget.line.words ?? [];
    _words = [];
    for (int j = 0; j < raw.length; j++) {
      final current = raw[j];
      final snapEnd = (j < raw.length - 1)
          ? raw[j + 1].startTime
          : current.endTime;
      _words.add(
        LyricWord(
          startTime: current.startTime,
          endTime: snapEnd,
          text: current.text,
          romanText: current.romanText,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: widget.alignment,
      spacing: widget.isBackground ? 2.0 : 3.0,
      runSpacing: 4.0,
      children: List.generate(_words.length, (i) {
        final word = _words[i];
        final String? wordRoman =
            (widget.romanWords != null && i < widget.romanWords!.length)
            ? widget.romanWords![i]
            : word.romanText;

        return _SmoothWord(
          text: word.text,
          isBackground: widget.isBackground,
          romanText: wordRoman,
          wordStartMs: word.startTime.inMilliseconds,
          durationMs: math.max(
            word.endTime.inMilliseconds - word.startTime.inMilliseconds,
            1,
          ),
          posMs: widget.posMs,
          allowGrow:
              !widget.isBackground &&
              (widget.line.words != null && widget.line.words!.isNotEmpty),
          isActive: widget.isActive,
        );
      }),
    );
  }
}

// SMOOTH WORD — YouLy+ dual-layer gradient wipe with character grow support
enum _WordAnimState { future, animating, past }

class _SmoothWord extends ConsumerStatefulWidget {
  final String text;
  final bool isBackground;
  final String? romanText;
  final int wordStartMs;
  final int durationMs;
  final ValueNotifier<int> posMs;
  final bool allowGrow;
  final bool isActive;

  const _SmoothWord({
    required this.text,
    required this.isBackground,
    this.romanText,
    required this.wordStartMs,
    required this.durationMs,
    required this.posMs,
    required this.allowGrow,
    this.isActive = true,
  });

  @override
  ConsumerState<_SmoothWord> createState() => _SmoothWordState();
}

class _SmoothWordState extends ConsumerState<_SmoothWord> {
  Widget? _staticFutureWidget;
  Widget? _staticPastWidget;

  double _totalDurationMs = 1.0;
  double _growDurationMs = 1.0;
  double _baseDelayPerChar = 0.0;
  int _numChars = 0;

  _WordAnimState _currentState = _WordAnimState.future;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    widget.posMs.addListener(_onPositionChanged);
    _updateState(widget.posMs.value, init: true);
  }

  @override
  void didUpdateWidget(_SmoothWord oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.posMs != widget.posMs) {
      oldWidget.posMs.removeListener(_onPositionChanged);
      widget.posMs.addListener(_onPositionChanged);
    }
    if (oldWidget.text != widget.text ||
        oldWidget.isBackground != widget.isBackground ||
        oldWidget.romanText != widget.romanText ||
        oldWidget.wordStartMs != widget.wordStartMs ||
        oldWidget.durationMs != widget.durationMs ||
        oldWidget.allowGrow != widget.allowGrow) {
      _staticFutureWidget = null;
      _staticPastWidget = null;
      _initAnimation();
      _updateState(widget.posMs.value, init: true);
    }
  }

  @override
  void dispose() {
    widget.posMs.removeListener(_onPositionChanged);
    super.dispose();
  }

  void _onPositionChanged() {
    if (mounted) {
      _updateState(widget.posMs.value);
    }
  }

  void _updateState(int posMs, {bool init = false}) {
    final double elapsedMs = (posMs - widget.wordStartMs).toDouble();
    _WordAnimState newState;
    if (elapsedMs < 0.0) {
      newState = _WordAnimState.future;
    } else if (elapsedMs >= _totalDurationMs) {
      newState = _WordAnimState.past;
    } else {
      newState = _WordAnimState.animating;
    }

    if (init) {
      _currentState = newState;
    } else {
      if (_currentState != newState || newState == _WordAnimState.animating) {
        setState(() {
          _currentState = newState;
        });
      }
    }
  }

  void _initAnimation() {
    _numChars = widget.text.characters.length;
    if (_isGrowable()) {
      _growDurationMs = widget.durationMs * 1.5;
      _baseDelayPerChar = widget.durationMs * 0.09;
      final double maxGrowDelayMs = _baseDelayPerChar * (_numChars - 1);
      _totalDurationMs = math.max(maxGrowDelayMs + _growDurationMs, 1.0);
    } else {
      _totalDurationMs = widget.durationMs.toDouble();
    }
    _totalDurationMs = math.max(
      _totalDurationMs,
      math.max(widget.durationMs * 2.5, 2000.0),
    );
  }

  bool _isGrowable() {
    if (!widget.allowGrow) return false;
    if (widget.isBackground) return false;
    final trimmed = widget.text.trim();
    if (trimmed.isEmpty) return false;
    if (_isCJK(trimmed) || _isRTL(trimmed) || _isComplexScript(trimmed)) return false;
    if (trimmed.characters.length < 3 || trimmed.characters.length > 7) return false;
    if (widget.durationMs < 1000) return false;
    return true;
  }

  bool _isComplexScript(String text) {
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      // Devanagari & Indic scripts: 0x0900 to 0x0D7F
      if (code >= 0x0900 && code <= 0x0D7F) return true;
      // Arabic & Persian: 0x0600 to 0x08FF
      if (code >= 0x0600 && code <= 0x08FF) return true;
      // Thai: 0x0E00 to 0x0E7F
      if (code >= 0x0E00 && code <= 0x0E7F) return true;
      // Khmer: 0x1780 to 0x17FF
      if (code >= 0x1780 && code <= 0x17FF) return true;
      // Myanmar (Burmese): 0x1000 to 0x109F
      if (code >= 0x1000 && code <= 0x109F) return true;
    }
    return false;
  }

  Widget _buildStaticWord(TextStyle baseStyle, {required double progress}) {
    if (widget.isBackground || !_isGrowable()) {
      return _buildSweptStaticWord(baseStyle, progress);
    }

    final chars = widget.text.characters.toList();
    final int numChars = chars.length;

    Widget mainWordRow;
    if (progress == 0.0) {
      mainWordRow = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: List.generate(
          numChars,
          (i) => Text(
            chars[i],
            style: baseStyle.copyWith(
              color: Colors.white.withValues(alpha: 0.28),
            ),
          ),
        ),
      );
    } else {
      mainWordRow = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: List.generate(numChars, (i) {
          // Settled past state should match progress=1.0 of animating state
          // scale = 1.0, translateY = -1.0 (approx -3.5% of font size), shadows = null
          const double translateY = -1.0;
          return Transform.translate(
            offset: const Offset(0.0, translateY),
            child: Text(
              chars[i],
              style: baseStyle.copyWith(color: Colors.white),
            ),
          );
        }),
      );
    }

    if (widget.romanText == null || widget.romanText!.trim().isEmpty) {
      return mainWordRow;
    }

    final romanStyle = baseStyle.copyWith(
      fontSize: widget.isBackground ? _kFontSub * 0.60 : _kFontSub,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.0,
      height: 1.3,
    );

    if (progress == 0.0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          mainWordRow,
          Text(
            widget.romanText!,
            style: romanStyle.copyWith(
              color: Colors.white.withValues(alpha: 0.28),
            ),
          ),
        ],
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          mainWordRow,
          Text(
            widget.romanText!,
            style: romanStyle.copyWith(color: Colors.white),
          ),
        ],
      );
    }
  }

  Widget _buildSweptStaticWord(TextStyle baseStyle, double progress) {
    return _buildTextBound(baseStyle, progress);
  }

  Widget _buildTextWithGlow(String text, TextStyle textStyle) {
    return Text(text, style: textStyle);
  }

  Widget _buildTextBound(TextStyle baseStyle, double progress) {
    final double fs = widget.isBackground ? _kFontMain * 0.60 : _kFontMain;
    final double alpha = widget.isBackground ? 0.22 : 0.28;

    final style = baseStyle.copyWith(
      fontSize: fs,
      color: Colors.white,
      shadows: const [],
    );

    if (progress <= 0.0) {
      final dimStyle = style.copyWith(color: Colors.white.withValues(alpha: alpha));
      if (widget.romanText == null || widget.romanText!.trim().isEmpty) {
        return Text(widget.text, style: dimStyle);
      } else {
        final dimRomanStyle = dimStyle.copyWith(
          fontSize: widget.isBackground ? _kFontSub * 0.60 : _kFontSub,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.0,
          height: 1.3,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(widget.text, style: dimStyle),
            Text(widget.romanText!, style: dimRomanStyle),
          ],
        );
      }
    } else if (progress >= 1.0) {
      if (widget.romanText == null || widget.romanText!.trim().isEmpty) {
        return Text(widget.text, style: style);
      } else {
        final romanStyle = style.copyWith(
          fontSize: widget.isBackground ? _kFontSub * 0.60 : _kFontSub,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.0,
          height: 1.3,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(widget.text, style: style),
            Text(widget.romanText!, style: romanStyle),
          ],
        );
      }
    } else {
      if (widget.romanText == null || widget.romanText!.trim().isEmpty) {
        return GradientTextWidget(
          text: widget.text,
          style: style,
          progress: progress,
          alpha: alpha,
        );
      } else {
        final romanStyle = style.copyWith(
          fontSize: widget.isBackground ? _kFontSub * 0.60 : _kFontSub,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.0,
          height: 1.3,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GradientTextWidget(
              text: widget.text,
              style: style,
              progress: progress,
              alpha: alpha,
            ),
            GradientTextWidget(
              text: widget.romanText!,
              style: romanStyle,
              progress: progress,
              alpha: alpha,
            ),
          ],
        );
      }
    }
  }

  Widget _buildAnimatingWord(
    TextStyle baseStyle,
    double elapsedMs,
    int numChars,
    Color glowColor,
    double glowDecay,
  ) {
    if (widget.isBackground || !_isGrowable()) {
      final int posMs = widget.posMs.value;
      final double progress = (posMs - widget.wordStartMs) / widget.durationMs;
      final double p = progress.clamp(0.0, 1.0);
      return _buildSweptStaticWord(baseStyle, p);
    }

    // Emphasis metrics
    final double durationMs = widget.durationMs.toDouble();
    final double progressMetric = ((durationMs - 1000.0) / 4000.0).clamp(
      0.0,
      1.0,
    );
    final double easedProgress = math.pow(progressMetric, 3.0).toDouble();
    const double penaltyFactor = 1.0;

    final trimmed = widget.text.trim();
    final int wordLength = trimmed.characters.length;
    double maxDecayRate = 0.0;
    final bool isLongWord = wordLength > 5;
    final bool isShortDuration = durationMs < 1500.0;
    if (isLongWord || isShortDuration) {
      double decayStrength = 0.0;
      if (isLongWord) {
        decayStrength += ((wordLength - 5) / 3.0).clamp(0.0, 1.0) * 0.4;
      }
      if (isShortDuration) {
        decayStrength +=
            (1.0 - (durationMs - 1000.0) / 500.0).clamp(0.0, 1.0) * 0.4;
      }
      maxDecayRate = decayStrength.clamp(0.0, 0.85);
    }

    final chars = widget.text.characters.toList();
    final mainWordRow = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: List.generate(numChars, (i) {
        final char = chars[i];

        // Character wipe progress (exact syllable-like calculation)
        final int posMs = widget.posMs.value;
        final double totalChars = numChars.toDouble();
        final double startPercent = i / totalChars;
        final double durationPercent = 1.0 / totalChars;
        final double charStartMs =
            widget.wordStartMs + widget.durationMs * startPercent;
        final double charSweepDurationMs = widget.durationMs * durationPercent;
        final double charElapsedMs = posMs - charStartMs;

        double pChar = 0.0;
        if (charElapsedMs >= 0) {
          pChar = (charElapsedMs / charSweepDurationMs).clamp(0.0, 1.0);
        }

        // Character grow timing: starts exactly when the character is hit by the highlight wipe
        final double charGrowElapsedMs = posMs - charStartMs;
        double tChar = 0.0;
        if (charGrowElapsedMs >= 0) {
          tChar = (charGrowElapsedMs / _growDurationMs).clamp(0.0, 1.0);
        }

        // Emphasis calculations per character
        final double positionInWord = numChars > 1 ? i / (numChars - 1) : 0.0;
        final double decayFactor = 1.0 - positionInWord * maxDecayRate;
        final double charProgress = easedProgress * penaltyFactor * decayFactor;

        final double baseGrowth = numChars <= 3 ? 0.04 : 0.03;
        final double charMaxScale = 1.0 + baseGrowth + charProgress * 0.06;
        final double charShadowIntensity = 0.4 + charProgress * 0.4;
        final double normalizedGrowth = (charMaxScale - 1.0) / 0.10;
        final double charTranslateYPeak =
            -normalizedGrowth * 4.0; // in pixels (e.g. -4px)

        // horizontal offset based on character relative position (approximate index)
        final double charPct = numChars > 1 ? i / (numChars - 1) : 0.0;
        final double horizontalOffsetPixels =
            (charPct - 0.5) * 2.0 * (charMaxScale - 1.0) * 18.0;

        double scale = 1.0;
        double translateY = 0.0;
        double translateX = 0.0;
        double shadowIntensity = 0.0;

        // Keyframe interpolation based on tChar:
        // 0% -> 25% -> 30% -> 100% with segment-based Curves.easeInOut easing
        if (tChar < 0.25) {
          final double segmentT = tChar / 0.25;
          final double easedSegmentT = Curves.easeInOut.transform(segmentT);
          scale = 1.0 + (charMaxScale - 1.0) * easedSegmentT;
          translateY = charTranslateYPeak * easedSegmentT;
          translateX = horizontalOffsetPixels * easedSegmentT;
          shadowIntensity = charShadowIntensity * easedSegmentT;
        } else if (tChar >= 0.25 && tChar <= 0.30) {
          scale = charMaxScale;
          translateY = charTranslateYPeak;
          translateX = horizontalOffsetPixels;
          shadowIntensity = charShadowIntensity;
        } else {
          final double segmentT = (tChar - 0.30) / 0.70;
          final double easedSegmentT = Curves.easeInOut.transform(segmentT);
          scale = charMaxScale + (1.0 - charMaxScale) * easedSegmentT;
          translateY =
              charTranslateYPeak + (-1.0 - charTranslateYPeak) * easedSegmentT;
          translateX = horizontalOffsetPixels * (1.0 - easedSegmentT);
          shadowIntensity = charShadowIntensity * (1.0 - easedSegmentT);
        }

        final Color charColor = Color.lerp(
          Colors.white.withValues(alpha: 0.28),
          Colors.white,
          pChar,
        )!;

        // Shadow alpha matches YouLy+ shadow-intensity * 0.5 * pChar (since shadow only shows on bright text)
        final double shadowAlpha = shadowIntensity * 0.5 * pChar;

        final List<Shadow> finalShadows = [];
        if (shadowAlpha > 0.01 || glowDecay > 0.01) {
          // Layer 1: Tight white blur for focus core (grow driven)
          final double tightAlpha = math.max(
            shadowAlpha * 0.95,
            (glowDecay * 0.70) * pChar,
          );
          if (tightAlpha > 0.01) {
            finalShadows.add(
              Shadow(
                color: Colors.white.withValues(alpha: tightAlpha),
                blurRadius: 5.0,
              ),
            );
          }

          // Layer 2: Medium white glow bloom (vibrant)
          final double activeGlowAlpha = math.max(
            shadowAlpha * 0.85,
            (glowDecay * 0.95) * pChar,
          );
          if (activeGlowAlpha > 0.01) {
            finalShadows.add(
              Shadow(
                color: Colors.white.withValues(alpha: activeGlowAlpha),
                blurRadius: 12.0,
              ),
            );
          }

          // Layer 3: Wide ambient blur/glow aura (new combined effect!)
          final double wideGlowAlpha = math.max(
            shadowAlpha * 0.50,
            (glowDecay * 0.60) * pChar,
          );
          if (wideGlowAlpha > 0.01) {
            finalShadows.add(
              Shadow(
                color: Colors.white.withValues(alpha: wideGlowAlpha),
                blurRadius: 24.0,
              ),
            );
          }
        }

        final Widget positionedChar = Text(
          char,
          style: baseStyle.copyWith(color: charColor, shadows: finalShadows),
        );

        return Transform.translate(
          offset: Offset(translateX, translateY),
          child: Transform.scale(
            alignment: Alignment.bottomCenter,
            scale: scale,
            child: positionedChar,
          ),
        );
      }),
    );

    if (widget.romanText == null || widget.romanText!.trim().isEmpty) {
      return mainWordRow;
    }

    final romanStyle = baseStyle.copyWith(
      fontSize: widget.isBackground ? _kFontSub * 0.60 : _kFontSub,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.0,
      height: 1.3,
    );

    final int posMs = widget.posMs.value;
    final double progress = (posMs - widget.wordStartMs) / widget.durationMs;
    final double p = progress.clamp(0.0, 1.0);

    Widget romanWidget = Text(widget.romanText!, style: romanStyle);
    if (p > 0.0 && p < 1.0) {
      romanWidget = ClipRect(
        clipper: _HorizontalPercentClipper(p),
        child: romanWidget,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mainWordRow,
        Stack(
          children: [
            Text(
              widget.romanText!,
              style: romanStyle.copyWith(
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ),
            if (p > 0.0) romanWidget,
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final double fs = widget.isBackground ? _kFontMain * 0.60 : _kFontMain;

    final baseStyle = TextStyle(
      color: Colors.white,
      fontSize: fs,
      fontWeight: widget.isActive ? FontWeight.w800 : FontWeight.w600,
      fontStyle: widget.isBackground ? FontStyle.italic : FontStyle.normal,
      height: 1.2,
      letterSpacing: -0.2,
    );

    final int posMs = widget.posMs.value;
    final double elapsedMs = (posMs - widget.wordStartMs).toDouble();

    double scaleX = 1.0;
    double translateX = 0.0;
    double glowDecay = 0.0;

    if (_currentState == _WordAnimState.animating) {
      final double wobbleDurationMs = math.min(1000.0, widget.durationMs * 1.5);
      final double tWobble = (elapsedMs / wobbleDurationMs).clamp(0.0, 1.0);
      if (tWobble < 0.125) {
        final double segmentT = tWobble / 0.125;
        final double eased = Curves.easeInOut.transform(segmentT);
        scaleX = 1.0 + 0.008 * eased;
        translateX = (0.015 * fs) * eased;
      } else if (tWobble >= 0.125 && tWobble < 0.75) {
        final double segmentT = (tWobble - 0.125) / 0.625;
        final double eased = Curves.easeInOut.transform(segmentT);
        scaleX = 1.008 - 0.008 * eased;
        translateX = (0.015 * fs) * (1.0 - eased);
      }

      final double glowDurationMs = math.max(widget.durationMs * 2.0, 1500.0);
      final double tGlow = (elapsedMs / glowDurationMs).clamp(0.0, 1.0);
      glowDecay = Curves.easeOut.transform(1.0 - tGlow);
    }

    final glowColor = Colors.white;

    Widget childWidget;
    if (!_isGrowable()) {
      final double progress =
          (widget.posMs.value - widget.wordStartMs) / widget.durationMs;
      final double p = progress.clamp(0.0, 1.0);
      // Note: no glow shadows here — the soft-edge ShaderMask wipe clips to the
      // glyph box, so any shadow overflow would show as a hard rectangle around
      // the active word. Glow stays on the emphasized (growable) char path.
      childWidget = _buildSweptStaticWord(baseStyle, p);
    } else if (_currentState == _WordAnimState.future) {
      _staticFutureWidget ??= _buildStaticWord(baseStyle, progress: 0.0);
      childWidget = _staticFutureWidget!;
    } else if (_currentState == _WordAnimState.past) {
      _staticPastWidget ??= _buildStaticWord(baseStyle, progress: 1.0);
      childWidget = _staticPastWidget!;
    } else {
      childWidget = _buildAnimatingWord(
        baseStyle,
        elapsedMs,
        _numChars,
        glowColor,
        glowDecay,
      );
    }

    // Apply horizontal Wobble transform to the animating word (subtle stretch + translation)
    if (_currentState == _WordAnimState.animating &&
        (translateX.abs() > 0.01 || (scaleX - 1.0).abs() > 0.001)) {
      childWidget = Transform(
        transform: Matrix4.translationValues(translateX, 0.0, 0.0)
          ..scaleByDouble(scaleX, 1.0, 1.0, 1.0),
        alignment: Alignment.centerLeft,
        child: childWidget,
      );
    }

    return childWidget;
  }
}

// TRANSLATION BOTTOM SHEET
class _TranslationSheet extends ConsumerWidget {
  final String currentLang;
  final bool hasTranslation;
  final bool hasRomanization;
  final bool isRomanizationSupported;
  final VoidCallback onToggleTranslation;
  final VoidCallback onToggleRomanization;
  final ValueChanged<String> onLanguageSelect;

  const _TranslationSheet({
    required this.currentLang,
    required this.hasTranslation,
    required this.hasRomanization,
    required this.isRomanizationSupported,
    required this.onToggleTranslation,
    required this.onToggleRomanization,
    required this.onLanguageSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(currentExtractedColorsProvider);
    final accentColor = colors.vibrant;
    final swapRomanization = ref.watch(swapRomanizationProvider);
    final onlyShowRomanization = ref.watch(onlyShowRomanizationProvider);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xE6141414), // Frosted translucent background
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Lyrics Options',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white60,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  children: [
                    _ToggleTile(
                      icon: Icons.translate_rounded,
                      label: 'Show Translation',
                      active: hasTranslation,
                      accentColor: accentColor,
                      onTap: onToggleTranslation,
                    ),
                    Divider(
                      color: Colors.white.withValues(alpha: 0.05),
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                    _ToggleTile(
                      icon: Icons.spellcheck_rounded,
                      label: 'Show Romanization',
                      active: isRomanizationSupported ? hasRomanization : false,
                      subtitle: isRomanizationSupported
                          ? null
                          : 'Not needed for this song',
                      accentColor: accentColor,
                      onTap: isRomanizationSupported
                          ? onToggleRomanization
                          : () {},
                    ),
                    if (isRomanizationSupported) ...[
                      Divider(
                        color: Colors.white.withValues(alpha: 0.05),
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                      ),
                      _ToggleTile(
                        icon: Icons.swap_vert_rounded,
                        label: 'Romanization as Main Line',
                        active: swapRomanization,
                        accentColor: accentColor,
                        onTap: () {
                          ref
                              .read(swapRomanizationProvider.notifier)
                              .update(!swapRomanization);
                        },
                      ),
                      Divider(
                        color: Colors.white.withValues(alpha: 0.05),
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                      ),
                      _ToggleTile(
                        icon: Icons.visibility_rounded,
                        label: 'Only Show Romanization',
                        active: onlyShowRomanization,
                        accentColor: accentColor,
                        onTap: () {
                          ref
                              .read(onlyShowRomanizationProvider.notifier)
                              .update(!onlyShowRomanization);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'TRANSLATION LANGUAGE',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: supportedLanguages.entries.map((e) {
                  final sel = e.key == currentLang;
                  return GestureDetector(
                    onTap: () => onLanguageSelect(e.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: sel
                            ? accentColor.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: sel
                              ? accentColor.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                  color: accentColor.withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (sel) ...[
                            Icon(
                              Icons.check_rounded,
                              color: accentColor,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            e.value,
                            style: TextStyle(
                              color: sel ? Colors.white : Colors.white60,
                              fontWeight: sel
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
         ),
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool active;
  final Color accentColor;
  final VoidCallback onTap;

  const _ToggleTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.active,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle != null;
    return InkWell(
      onTap: () {
        if (subtitle != null && !active) return;
        onTap();
      },
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: active
                    ? accentColor.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.03),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: active ? accentColor : Colors.white38,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.white60,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch(
              value: active,
              onChanged: (val) {
                if (subtitle != null && !active) return;
                onTap();
              },
              activeThumbColor: accentColor,
              activeTrackColor: accentColor.withValues(alpha: 0.2),
              inactiveTrackColor: Colors.white12,
              inactiveThumbColor: Colors.white38,
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
bool _isCJK(String text) {
  for (int i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if ((code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3040 && code <= 0x309F) ||
        (code >= 0x30A0 && code <= 0x30FF) ||
        (code >= 0xAC00 && code <= 0xD7A3)) {
      return true;
    }
  }
  return false;
}

// ignore: unused_element
bool _isRTL(String text) {
  for (int i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if ((code >= 0x0590 && code <= 0x05FF) ||
        (code >= 0x0600 && code <= 0x06FF) ||
        (code >= 0x0750 && code <= 0x077F) ||
        (code >= 0xFB50 && code <= 0xFDFF) ||
        (code >= 0xFE70 && code <= 0xFEFF)) {
      return true;
    }
  }
  return false;
}

class _HorizontalPercentClipper extends CustomClipper<Rect> {
  final double percent;
  _HorizontalPercentClipper(this.percent);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      -100.0,
      -100.0,
      size.width * percent,
      size.height + 100.0,
    );
  }

  @override
  bool shouldReclip(_HorizontalPercentClipper oldClipper) =>
      oldClipper.percent != percent;
}

class DampedSpringCurve extends Curve {
  final double damping;
  final double stiffness;
  final double mass;

  const DampedSpringCurve({
    this.mass = 1.0,
    this.stiffness = 100.0,
    this.damping = 15.0,
  });

  @override
  double transformInternal(double t) {
    if (t == 0.0) return 0.0;
    if (t == 1.0) return 1.0;

    final double time = t * 0.8;

    final double w0 = math.sqrt(stiffness / mass);
    final double beta = damping / (2.0 * mass);

    if (beta < w0) {
      final double omega = math.sqrt(w0 * w0 - beta * beta);
      final double envelope = math.exp(-beta * time);
      final double oscillation =
          math.cos(omega * time) + (beta / omega) * math.sin(omega * time);
      return 1.0 - envelope * oscillation;
    } else {
      return 1.0 - math.exp(-10.0 * time);
    }
  }
}

class GradientTextWidget extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double progress;
  final double alpha;

  const GradientTextWidget({
    super.key,
    required this.text,
    required this.style,
    required this.progress,
    required this.alpha,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final resolvedStyle = defaultStyle.merge(style);

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: resolvedStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    return CustomPaint(
      size: Size(textPainter.width, textPainter.height),
      painter: GradientTextPainter(
        text: text,
        style: resolvedStyle,
        progress: progress,
        alpha: alpha,
      ),
    );
  }
}

class GradientTextPainter extends CustomPainter {
  final String text;
  final TextStyle style;
  final double progress;
  final double alpha;

  GradientTextPainter({
    required this.text,
    required this.style,
    required this.progress,
    required this.alpha,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(color: Colors.white)),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(minWidth: 0, maxWidth: size.width);

    final rect = Rect.fromLTWH(0, 0, textPainter.width, textPainter.height);

    const double feather = 0.12;
    final double s0 = (progress - feather * 0.5).clamp(0.0, 1.0);
    double s1 = (progress + feather * 0.5).clamp(0.0, 1.0);
    if (s1 <= s0) s1 = (s0 + 0.001).clamp(0.0, 1.0);

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white,
          Colors.white,
          Colors.white.withValues(alpha: alpha),
        ],
        stops: [0.0, s0, s1],
      ).createShader(rect);

    textPainter.text = TextSpan(
      text: text,
      style: style.copyWith(foreground: paint),
    );
    textPainter.layout(minWidth: 0, maxWidth: size.width);
    textPainter.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(covariant GradientTextPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.progress != progress ||
        oldDelegate.style != style ||
        oldDelegate.alpha != alpha;
  }
}

