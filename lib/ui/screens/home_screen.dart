
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/song.dart';
import '../../state/audio_state.dart';
import '../widgets/mini_player.dart';
import '../widgets/m3_loading_indicator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/smooth_art_widget.dart';
import '../widgets/main_drawer.dart';
import 'library/albums_screen.dart';
import 'library/playlists_screen.dart';
import 'library/genres_screen.dart';
import 'search_screen.dart';
import '../../services/listening_stats_service.dart';
import '../../services/playback_persistence.dart';
import '../../services/library_cache_service.dart';
import '../../services/settings_service.dart';
import '../../services/haptic_service.dart';
import '../widgets/list_entrance_animation.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late PageController _pageController;
  late ScrollController _songListScrollController;
  final OnAudioQuery _audioQuery = OnAudioQuery();
  bool _isLoading = true;
  double _loadingProgress = 0.0;
  String _loadingMessage = "Initializing...";
  bool _permissionDenied = false;
  int _bottomNavIndex = 1; // Default to Library (Songs)
  final ValueNotifier<bool> _showSearchBarNotifier = ValueNotifier<bool>(true);
  final Map<int, double> _pageScrollOffsets = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0};
  double _accumulatedScrollDelta = 0.0;
  final ValueNotifier<bool> _isScrolledNotifier = ValueNotifier<bool>(false);
  bool _isEntranceAnimationCompleted = false;
  int _lastScrolledItemIndex = -1;


  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _bottomNavIndex);
    _songListScrollController = ScrollController()..addListener(_onSongListScroll);
    _requestPermissionAndLoad();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _songListScrollController.dispose();
    _showSearchBarNotifier.dispose();
    _isScrolledNotifier.dispose();
    super.dispose();
  }

  void _onSongListScroll() {
    if (!_songListScrollController.hasClients) return;
    
    // Only tick when the user is actively scrolling with their finger
    final direction = _songListScrollController.position.userScrollDirection;
    if (direction == ScrollDirection.idle) return;

    final double pixels = _songListScrollController.position.pixels;
    
    // Ignore bounce/overscroll areas to keep the ticks clean
    if (pixels < 0 || pixels > _songListScrollController.position.maxScrollExtent) return;

    int scrolledIndex = 0;
    if (pixels > 56.0) {
      scrolledIndex = 1 + ((pixels - 56.0) / 72.0).floor();
    }

    if (scrolledIndex != _lastScrolledItemIndex) {
      _lastScrolledItemIndex = scrolledIndex;
      HapticService.tick();
    }
  }

  void _updateProgress(double progress, String message) {
    if (mounted) {
      setState(() {
        _loadingProgress = progress;
        _loadingMessage = message;
      });
    }
  }

  Future<void> _requestPermissionAndLoad() async {
    final prefs = ref.read(sharedPreferencesProvider);

    // 0. INSTANT ZERO-WAIT UI FLIP
    // UI parses state natively through providers now

    if (mounted) {
      setState(() {
        _isLoading = false;
        _permissionDenied = false;
      });
    }

    final cachedLibrary = await LibraryCacheService.loadLibraryAsync(prefs);
    if (cachedLibrary != null && cachedLibrary.isNotEmpty) {
      ref.read(globalLibraryProvider.notifier).setLibrary(cachedLibrary);
      _restorePlaybackState(cachedLibrary);
      
      // Also trigger a rebuild/populate of smart libraries
      // The providers (smartAlbumProvider, smartArtistProvider) will automatically update when globalLibraryProvider updates

      // UI is already mounted and isLoading is false from step 0.
      _syncLibraryBackground(prefs);
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _permissionDenied = false;
      });
    }
    
    // Give Flutter a frame to render the "Initializing..." UI before blocking thread
    await Future.delayed(const Duration(milliseconds: 100));
    await _syncLibraryBackground(prefs, showProgress: true);
  }

  Future<void> _syncLibraryBackground(SharedPreferences prefs, {bool showProgress = false}) async {
    if (showProgress) _updateProgress(0.1, "Checking permissions...");
    final status = await _audioQuery.checkAndRequest(retryRequest: true);
    if (!status) {
      if (mounted) {
        setState(() {
          if (showProgress) _isLoading = false;
          _permissionDenied = true;
        });
      }
      return;
    }

    if (showProgress) _updateProgress(0.3, "Loading library...");
    final songs = await _audioQuery.querySongs(
      sortType: null,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    // Provide only songs that actually exist with a duration
    List<Song> validSongs = [];
    if (songs.isNotEmpty) {
      validSongs = songs.where((s) => (s.duration ?? 0) > 0 && s.isMusic == true).map((s) {
        final rawMap = s.getMap;
        final albumArtist = (rawMap['album_artist'] as String?) ?? '';
        return Song(
          id: s.id,
          title: s.title,
          artist: s.artist ?? 'Unknown Artist',
          album: s.album ?? 'Unknown Album',
          albumArtist: albumArtist,
          genre: s.genre ?? '',
          uri: s.data,
          duration: Duration(milliseconds: s.duration ?? 0),
          dateAdded: s.dateAdded ?? 0,
        );
      }).toList();
    }

    if (showProgress) _updateProgress(0.6, "Loading albums & artists...");
    
    if (showProgress) _updateProgress(0.9, "Finishing up...");

    // Cache the library for future instant starts natively via background isolates
    LibraryCacheService.saveLibrary(prefs, validSongs);

    ref.read(globalLibraryProvider.notifier).setLibrary(validSongs);

    // If it's a cold start with no cache, restore playback now
    if (showProgress) {
      _restorePlaybackState(validSongs);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restorePlaybackState(List<Song> validSongs) async {
    final savedState = ref.read(lastPlaybackStateProvider);
    if (savedState != null && savedState.queueIds.isNotEmpty) {
      final songMap = { for (final s in validSongs) s.id: s };
      final restoredQueue = savedState.queueIds
          .where((id) => songMap.containsKey(id))
          .map((id) => songMap[id]!)
          .toList();

      final restoredOriginalQueue = savedState.originalQueueIds.isNotEmpty
          ? savedState.originalQueueIds
              .where((id) => songMap.containsKey(id))
              .map((id) => songMap[id]!)
              .toList()
          : null;

      bool isMockedQueue = ref.read(queueProvider).length <= 1;
      if (restoredQueue.isNotEmpty && (ref.read(queueProvider).isEmpty || isMockedQueue)) {
        final idx = savedState.queueIndex.clamp(0, restoredQueue.length - 1);
        await ref.read(queueProvider.notifier).setQueue(
          restoredQueue,
          initialIndex: idx,
          initialPosition: Duration(milliseconds: savedState.positionMs),
          originalQueue: restoredOriginalQueue,
        );
      }
    }

    if (ref.read(queueProvider).isEmpty || ref.read(queueProvider).length <= 1) {
      await ref.read(queueProvider.notifier).setQueue(validSongs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedSong = ref.watch(currentSongProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final navHeight = 80.0 + bottomPadding;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      extendBody: true,
      drawer: const MainDrawer(),
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification is ScrollUpdateNotification && notification.metrics.axis == Axis.vertical) {
            final double currentOffset = notification.metrics.pixels;
            final double lastOffset = _pageScrollOffsets[_bottomNavIndex] ?? 0.0;
            final double delta = currentOffset - lastOffset;
            _pageScrollOffsets[_bottomNavIndex] = currentOffset;

            // Accumulate delta if same direction, otherwise reset and accumulate
            if (delta > 0 && _accumulatedScrollDelta < 0) {
              _accumulatedScrollDelta = delta;
            } else if (delta < 0 && _accumulatedScrollDelta > 0) {
              _accumulatedScrollDelta = delta;
            } else {
              _accumulatedScrollDelta += delta;
            }

            // Always show search bar when close to the top
            if (currentOffset <= 40) {
              if (!_showSearchBarNotifier.value) {
                _showSearchBarNotifier.value = true;
                _accumulatedScrollDelta = 0.0;
              }
            } else if (_accumulatedScrollDelta > 40.0 && _showSearchBarNotifier.value) {
              // Scroll down (content moves up) -> hide search bar
              _showSearchBarNotifier.value = false;
              _accumulatedScrollDelta = 0.0;
            } else if (_accumulatedScrollDelta < -40.0 && !_showSearchBarNotifier.value) {
              // Scroll up (content moves down) -> show search bar
              _showSearchBarNotifier.value = true;
              _accumulatedScrollDelta = 0.0;
            }

            final bool isScrolled = currentOffset > 10;
            if (isScrolled != _isScrolledNotifier.value) {
              _isScrolledNotifier.value = isScrolled;
            }
          }
          return false;
        },
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _bottomNavIndex = index;
                });
                // Restore search bar scroll state for the new page
                final double offset = _pageScrollOffsets[index] ?? 0.0;
                _isScrolledNotifier.value = offset > 10;
                _showSearchBarNotifier.value = true; // Always show search bar when switching tabs
                _accumulatedScrollDelta = 0.0;
              },
              children: [
                _KeepAliveWrapper(child: _buildHomeDashboard()),
                _KeepAliveWrapper(child: _buildSongList()),
                _KeepAliveWrapper(child: const AlbumsScreen()),
                _KeepAliveWrapper(child: const PlaylistsScreen()),
                _KeepAliveWrapper(child: const GenresScreen()),
              ],
            ),
            
            AnimatedBuilder(
              animation: Listenable.merge([_showSearchBarNotifier, _isScrolledNotifier]),
              builder: (context, child) {
                final showSearchBar = _showSearchBarNotifier.value;
                final isScrolled = _isScrolledNotifier.value;
                return AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutQuart,
                  top: showSearchBar ? 0.0 : -(80.0 + topPadding),
                  left: 0.0,
                  right: 0.0,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                      child: Container(
                        height: 80.0 + topPadding,
                        padding: EdgeInsets.only(
                          top: topPadding + 8.0,
                          bottom: 8.0,
                          left: 16.0,
                          right: 16.0,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor.withValues(
                                alpha: isScrolled ? 0.72 : 0.45,
                              ),
                          border: Border(
                            bottom: BorderSide(
                              color: isScrolled
                                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                                  : Colors.transparent,
                              width: 1.0,
                            ),
                          ),
                        ),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
              child: Center(
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                  child: Container(
                    height: 48.0,
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                          Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.15),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24.0),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Builder(
                          builder: (ctx) => IconButton(
                            icon: const Icon(Icons.menu),
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          ),
                        ),
                        const SizedBox(width: 4.0),
                        Expanded(
                          child: Text(
                            'Search songs, artists, albums...',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            if (selectedSong != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: navHeight + 12, // dynamically above extended bottom nav
                child: const MiniPlayerHero(),
              ),
              
            if (_bottomNavIndex == 1)
              Positioned(
                right: 16,
                bottom: selectedSong != null ? (navHeight + 96.0) : (navHeight + 16.0),
                child: ClipOval(
                    child: FloatingActionButton(
                      elevation: 0,
                      focusElevation: 0,
                      hoverElevation: 0,
                      highlightElevation: 0,
                      shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                      heroTag: 'shuffleFAB',
                      onPressed: () async {
                        HapticService.medium();
                        final library = ref.read(globalLibraryProvider);
                        if (library.isEmpty) return;

                        await ref.read(shuffleModeProvider.notifier).setShuffle(true);

                        final randomIndex = math.Random().nextInt(library.length);
                        await ref.read(queueProvider.notifier).setQueue(
                          library,
                          initialIndex: randomIndex,
                        );

                        ref.read(isPlayingProvider.notifier).play();
                      },
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.95),
                      child: Icon(Icons.shuffle, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ), // Closes FloatingActionButton
                ), // Closes ClipOval
              ), // Closes Positioned
          ],
        ), // Closes Stack
      ), // Closes NotificationListener
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Color.lerp(
                Theme.of(context).colorScheme.surfaceContainer,
                Theme.of(context).colorScheme.primary,
                0.05, // 5% primary tint for subtle distinction
              )!.withValues(alpha: 0.65),
            ),
            child: VenomNavigationBar(
              pageController: _pageController,
              currentIndex: _bottomNavIndex,
              onTap: (value) {
                if (_bottomNavIndex == value) return;
                setState(() {
                  _bottomNavIndex = value;
                });
                _pageController.animateToPage(
                  value,
                  duration: const Duration(milliseconds: 250), // Rapid snap timing
                  curve: Curves.easeOutQuart, // Punchy, extremely fast start that glides directly onto target
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeDashboard() {
    final library = ref.watch(globalLibraryProvider);
    final stats = ref.watch(listeningStatsProvider);
    final theme = Theme.of(context);

    if (library.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_music,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text("Your library is empty", style: theme.textTheme.titleLarge),
          ],
        ),
      );
    }

    // 1. Calculate Music Greeting
    final musicGreetings = [
      'Ready to chill?',
      'Let the music play',
      'Keep on chilling',
      'Your daily soundtrack',
      'Vibe with your library',
      'Sounds like a good time',
      'Turn up the volume',
      'Drown out the noise',
    ];
    final greetingIndex = (DateTime.now().hour + DateTime.now().day) % musicGreetings.length;
    final greeting = musicGreetings[greetingIndex];

    // 2. Recently Played Songs
    final recentIds = stats.recentlyPlayed(limit: 10);
    final recentSongs = <Song>[];
    for (final id in recentIds) {
      final match = library.where((s) => s.id == id);
      if (match.isNotEmpty) recentSongs.add(match.first);
    }

    // 3. Most Played Songs (Top 5)
    final topIds = stats.topPlayed(limit: 5);
    final topSongs = <Song>[];
    for (final id in topIds) {
      final match = library.where((s) => s.id == id);
      if (match.isNotEmpty) topSongs.add(match.first);
    }

    // 4. Recently Added Songs
    final recentlyAdded = List<Song>.from(library)
      ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    final latestSongs = recentlyAdded.take(10).toList();

    final topPadding = MediaQuery.of(context).padding.top;

    return RefreshIndicator(
      edgeOffset: 88.0 + topPadding,
      onRefresh: () async {
        final prefs = ref.read(sharedPreferencesProvider);
        await _syncLibraryBackground(prefs, showProgress: false);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 88.0 + topPadding, 16, 120.0),
        children: [
        // Welcome Greeting Header
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 30,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Here is your music dashboard.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),

        const SizedBox(height: 24),

        // Quick Actions Row
        Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      HapticService.medium();
                      if (library.isEmpty) return;
                      await ref.read(shuffleModeProvider.notifier).setShuffle(true);
                      final randomIndex = math.Random().nextInt(library.length);
                      await ref.read(queueProvider.notifier).setQueue(
                            library,
                            initialIndex: randomIndex,
                          );
                      ref.read(isPlayingProvider.notifier).play();
                    },
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shuffle, color: theme.colorScheme.onPrimary, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Shuffle',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      HapticService.medium();
                      final favoriteIds = stats.topPlayed(limit: 20);
                      final favoriteSongs = library.where((s) => favoriteIds.contains(s.id)).toList();
                      if (favoriteSongs.isEmpty) return;
                      favoriteSongs.shuffle();
                      await ref.read(queueProvider.notifier).setQueue(favoriteSongs);
                      ref.read(isPlayingProvider.notifier).play();
                    },
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.star_rounded, color: theme.colorScheme.primary, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Favorites',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      HapticService.medium();
                      if (latestSongs.isEmpty) return;
                      final fresh = List<Song>.from(latestSongs)..shuffle();
                      await ref.read(queueProvider.notifier).setQueue(fresh);
                      ref.read(isPlayingProvider.notifier).play();
                    },
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_awesome, color: theme.colorScheme.secondary, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Fresh',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

        const SizedBox(height: 28),

        // Quick Stats Row
        Row(
          children: [
            Expanded(
              child: _QuickStatCard(
                icon: Icons.timer,
                title: 'Time Listened',
                value: stats.totalListenedFormatted,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickStatCard(
                icon: Icons.library_music,
                title: 'Total Songs',
                value: '${library.length}',
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickStatCard(
                icon: Icons.play_circle_fill_rounded,
                title: 'Plays',
                value: '${stats.totalSongsPlayed}',
                color: theme.colorScheme.tertiary,
              ),
            ),
          ],
        ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

        const SizedBox(height: 32),

        // Recently Played Section
        if (recentSongs.isNotEmpty) ...[
          Row(
            children: [
              Text(
                'Recently Played',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: ListEntranceAnimation(
              builder: (context, animation) {
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: recentSongs.length,
                  itemBuilder: (context, index) {
                    final song = recentSongs[index];
                    final double start = (index * 0.05).clamp(0.0, 0.7);
                    final double end = (start + 0.35).clamp(0.0, 1.0);
                    final itemAnim = CurvedAnimation(
                      parent: animation,
                      curve: Interval(start, end, curve: Curves.easeOutCubic),
                    );

                    return FadeTransition(
                      opacity: itemAnim,
                      child: SlideTransition(
                        position: itemAnim.drive(Tween<Offset>(
                          begin: const Offset(0.15, 0.0),
                          end: Offset.zero,
                        )),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              await ref.read(queueProvider.notifier).setQueue([song]);
                              ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                              ref.read(isPlayingProvider.notifier).play();
                            },
                            child: SizedBox(
                              width: 120,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.12),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        )
                                      ],
                                    ),
                                    child: SmoothArtWidget(
                                      id: song.id,
                                      size: 200,
                                      borderRadius: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],

        // Recently Added Section
        if (latestSongs.isNotEmpty) ...[
          Row(
            children: [
              Text(
                'Recently Added',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: ListEntranceAnimation(
              builder: (context, animation) {
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: latestSongs.length,
                  itemBuilder: (context, index) {
                    final song = latestSongs[index];
                    final double start = (index * 0.05).clamp(0.0, 0.7);
                    final double end = (start + 0.35).clamp(0.0, 1.0);
                    final itemAnim = CurvedAnimation(
                      parent: animation,
                      curve: Interval(start, end, curve: Curves.easeOutCubic),
                    );

                    return FadeTransition(
                      opacity: itemAnim,
                      child: SlideTransition(
                        position: itemAnim.drive(Tween<Offset>(
                          begin: const Offset(0.15, 0.0),
                          end: Offset.zero,
                        )),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              await ref.read(queueProvider.notifier).setQueue([song]);
                              ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                              ref.read(isPlayingProvider.notifier).play();
                            },
                            child: SizedBox(
                              width: 120,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Stack(
                                    children: [
                                      Container(
                                        width: 120,
                                        height: 120,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.12),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            )
                                          ],
                                        ),
                                        child: SmoothArtWidget(
                                          id: song.id,
                                          size: 200,
                                          borderRadius: 16,
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primaryContainer,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.2),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            'NEW',
                                            style: TextStyle(
                                              color: theme.colorScheme.onPrimaryContainer,
                                              fontSize: 8,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],

        // Most Played Section (Top 5)
        if (topSongs.isNotEmpty) ...[
          Row(
            children: [
              Text(
                'Most Played Songs',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: List.generate(topSongs.length, (index) {
              final song = topSongs[index];
              final playCount = stats.playCounts[song.id] ?? 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ranking number badge
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: index == 0
                              ? theme.colorScheme.primaryContainer
                              : (index == 1
                                  ? theme.colorScheme.secondaryContainer
                                  : theme.colorScheme.surfaceContainerHighest),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '#${index + 1}',
                            style: TextStyle(
                              color: index == 0
                                  ? theme.colorScheme.onPrimaryContainer
                                  : (index == 1
                                      ? theme.colorScheme.onSecondaryContainer
                                      : theme.colorScheme.onSurfaceVariant),
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: SmoothArtWidget(
                            id: song.id,
                            size: 100,
                            borderRadius: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$playCount ${playCount == 1 ? 'play' : 'plays'}',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  onTap: () async {
                    await ref.read(queueProvider.notifier).setQueue([song]);
                    ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                    ref.read(isPlayingProvider.notifier).play();
                  },
                ),
              ).animate().fadeIn(delay: (300 + index * 50).ms, duration: 400.ms);
            }),
          ),
        ],
      ],
    ),
    );
  }

  Widget _buildHeader(BuildContext context, List<Song> library, LibrarySortType sortType, bool sortAscending) {
    Widget buildPopupItem(BuildContext context, String text, bool selected) {
      final theme = Theme.of(context);
      return Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (selected)
            Icon(
              Icons.check_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
        ],
      );
    }

    return SizedBox(
      height: 56.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6.0),
            Text(
              '${library.length} Songs',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const Spacer(),
            PopupMenuButton<LibrarySortType>(
              icon: Icon(Icons.sort, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onSelected: (LibrarySortType type) {
                ref.read(songSortTypeProvider.notifier).setType(type);
              },
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: LibrarySortType.title,
                  child: buildPopupItem(context, 'Title', sortType == LibrarySortType.title),
                ),
                PopupMenuItem(
                  value: LibrarySortType.artist,
                  child: buildPopupItem(context, 'Artist', sortType == LibrarySortType.artist),
                ),
                PopupMenuItem(
                  value: LibrarySortType.album,
                  child: buildPopupItem(context, 'Album', sortType == LibrarySortType.album),
                ),
                PopupMenuItem(
                  value: LibrarySortType.duration,
                  child: buildPopupItem(context, 'Duration', sortType == LibrarySortType.duration),
                ),
              ],
            ),
            IconButton(
              icon: Icon(
                sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              onPressed: () {
                ref.read(songSortAscendingProvider.notifier).setAscending(!sortAscending);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongCard(BuildContext context, Song song, int index, List<Song> library) {
    final isFirst = index == 1;
    final isLast = index == library.length;
    
    final borderRadius = BorderRadius.vertical(
      top: Radius.circular(isFirst ? 28 : 4),
      bottom: Radius.circular(isLast ? 28 : 4),
    );
    
    final shape = RoundedRectangleBorder(borderRadius: borderRadius);

    return SizedBox(
      height: 72.0,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        shape: shape,
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        clipBehavior: Clip.none,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () async {
            final currentQueue = ref.read(queueProvider);
            bool needsUpdate = currentQueue.length != library.length;
            if (!needsUpdate) {
              for (int i = 0; i < library.length; i++) {
                if (currentQueue[i].id != library[i].id) {
                  needsUpdate = true;
                  break;
                }
              }
            }

            if (needsUpdate) {
               await ref.read(queueProvider.notifier).setQueue(library, initialIndex: index - 1);
               ref.read(isPlayingProvider.notifier).play();
            } else {
               ref.read(audioPlayerProvider).seek(Duration.zero, index: index - 1);
               ref.read(isPlayingProvider.notifier).play();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 54,
                  height: 54,
                  child: SmoothArtWidget(
                    id: song.id,
                    size: 200,
                    isMini: true,
                    borderRadius: 8,
                    iconSize: 26,
                  ),
                ),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongList() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            M3LoadingIndicator(
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              "${(_loadingProgress * 100).toStringAsFixed(0)}%",
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _loadingMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    if (_permissionDenied) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off_outlined, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            Text("Permission Required", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Chill Player needs storage and audio permissions to scan your device for local music files.", 
                textAlign: TextAlign.center, 
                style: TextStyle(color: Colors.grey)
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text("Open Settings"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              ),
              onPressed: () async => await openAppSettings(),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _requestPermissionAndLoad,
              child: const Text("Retry Check"),
            )
          ],
        ),
      );
    }

    final libraryUnsorted = ref.watch(globalLibraryProvider);
    if (libraryUnsorted.isEmpty) {
      return const Center(child: Text("No songs found on device"));
    }
    
    final sortType = ref.watch(songSortTypeProvider);
    final sortAscending = ref.watch(songSortAscendingProvider);
    
    final library = List<Song>.from(libraryUnsorted);
    library.sort((a, b) {
       int result;
       switch (sortType) {
         case LibrarySortType.title: result = a.title.compareTo(b.title); break;
         case LibrarySortType.artist: result = a.artist.compareTo(b.artist); break;
         case LibrarySortType.album: result = a.album.compareTo(b.album); break;
         case LibrarySortType.duration: result = a.duration.compareTo(b.duration); break;
       }
       return sortAscending ? result : -result;
    });

    final topPadding = MediaQuery.of(context).padding.top;

    if (_isEntranceAnimationCompleted) {
      final listWidget = ListView.builder(
        controller: _songListScrollController,
        padding: EdgeInsets.only(top: 80.0 + topPadding + 8.0, bottom: 120.0),
        itemCount: library.length + 1,
        itemExtentBuilder: (index, dimensions) => index == 0 ? 56.0 : 72.0,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildHeader(context, library, sortType, sortAscending);
          }
          final song = library[index - 1];
          return _buildSongCard(context, song, index, library);
        },
      );

      return Stack(
        children: [
          listWidget,
          Positioned(
            right: 0,
            top: 80.0 + topPadding + 64.0,
            bottom: 140.0,
            width: 32,
            child: FastScroller(
              library: library,
              scrollController: _songListScrollController,
              sortType: sortType,
            ),
          ),
        ],
      );
    }

    final listWidget = ListEntranceAnimation(
      onComplete: () {
        if (mounted) {
          setState(() {
            _isEntranceAnimationCompleted = true;
          });
        }
      },
      builder: (context, animation) {
        return ListView.builder(
          controller: _songListScrollController,
          padding: EdgeInsets.only(top: 80.0 + topPadding + 8.0, bottom: 120.0),
          itemCount: library.length + 1,
          itemExtentBuilder: (index, dimensions) => index == 0 ? 56.0 : 72.0,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildHeader(context, library, sortType, sortAscending);
            }
            
            final song = library[index - 1];
            final cardWidget = _buildSongCard(context, song, index, library);

            final double start = ((index - 1) * 0.03).clamp(0.0, 0.7);
            final double end = (start + 0.30).clamp(0.0, 1.0);
            final itemAnim = CurvedAnimation(
              parent: animation,
              curve: Interval(start, end, curve: Curves.easeOutQuad),
            );

            return FadeTransition(
              opacity: itemAnim,
              child: SlideTransition(
                position: itemAnim.drive(Tween<Offset>(
                  begin: const Offset(0.08, 0.0),
                  end: Offset.zero,
                )),
                child: cardWidget,
              ),
            );
          },
        );
      },
    );

    return Stack(
      children: [
        listWidget,
        Positioned(
          right: 0,
          top: 80.0 + topPadding + 64.0,
          bottom: 140.0,
          width: 32,
          child: FastScroller(
            library: library,
            scrollController: _songListScrollController,
            sortType: sortType,
          ),
        ),
      ],
    );
  }
}

class VenomNavigationBar extends StatefulWidget {
  final PageController pageController;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const VenomNavigationBar({super.key, required this.pageController, required this.currentIndex, required this.onTap});

  @override
  State<VenomNavigationBar> createState() => _VenomNavigationBarState();
}

class _VenomNavigationBarState extends State<VenomNavigationBar> {
  @override
  void initState() {
    super.initState();
    widget.pageController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(VenomNavigationBar oldWidget) {
    if (oldWidget.pageController != widget.pageController) {
      oldWidget.pageController.removeListener(_onScroll);
      widget.pageController.addListener(_onScroll);
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    setState(() {}); // Drive the venom calculation in real-time from the physics engine
  }

  @override
  Widget build(BuildContext context) {
    final double page = widget.pageController.hasClients ? (widget.pageController.page ?? widget.currentIndex.toDouble()) : widget.currentIndex.toDouble();
    
    int baseIndex = page.floor();
    double fraction = page - baseIndex;
    
    // Core Venom Mathematics: Right edge pushes out first, Left edge lags and snaps into place
    double leftVal = baseIndex + Curves.easeInQuint.transform(fraction);
    double rightVal = baseIndex + Curves.easeOutQuint.transform(fraction);
    
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        double width = constraints.maxWidth;
        double segmentWidth = width / 5;
        double pillMaxWidth = 64.0;
        
        double leftPx = (leftVal + 0.5) * segmentWidth - (pillMaxWidth / 2);
        double stretchWidth = (rightVal - leftVal) * segmentWidth + pillMaxWidth;

        return Container(
          height: 80 + bottomPad,
          padding: EdgeInsets.only(bottom: bottomPad),
          color: Colors.transparent, // Background handled by parent backdrop filter directly via BackdropFilter wrapper
          child: Stack(
            children: [
              Positioned(
                left: leftPx,
                top: 14,
                height: 32,
                child: Container(
                  width: stretchWidth,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              
              Row(
                children: [
                  _buildIcon(0, Icons.home_outlined, Icons.home, "Home"),
                  _buildIcon(1, Icons.music_note_outlined, Icons.music_note, "Library"),
                  _buildIcon(2, Icons.album_outlined, Icons.album, "Albums"),
                  _buildIcon(3, Icons.queue_music_outlined, Icons.queue_music, "Playlists"),
                  _buildIcon(4, Icons.category_outlined, Icons.category, "Genres"),
                ],
              )
            ],
          ),
        );
      }
    );
  }

  Widget _buildIcon(int index, IconData outline, IconData solid, String label) {
    bool isSelected = widget.currentIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(index),
        child: Padding(
          padding: const EdgeInsets.only(top: 18.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(isSelected ? solid : outline, 
                color: isSelected 
                    ? Theme.of(context).colorScheme.onSecondaryContainer 
                    : Theme.of(context).colorScheme.onSurfaceVariant
              ),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected 
                    ? Theme.of(context).colorScheme.onSurface 
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _QuickStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 116,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    )
    .animate()
    .fadeIn(duration: 500.ms, delay: 150.ms)
    .slideY(begin: 0.15, end: 0.0, duration: 500.ms, curve: Curves.easeOutCubic);
  }
}

class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const _KeepAliveWrapper({required this.child});

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class FastScroller extends StatefulWidget {
  final List<Song> library;
  final ScrollController scrollController;
  final LibrarySortType sortType;

  const FastScroller({
    super.key,
    required this.library,
    required this.scrollController,
    required this.sortType,
  });

  @override
  State<FastScroller> createState() => _FastScrollerState();
}

class _FastScrollerState extends State<FastScroller> {
  bool _isDragging = false;
  String _activeChar = '';
  double _scrollerHeight = 0.0;
  double _handleY = 0.0;
  bool _isVisible = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients || _scrollerHeight <= 0) return;

    final position = widget.scrollController.position;
    final double maxScroll = position.maxScrollExtent;
    final double currentScroll = position.pixels;

    if (maxScroll <= 0) return;

    if (!_isVisible) {
      setState(() {
        _isVisible = true;
      });
    }

    _hideTimer?.cancel();
    if (!_isDragging) {
      _hideTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _isVisible = false;
          });
        }
      });
    }

    final double scrollPercent = (currentScroll / maxScroll).clamp(0.0, 1.0);
    const double handleHeight = 48.0;
    final double targetY = scrollPercent * (_scrollerHeight - handleHeight);

    if (!_isDragging && _handleY != targetY) {
      setState(() {
        _handleY = targetY;
      });
    }
  }

  String _getSongSortChar(Song song, LibrarySortType sortType) {
    String text = '';
    switch (sortType) {
      case LibrarySortType.title:
        text = song.title;
        break;
      case LibrarySortType.artist:
        text = song.artist;
        break;
      case LibrarySortType.album:
        text = song.album;
        break;
      case LibrarySortType.duration:
        return '🕒';
    }
    if (text.isEmpty) return '#';
    final char = text[0].toUpperCase();
    if (RegExp(r'[A-Z]').hasMatch(char)) {
      return char;
    }
    return '#';
  }

  void _handleDrag(double localY) {
    if (_scrollerHeight <= 0) return;

    const double handleHeight = 48.0;
    // Snap handle center to the touch position: targetY = localY - (handleHeight / 2)
    final double targetY = (localY - 24.0).clamp(0.0, _scrollerHeight - handleHeight);

    setState(() {
      _handleY = targetY;
      _isVisible = true;
    });

    _hideTimer?.cancel();

    final double scrollPercent = targetY / (_scrollerHeight - handleHeight);

    if (widget.scrollController.hasClients) {
      final position = widget.scrollController.position;
      final double maxScroll = position.maxScrollExtent;
      final double targetScroll = scrollPercent * maxScroll;

      widget.scrollController.jumpTo(targetScroll);

      final int songIndex = ((scrollPercent * (widget.library.length - 1)).round()).clamp(0, widget.library.length - 1);
      final song = widget.library[songIndex];
      final char = _getSongSortChar(song, widget.sortType);

      if (_activeChar != char) {
        setState(() {
          _activeChar = char;
        });
        HapticService.tick();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.library.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        _scrollerHeight = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (details) {
            setState(() {
              _isDragging = true;
              _activeChar = '';
            });
            HapticService.light();
            _handleDrag(details.localPosition.dy);
          },
          onVerticalDragUpdate: (details) {
            _handleDrag(details.localPosition.dy);
          },
          onVerticalDragEnd: (_) {
            setState(() {
              _isDragging = false;
            });
            _onScroll();
          },
          onVerticalDragCancel: () {
            setState(() {
              _isDragging = false;
            });
            _onScroll();
          },
          child: Container(
            width: 32,
            color: Colors.transparent, // Capture touches on transparent area
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (_isDragging && _activeChar.isNotEmpty)
                  Positioned(
                    right: 36,
                    top: (_handleY + 24) - 26,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 180),
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Opacity(
                            opacity: value,
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.95),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _activeChar,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                Positioned(
                  top: _handleY,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _isVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Material(
                      elevation: 4,
                      shadowColor: Colors.black.withValues(alpha: 0.3),
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                      color: Theme.of(context).colorScheme.primary,
                      child: Container(
                        width: 24,
                        height: 48,
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
                        ),
                        child: Icon(
                          Icons.unfold_more,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

