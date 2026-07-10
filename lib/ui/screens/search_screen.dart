import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../models/song.dart';
import '../../state/audio_state.dart';
import '../../state/smart_library.dart';
import '../widgets/smooth_art_widget.dart';
import 'library/album_details_screen.dart';
import 'library/artist_details_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  late PageController _pageController;
  final ScrollController _chipScrollController = ScrollController();
  String _query = '';
  int _selectedFilter = 0;
  final List<String> _filters = ['All', 'Songs', 'Albums', 'Artists', 'Album artists', 'Genres', 'Playlists'];

  // Debounce timer to avoid filtering on every keystroke
  Timer? _debounce;

  // Cached search results — computed once per query, not per tab/frame
  List<Song> _cachedSongs = [];
  List<SmartAlbum> _cachedAlbums = [];
  List<SmartArtist> _cachedArtists = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _pageController.dispose();
    _chipScrollController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _onQueryChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _performSearch(val);
    });
  }

  void _performSearch(String query) {
    final lowerQuery = query.toLowerCase().trim();

    if (lowerQuery.isEmpty) {
      setState(() {
        _query = query;
        _cachedSongs = [];
        _cachedAlbums = [];
        _cachedArtists = [];
      });
      return;
    }

    final library = ref.read(globalLibraryProvider);
    final songs = <Song>[];
    for (final song in library) {
      if (song.title.toLowerCase().contains(lowerQuery) ||
          song.artist.toLowerCase().contains(lowerQuery) ||
          song.album.toLowerCase().contains(lowerQuery)) {
        songs.add(song);
        if (songs.length >= 100) break; // Cap results for performance
      }
    }

    final albums = ref.read(smartAlbumProvider);
    final filteredAlbums = <SmartAlbum>[];
    for (final a in albums) {
      if (a.name.toLowerCase().contains(lowerQuery) || a.albumArtist.toLowerCase().contains(lowerQuery)) {
        filteredAlbums.add(a);
        if (filteredAlbums.length >= 50) break;
      }
    }

    final artists = ref.read(smartArtistProvider);
    final filteredArtists = <SmartArtist>[];
    for (final a in artists) {
      if (a.name.toLowerCase().contains(lowerQuery)) {
        filteredArtists.add(a);
        if (filteredArtists.length >= 50) break;
      }
    }

    setState(() {
      _query = query;
      _cachedSongs = songs;
      _cachedAlbums = filteredAlbums;
      _cachedArtists = filteredArtists;
    });
  }

  void _onChipSelected(int index) {
    setState(() {
      _selectedFilter = index;
    });
    _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    _scrollToChip(index);
  }

  void _scrollToChip(int index) {
    if (!_chipScrollController.hasClients) return;
    final position = (index * 80.0) - (MediaQuery.of(context).size.width / 2) + 40;
    _chipScrollController.animateTo(
      position.clamp(0.0, _chipScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: SearchBar(
            controller: _controller,
            autoFocus: true,
            hintText: 'Search something...',
            elevation: WidgetStateProperty.all(0),
            backgroundColor: WidgetStateProperty.all(Theme.of(context).colorScheme.surfaceContainerHighest),
            padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16)),
            onChanged: _onQueryChanged,
            trailing: [
              if (_query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _controller.clear();
                    _debounce?.cancel();
                    _performSearch('');
                  },
                ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              controller: _chipScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                height: 40,
                child: VenomFilterChips(
                  pageController: _pageController,
                  filters: _filters,
                  selectedIndex: _selectedFilter,
                  onSelected: _onChipSelected,
                ),
              ),
            ),
          ),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _selectedFilter = index);
          _scrollToChip(index);
        },
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          return _buildSearchTabContent(index);
        },
      ),
    );
  }

  Widget _buildSearchTabContent(int filterIndex) {
    if (_query.isEmpty) return _buildEmptyState();

    // Use the cached results based on the active filter tab
    final bool showSongs = filterIndex == 0 || filterIndex == 1;
    final bool showAlbums = filterIndex == 0 || filterIndex == 2;
    final bool showArtists = filterIndex == 0 || filterIndex == 3 || filterIndex == 4;

    final songs = showSongs ? _cachedSongs : <Song>[];
    final albums = showAlbums ? _cachedAlbums : <SmartAlbum>[];
    final artists = showArtists ? _cachedArtists : <SmartArtist>[];

    if (songs.isEmpty && albums.isEmpty && artists.isEmpty) {
      return _buildEmptyState();
    }

    // Calculate total item count for the flat list
    int totalCount = 0;
    final int songHeaderIdx = totalCount;
    if (songs.isNotEmpty) totalCount += 1 + songs.length; // header + items
    final int albumHeaderIdx = totalCount;
    if (albums.isNotEmpty) totalCount += 1 + albums.length;
    final int artistHeaderIdx = totalCount;
    if (artists.isNotEmpty) totalCount += 1 + artists.length;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 150),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (songs.isNotEmpty) {
          if (index == songHeaderIdx) {
            return _buildSectionHeader('SONGS', songs.length);
          }
          final songIdx = index - songHeaderIdx - 1;
          if (songIdx >= 0 && songIdx < songs.length) {
            return _buildSongTile(songs[songIdx], songs);
          }
        }
        if (albums.isNotEmpty) {
          if (index == albumHeaderIdx) {
            return _buildSectionHeader('ALBUMS', albums.length);
          }
          final albumIdx = index - albumHeaderIdx - 1;
          if (albumIdx >= 0 && albumIdx < albums.length) {
            return _buildAlbumTile(albums[albumIdx]);
          }
        }
        if (artists.isNotEmpty) {
          if (index == artistHeaderIdx) {
            return _buildSectionHeader('ARTISTS', artists.length);
          }
          final artistIdx = index - artistHeaderIdx - 1;
          if (artistIdx >= 0 && artistIdx < artists.length) {
            return _buildArtistTile(artists[artistIdx]);
          }
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildEmptyState() {
     return Center(
       child: Column(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           SizedBox(
             width: 120, height: 120,
             child: Stack(
               alignment: Alignment.center,
               children: [
                 Icon(Icons.library_music, size: 80, color: Colors.grey.withValues(alpha: 0.1)),
                 const Positioned(
                   right: 15, bottom: 15,
                   child: Icon(Icons.search, size: 50, color: Color(0xFF83C7A8)),
                 ),
               ],
             ),
           ),
           const SizedBox(height: 16),
           const Text("No search results", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500)),
         ],
       ),
     );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text('$count $title', style: const TextStyle(color: Color(0xFF83C7A8), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
    );
  }

  Widget _buildSongTile(Song song, List<Song> playableQueue) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SizedBox(
        width: 50, height: 50,
        child: SmoothArtWidget(
          id: song.id, 
          isMini: true, 
          iconSize: 20,
          borderRadius: 8,
        ),
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text('${song.artist} • ${_formatDuration(song.duration)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      trailing: IconButton(icon: const Icon(Icons.more_vert), color: Theme.of(context).colorScheme.onSurfaceVariant, onPressed: (){}),
      onTap: () {
        ref.read(queueProvider.notifier).setQueue(playableQueue);
        ref.read(audioPlayerProvider).seek(Duration.zero, index: playableQueue.indexOf(song));
        ref.read(isPlayingProvider.notifier).play();
        Navigator.pop(context);
      },
    );
  }

  Widget _buildAlbumTile(SmartAlbum album) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SizedBox(
        width: 50, height: 50,
        child: SmoothArtWidget(
          id: album.fallbackImageId, 
          artworkType: ArtworkType.AUDIO,
          isMini: true, 
          iconSize: 20,
          borderRadius: 8,
        ),
      ),
      title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(album.albumArtist.isEmpty ? 'Unknown Artist' : album.albumArtist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
      onTap: () {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AlbumDetailsScreen(album: album)));
      },
    );
  }

  Widget _buildArtistTile(SmartArtist artist) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SizedBox(
        width: 50, height: 50,
        child: SmoothArtWidget(
          id: artist.fallbackImageId, 
          artworkType: ArtworkType.AUDIO,
          isMini: true, 
          iconSize: 20,
          borderRadius: 8,
        ),
      ),
      title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text('${artist.songs.length} songs', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
      onTap: () {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ArtistDetailsScreen(artist: artist)));
      },
    );
  }
}

