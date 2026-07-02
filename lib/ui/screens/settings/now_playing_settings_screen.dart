import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/settings_service.dart';

class NowPlayingSettingsScreen extends ConsumerWidget {
  const NowPlayingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showSongInfo = ref.watch(showSongInfoProvider);
    final extraControls = ref.watch(extraControlsProvider);
    final showVolumeSlider = ref.watch(showVolumeSliderProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Now playing'),
      ),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Now Playing Theme'),
            subtitle: Text('Material You'),
          ),
          SwitchListTile(
            title: const Text('Show song info'),
            subtitle: const Text('Show song information such as file format, bitrate and frequency in the main player'),
            value: showSongInfo,
            onChanged: (val) => ref.read(showSongInfoProvider.notifier).update(val),
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          SwitchListTile(
            title: const Text('Extra controls'),
            subtitle: const Text('Add previous and forward button in the mini player'),
            value: extraControls,
            onChanged: (val) => ref.read(extraControlsProvider.notifier).update(val),
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          SwitchListTile(
            title: const Text('Show remaining time'),
            subtitle: const Text('Show remaining time instead of duration in the main player'),
            value: false, // mock
            onChanged: (val) {},
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          SwitchListTile(
            title: const Text('Show volume slider'),
            subtitle: const Text('Show volume slider in the main player'),
            value: showVolumeSlider,
            onChanged: (val) => ref.read(showVolumeSliderProvider.notifier).update(val),
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}
