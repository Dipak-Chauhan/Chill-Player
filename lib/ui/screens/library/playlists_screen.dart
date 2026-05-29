import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/audio_state.dart';
import '../../../models/song.dart';
import '../../../services/settings_service.dart';
import '../../widgets/smooth_art_widget.dart';
import '../../widgets/list_entrance_animation.dart';


// ---------------------------------------------------------------------------
// Playlist Model & Persistence
// ---------------------------------------------------------------------------
class Playlist {
  final String id;
  String name;
  List<int> songIds; // Store song IDs for persistence
  DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songIds': songIds,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as String,
    name: json['name'] as String,
    songIds: (json['songIds'] as List).cast<int>(),
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );
}

class PlaylistsNotifier extends Notifier<List<Playlist>> {
  static const _storageKey = 'user_playlists';

  @override
  List<Playlist> build() {
    // Load synchronously — SharedPreferences is already initialized
    return _loadFromDisk();
  }

  List<Playlist> _loadFromDisk() {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        return (jsonDecode(raw) as List)
            .map((e) => Playlist.fromJson(e))
            .toList();
      } catch (_) {}
    }
    return [];
  }

  Future<void> _saveToDisk() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = jsonEncode(state.map((p) => p.toJson()).toList());
    await prefs.setString(_storageKey, raw);
  }

  void createPlaylist(String name) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    state = [...state, Playlist(id: id, name: name, songIds: [])];
    _saveToDisk();
  }

  void createPlaylistWithSongs(String name, List<int> songIds) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    state = [...state, Playlist(id: id, name: name, songIds: songIds)];
    _saveToDisk();
  }

  void deletePlaylist(String id) {
    state = state.where((p) => p.id != id).toList();
    _saveToDisk();
  }

  void renamePlaylist(String id, String newName) {
    state = [
      for (final p in state)
        if (p.id == id) Playlist(id: p.id, name: newName, songIds: p.songIds, createdAt: p.createdAt)
        else p,
    ];
    _saveToDisk();
  }

  void addSongToPlaylist(String playlistId, int songId) {
    state = [
      for (final p in state)
        if (p.id == playlistId && !p.songIds.contains(songId))
          Playlist(id: p.id, name: p.name, songIds: [...p.songIds, songId], createdAt: p.createdAt)
        else p,
    ];
    _saveToDisk();
  }

  void removeSongFromPlaylist(String playlistId, int songId) {
    state = [
      for (final p in state)
        if (p.id == playlistId)
          Playlist(id: p.id, name: p.name, songIds: p.songIds.where((id) => id != songId).toList(), createdAt: p.createdAt)
        else p,
    ];
    _saveToDisk();
  }
}

final playlistsProvider = NotifierProvider<PlaylistsNotifier, List<Playlist>>(PlaylistsNotifier.new);

// ---------------------------------------------------------------------------
// Playlists Screen
// ---------------------------------------------------------------------------
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final theme = Theme.of(context);
    final topPadding = MediaQuery.of(context).padding.top;

    return ListEntranceAnimation(
      builder: (context, animation) {
        return ListView.builder(
          padding: EdgeInsets.only(top: 80.0 + topPadding + 8.0, bottom: 150.0, left: 16.0, right: 16.0),
          itemCount: playlists.isEmpty ? 2 : playlists.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              // Create playlist button
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _showCreateDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('New Playlist'),
                  ),
                ),
              );
            }

            if (playlists.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: 60.0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.queue_music, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text('No playlists yet', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text('Tap "New Playlist" to create one', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
              );
            }

            final playlistIndex = index - 1;
            final playlist = playlists[playlistIndex];
            final isFirst = playlistIndex == 0;
            final isLast = playlistIndex == playlists.length - 1;

            final shape = RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(isFirst ? 28 : 4),
                bottom: Radius.circular(isLast ? 28 : 4),
              ),
            );

            final cardWidget = Card(
              margin: const EdgeInsets.symmetric(vertical: 2),
              shape: shape,
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHigh,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primaryContainer,
                        theme.colorScheme.tertiaryContainer,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.queue_music, color: theme.colorScheme.onPrimaryContainer),
                ),
                title: Text(
                  playlist.name,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${playlist.songIds.length} track${playlist.songIds.length != 1 ? 's' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') _showRenameDialog(context, ref, playlist);
                    if (value == 'delete') ref.read(playlistsProvider.notifier).deletePlaylist(playlist.id);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
                shape: shape,
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _PlaylistDetailScreen(playlist: playlist),
                  ));
                },
              ),
            );

            final double start = (playlistIndex * 0.04).clamp(0.0, 0.7);
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
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(playlistsProvider.notifier).createPlaylist(name);
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, Playlist playlist) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'New name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(playlistsProvider.notifier).renamePlaylist(playlist.id, name);
                Navigator.pop(context);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Playlist Detail Screen
// ---------------------------------------------------------------------------
class _PlaylistDetailScreen extends ConsumerWidget {
  final Playlist playlist;

  const _PlaylistDetailScreen({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final library = ref.watch(globalLibraryProvider);
    final currentPlaylist = ref.watch(playlistsProvider).firstWhere((p) => p.id == playlist.id, orElse: () => playlist);
    final currentSong = ref.watch(currentSongProvider);

    // Resolve song IDs to actual Song objects
    final songs = <Song>[];
    for (final id in currentPlaylist.songIds) {
      final match = library.where((s) => s.id == id);
      if (match.isNotEmpty) songs.add(match.first);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(currentPlaylist.name),
        actions: [
          if (songs.isNotEmpty) ...[
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
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Add songs',
            onPressed: () => _showAddSongsSheet(context, ref, currentPlaylist),
          ),
        ],
      ),
      body: songs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.music_off, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text('Empty playlist', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => _showAddSongsSheet(context, ref, currentPlaylist),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Songs'),
                  ),
                ],
              ),
            )
          : ListEntranceAnimation(
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

                    final dismissibleWidget = Dismissible(
                      key: ValueKey('pl_${playlist.id}_${song.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                      ),
                      onDismissed: (_) {
                        ref.read(playlistsProvider.notifier).removeSongFromPlaylist(playlist.id, song.id);
                      },
                      child: Card(
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
                        child: dismissibleWidget,
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  void _showAddSongsSheet(BuildContext context, WidgetRef ref, Playlist playlist) {
    final library = ref.read(globalLibraryProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            final theme = Theme.of(context);
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Add Songs', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: library.length,
                      itemBuilder: (context, index) {
                        final song = library[index];
                        final alreadyAdded = playlist.songIds.contains(song.id);

                        return ListTile(
                          leading: SizedBox(
                            width: 40,
                            height: 40,
                            child: SmoothArtWidget(
                              id: song.id,
                              size: 100,
                              isMini: true,
                              borderRadius: 8,
                              iconSize: 16,
                            ),
                          ),
                          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                          trailing: alreadyAdded
                              ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                              : IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () {
                                    ref.read(playlistsProvider.notifier).addSongToPlaylist(playlist.id, song.id);
                                  },
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
