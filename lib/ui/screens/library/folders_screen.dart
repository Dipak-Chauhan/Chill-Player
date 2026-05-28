import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/audio_state.dart';
import '../../../models/song.dart';
import '../../widgets/smooth_art_widget.dart';
import '../../widgets/m3_loading_indicator.dart';
import '../../widgets/list_entrance_animation.dart';

class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(globalLibraryProvider);
    final theme = Theme.of(context);
    
    if (library.isEmpty) {
      return const Center(child: M3LoadingIndicator());
    }

    // Group songs by folder path
    final Map<String, List<Song>> folderMap = {};
    for (final song in library) {
      if (song.uri.isNotEmpty) {
        final lastSlash = song.uri.lastIndexOf('/');
        if (lastSlash != -1) {
          final folder = song.uri.substring(0, lastSlash);
          folderMap.putIfAbsent(folder, () => []).add(song);
        }
      }
    }

    final folders = folderMap.entries.toList()
      ..sort((a, b) => a.key.split('/').last.toLowerCase().compareTo(b.key.split('/').last.toLowerCase()));

    return folders.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_off, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('No folders found', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          )
        : ListEntranceAnimation(
            builder: (context, animation) {
              return ListView.builder(
                itemCount: folders.length,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemBuilder: (context, index) {
                  final entry = folders[index];
                  final folderName = entry.key.split('/').last;
                  final songs = entry.value;

                  final cardWidget = Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    color: theme.colorScheme.surfaceContainerHigh,
                    elevation: 0,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.folder, color: theme.colorScheme.primary),
                      ),
                      title: Text(
                        folderName,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${songs.length} track${songs.length != 1 ? 's' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => _FolderDetailScreen(
                            folderName: folderName,
                            folderPath: entry.key,
                            songs: songs,
                          ),
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
  }
}

class _FolderDetailScreen extends ConsumerWidget {
  final String folderName;
  final String folderPath;
  final List<Song> songs;

  const _FolderDetailScreen({
    required this.folderName,
    required this.folderPath,
    required this.songs,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentSong = ref.watch(currentSongProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(folderName),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Play all',
            onPressed: () async {
              await ref.read(queueProvider.notifier).setQueue(songs);
              ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
              ref.read(isPlayingProvider.notifier).play();
            },
          ),
          IconButton(
            icon: const Icon(Icons.shuffle),
            tooltip: 'Shuffle play',
            onPressed: () async {
              final shuffled = List<Song>.from(songs)..shuffle();
              await ref.read(queueProvider.notifier).setQueue(shuffled);
              ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
              ref.read(isPlayingProvider.notifier).play();
            },
          ),
        ],
      ),
      body: ListEntranceAnimation(
        builder: (context, animation) {
          return ListView.builder(
            itemCount: songs.length,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemBuilder: (context, index) {
              final song = songs[index];
              final isPlaying = currentSong?.id == song.id;

              final listTileWidget = ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
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
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isPlaying
                    ? Icon(Icons.bar_chart, color: theme.colorScheme.primary, size: 20)
                    : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () async {
                  await ref.read(queueProvider.notifier).setQueue(songs);
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
    );
  }
}
