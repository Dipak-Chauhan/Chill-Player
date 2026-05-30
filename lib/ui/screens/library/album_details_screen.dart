import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/smooth_art_widget.dart';
import '../../widgets/spring_button.dart';
import '../../../state/audio_state.dart';
import '../../../state/smart_library.dart';
import '../../../models/song.dart';
import '../../../theme/color_provider.dart';
import '../../widgets/list_entrance_animation.dart';

class AlbumDetailsScreen extends ConsumerWidget {
  final SmartAlbum album;

  const AlbumDetailsScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentSong = ref.watch(currentSongProvider);
    final activeColors = ref.watch(currentExtractedColorsProvider);
    final tintColor = activeColors.vibrant;

    return Scaffold(
      body: ListEntranceAnimation(
        builder: (context, animation) {
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 240.0,
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
                        child: Hero(
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
                          padding: const EdgeInsets.only(top: 48, left: 24, right: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                album.name,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                album.albumArtist.isEmpty ? 'Unknown Artist' : album.albumArtist,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${album.songs.length} track${album.songs.length != 1 ? 's' : ''}',
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
              
              // Tactile Stadium Action Buttons
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: SpringButton(
                          onTap: () async {
                            await ref.read(queueProvider.notifier).setQueue(album.songs);
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
                            final queue = List<Song>.from(album.songs)..shuffle();
                            await ref.read(queueProvider.notifier).setQueue(queue);
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

              // Tracks List
              SliverPadding(
                padding: const EdgeInsets.only(top: 8, bottom: 150, left: 16, right: 16),
                sliver: SliverList.builder(
                  itemCount: album.songs.length,
                  itemBuilder: (context, index) {
                    final song = album.songs[index];
                    final isPlaying = currentSong?.id == song.id;

                    final isFirst = index == 0;
                    final isLast = index == album.songs.length - 1;

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

                    final listTileWidget = Card(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      shape: shape,
                      color: theme.colorScheme.surfaceContainerHigh,
                      elevation: 0,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
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
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        trailing: isPlaying
                            ? Icon(Icons.bar_chart, color: theme.colorScheme.primary, size: 20)
                            : Text(
                                _formatDuration(song.duration.inMilliseconds),
                                style: theme.textTheme.bodySmall,
                              ),
                        shape: shape,
                        onTap: () {
                          ref.read(queueProvider.notifier).setQueue(album.songs);
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
                        child: listTileWidget,
                      ),
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

  String _formatDuration(int? ms) {
    if (ms == null) return '--:--';
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
