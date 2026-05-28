import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/smooth_art_widget.dart';
import '../../../state/audio_state.dart';
import '../../../state/smart_library.dart';
import '../../../models/song.dart';
import '../../widgets/list_entrance_animation.dart';

class AlbumDetailsScreen extends ConsumerWidget {
  final SmartAlbum album;

  const AlbumDetailsScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentSong = ref.watch(currentSongProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(album.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'album_${album.name}',
                child: SmoothArtWidget(
                  id: album.fallbackImageId,
                  size: 800,
                  artworkType: ArtworkType.AUDIO,
                  borderRadius: 0,
                  iconSize: 100,
                ),
              ),
            ),
          ),
          // Album info bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      album.albumArtist.isEmpty ? 'Unknown Artist' : album.albumArtist,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          Text(
                            '${album.songs.length} track${album.songs.length != 1 ? 's' : ''}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.play_arrow_rounded),
                            tooltip: 'Play all',
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              foregroundColor: theme.colorScheme.onPrimaryContainer,
                            ),
                            onPressed: () {
                              ref.read(queueProvider.notifier).setQueue(album.songs);
                              ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                              ref.read(isPlayingProvider.notifier).play();
                            },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.shuffle_rounded),
                            tooltip: 'Shuffle',
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.secondaryContainer,
                              foregroundColor: theme.colorScheme.onSecondaryContainer,
                            ),
                            onPressed: () {
                              final queue = List<Song>.from(album.songs)..shuffle();
                              ref.read(queueProvider.notifier).setQueue(queue);
                              ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                              ref.read(isPlayingProvider.notifier).play();
                            },
                          ),
                        ],
                      ),
                    ),
                    ListEntranceAnimation(
                      builder: (context, animation) {
                        return ListView.builder(
                          padding: const EdgeInsets.only(bottom: 150),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: album.songs.length,
                          itemBuilder: (context, index) {
                            final song = album.songs[index];
                            final isPlaying = currentSong?.id == song.id;

                            final listTileWidget = ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${index + 1}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: isPlaying ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                                    fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                              title: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                  color: isPlaying ? theme.colorScheme.primary : null,
                                ),
                              ),
                              subtitle: Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                _formatDuration(song.duration.inMilliseconds),
                                style: theme.textTheme.bodySmall,
                              ),
                              onTap: () {
                                ref.read(queueProvider.notifier).setQueue(album.songs);
                                ref.read(audioPlayerProvider).seek(Duration.zero, index: index);
                                ref.read(isPlayingProvider.notifier).play();
                              },
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
                                child: listTileWidget,
                              ),
                            );
                          },
                        );
                      },
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int? ms) {
    if (ms == null) return '--:--';
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
