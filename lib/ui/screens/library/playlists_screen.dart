import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/audio_state.dart';
import '../../../models/song.dart';
import '../../../services/settings_service.dart';
import '../../../theme/color_provider.dart';
import '../../widgets/smooth_art_widget.dart';
import '../../widgets/spring_button.dart';
import '../../widgets/frosted_glass.dart';
import '../../widgets/list_entrance_animation.dart';

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

class _PlaylistCollage extends StatelessWidget {
  final List<int> songIds;
  final double borderRadius;

  const _PlaylistCollage({required this.songIds, this.borderRadius = 16.0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = songIds.length;

    if (count == 0) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Center(
          child: Icon(
            Icons.queue_music_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      );
    }

    if (count == 1) {
      return SmoothArtWidget(
        id: songIds[0],
        size: 250,
        borderRadius: borderRadius,
        iconSize: 32,
      );
    }

    if (count == 2) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Row(
          children: [
            Expanded(
              child: SmoothArtWidget(
                id: songIds[0],
                size: 250,
                borderRadius: 0,
                iconSize: 24,
              ),
            ),
            const SizedBox(width: 1),
            Expanded(
              child: SmoothArtWidget(
                id: songIds[1],
                size: 250,
                borderRadius: 0,
                iconSize: 24,
              ),
            ),
          ],
        ),
      );
    }

