import 'package:flutter/material.dart';

class PlaylistsSettingsScreen extends StatelessWidget {
  const PlaylistsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Playlist export path'),
            subtitle: const Text('/storage/emulated/0/Music/Playlists'),
            onTap: () {},
          ),
          ListTile(
            title: const Text('Last added playlist interval'),
            subtitle: const Text('Past three months'),
            onTap: () {},
          ),
          ListTile(
            title: const Text('Recently played playlist interval'),
            subtitle: const Text('Past three months'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
