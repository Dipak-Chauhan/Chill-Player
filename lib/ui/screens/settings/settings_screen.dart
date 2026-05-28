import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'themes_settings_screen.dart';
import 'now_playing_settings_screen.dart';
import 'playlists_settings_screen.dart';
import 'audio_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24, top: 8),
        children: [
          _buildSettingCard(
            context,
            icon: Icons.palette_outlined,
            title: 'Themes & Colors',
            subtitle: 'Change theme, accent color and highlight color',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemesSettingsScreen())),
          ),
          _buildSettingCard(
            context,
            icon: Icons.play_arrow_outlined,
            title: 'Now playing',
            subtitle: 'Themes, extra controls, display content, lockscreen',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NowPlayingSettingsScreen())),
          ),
          _buildSettingCard(
            context,
            icon: Icons.category_outlined,
            title: 'Library',
            subtitle: 'Multiple artists and genres, Filters, navigation',
            onTap: () {},
          ),
          _buildSettingCard(
            context,
            icon: Icons.image_outlined,
            title: 'Images',
            subtitle: 'Enable image caching, metadata download etc',
            onTap: () {},
          ),
          _buildSettingCard(
            context,
            icon: Icons.music_note_outlined,
            title: 'Audio',
            subtitle: 'Crossfade, minimum duration, gapless playback',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioSettingsScreen())),
          ),
          _buildSettingCard(
            context,
            icon: Icons.queue_music_outlined,
            title: 'Playlists',
            subtitle: 'Recently added and recently played playlist duration, import and export',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlaylistsSettingsScreen())),
          ),
        ].animate(interval: 50.ms).fadeIn(duration: 300.ms).slideX(begin: 0.1, curve: Curves.easeOutQuad),
      ),
    );
  }

  Widget _buildSettingCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
