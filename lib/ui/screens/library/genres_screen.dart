import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../widgets/m3_loading_indicator.dart';
import '../../widgets/smooth_art_widget.dart';
import '../../widgets/spring_button.dart';
import '../../../state/audio_state.dart';
import '../../../models/song.dart';
import '../../widgets/list_entrance_animation.dart';
import '../../../theme/color_provider.dart';

class GenresScreen extends StatelessWidget {
  const GenresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<GenreModel>>(
      future: OnAudioQuery().queryGenres(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString(), style: TextStyle(color: theme.colorScheme.error)));
        }
        if (!snapshot.hasData) return const Center(child: M3LoadingIndicator(size: 40));
        final genres = snapshot.data!;
        if (genres.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.category, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text(
                  'No genres found',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }

        final topPadding = MediaQuery.of(context).padding.top;
        
        return ListEntranceAnimation(
          builder: (context, animation) {
            return GridView.builder(
              padding: EdgeInsets.only(top: 80.0 + topPadding + 8.0, bottom: 150, left: 16, right: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.82, // Standard child aspect ratio for elegant display
              ),
              itemCount: genres.length,
              itemBuilder: (context, index) {
                final genre = genres[index];

                final double start = (index * 0.04).clamp(0.0, 0.7);
                final double end = (start + 0.30).clamp(0.0, 1.0);
                final itemAnim = CurvedAnimation(
                  parent: animation,
                  curve: Interval(start, end, curve: Curves.easeOutQuad),
                );

                final cardWidget = _GenreCard(
                  genre: genre,
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _GenreDetailScreen(genre: genre),
                    ));
                  },
                );

                return FadeTransition(
                  opacity: itemAnim,
                  child: SlideTransition(
                    position: itemAnim.drive(Tween<Offset>(
                      begin: const Offset(0.0, 0.08),
                      end: Offset.zero,
                    )),
                    child: cardWidget,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Dynamic Genre Card Widget with Background Collage & Frosted Glass Bottom
// ---------------------------------------------------------------------------
class _GenreCard extends StatefulWidget {
  final GenreModel genre;
  final VoidCallback onTap;

  const _GenreCard({
    required this.genre,
    required this.onTap,
  });

  @override
  State<_GenreCard> createState() => _GenreCardState();
}

class _GenreCardState extends State<_GenreCard> {
  List<int>? _songIds;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    try {
      final songModels = await OnAudioQuery().queryAudiosFrom(AudiosFromType.GENRE_ID, widget.genre.id);
      if (mounted) {
        setState(() {
          _songIds = songModels.map((s) => s.id).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _songIds = [];
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SpringButton(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Bottom Layer: Natural Art Collage Background
              if (!_isLoading && _songIds != null && _songIds!.isNotEmpty)
                Positioned.fill(
                  child: _GenreCollage(songIds: _songIds!),
                )
              else
                Container(color: theme.colorScheme.surfaceContainerHigh),
              
              // 2. Middle Layer: Dark Radial Vignette
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.45),
                      ],
                      center: Alignment.center,
                      radius: 0.85,
                    ),
                  ),
                ),
              ),

              // 3. Top Layer: Frosted Glass Bottom Panel
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.42),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.genre.genre,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${widget.genre.numOfSongs} track${widget.genre.numOfSongs != 1 ? 's' : ''}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.bold,
                                fontSize: 9.5,
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
    );
  }
}

// ---------------------------------------------------------------------------
// Private Artwork Collage Widget for Genres
// ---------------------------------------------------------------------------
class _GenreCollage extends StatelessWidget {
  final List<int> songIds;

  const _GenreCollage({required this.songIds});

