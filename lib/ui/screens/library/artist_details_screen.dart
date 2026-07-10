import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/artist_image_widget.dart';
import '../../widgets/smooth_art_widget.dart';
import '../../../state/audio_state.dart';
import '../../../state/smart_library.dart';
import '../../../models/song.dart';
import '../../widgets/list_entrance_animation.dart';

class ArtistDetailsScreen extends ConsumerWidget {
  final SmartArtist artist;

  const ArtistDetailsScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentSong = ref.watch(currentSongProvider);

    // Group songs by album for a clean, organized view
    final Map<String, List<Song>> albumGroups = {};
    for (final song in artist.songs) {
      final albumName = song.album.isNotEmpty ? song.album : 'Unknown Album';
      albumGroups.putIfAbsent(albumName, () => []).add(song);
    }
    // Sort albums alphabetically
    final sortedAlbums = albumGroups.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    return ListEntranceAnimation(
      builder: (context, animation) {
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar.large(
                title: Text(artist.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                flexibleSpace: FlexibleSpaceBar(
                  background: Hero(
                    tag: 'artist_${artist.name}',
                    child: ArtistImageWidget(
                      artistName: artist.name,
                      fallbackId: artist.fallbackImageId,
                      borderRadius: 0,
                      iconSize: 100,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${artist.songs.length} tracks • ${artist.albumNames.length} albums',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatDuration(artist.totalDuration),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.play_arrow_rounded),
                            tooltip: 'Play all',
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              foregroundColor: theme.colorScheme.onPrimaryContainer,
                            ),
                            onPressed: () async {
                              await ref.read(queueProvider.notifier).setQueue(artist.songs);
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
                            onPressed: () async {
                              final shuffled = List<Song>.from(artist.songs)..shuffle();
                              await ref.read(queueProvider.notifier).setQueue(shuffled);
                              ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                              ref.read(isPlayingProvider.notifier).play();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              for (final albumEntry in sortedAlbums) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: SmoothArtWidget(
                            id: albumEntry.value.first.id,
                            size: 100,
                            isMini: true,
                            borderRadius: 8,
                            iconSize: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                albumEntry.key,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${albumEntry.value.length} track${albumEntry.value.length != 1 ? 's' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.play_circle_outline, size: 28),
                          tooltip: 'Play ${albumEntry.key}',
                          color: theme.colorScheme.primary,
                          onPressed: () async {
                            await ref.read(queueProvider.notifier).setQueue(albumEntry.value);
                            ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                            ref.read(isPlayingProvider.notifier).play();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final song = albumEntry.value[index];
                      final isPlaying = currentSong?.id == song.id;

                      final listTileWidget = ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        leading: SizedBox(
                          width: 48,
                          height: 48,
                          child: SmoothArtWidget(
                            id: song.id,
                            isMini: true,
                            size: 150,
                            borderRadius: 8,
                            iconSize: 20,
                          ),
                        ),
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isPlaying ? theme.colorScheme.primary : null,
                            fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          _formatSongDuration(song.duration),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: isPlaying
                            ? Icon(Icons.bar_chart, color: theme.colorScheme.primary, size: 20)
                            : null,
                        onTap: () async {
                          await ref.read(queueProvider.notifier).setQueue(albumEntry.value);
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
                    childCount: albumEntry.value.length,
                  ),
                ),
              ],
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m total';
    return '${minutes}m total';
  }

  String _formatSongDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
