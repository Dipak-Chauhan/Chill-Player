import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../widgets/m3_loading_indicator.dart';
import '../../widgets/smooth_art_widget.dart';
import '../../../state/audio_state.dart';
import '../../../models/song.dart';
import '../../widgets/list_entrance_animation.dart';

class GenresScreen extends StatelessWidget {
  const GenresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<GenreModel>>(
      future: OnAudioQuery().queryGenres(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
        if (!snapshot.hasData) return const Center(child: M3LoadingIndicator(size: 40));
        final genres = snapshot.data!;
        if (genres.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.category, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('No genres found', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        }

        final topPadding = MediaQuery.of(context).padding.top;
        return ListEntranceAnimation(
          builder: (context, animation) {
            return ListView.builder(
              padding: EdgeInsets.only(top: 80.0 + topPadding + 8.0, bottom: 150, left: 16, right: 16),
              itemCount: genres.length,
              itemBuilder: (context, index) {
                final genre = genres[index];
                // Generate a unique color for each genre from theme
                final colors = [
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.secondaryContainer,
                  theme.colorScheme.tertiaryContainer,
                ];
                final color = colors[index % colors.length];

                final isFirst = index == 0;
                final isLast = index == genres.length - 1;

                final shape = RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(isFirst ? 28 : 4),
                    bottom: Radius.circular(isLast ? 28 : 4),
                  ),
                );

                final cardWidget = Card(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  shape: shape,
                  color: theme.colorScheme.surfaceContainerHigh,
                  elevation: 0,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.category, color: theme.colorScheme.onPrimaryContainer),
                    ),
                    title: Text(
                      genre.genre,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${genre.numOfSongs} track${genre.numOfSongs != 1 ? 's' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    shape: shape,
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _GenreDetailScreen(genre: genre),
                      ));
                    },
                  ),
                );

                final double start = (index * 0.04).clamp(0.0, 0.7);
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
      },
    );
  }
}

class _GenreDetailScreen extends ConsumerWidget {
  final GenreModel genre;

  const _GenreDetailScreen({required this.genre});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentSong = ref.watch(currentSongProvider);

    return Scaffold(
      appBar: AppBar(title: Text(genre.genre)),
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
            return Center(child: Text('No songs in this genre', style: theme.textTheme.bodyLarge));
          }

          return Column(
            children: [
              // Play/Shuffle controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          await ref.read(queueProvider.notifier).setQueue(songs);
                          ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                          ref.read(isPlayingProvider.notifier).play();
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play All'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          final shuffled = List<Song>.from(songs)..shuffle();
                          await ref.read(queueProvider.notifier).setQueue(shuffled);
                          ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                          ref.read(isPlayingProvider.notifier).play();
                        },
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Shuffle'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListEntranceAnimation(
                  builder: (context, animation) {
                    return ListView.builder(
                      itemCount: songs.length,
                      padding: const EdgeInsets.only(top: 8, bottom: 150, left: 16, right: 16),
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        final isPlaying = currentSong?.id == song.id;

                        final isFirst = index == 0;
                        final isLast = index == songs.length - 1;

                        final shape = RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(isFirst ? 28 : 4),
                            bottom: Radius.circular(isLast ? 28 : 4),
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
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: isPlaying ? Icon(Icons.bar_chart, color: theme.colorScheme.primary, size: 20) : null,
                            shape: shape,
                            onTap: () async {
                              await ref.read(queueProvider.notifier).setQueue(songs);
                              ref.read(audioPlayerProvider).seek(Duration.zero, index: index);
                              ref.read(isPlayingProvider.notifier).play();
                            },
                          ),
                        );

                        final double start = (index * 0.04).clamp(0.0, 0.7);
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