  @override
  Widget build(BuildContext context) {
    final count = songIds.length;

    if (count == 0) {
      return Container(color: Colors.black54);
    }

    if (count == 1) {
      return SmoothArtWidget(
        id: songIds[0],
        size: 200,
        borderRadius: 0,
        iconSize: 24,
      );
    }

    if (count == 2) {
      return Row(
        children: [
          Expanded(
            child: SmoothArtWidget(
              id: songIds[0],
              size: 200,
              borderRadius: 0,
              iconSize: 20,
            ),
          ),
          const SizedBox(width: 1),
          Expanded(
            child: SmoothArtWidget(
              id: songIds[1],
              size: 200,
              borderRadius: 0,
              iconSize: 20,
            ),
          ),
        ],
      );
    }

    final displayIds = songIds.take(4).toList();
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: SmoothArtWidget(
                  id: displayIds[0],
                  size: 120,
                  borderRadius: 0,
                  iconSize: 16,
                ),
              ),
              const SizedBox(width: 1),
              Expanded(
                child: SmoothArtWidget(
                  id: displayIds[1],
                  size: 120,
                  borderRadius: 0,
                  iconSize: 16,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 1),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: SmoothArtWidget(
                  id: displayIds[2],
                  size: 120,
                  borderRadius: 0,
                  iconSize: 16,
                ),
              ),
              const SizedBox(width: 1),
              Expanded(
                child: displayIds.length > 3
                    ? SmoothArtWidget(
                        id: displayIds[3],
                        size: 120,
                        borderRadius: 0,
                        iconSize: 16,
                      )
                    : Container(
                        color: Colors.white.withValues(alpha: 0.1),
                        child: const Icon(
                          Icons.music_note,
                          color: Colors.white24,
                          size: 16,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Genre Detail Screen
// ---------------------------------------------------------------------------
class _GenreDetailScreen extends ConsumerWidget {
  final GenreModel genre;

  const _GenreDetailScreen({required this.genre});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentSong = ref.watch(currentSongProvider);
    final activeColors = ref.watch(currentExtractedColorsProvider);
    final tintColor = activeColors.vibrant;

    return Scaffold(
      body: FutureBuilder<List<SongModel>>(
        future: OnAudioQuery().queryAudiosFrom(AudiosFromType.GENRE_ID, genre.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: M3LoadingIndicator(size: 40));
          final songModels = snapshot.data!;

          final songs = songModels.map((s) {
            final rawMap = s.getMap;
            final albumArtist = (rawMap['album_artist'] as String?) ?? '';
            return Song(
              id: s.id,
              title: s.title,
              artist: s.artist ?? 'Unknown',
              album: s.album ?? 'Unknown',
              albumArtist: albumArtist,
              genre: s.genre ?? '',
              uri: s.data,
              duration: Duration(milliseconds: s.duration ?? 0),
            );
          }).toList();

          if (songs.isEmpty) {
            return Scaffold(
              appBar: AppBar(title: Text(genre.genre)),
              body: Center(
                child: Text(
                  'No songs in this genre',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            );
          }

          return ListEntranceAnimation(
            builder: (context, animation) {
              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    expandedHeight: 220.0,
                    pinned: true,
                    stretch: true,
                    backgroundColor: theme.colorScheme.surface,
                    iconTheme: const IconThemeData(color: Colors.white),
                    flexibleSpace: FlexibleSpaceBar(
                      stretchModes: const [
                        StretchMode.zoomBackground,
                        StretchMode.blurBackground,
                      ],
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: _GenreCollage(songIds: songs.map((s) => s.id).toList()),
                          ),
                          Container(color: Colors.black.withValues(alpha: 0.45)),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                                begin: Alignment.bottomCenter,
                                end: Alignment.center,
                              ),
                            ),
                          ),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 48),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    genre.genre,
                                    style: theme.textTheme.headlineMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${songs.length} track${songs.length != 1 ? 's' : ''}',
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: SpringButton(
                              onTap: () async {
                                await ref.read(queueProvider.notifier).setQueue(songs);
                                ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                                ref.read(isPlayingProvider.notifier).play();
                              },
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: tintColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: tintColor.withValues(alpha: 0.35),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: tintColor.withValues(alpha: 0.15),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text(
                                    'Play All',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SpringButton(
                              onTap: () async {
                                final shuffled = List<Song>.from(songs)..shuffle();
                                await ref.read(queueProvider.notifier).setQueue(shuffled);
                                ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                                ref.read(isPlayingProvider.notifier).play();
                              },
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: tintColor.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: tintColor.withValues(alpha: 0.15),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: tintColor.withValues(alpha: 0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.shuffle_rounded,
                                      color: Colors.white.withValues(alpha: 0.8),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Shuffle',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 8, bottom: 150, left: 16, right: 16),
                    sliver: SliverList.builder(
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        final isPlaying = currentSong?.id == song.id;

                        final isFirst = index == 0;
                        final isLast = index == songs.length - 1;

                        final double start = (index * 0.04).clamp(0.0, 0.7);
                        final double end = (start + 0.30).clamp(0.0, 1.0);
                        final itemAnim = CurvedAnimation(
                          parent: animation,
                          curve: Interval(start, end, curve: Curves.easeOutQuad),
                        );

                        final shape = RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(isFirst ? 24 : 4),
                            bottom: Radius.circular(isLast ? 24 : 4),
                          ),
                        );

                        final cardWidget = Card(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          shape: shape,
                          color: theme.colorScheme.surfaceContainerHigh,
                          elevation: 0,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
                            leading: SizedBox(
                              width: 48,
                              height: 48,
                              child: SmoothArtWidget(
                                id: song.id,
                                size: 150,
                                isMini: true,
                                borderRadius: 8,
                                iconSize: 20,
                              ),
                            ),
                            title: Text(
                              song.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: isPlaying ? theme.colorScheme.primary : null,
                                fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              song.artist,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: isPlaying
                                ? Icon(Icons.bar_chart, color: theme.colorScheme.primary, size: 20)
                                : null,
                            shape: shape,
                            onTap: () async {
                              await ref.read(queueProvider.notifier).setQueue(songs);
                              ref.read(audioPlayerProvider).seek(Duration.zero, index: index);
                              ref.read(isPlayingProvider.notifier).play();
                            },
                          ),
                        );

                        return FadeTransition(
                          opacity: itemAnim,
                          child: SlideTransition(
                            position: itemAnim.drive(Tween<Offset>(
                              begin: const Offset(0.0, 0.08),
                              end: Offset.zero,
                            )),
                            child: cardWidget,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
