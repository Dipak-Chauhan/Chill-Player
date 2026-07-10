import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/listening_stats_service.dart';
import '../../../state/audio_state.dart';
import '../../../models/song.dart';
import '../../widgets/smooth_art_widget.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(listeningStatsProvider);
    final library = ref.watch(globalLibraryProvider);
    final theme = Theme.of(context);

    // Build top played songs list
    final topPlayedIds = stats.topPlayed(limit: 10);
    final topPlayedSongs = <Song>[];
    for (final id in topPlayedIds) {
      final match = library.where((s) => s.id == id);
      if (match.isNotEmpty) topPlayedSongs.add(match.first);
    }

    // Build recently played songs list
    final recentIds = stats.recentlyPlayed(limit: 10);
    final recentSongs = <Song>[];
    for (final id in recentIds) {
      final match = library.where((s) => s.id == id);
      if (match.isNotEmpty) recentSongs.add(match.first);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Listening Stats')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Row(
            children: [
              Expanded(child: _StatCard(
                icon: Icons.headphones,
                label: 'Time Listened',
                value: stats.totalListenedFormatted,
                color: theme.colorScheme.primaryContainer,
              )),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                icon: Icons.music_note,
                label: 'Songs Played',
                value: stats.totalSongsPlayed.toString(),
                color: theme.colorScheme.secondaryContainer,
              )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _StatCard(
                icon: Icons.library_music,
                label: 'Library Size',
                value: library.length.toString(),
                color: theme.colorScheme.tertiaryContainer,
              )),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                icon: Icons.star,
                label: 'Unique Tracks',
                value: stats.playCounts.length.toString(),
                color: theme.colorScheme.primaryContainer,
              )),
            ],
          ),

          const SizedBox(height: 24),

          if (topPlayedSongs.isNotEmpty) ...[
            Text(
              'Most Played',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...topPlayedSongs.asMap().entries.map((entry) {
              final index = entry.key;
              final song = entry.value;
              final count = stats.playCounts[song.id] ?? 0;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: index < 3 ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
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
                  ],
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count plays',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () async {
                  await ref.read(queueProvider.notifier).setQueue([song]);
                  ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                  ref.read(isPlayingProvider.notifier).play();
                },
              );
            }),
          ],

          const SizedBox(height: 24),

          if (recentSongs.isNotEmpty) ...[
            Text(
              'Recently Played',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...recentSongs.map((song) {
              final lastMs = stats.lastPlayed[song.id] ?? 0;
              final ago = _timeAgo(DateTime.fromMillisecondsSinceEpoch(lastMs));

              return ListTile(
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                trailing: Text(
                  ago,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () async {
                  await ref.read(queueProvider.notifier).setQueue([song]);
                  ref.read(audioPlayerProvider).seek(Duration.zero, index: 0);
                  ref.read(isPlayingProvider.notifier).play();
                },
              );
            }),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: theme.colorScheme.onSurface),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