class VenomFilterChips extends StatefulWidget {
  final PageController pageController;
  final List<String> filters;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const VenomFilterChips({super.key, required this.pageController, required this.filters, required this.selectedIndex, required this.onSelected});

  @override
  State<VenomFilterChips> createState() => _VenomFilterChipsState();
}

class _VenomFilterChipsState extends State<VenomFilterChips> {
  final List<double> _chipWidths = [45, 65, 75, 75, 115, 75, 85];
  final double _chipSpacing = 8.0;

  @override
  void initState() {
    super.initState();
    widget.pageController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(VenomFilterChips oldWidget) {
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
    setState(() {}); 
  }

  double _getInterpolatedPosition(double progress, bool isRightEdge) {
    int maxIndex = widget.filters.length - 1;
    int base = progress.floor().clamp(0, maxIndex);
    int next = (base + 1).clamp(0, maxIndex);
    
    double getOffsets(int targetIndex, bool rightEdge) {
      double pos = 0;
      for (int i = 0; i < targetIndex; i++) {
        pos += _chipWidths[i] + _chipSpacing;
      }
      if (rightEdge) {
        pos += _chipWidths[targetIndex];
      }
      return pos;
    }

    double basePos = getOffsets(base, isRightEdge);
    double nextPos = getOffsets(next, isRightEdge);
    return basePos + (nextPos - basePos) * (progress - base);
  }

  @override
  Widget build(BuildContext context) {
    final double page = widget.pageController.hasClients ? (widget.pageController.page ?? widget.selectedIndex.toDouble()) : widget.selectedIndex.toDouble();
    
    int baseIndex = page.floor();
    double fraction = page - baseIndex;
    
    double leftProgress = baseIndex + Curves.easeInQuint.transform(fraction);
    double rightProgress = baseIndex + Curves.easeOutQuint.transform(fraction);
    
    double leftPx = _getInterpolatedPosition(leftProgress, false);
    double rightPx = _getInterpolatedPosition(rightProgress, true);
    double stretchWidth = rightPx - leftPx;

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Positioned(
          left: leftPx,
          top: 0,
          bottom: 0,
          child: Container(
            width: stretchWidth,
            decoration: BoxDecoration(
              color: const Color(0xFF2E453D),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.filters.length, (index) {
            final isSelected = widget.selectedIndex == index;
            return GestureDetector(
              onTap: () => widget.onSelected(index),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: _chipWidths[index],
                margin: EdgeInsets.only(right: index == widget.filters.length - 1 ? 0 : _chipSpacing),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.filters[index],
                  style: TextStyle(
                    color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            );
          }),
        )
      ],
    );
  }
}