    final displayIds = songIds.take(4).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: SmoothArtWidget(
                    id: displayIds[0],
                    size: 150,
                    borderRadius: 0,
                    iconSize: 18,
                  ),
                ),
                const SizedBox(width: 1),
                Expanded(
                  child: SmoothArtWidget(
                    id: displayIds[1],
                    size: 150,
                    borderRadius: 0,
                    iconSize: 18,
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
                    size: 150,
                    borderRadius: 0,
                    iconSize: 18,
                  ),
                ),
                const SizedBox(width: 1),
                Expanded(
                  child: displayIds.length > 3
                      ? SmoothArtWidget(
                          id: displayIds[3],
                          size: 150,
                          borderRadius: 0,
                          iconSize: 18,
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          child: Icon(
                            Icons.music_note,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                            size: 18,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Playlists Screen
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final theme = Theme.of(context);
    final topPadding = MediaQuery.of(context).padding.top;

    return ListEntranceAnimation(
      builder: (context, animation) {
        return GridView.builder(
          padding: EdgeInsets.only(top: 80.0 + topPadding + 8.0, bottom: 150.0, left: 16.0, right: 16.0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.82,
          ),
          itemCount: playlists.length + 1,
          itemBuilder: (context, index) {
            final double start = (index * 0.04).clamp(0.0, 0.7);
            final double end = (start + 0.30).clamp(0.0, 1.0);
            final itemAnim = CurvedAnimation(
              parent: animation,
              curve: Interval(start, end, curve: Curves.easeOutQuad),
            );

            Widget gridCell;

            if (index == 0) {
              // Create playlist trigger card (Frosted Glass Style)
              gridCell = SpringButton(
                onTap: () => _showCreateDialog(context, ref),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: FrostedGlass(
                      borderRadius: BorderRadius.circular(24),
                      tintOpacity: 0.45,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(Icons.add, color: theme.colorScheme.primary, size: 28),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'New Playlist',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            } else {
              final playlistIndex = index - 1;
              final playlist = playlists[playlistIndex];

              gridCell = SpringButton(
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _PlaylistDetailScreen(playlist: playlist),
                  ));
                },
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
                        // 1. Bottom Layer: Dynamic Cover Collage
                        Positioned.fill(
                          child: _PlaylistCollage(songIds: playlist.songIds, borderRadius: 0),
                        ),

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



                        // 4. Top Layer: Frosted Glass Bottom Panel
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
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            playlist.name,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              fontSize: 15,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${playlist.songIds.length} track${playlist.songIds.length != 1 ? 's' : ''}',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: Colors.white.withValues(alpha: 0.75),
                                              fontWeight: FontWeight.w500,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, size: 20, color: Colors.white70),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onSelected: (value) {
                                        if (value == 'rename') _showRenameDialog(context, ref, playlist);
                                        if (value == 'delete') ref.read(playlistsProvider.notifier).deletePlaylist(playlist.id);
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(value: 'rename', child: Text('Rename')),
                                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                      ],
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

            return FadeTransition(
              opacity: itemAnim,
              child: SlideTransition(
                position: itemAnim.drive(Tween<Offset>(
                  begin: const Offset(0.0, 0.08),
                  end: Offset.zero,
                )),
                child: gridCell,
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

class _PlaylistDetailScreen extends ConsumerWidget {
  final Playlist playlist;

  const _PlaylistDetailScreen({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final library = ref.watch(globalLibraryProvider);
    final currentPlaylist = ref.watch(playlistsProvider).firstWhere((p) => p.id == playlist.id, orElse: () => playlist);
    final currentSong = ref.watch(currentSongProvider);
    final activeColors = ref.watch(currentExtractedColorsProvider);
    final tintColor = activeColors.vibrant;

    // Resolve song IDs to actual Song objects
    final songs = <Song>[];
    for (final id in currentPlaylist.songIds) {
      final match = library.where((s) => s.id == id);
      if (match.isNotEmpty) songs.add(match.first);
    }

    return Scaffold(
      body: songs.isEmpty
          ? Scaffold(
              appBar: AppBar(
                title: Text(currentPlaylist.name),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.playlist_add),
                    tooltip: 'Add songs',
                    onPressed: () => _showAddSongsSheet(context, ref, currentPlaylist),
                  ),
                ],
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.music_off_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
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
              ),
            )
          : ListEntranceAnimation(
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
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.playlist_add, color: Colors.white),
                          tooltip: 'Add songs',
                          onPressed: () => _showAddSongsSheet(context, ref, currentPlaylist),
                        ),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        stretchModes: const [
                          StretchMode.zoomBackground,
                          StretchMode.blurBackground,
                        ],
                        background: Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: _PlaylistCollage(songIds: currentPlaylist.songIds, borderRadius: 0),
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
                                      currentPlaylist.name,
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

                          final dismissibleWidget = Dismissible(
                            key: ValueKey('pl_${playlist.id}_${song.id}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(isFirst ? 24 : 4),
                                  bottom: Radius.circular(isLast ? 24 : 4),
                                ),
                              ),
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
                            ),
                          );

                          return FadeTransition(
                            opacity: itemAnim,
                            child: SlideTransition(
                              position: itemAnim.drive(Tween<Offset>(
                                begin: const Offset(0.0, 0.08),
                                end: Offset.zero,
                              )),
                              child: dismissibleWidget,
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

  void _showAddSongsSheet(BuildContext context, WidgetRef ref, Playlist playlist) {
    final library = ref.read(globalLibraryProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              expand: false,
              builder: (context, scrollController) {
                final theme = Theme.of(context);
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  child: FrostedGlass(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    tintOpacity: 0.6,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Text(
                              'Add Songs',
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          _SearchInputBar(
                            onChanged: (val) {
                              setState(() {}); // refresh sheet to re-apply filter inside state
                            },
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Consumer(
                              builder: (context, ref, child) {
                                final searchVal = _SearchInputBar.currentQuery;
                                final filteredList = library.where((song) {
                                  return song.title.toLowerCase().contains(searchVal) ||
                                         song.artist.toLowerCase().contains(searchVal);
                                }).toList();

                                return ListView.builder(
                                  controller: scrollController,
                                  itemCount: filteredList.length,
                                  itemBuilder: (context, index) {
                                    final song = filteredList[index];
                                    final currentPlaylistState = ref.watch(playlistsProvider)
                                        .firstWhere((p) => p.id == playlist.id, orElse: () => playlist);
                                    final alreadyAdded = currentPlaylistState.songIds.contains(song.id);

                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                      leading: SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: SmoothArtWidget(
                                          id: song.id,
                                          size: 100,
                                          isMini: true,
                                          borderRadius: 8,
                                          iconSize: 18,
                                        ),
                                      ),
                                      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      subtitle: Text(
                                        song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                        ),
                                      ),
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
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _SearchInputBar extends StatefulWidget {
  final ValueChanged<String> onChanged;
  static String currentQuery = '';

  const _SearchInputBar({required this.onChanged});

  @override
  State<_SearchInputBar> createState() => _SearchInputBarState();
}

class _SearchInputBarState extends State<_SearchInputBar> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _SearchInputBar.currentQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _controller,
        onChanged: (val) {
          _SearchInputBar.currentQuery = val.trim().toLowerCase();
          widget.onChanged(val);
        },
        decoration: InputDecoration(
          hintText: 'Search library...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _controller.clear();
                      _SearchInputBar.currentQuery = '';
                    });
                    widget.onChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }
}
