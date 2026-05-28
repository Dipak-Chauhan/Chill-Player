import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/audio_state.dart';
import '../widgets/smooth_art_widget.dart';

class QueueScreen extends ConsumerWidget {
  final EdgeInsets systemPadding;

  const QueueScreen({super.key, required this.systemPadding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final topPadding = systemPadding.top;

    final queue = ref.watch(queueProvider);
    final currentSong = ref.watch(currentSongProvider);
    final audioPlayer = ref.read(audioPlayerProvider);

    return Container(
      margin: EdgeInsets.only(top: topPadding + 20),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                'Up Next',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${queue.length} tracks',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: queue.length,
              physics: const BouncingScrollPhysics(),
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final elevation = Tween<double>(begin: 0, end: 8).animate(animation).value;
                    return Material(
                      elevation: elevation,
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      child: child,
                    );
                  },
                  child: child,
                );
              },
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                ref.read(queueProvider.notifier).reorder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final song = queue[index];
                final isPlayingThis = currentSong?.id == song.id;

                return Dismissible(
                  key: ValueKey('queue_${song.id}_$index'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                  ),
                  onDismissed: (_) {
                    ref.read(queueProvider.notifier).removeAt(index);
                  },
                  child: InkWell(
                    onTap: () {
                      audioPlayer.seek(Duration.zero, index: index);
                      ref.read(isPlayingProvider.notifier).play();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        decoration: BoxDecoration(
                          color: isPlayingThis
                              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: SmoothArtWidget(
                                id: song.id,
                                size: 150,
                                isMini: true,
                                borderRadius: 8,
                                iconSize: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    song.title,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: isPlayingThis ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                      fontWeight: isPlayingThis ? FontWeight.bold : FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    song.artist,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (isPlayingThis)
                              Icon(Icons.bar_chart, color: theme.colorScheme.primary)
                            else
                              ReorderableDragStartListener(
                                index: index,
                                child: Icon(Icons.drag_handle, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
