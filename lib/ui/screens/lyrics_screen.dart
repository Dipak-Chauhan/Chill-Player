import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
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
import '../../state/translation_state.dart';
import '../../services/translation_service.dart';
import '../../theme/color_provider.dart';
import 'lyrics_editor_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../widgets/drag_to_dismiss_wrapper.dart';

// ─── Design constants — sourced from YouLy+ CSS analysis ────────────────────
const double _kFontMain = 28.0;
const double _kFontSub = 18.0;
const double _kBlurFar = 3.0; // distant lines
const double _kBlurNear = 1.5; // adjacent lines
const double _kScaleOff = 0.93; // inactive line scale

// ═══════════════════════════════════════════════════════════════════════════════
// LYRICS SCREEN — full opaque modal (opened from NowPlayingScreen)
// Background: album art blurred + dark overlay (like Apple Music / YouLy+)
// Timing: Rush model — anchor on positionStream, interpolate with speed×elapsed at 60fps
// Wipe: YouLy+ dual-layer soft gradient, pure math from position (no ctrl per word)
// ═══════════════════════════════════════════════════════════════════════════════

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
  // ── Scroll ─────────────────────────────────────────────────────────────────
  late final ScrollController _scroll;
  bool _userScrolling = false;
  Timer? _scrollLockTimer;
  List<GlobalKey> _lineKeys = [];
  bool _initialScrollDone = false;
  bool _isSeeking = false;
  final GlobalKey _columnKey = GlobalKey();

  // ── Position ───────────────────────────────────────────────────────────────
  late Ticker _ticker;
  final ValueNotifier<int> _posMs = ValueNotifier(0);

  // Interpolation anchors for 60fps sub-frame timing
  Duration _lastPosition = Duration.zero;
  int _lastPositionTime = 0;
  bool _lastPlaying = false;

  // ── Active line ────────────────────────────────────────────────────────────
  final ValueNotifier<int> _activeIdxNotifier = ValueNotifier(-1);

  // ── Song change tracking ───────────────────────────────────────────────────
  List<LyricLine>? _currentLyrics;

  // ── Testing Features ───────────────────────────────────────────────────────
  bool _isAmoledMode = false;
  int _artDisplayMode = 0; // 0=Norm, 1=Dim, 2=B&W

  late final _player = ref.read(audioPlayerProvider);

  // ── Local caching of player state ──────────────────────────────────────────
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
    _activeIdxNotifier.addListener(_animateToActiveLine);

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
        // Throttle to 60fps (~16ms per frame) to prevent extra load on 120Hz screens
        if (now - _lastTickTime < 16) {
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
            // Limit interpolation to 500ms to avoid runaway drift during buffering/lag
            if (elapsed >= 0 && elapsed < 500) {
              final speed = _cachedSpeed;
              posMs = (rawPos.inMilliseconds + elapsed * speed).round();
            }
          }

          _posMs.value = posMs;

          final lines = _currentLyrics;
          if (lines != null && lines.isNotEmpty) {
            final newActive = _calculateActiveIndex(posMs, lines);
            if (newActive != _activeIdxNotifier.value) {
              _activeIdxNotifier.value = newActive;
            }
          }
        }
      } catch (e, stack) {
        debugPrint('Lyrics Ticker error: $e\n$stack');
      }
    })..start();
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

  void _animateToActiveLine() {
    if (!mounted || _userScrolling || !_scroll.hasClients) return;
    final activeIdx = _activeIdxNotifier.value;
    if (activeIdx < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userScrolling || !_scroll.hasClients) return;
      final double? targetOffset = _getScrollOffsetFor(activeIdx);
      if (targetOffset != null) {
        if (!_initialScrollDone) {
          _scroll.jumpTo(targetOffset);
          _initialScrollDone = true;
        } else {
          _scroll.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });
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
      if (scrollableBox == null || !scrollableBox.hasSize || !scrollableBox.attached) return null;

      final double lineHeight = box.size.height;
      final double viewportHeight = scrollableBox.size.height;

      // Calculate local offset of the child relative to the scrollable viewport RenderBox
      final localOffset = box.localToGlobal(Offset.zero, ancestor: scrollableBox);

      // Target scroll offset to center the line
      final double targetOffset = _scroll.offset + localOffset.dy + (lineHeight / 2) - (viewportHeight / 2);

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

  // ── Overlay Controls ───────────────────────────────────────────────────────
  bool _showControls = false;
  Timer? _controlsTimer;

  void _onAlbumTapped() {
    if (_showControls) {
      setState(() {
        _showControls = false;
      });
      _controlsTimer?.cancel();
    } else {
      setState(() {
        _showControls = true;
      });
      _controlsTimer?.cancel();
      _controlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _scrollLockTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    ); // Restore status bar
    WakelockPlus.disable(); // Allow screen to sleep again when user leaves
    _activeIdxNotifier.removeListener(_animateToActiveLine);
    _posSubscription?.cancel();
    _playSubscription?.cancel();
    _speedSubscription?.cancel();
    _ticker.dispose();
    _posMs.dispose();
    _activeIdxNotifier.dispose();
    _scroll.dispose();
    super.dispose();
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
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentSongProvider);

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
                    mode == TranslationDisplayMode.both) &&
                ref.read(romanizationDataProvider) == null) {
              ctrl.fetchRomanization();
            }
          }
        }
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

    Widget foregroundContent;
    if (isLandscape) {
      foregroundContent = Row(
        children: [
          Expanded(
            flex: 4,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: GestureDetector(
                  onTap: _onAlbumTapped,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Stack(
                        fit: StackFit.expand,
                        alignment: Alignment.center,
                        children: [
                          // 1. Album Art
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

                          // 2. Controls Overlay
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: !_showControls,
                              child: AnimatedOpacity(
                                opacity: _showControls ? 1.0 : 0.0,
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
                                          _onAlbumTapped(); // reset fade timer
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
                                              _onAlbumTapped(); // reset fade timer
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
                                          _onAlbumTapped(); // reset fade timer
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
            flex: 6,
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
              data: (lines) => _buildList(lines, mode, transData, romanData),
            ),
          ),
        ],
      );
    } else {
      foregroundContent = lyricsAsync.when(
        loading: () => const Center(
          child: M3LoadingIndicator(size: 40, color: Colors.white38),
        ),
        error: (e, _) => Center(
          child: Text('$e', style: const TextStyle(color: Colors.white54)),
        ),
        data: (lines) => _buildList(lines, mode, transData, romanData),
      );
    }

    final safePadding = MediaQueryData.fromView(View.of(context)).padding;

    Widget contentStack = Stack(
      fit: StackFit.expand,
      children: [
        // ── Background: album art blurred + dark overlay (Apple Music style) ──
        if (!_isAmoledMode) _BlurredBackground(songId: activeSong.id),

        // ── The Foreground Content ──
        foregroundContent,

        // ── Top fade gradient ───────────────
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

        // ── Bottom fade gradient ────────────────────────────────────────────
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

        // ── Mini Translucent Controls & Song Info (Portrait) ────────────────
        if (!isLandscape)
          Positioned(
            bottom: safePadding.bottom + 24,
            left: 24,
            right: 24,
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
                    // Previous
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
                    // Play/Pause
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
                    // Next
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

        // ── Header (Always Visible) ──────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, safePadding.top + 8, 4, 0),
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
                  onPressed: () {
                    final song = ref.read(currentSongProvider);
                    if (song != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LyricsEditorScreen(song: song),
                        ),
                      );
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
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
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
      ],
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
            color: Colors.black, // pure black behind the notch spacing
            child: Padding(
              padding: EdgeInsets.only(
                left: safePadding.left,
                right: safePadding.right,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.horizontal(
                  left: safePadding.left > 0
                      ? const Radius.circular(44)
                      : Radius.zero,
                  right: safePadding.right > 0
                      ? const Radius.circular(44)
                      : Radius.zero,
                ),
                child: SizedBox.expand(child: contentStack),
              ),
            ),
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

        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(dismissProgress > 0 ? 32 : 0),
              child: result,
            ),
          ),
        );
      },
    );
  }

  static String _cleanForCompare(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r"[.,\/#!$%\^&\*;:{}=\-_`~()?'" '"]'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  Widget _buildList(
    List<LyricLine> lyrics,
    TranslationDisplayMode mode,
    TranslationResult? trans,
    TranslationResult? roman,
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
            vh * 0.50, // 50% clearance so the first line starts exactly at vertical center
            20,
            vh * 0.50, // 50% clearance so the last line can end exactly at vertical center
          ),
          child: Column(
            key: _columnKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(lyrics.length, (i) {
              final line = lyrics[i];
              final String? transTextRaw =
                  (mode == TranslationDisplayMode.translate ||
                          mode == TranslationDisplayMode.both) &&
                      trans != null &&
                      i < trans.translations.length &&
                      trans.translations[i].isNotEmpty
                  ? trans.translations[i]
                  : null;
              final String? transText = transTextRaw != null &&
                      _cleanForCompare(transTextRaw) != _cleanForCompare(line.text)
                  ? transTextRaw
                  : null;
              final String? romanText =
                  (mode == TranslationDisplayMode.romanize ||
                          mode == TranslationDisplayMode.both) &&
                      roman != null &&
                      i < roman.romanizations.length
                  ? roman.romanizations[i]
                  : null;
              final List<String>? romanWordsList =
                  (mode == TranslationDisplayMode.romanize ||
                          mode == TranslationDisplayMode.both) &&
                      roman != null &&
                      i < roman.romanizedWords.length
                  ? roman.romanizedWords[i]
                  : null;
  
              return RepaintBoundary(
                child: _LyricLineWrapper(
                  key: _lineKeys[i],
                  index: i,
                  activeIdxNotifier: _activeIdxNotifier,
                  line: line,
                  posMs: _posMs,
                  transText: transText,
                  romanText: romanText,
                  romanWords: romanWordsList,
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLURRED BACKGROUND — album art + dark overlay
// ═══════════════════════════════════════════════════════════════════════════════
class _BlurredBackground extends StatelessWidget {
  final int songId;
  const _BlurredBackground({required this.songId});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Album art (blurred)
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 40,
              sigmaY: 40,
              tileMode: TileMode.clamp,
            ),
            child: Transform.scale(
              scale: 1.15,
              child: QueryArtworkWidget(
                id: songId,
                type: ArtworkType.AUDIO,
                quality: 25,
                size: 300,
                artworkFit: BoxFit.cover,
                artworkWidth: double.infinity,
                artworkHeight: double.infinity,
                nullArtworkWidget: Container(color: const Color(0xFF1A1A1A)),
                keepOldArtwork: true,
              ),
            ),
          ),
          // Dark overlay — deepens the bg so text stays legible
          Container(color: Colors.black.withValues(alpha: 0.60)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LYRIC LINE WIDGET — handles scale animation, blur, opacity
// ═══════════════════════════════════════════════════════════════════════════════
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
      duration: const Duration(milliseconds: 600), // Extended for spring settle
    );
    if (widget.isActive) _scaleCtrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_LyricLineWidget old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) _scaleCtrl.forward();
    if (!widget.isActive && old.isActive) _scaleCtrl.reverse();
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.line.isGap) {
      return _GapIndicator(
        line: widget.line,
        isActive: widget.isActive,
        posMs: widget.posMs,
      );
    }

    final side = widget.line.singerSide;
    final vWidth = MediaQuery.sizeOf(context).width;

    final crossAlign = side == 'right'
        ? CrossAxisAlignment.end
        : (side == 'center' ? CrossAxisAlignment.center : CrossAxisAlignment.start);

    final scaleAlignment = side == 'right'
        ? Alignment.centerRight
        : (side == 'center' ? Alignment.center : Alignment.centerLeft);

    final padding = side == 'right'
        ? EdgeInsets.only(left: vWidth * 0.18, right: 8)
        : (side == 'left' ? EdgeInsets.only(right: vWidth * 0.18, left: 8) : EdgeInsets.symmetric(horizontal: 8));

    Widget core = GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: padding.add(const EdgeInsets.symmetric(vertical: 7)),
        child: AnimatedBuilder(
          animation: _scaleCtrl,
          builder: (ctx, child) {
            final t = Curves.easeOutCubic.transform(_scaleCtrl.value);
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

    if (widget.blur > 0.05) {
      core = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: widget.blur,
          sigmaY: widget.blur,
          tileMode: TileMode.decal,
        ),
        child: core,
      );
    }

    return AnimatedOpacity(
      opacity: widget.opacity,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: core,
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
        if (widget.isActive && (widget.line.words?.isNotEmpty ?? false))
          _WordByWordLine(
            line: widget.line,
            posMs: widget.posMs,
            isBackground: false,
            romanWords: widget.romanWords,
            alignment: wrapAlign,
          )
        else
          _StaticText(
            text: widget.line.text,
            isBackground: false,
            isActive: widget.isActive,
            textAlign: textAlign,
          ),

        // Background vocals collapse
        if (widget.line.backgroundLines != null)
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            child: widget.isActive
                ? AnimatedOpacity(
                    opacity: widget.isActive ? 0.70 : 0.0,
                    duration: const Duration(milliseconds: 300),
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
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),

        // Romanization
        if (widget.romanText != null &&
            !(widget.isActive &&
                (widget.line.words?.isNotEmpty ?? false) &&
                widget.romanWords != null))
          Padding(
            padding: const EdgeInsets.only(top: 5),
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

        // Translation
        if (widget.transText != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
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

// ═══════════════════════════════════════════════════════════════════════════════
// STATIC TEXT — used for inactive lines, or line-synced LRC active lines
// ═══════════════════════════════════════════════════════════════════════════════
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
      fontWeight: FontWeight.w700,
      fontStyle: isBackground ? FontStyle.italic : FontStyle.normal,
      height: 1.25,
      letterSpacing: -0.3,
    );

    if (!isActive) {
      return Text(
        text,
        textAlign: textAlign,
        style: baseStyle,
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: 2.0,
            sigmaY: 2.0,
            tileMode: TileMode.decal,
          ),
          child: Text(
            text,
            textAlign: textAlign,
            style: baseStyle.copyWith(
              color: Colors.white38,
            ),
          ),
        ),
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: 5.0,
            sigmaY: 5.0,
            tileMode: TileMode.decal,
          ),
          child: Text(
            text,
            textAlign: textAlign,
            style: baseStyle.copyWith(
              color: Colors.white24,
            ),
          ),
        ),
        Text(
          text,
          textAlign: textAlign,
          style: baseStyle,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GAP INDICATOR — instrumental break 🎶 icon
// ═══════════════════════════════════════════════════════════════════════════════
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
              style: style.copyWith(
                fontSize: 30.0,
              ),
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
              style: style.copyWith(
                fontSize: 40.0,
              ),
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

                    final double progress = ((ms - startMs) / durMs).clamp(0.0, 1.0);
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
                        Shadow(
                          color: Colors.white,
                          blurRadius: 10.0,
                        ),
                        Shadow(
                          color: Colors.white70,
                          blurRadius: 20.0,
                        ),
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

// ═══════════════════════════════════════════════════════════════════════════════
// WORD-BY-WORD LINE
//
// Design: YouLy+ dual-layer gradient wipe
//   Layer 1 (dim):    always visible, alpha ~0.25
//   Layer 2 (bright): ShaderMask LinearGradient sweeps left→right
//   Completed words:  full bright + glow shadows
//
// Timing: Pure math from posMs (0 controllers for words, as documented)
//   wordProgress = (posMs - startMs) / durationMs  clamped [0,1]
//   → directly used as gradient stop position
//
// Rush influence: endMs snapped to NEXT word's startMs (eliminates inter-word gaps)
// ═══════════════════════════════════════════════════════════════════════════════
class _WordByWordLine extends StatefulWidget {
  final LyricLine line;
  final ValueNotifier<int> posMs;
  final bool isBackground;
  final List<String>? romanWords;
  final WrapAlignment alignment;

  const _WordByWordLine({
    required this.line,
    required this.posMs,
    required this.isBackground,
    this.romanWords,
    this.alignment = WrapAlignment.start,
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
      _words.add(LyricWord(
        startTime: current.startTime,
        endTime: snapEnd,
        text: current.text,
      ));
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
            widget.romanWords != null && i < widget.romanWords!.length
            ? widget.romanWords![i]
            : null;

        return _SmoothWord(
          text: word.text,
          isBackground: widget.isBackground,
          romanText: wordRoman,
          wordStartMs: word.startTime.inMilliseconds,
          durationMs: math.max(word.endTime.inMilliseconds - word.startTime.inMilliseconds, 1),
          posMs: widget.posMs,
          allowGrow: !widget.isBackground && (widget.line.words != null && widget.line.words!.isNotEmpty),
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMOOTH WORD — YouLy+ dual-layer gradient wipe with character grow support
// ═══════════════════════════════════════════════════════════════════════════════
enum _WordAnimState {
  future,
  animating,
  past,
}

class _SmoothWord extends ConsumerStatefulWidget {
  final String text;
  final bool isBackground;
  final String? romanText;
  final int wordStartMs;
  final int durationMs;
  final ValueNotifier<int> posMs;
  final bool allowGrow;

  const _SmoothWord({
    required this.text,
    required this.isBackground,
    this.romanText,
    required this.wordStartMs,
    required this.durationMs,
    required this.posMs,
    required this.allowGrow,
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
    _totalDurationMs = math.max(_totalDurationMs, math.max(widget.durationMs * 2.5, 2000.0));
  }

  bool _isGrowable() {
    if (!widget.allowGrow) return false;
    if (widget.isBackground) return false;
    final trimmed = widget.text.trim();
    if (trimmed.isEmpty) return false;
    if (_isCJK(trimmed) || _isRTL(trimmed)) return false;
    if (trimmed.characters.length > 7) return false;
    if (widget.durationMs < 1000) return false;
    return true;
  }

  Widget _buildStaticWord(TextStyle baseStyle, {required double progress}) {
    if (widget.isBackground) {
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
              style: baseStyle.copyWith(
                color: Colors.white,
              ),
            ),
          );
        }),
      );
    }

    if (widget.romanText == null || widget.romanText!.trim().isEmpty) {
      return mainWordRow;
    }

    final romanStyle = baseStyle.copyWith(
      fontSize: baseStyle.fontSize! * 0.60,
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
            style: romanStyle.copyWith(
              color: Colors.white,
            ),
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

    // Style for the bottom (inactive/dim) layer: no shadows, white with alpha
    final bottomStyle = baseStyle.copyWith(
      fontSize: fs,
      color: Colors.white.withValues(alpha: alpha),
      shadows: const [],
    );

    // Style for the top (active/glowing) layer: has shadows, full white text
    final topStyle = baseStyle.copyWith(
      fontSize: fs,
      color: Colors.white,
    );

    final Widget bottomWordText = Text(widget.text, style: bottomStyle);
    Widget bottomBlock;
    if (widget.romanText == null || widget.romanText!.trim().isEmpty) {
      bottomBlock = bottomWordText;
    } else {
      final bottomRomanStyle = bottomStyle.copyWith(
        fontSize: bottomStyle.fontSize! * 0.60,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        height: 1.3,
      );
      bottomBlock = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          bottomWordText,
          Text(widget.romanText!, style: bottomRomanStyle),
        ],
      );
    }

    final Widget topWordText = _buildTextWithGlow(widget.text, topStyle);
    Widget topBlock;
    if (widget.romanText == null || widget.romanText!.trim().isEmpty) {
      topBlock = topWordText;
    } else {
      final topRomanStyle = topStyle.copyWith(
        fontSize: topStyle.fontSize! * 0.60,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        height: 1.3,
      );
      final Widget topRomanText = _buildTextWithGlow(widget.romanText!, topRomanStyle);
      topBlock = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          topWordText,
          topRomanText,
        ],
      );
    }

    if (progress <= 0.0) {
      return bottomBlock;
    } else if (progress >= 1.0) {
      return topBlock;
    } else {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          bottomBlock,
          ClipRect(
            clipper: _HorizontalPercentClipper(progress),
            child: topBlock,
          ),
        ],
      );
    }
  }

  Widget _buildAnimatingWord(
    TextStyle baseStyle,
    double elapsedMs,
    int numChars,
    Color glowColor,
    double glowDecay,
  ) {
    if (widget.isBackground) {
      final int posMs = widget.posMs.value;
      final double progress = (posMs - widget.wordStartMs) / widget.durationMs;
      final double p = progress.clamp(0.0, 1.0);
      return _buildSweptStaticWord(baseStyle, p);
    }

    // Emphasis metrics
    final double durationMs = widget.durationMs.toDouble();
    final double progressMetric = ((durationMs - 1000.0) / 4000.0).clamp(0.0, 1.0);
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
        decayStrength += (1.0 - (durationMs - 1000.0) / 500.0).clamp(0.0, 1.0) * 0.4;
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
        final double charStartMs = widget.wordStartMs + widget.durationMs * startPercent;
        final double charSweepDurationMs = widget.durationMs * durationPercent;
        final double charElapsedMs = posMs - charStartMs;

        double pChar = 0.0;
        if (charElapsedMs >= 0) {
          pChar = (charElapsedMs / charSweepDurationMs).clamp(0.0, 1.0);
        }

        // Character grow timing
        final double charDelayMs = _baseDelayPerChar * i;
        final double charGrowElapsedMs = elapsedMs - charDelayMs;

        double tChar = 0.0;
        if (charGrowElapsedMs >= 0) {
          tChar = (charGrowElapsedMs / _growDurationMs).clamp(0.0, 1.0);
        }

        // Emphasis calculations per character
        final double positionInWord = numChars > 1 ? i / (numChars - 1) : 0.0;
        final double decayFactor = 1.0 - positionInWord * maxDecayRate;
        final double charProgress = easedProgress * penaltyFactor * decayFactor;

        final double baseGrowth = numChars <= 3 ? 0.07 : 0.05;
        final double charMaxScale = 1.0 + baseGrowth + charProgress * 0.1;
        final double charShadowIntensity = 0.4 + charProgress * 0.4;
        final double normalizedGrowth = (charMaxScale - 1.0) / 0.13;
        final double charTranslateYPeak = -normalizedGrowth * 6.0; // in pixels (e.g. -6px)

        // horizontal offset based on character relative position (approximate index)
        final double charPct = numChars > 1 ? i / (numChars - 1) : 0.0;
        final double horizontalOffsetPixels = (charPct - 0.5) * 2.0 * (charMaxScale - 1.0) * 28.0;

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
          translateY = charTranslateYPeak + (-1.0 - charTranslateYPeak) * easedSegmentT;
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
          final double tightAlpha = math.max(shadowAlpha * 0.95, (glowDecay * 0.70) * pChar);
          if (tightAlpha > 0.01) {
            finalShadows.add(Shadow(
              color: Colors.white.withValues(alpha: tightAlpha),
              blurRadius: 5.0,
            ));
          }

          // Layer 2: Medium white glow bloom (vibrant)
          final double activeGlowAlpha = math.max(shadowAlpha * 0.85, (glowDecay * 0.95) * pChar);
          if (activeGlowAlpha > 0.01) {
            finalShadows.add(Shadow(
              color: Colors.white.withValues(alpha: activeGlowAlpha),
              blurRadius: 12.0,
            ));
          }

          // Layer 3: Wide ambient blur/glow aura (new combined effect!)
          final double wideGlowAlpha = math.max(shadowAlpha * 0.50, (glowDecay * 0.60) * pChar);
          if (wideGlowAlpha > 0.01) {
            finalShadows.add(Shadow(
              color: Colors.white.withValues(alpha: wideGlowAlpha),
              blurRadius: 24.0,
            ));
          }
        }

        final Widget positionedChar = Text(
          char,
          style: baseStyle.copyWith(
            color: charColor,
            shadows: finalShadows,
          ),
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
      fontSize: baseStyle.fontSize! * 0.60,
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
      fontWeight: FontWeight.w700,
      fontStyle: widget.isBackground ? FontStyle.italic : FontStyle.normal,
      height: 1.25,
      letterSpacing: -0.3,
    );

    final int posMs = widget.posMs.value;
    final double elapsedMs = (posMs - widget.wordStartMs).toDouble();

    double scaleX = 1.0;
    double translateX = 0.0;
    double glowDecay = 0.0;

    if (_currentState == _WordAnimState.animating) {
      // 1. Subtle Wobble animation (1.0s duration) - reduced bounds for a soft organic pop
      const double wobbleDurationMs = 1000.0;
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

      // 2. Decaying vibrant glow animation (2.0x word duration, min 1.5s)
      final double glowDurationMs = math.max(widget.durationMs * 2.0, 1500.0);
      final double tGlow = (elapsedMs / glowDurationMs).clamp(0.0, 1.0);
      glowDecay = Curves.easeOut.transform(1.0 - tGlow);
    }

    final glowColor = Colors.white;

    Widget childWidget;
    if (!_isGrowable()) {
      final double progress = (widget.posMs.value - widget.wordStartMs) / widget.durationMs;
      final double p = progress.clamp(0.0, 1.0);
      final List<Shadow>? staticGlow = glowDecay > 0.01 
          ? [
              Shadow(color: Colors.white.withValues(alpha: glowDecay * 0.95), blurRadius: 8.0),
              Shadow(color: Colors.white.withValues(alpha: glowDecay * 0.60), blurRadius: 20.0),
            ]
          : null;
      final styleWithGlow = staticGlow != null 
          ? baseStyle.copyWith(shadows: staticGlow) 
          : baseStyle;
      childWidget = _buildSweptStaticWord(styleWithGlow, p);
    } else if (_currentState == _WordAnimState.future) {
      _staticFutureWidget ??= _buildStaticWord(baseStyle, progress: 0.0);
      childWidget = _staticFutureWidget!;
    } else if (_currentState == _WordAnimState.past) {
      _staticPastWidget ??= _buildStaticWord(baseStyle, progress: 1.0);
      childWidget = _staticPastWidget!;
    } else {
      childWidget = _buildAnimatingWord(baseStyle, elapsedMs, _numChars, glowColor, glowDecay);
    }

    // Apply horizontal Wobble transform to the animating word (subtle stretch + translation)
    if (_currentState == _WordAnimState.animating && (translateX.abs() > 0.01 || (scaleX - 1.0).abs() > 0.001)) {
      childWidget = Transform(
        transform: Matrix4.translationValues(translateX, 0.0, 0.0)..scaleByDouble(scaleX, 1.0, 1.0, 1.0),
        alignment: Alignment.centerLeft,
        child: childWidget,
      );
    }

    return childWidget;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRANSLATION BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
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
                    icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Option tiles grouped in a card style
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
                      subtitle: isRomanizationSupported ? null : 'Not needed for this song',
                      accentColor: accentColor,
                      onTap: isRomanizationSupported ? onToggleRomanization : () {},
                    ),
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
                        boxShadow: sel ? [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ] : null,
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
                              fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
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
    return Rect.fromLTRB(-100.0, -100.0, size.width * percent, size.height + 100.0);
  }

  @override
  bool shouldReclip(_HorizontalPercentClipper oldClipper) =>
      oldClipper.percent != percent;
}
