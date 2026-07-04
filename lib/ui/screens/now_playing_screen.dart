
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/audio_state.dart';
import '../../models/song.dart';
import '../../services/haptic_service.dart';
import '../widgets/squiggly_seekbar.dart';
import '../widgets/spring_button.dart';
import 'lyrics_screen.dart';
import 'queue_screen.dart';
import 'tag_editor_screen.dart';
import '../widgets/expand_player_route.dart';
import '../widgets/mini_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:text_scroll/text_scroll.dart';

import '../widgets/smooth_art_widget.dart';
import '../../services/settings_service.dart';
import '../../services/artwork_cache.dart';
import 'dart:io';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  Orientation? _lastOrientation;
  late PageController _pageController;
  final ValueNotifier<double> _pageNotifier = ValueNotifier<double>(0.0);
  bool _isProgrammaticScroll = false;
  int? _lastSafeIndex;
  bool _isReorderOrShuffle = false;

  // The interactive queue PageView (swipe deviation math, per-item
  // AnimatedBuilder scale/opacity) is expensive to build while the container
  // transform is also animating shape/position. A cheap static placeholder is
  // shown until the open transition settles, then swaps to the real PageView.
  bool _artSettled = false;

  @override
  void initState() {
    super.initState();
    final queue = ref.read(queueProvider);
    final currentSong = ref.read(currentSongProvider);
    final initialIndex = currentSong != null ? queue.indexWhere((s) => s.id == currentSong.id) : 0;
    final safeInitialIndex = initialIndex >= 0 ? initialIndex : 0;
    _lastSafeIndex = safeInitialIndex;
    
    _pageController = PageController(
      initialPage: safeInitialIndex,
      viewportFraction: 1.0,
    );
    
    _pageNotifier.value = safeInitialIndex.toDouble();
    _pageController.addListener(() {
      if (_pageController.hasClients) {
        _pageNotifier.value = _pageController.page ?? 0.0;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheAround(safeInitialIndex);
    });

    // Matches the OpenContainer transition duration (450ms) plus a small
    // buffer, so the swap happens right as the morph settles.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _artSettled = true);
    });
  }

  /// Warms the artwork cache for the songs around [index] so swiping the queue
  /// (and next/previous) shows art instantly instead of querying mid-gesture.
  void _precacheAround(int index) {
    final queue = ref.read(queueProvider);
    if (queue.isEmpty) return;
    final ids = <int>[];
    for (int offset = -2; offset <= 2; offset++) {
      final i = index + offset;
      if (i >= 0 && i < queue.length) ids.add(queue[i].id);
    }
    ArtworkCache.precache(ids, full: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pageNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (orientation != _lastOrientation) {
      _lastOrientation = orientation;
      if (orientation == Orientation.landscape) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(currentSongProvider);
    final theme = Theme.of(context);
    final rootPadding = MediaQuery.of(context).viewPadding;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final isAmoled = ref.watch(nowPlayingAmoledProvider);
    
    if (song == null) return const Scaffold();

    // Listen for song changes from outside to animate the PageView smoothly
    ref.listen<Song?>(currentSongProvider, (previous, next) {
      if (next != null) {
        final queue = ref.read(queueProvider);
        final nextIndex = queue.indexWhere((s) => s.id == next.id);
        if (nextIndex >= 0) {
          _lastSafeIndex = nextIndex;
          _precacheAround(nextIndex);
          if (_pageController.hasClients) {
            final currentPage = _pageController.page ?? 0.0;
            final double diff = (currentPage - nextIndex).abs();
            
            // Only animate if the PageView is not already scrolling/snapping to the target page (diff >= 0.5)
            if (diff >= 0.5) {
              _isProgrammaticScroll = true;
              _pageController.animateToPage(
                nextIndex,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
              ).then((_) {
                _isProgrammaticScroll = false;
              }).catchError((_) {
                _isProgrammaticScroll = false;
              });
            }
          }
        }
      }
    });

    // Listen for queue changes (shuffle or reordering) to instantly jump PageView to the new song position,
    // keeping the currently playing artwork static and perfectly in sync!
    ref.listen<List<Song>>(queueProvider, (previous, next) {
      final currentSong = ref.read(currentSongProvider);
      if (currentSong != null) {
        final nextIndex = next.indexWhere((s) => s.id == currentSong.id);
        if (nextIndex >= 0 && _pageController.hasClients) {
          final currentPage = _pageController.page ?? 0.0;
          if ((currentPage - nextIndex).abs() >= 0.5) {
            if (mounted) {
              setState(() {
                _lastSafeIndex = currentPage.round();
                _isReorderOrShuffle = true;
              });
            }
            
            _isProgrammaticScroll = true;
            _pageController.jumpToPage(nextIndex);
            _isProgrammaticScroll = false;
            
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _isReorderOrShuffle = false;
                });
              }
            });
          }
        }
      }
    });

    return PlayerDragToDismiss(
        onDragUp: () {
          final queueKey = GlobalKey<QueueScreenState>();
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.black,
            elevation: 0,
            showDragHandle: false,
            barrierColor: Colors.black.withValues(alpha: 0.35),
            constraints: const BoxConstraints(maxWidth: double.infinity),
            builder: (context) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Real mini-player sits above the queue sheet, sharing the
                  // same side margins so both edges line up.
                  MiniPlayerHero(
                    onTapOverride: () {
                      HapticService.medium();
                      queueKey.currentState?.scrollToCurrentSong();
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: QueueScreen(key: queueKey, systemPadding: rootPadding),
                  ),
                ],
              ),
            ),
          );
        },
        child: RepaintBoundary(
          child: Stack(
                fit: StackFit.expand,
                children: [
                  // Static blurred album-art backdrop. Rasterized once per song
                  // (RepaintBoundary) instead of a per-frame BackdropFilter, so
                  // the screen stays smooth while the seekbar/art animate.
                  if (!isAmoled)
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: ClipRect(
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                            child: Transform.scale(
                              scale: 1.3,
                              child: SmoothArtWidget(id: song.id, size: 200, borderRadius: 0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    color: isAmoled ? Colors.black : Colors.black.withValues(alpha: 0.5),
                  ),
                  Scaffold(
                    backgroundColor: Colors.transparent,
                    extendBodyBehindAppBar: true,
                    appBar: null,
                    body: Material(
                      type: MaterialType.transparency,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // System UI mode is now handled in didChangeDependencies

                          return SafeArea(
                            top: !isLandscape,
                            bottom: !isLandscape,
                            left: true,
                            right: true,
                            child: isLandscape 
                                ? _buildLandscape(context, ref, song, theme, rootPadding, constraints, isAmoled)
                                : _buildPortrait(context, ref, song, theme, rootPadding, constraints, isAmoled),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
        ),
    );
  }

  Widget _buildPortrait(BuildContext context, WidgetRef ref, dynamic song, ThemeData theme, EdgeInsets rootPadding, BoxConstraints constraints, bool isAmoled) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double contentHeight = screenHeight > 650 ? screenHeight - 60 : 650.0;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: SizedBox(
        height: contentHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Cover art PageView spans full screen width for seamless edge overflow
              Expanded(
                child: Center(
                  child: _buildAlbumArtPageView(context, ref, song, theme, isAmoled),
                ),
              ),
              const SizedBox(height: 16),
              // Controls share the same 16px side margin as the artwork.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    _buildTitleBlock(ref, song, theme),
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: SquigglySeekbar(),
                    ),
                    const SizedBox(height: 24),
                    _buildMainControls(ref, theme, isLandscape: false),
                    const SizedBox(height: 24),
                    if (ref.watch(showVolumeSliderProvider)) ...[
                      _buildVolumeSlider(ref, theme),
                      const SizedBox(height: 16),
                    ],
                    _buildBottomTools(context, ref, song, theme, rootPadding),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLandscape(BuildContext context, WidgetRef ref, dynamic song, ThemeData theme, EdgeInsets rootPadding, BoxConstraints constraints, bool isAmoled) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left side: Album Art
          Expanded(
            flex: 4,
            child: Center(
              child: _buildAlbumArtPageView(context, ref, song, theme, isAmoled),
            ),
          ),
          const SizedBox(width: 48),
          
          // Right side: Controls
          Expanded(
            flex: 6,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTitleBlock(ref, song, theme),
                    const SizedBox(height: 24),
                    const SquigglySeekbar(),
                    const SizedBox(height: 24),
                    _buildMainControls(ref, theme, isLandscape: true),
                    const SizedBox(height: 48),
                    if (ref.watch(showVolumeSliderProvider)) ...[
                      _buildVolumeSlider(ref, theme),
                      const SizedBox(height: 16),
                    ],
                    _buildBottomTools(context, ref, song, theme, rootPadding),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArtPageView(
    BuildContext context, 
    WidgetRef ref, 
    dynamic song, 
    ThemeData theme, 
    bool isAmoled, 
  ) {
    final queue = ref.watch(queueProvider);
    if (queue.isEmpty) return const SizedBox.shrink();
    final isPlaying = ref.watch(isPlayingProvider);

    const double artRadius = 32.0;

    // During the open/close transition, skip the interactive PageView (swipe
    // math + per-item AnimatedBuilder) and show just the current artwork. The
    // container transform then only has to animate a single cheap layer.
    if (!_artSettled) {
      return ConstrainedBox(
        key: npArtKey,
        constraints: const BoxConstraints(maxHeight: 600),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(artRadius),
              child: SmoothArtWidget(
                id: song.id,
                size: 600,
                borderRadius: artRadius,
                iconSize: 80,
                isPlaying: isPlaying,
              ),
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      key: npArtKey,
      constraints: const BoxConstraints(maxHeight: 600),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: PageView.builder(
          key: const ValueKey('now_playing_page_view'),
          controller: _pageController,
          itemCount: queue.length,
          physics: const BouncingScrollPhysics(parent: PageScrollPhysics()),
          onPageChanged: (newIndex) {
            _precacheAround(newIndex);
            if (!_isProgrammaticScroll) {
              final player = ref.read(audioPlayerProvider);
              if (player.currentIndex != newIndex) {
                player.seek(Duration.zero, index: newIndex);
                HapticService.medium();
              }
            }
          },
          itemBuilder: (context, index) {
            if (index < 0 || index >= queue.length) return const SizedBox.shrink();
            final queueSong = queue[index];
            // Keep the playing song's art correct during a reorder/shuffle jump.
            final itemSong = (_isReorderOrShuffle && index == _lastSafeIndex) ? song : queueSong;

            // Built once per item; only the transform below updates per frame.
            final card = Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(artRadius),
                    child: SmoothArtWidget(
                      id: itemSong.id,
                      size: 600,
                      borderRadius: artRadius,
                      iconSize: 80,
                      isPlaying: isPlaying,
                    ),
                  ),
                ),
              ),
            );

            // Parallax scale/opacity from scroll position. AnimatedBuilder
            // rebuilds only this transform per frame, not the whole PageView
            // (or the artwork), which keeps swiping smooth.
            return AnimatedBuilder(
              animation: _pageController,
              child: card,
              builder: (context, child) {
                double page;
                if (_pageController.hasClients && _pageController.position.haveDimensions) {
                  page = _pageController.page ?? index.toDouble();
                } else {
                  page = (_lastSafeIndex ?? index).toDouble();
                }
                final difference = index - page;
                final double scale = (1.0 - (difference.abs() * 0.08)).clamp(0.8, 1.0);
                final double opacity = (1.0 - (difference.abs() * 0.6)).clamp(0.0, 1.0);
                final bool isActive = difference.abs() < 0.5;
                final double activePlayScale = isActive ? (isPlaying ? 1.0 : 0.95) : 1.0;
                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(scale: scale * activePlayScale, child: child),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildTitleBlock(WidgetRef ref, dynamic song, ThemeData theme) {
    final showSongInfo = ref.watch(showSongInfoProvider);

    return Container(
      constraints: BoxConstraints(minHeight: showSongInfo ? 85 : 65),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextScroll(
            song.title,
            key: npTitleKey,
            velocity: const Velocity(pixelsPerSecond: Offset(20, 0)),
            delayBefore: const Duration(milliseconds: 2000),
            pauseBetween: const Duration(milliseconds: 2000),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            song.artist,
            key: npArtistKey,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (showSongInfo) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: ShapeDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: const StadiumBorder(),
              ),
              child: Builder(
                builder: (context) {
                  final ext = song.uri.split('.').last.toUpperCase();
                  String sizeStr = 'Unknown';
                  try {
                    final f = File(song.uri);
                    if (f.existsSync()) {
                      final sizeBytes = f.lengthSync();
                      final durationMs = song.duration?.inMilliseconds ?? 1;
                      if (durationMs > 0) {
                        final kbps = ((sizeBytes * 8) / durationMs).round();
                        sizeStr = "${kbps}kbps";
                      }
                    }
                  } catch (_) {}
                  
                  if (sizeStr == 'Unknown') {
                    return Text(
                      ext,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }
                  
                  return Text(
                    "$ext • $sizeStr",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVolumeSlider(WidgetRef ref, ThemeData theme) {
    final player = ref.read(audioPlayerProvider);
    return StreamBuilder<double>(
      stream: player.volumeStream,
      initialData: player.volume,
      builder: (context, snapshot) {
        final volume = snapshot.data ?? 1.0;
        return Row(
          children: [
            Icon(volume == 0 ? Icons.volume_off : Icons.volume_down, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            Expanded(
              child: Slider(
                value: volume,
                min: 0.0,
                max: 1.0,
                activeColor: theme.colorScheme.primary,
                inactiveColor: theme.colorScheme.surfaceContainerHighest,
                onChanged: (val) {
                  player.setVolume(val);
                },
              ),
            ),
            Icon(Icons.volume_up, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          ],
        );
      },
    );
  }

  Widget _buildMainControls(WidgetRef ref, ThemeData theme, {required bool isLandscape}) {
    final double paddingVal = isLandscape ? 12.0 : 20.0;
    final double iconSize = isLandscape ? 28.0 : 36.0;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        SpringButton(
          onTap: () {
            ref.read(audioPlayerProvider).seekToPrevious();
          },
          child: Container(
            padding: EdgeInsets.all(paddingVal),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.skip_previous, size: iconSize, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Consumer(
          builder: (context, ref, child) {
            final isPlaying = ref.watch(isPlayingProvider);
            return SpringButton(
              onTap: () {
                ref.read(isPlayingProvider.notifier).toggle();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? (isPlaying ? 28 : 16) : (isPlaying ? 48 : 24),
                  vertical: isLandscape ? 16 : (isPlaying ? 28 : 24),
                ),
                decoration: ShapeDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: isPlaying
                      ? const StadiumBorder() // Pill when playing
                      : ContinuousRectangleBorder(borderRadius: BorderRadius.circular(50)), // Squircle when paused
                ),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  size: isLandscape ? 32 : 48,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            );
          },
        ),
        SpringButton(
          onTap: () {
            ref.read(audioPlayerProvider).seekToNext();
          },
          child: Container(
            padding: EdgeInsets.all(paddingVal),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.skip_next, size: iconSize, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomTools(BuildContext context, WidgetRef ref, dynamic song, ThemeData theme, EdgeInsets rootPadding) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.lyrics_outlined), 
          onPressed: () {
            Navigator.of(context).push(
              PageRouteBuilder(
                opaque: false,
                transitionDuration: const Duration(milliseconds: 500),
                reverseTransitionDuration: const Duration(milliseconds: 400),
                pageBuilder: (context, _, _) => LyricsScreen(song: song, systemPadding: rootPadding),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutQuart,
                    )),
                    child: child,
                  );
                },
              ),
            );
          },
        ),
        Consumer(
          builder: (context, ref, child) {
            final isShuffle = ref.watch(shuffleModeProvider);
            return IconButton(
              icon: Icon(Icons.shuffle, color: isShuffle ? theme.colorScheme.primary : null),
              onPressed: () => ref.read(shuffleModeProvider.notifier).toggle(),
            );
          },
        ),
        Consumer(
          builder: (context, ref, child) {
            final loopMode = ref.watch(loopModeProvider);
            IconData icon = Icons.repeat;
            if (loopMode == LoopMode.one) icon = Icons.repeat_one;
            return IconButton(
              icon: Icon(icon, color: loopMode != LoopMode.off ? theme.colorScheme.primary : null),
              onPressed: () => ref.read(loopModeProvider.notifier).toggle(),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.info_outline),
          tooltip: 'Song Details',
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TagEditorScreen(song: song),
            ));
          },
        ),
        Consumer(
          builder: (context, ref, child) {
            final isAmoled = ref.watch(nowPlayingAmoledProvider);
            return IconButton(
              icon: Icon(isAmoled ? Icons.dark_mode : Icons.dark_mode_outlined, color: isAmoled ? theme.colorScheme.primary : null),
              onPressed: () => ref.read(nowPlayingAmoledProvider.notifier).toggle(),
            );
          },
        ),
      ],
    );
  }
}
