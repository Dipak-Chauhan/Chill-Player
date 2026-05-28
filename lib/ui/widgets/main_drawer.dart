import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'm3_loading_indicator.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/equalizer_screen.dart';
import '../screens/library/playlists_screen.dart';
import '../screens/library/folders_screen.dart';
import '../screens/library/stats_screen.dart';

import '../../state/audio_state.dart';
import '../../services/library_cache_service.dart';
import '../../services/settings_service.dart';
import '../../models/song.dart';

class MainDrawer extends ConsumerWidget {
  const MainDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    
    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              child: Text(
                'Chill Player',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _DrawerItem(icon: Icons.library_music, title: 'Library', isSelected: true),
            _DrawerItem(
              icon: Icons.folder, 
              title: 'Folders',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const FoldersScreen()));
              },
            ),
            _DrawerItem(
              icon: Icons.queue_music, 
              title: 'Playlists',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PlaylistsScreen()));
              },
            ),
            _DrawerItem(
              icon: Icons.equalizer, 
              title: 'Equalizer',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerScreen()));
              },
            ),
            _DrawerItem(
              icon: Icons.bar_chart, 
              title: 'Stats',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()));
              },
            ),
            _DrawerItem(
              icon: Icons.sync, 
              title: 'Scan media',
              onTap: () {
                Navigator.pop(context); // Close drawer
                showDialog(
                  context: context, 
                  barrierDismissible: false,
                  builder: (_) => const _ScanMediaDialog(),
                );
              },
            ),
            const Divider(indent: 24, endIndent: 24, height: 32),
            _DrawerItem(
              icon: Icons.settings, 
              title: 'Settings',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),
            _DrawerItem(icon: Icons.info_outline, title: 'About'),
            _DrawerItem(icon: Icons.card_giftcard, title: 'Donate'),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final VoidCallback? onTap;

  const _DrawerItem({
    required this.icon,
    required this.title,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28), // M3 expressive pill shape
          onTap: onTap ?? () {},
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanMediaDialog extends ConsumerStatefulWidget {
  const _ScanMediaDialog();

  @override
  ConsumerState<_ScanMediaDialog> createState() => _ScanMediaDialogState();
}

class _ScanMediaDialogState extends ConsumerState<_ScanMediaDialog> {
  double _progress = 0.0;
  String _message = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _update(double p, String m) {
    if (mounted) {
      setState(() {
        _progress = p;
        _message = m;
      });
    }
  }

  Future<void> _startScan() async {
    try {
      _update(0.1, "Checking permissions...");
      final audioQuery = OnAudioQuery();
      final hasPermission = await audioQuery.checkAndRequest(retryRequest: true);
      if (hasPermission) {
        
        // Let UI update
        await Future.delayed(const Duration(milliseconds: 300));

        _update(0.3, "Extracting library data...");
        final songs = await audioQuery.querySongs(
          sortType: null,
          orderType: OrderType.ASC_OR_SMALLER,
          uriType: UriType.EXTERNAL,
          ignoreCase: true,
        );

        _update(0.6, "Processing audio files...");
        List<Song> validSongs = [];
        if (songs.isNotEmpty) {
          validSongs = songs.where((s) => (s.duration ?? 0) > 0 && s.isMusic == true).map((s) {
            final rawMap = s.getMap;
            final albumArtist = (rawMap['album_artist'] as String?) ?? '';
            return Song(
              id: s.id,
              title: s.title,
              artist: s.artist ?? 'Unknown Artist',
              album: s.album ?? 'Unknown Album',
              albumArtist: albumArtist,
              genre: s.genre ?? '',
              uri: s.data,
              duration: Duration(milliseconds: s.duration ?? 0),
            );
          }).toList();
        }

        _update(0.9, "Writing cache to disk...");
        final prefs = ref.read(sharedPreferencesProvider);
        await LibraryCacheService.saveLibrary(prefs, validSongs);
        ref.read(globalLibraryProvider.notifier).setLibrary(validSongs);

        _update(1.0, "Done!");
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Files synced successfully"),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const M3LoadingIndicator(size: 60),
            const SizedBox(height: 24),
            Text(
              "${(_progress * 100).toInt()}%",
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

