import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/audio_state.dart';
import '../../models/song.dart';
import '../../services/haptic_service.dart';
import '../widgets/smooth_art_widget.dart';
import '../widgets/frosted_glass.dart';
import 'library/playlists_screen.dart';
import 'package:just_audio/just_audio.dart';

class QueueScreen extends ConsumerStatefulWidget {
  final EdgeInsets systemPadding;

  const QueueScreen({super.key, required this.systemPadding});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    
    // Auto-scroll to currently playing song after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentSong();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentSong() {
    if (!mounted) return;
    final queue = ref.read(queueProvider);
    final currentSong = ref.read(currentSongProvider);
    if (currentSong != null) {
      final index = queue.indexWhere((s) => s.id == currentSong.id);
      if (index >= 0) {
        // Approximate height of each item is 64.0 (including padding/margins)
        final targetOffset = (index * 64.0).clamp(0.0, _scrollController.position.maxScrollExtent);
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }
  }

  void _showSavePlaylistDialog(BuildContext context, WidgetRef ref, List<Song> queue) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Queue as Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final songIds = queue.map((s) => s.id).toList();
                ref.read(playlistsProvider.notifier).createPlaylistWithSongs(name, songIds);
                Navigator.pop(context);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Saved queue as playlist "$name"'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmClearQueue(BuildContext context, WidgetRef ref, List<Song> queue) {
    if (queue.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Queue?'),
        content: const Text('This will stop playback and empty your current queue. You can undo this action instantly.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close bottom sheet since queue is empty now
              
              final oldQueue = List<Song>.from(queue);
              final player = ref.read(audioPlayerProvider);
              final oldIndex = player.currentIndex;
              final oldPosition = player.position;

              // Stop and clear
              await ref.read(currentSongProvider.notifier).stop();

              // Show snackbar with Undo
              if (context.mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Queue cleared'),
                    behavior: SnackBarBehavior.floating,
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () async {
                        await ref.read(queueProvider.notifier).setQueue(
                          oldQueue,
                          initialIndex: oldIndex,
                          initialPosition: oldPosition,
                        );
                        if (oldIndex != null) {
                          ref.read(isPlayingProvider.notifier).play();
                        }
                      },
                    ),
                  ),
                );
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive 
              ? theme.colorScheme.primaryContainer 
              : (isDestructive ? theme.colorScheme.errorContainer.withValues(alpha: 0.15) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive 
                ? theme.colorScheme.primary.withValues(alpha: 0.3) 
                : (isDestructive ? theme.colorScheme.error.withValues(alpha: 0.2) : Colors.transparent),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive 
                  ? theme.colorScheme.primary 
                  : (isDestructive ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isActive 
                    ? theme.colorScheme.primary 
                    : (isDestructive ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant),
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPadding = widget.systemPadding.top;

    final queue = ref.watch(queueProvider);
    final currentSong = ref.watch(currentSongProvider);
    final audioPlayer = ref.read(audioPlayerProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final isShuffle = ref.watch(shuffleModeProvider);
    final loopMode = ref.watch(loopModeProvider);

    return Padding(
      padding: EdgeInsets.only(top: topPadding + 20),
      child: FrostedGlass(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        tintOpacity: 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.09),
              width: 0.8,
            ),
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
              const SizedBox(height: 12),
              // Horizontally scrollable Action Buttons Bar
              if (queue.isNotEmpty) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildHeaderActionChip(
                        context,
                        icon: Icons.shuffle,
                        label: 'Shuffle',
                        isActive: isShuffle,
                        onTap: () {
                          ref.read(shuffleModeProvider.notifier).toggle();
                          HapticService.medium();
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildHeaderActionChip(
                        context,
                        icon: loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                        label: loopMode == LoopMode.off 
                            ? 'Repeat Off' 
                            : (loopMode == LoopMode.one ? 'Repeat One' : 'Repeat All'),
                        isActive: loopMode != LoopMode.off,
                        onTap: () {
                          ref.read(loopModeProvider.notifier).toggle();
                          HapticService.medium();
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildHeaderActionChip(
                        context,
                        icon: Icons.playlist_add,
                        label: 'Save Playlist',
                        isActive: false,
                        onTap: () {
                          HapticService.medium();
                          _showSavePlaylistDialog(context, ref, queue);
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildHeaderActionChip(
                        context,
                        icon: Icons.clear_all,
                        label: 'Clear Queue',
                        isActive: false,
                        isDestructive: true,
                        onTap: () {
                          HapticService.heavy();
                          _confirmClearQueue(context, ref, queue);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: queue.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.queue_music,
                              size: 64,
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Your queue is empty',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Play some music from your library to start your queue',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        scrollController: _scrollController,
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
                                child: Transform.translate(
                                  offset: const Offset(0, 3.0),
                                  child: child!,
                                ),
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
                            key: ValueKey('queue_${song.id}'),
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
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: isPlayingThis
                                        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                    border: isPlayingThis
                                        ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4), width: 1.5)
                                        : Border.all(color: Colors.transparent, width: 1.5),
                                    boxShadow: isPlayingThis
                                        ? [
                                            BoxShadow(
                                              color: theme.colorScheme.primary.withValues(alpha: 0.08),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: Stack(
                                          children: [
                                            Positioned.fill(
                                              child: SmoothArtWidget(
                                                id: song.id,
                                                size: 150,
                                                isMini: true,
                                                borderRadius: 8,
                                                iconSize: 24,
                                              ),
                                            ),
                                            if (isPlayingThis)
                                              Positioned.fill(
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withValues(alpha: 0.4),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Center(
                                                    child: MiniVisualizer(
                                                      color: Colors.white,
                                                      isPlaying: isPlaying,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    song.title,
                                                    style: theme.textTheme.titleMedium?.copyWith(
                                                      color: isPlayingThis ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                                      fontWeight: isPlayingThis ? FontWeight.bold : FontWeight.w500,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isPlayingThis) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      'NOW PLAYING',
                                                      style: theme.textTheme.labelSmall?.copyWith(
                                                        color: theme.colorScheme.primary,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 9,
                                                  ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 2),
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
                                        const SizedBox(width: 8),
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Icon(
                                              Icons.drag_handle,
                                              color: isPlayingThis
                                                  ? theme.colorScheme.primary.withValues(alpha: 0.6)
                                                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                            ),
                                          ),
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated Mini Music Visualizer Widget
// ---------------------------------------------------------------------------
class MiniVisualizer extends StatefulWidget {
  final Color color;
  final bool isPlaying;

  const MiniVisualizer({
    super.key,
    required this.color,
    required this.isPlaying,
  });

  @override
  State<MiniVisualizer> createState() => _MiniVisualizerState();
}

class _MiniVisualizerState extends State<MiniVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _speeds = [0.6, 1.2, 0.9, 0.7];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant MiniVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (index) {
            double factor = 0.25;
            if (widget.isPlaying) {
              final progress = _controller.value * 2 * math.pi * _speeds[index];
              factor = (math.sin(progress).abs() * 0.7) + 0.3; // between 0.3 and 1.0
            }
            return Container(
              width: 3.0,
              height: 16.0 * factor,
              margin: const EdgeInsets.symmetric(horizontal: 1.0),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        );
      },
    );
  }
}
