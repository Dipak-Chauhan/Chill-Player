import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/settings_service.dart';

class AudioSettingsScreen extends ConsumerWidget {
  const AudioSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final crossfadeDuration = ref.watch(crossfadeDurationProvider);
    final minDuration = ref.watch(minSongDurationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Audio')),
      body: ListView(
        children: [
          // ── Crossfade Section ──
          _sectionHeader(theme, 'Crossfade'),
          SwitchListTile(
            secondary: const Icon(Icons.shuffle_on_outlined),
            title: const Text('Crossfade playback'),
            subtitle: Text(crossfadeDuration > 0
                ? 'Fade between tracks over ${crossfadeDuration}s'
                : 'Disabled — tracks end abruptly'),
            value: crossfadeDuration > 0,
            onChanged: (enabled) {
              ref.read(crossfadeDurationProvider.notifier)
                  .update(enabled ? 5 : 0);
            },
          ),
          if (crossfadeDuration > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('${crossfadeDuration}s',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      )),
                  Expanded(
                    child: Slider(
                      value: crossfadeDuration.toDouble(),
                      min: 1,
                      max: 12,
                      divisions: 11,
                      label: '${crossfadeDuration}s',
                      onChanged: (val) {
                        ref.read(crossfadeDurationProvider.notifier)
                            .update(val.round());
                      },
                    ),
                  ),
                ],
              ),
            ),

          const Divider(indent: 16, endIndent: 16),

          // ── Library Filter Section ──
          _sectionHeader(theme, 'Library'),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Minimum song duration'),
            subtitle: Text(minDuration == 0
                ? 'Show all songs (no filter)'
                : 'Hide songs shorter than ${minDuration}s'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${minDuration}s',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  )),
            ),
            onTap: () => _showDurationPicker(context, ref, minDuration),
          ),

          const Divider(indent: 16, endIndent: 16),

          // ── Output Section ──
          _sectionHeader(theme, 'Output'),
          ListTile(
            leading: const Icon(Icons.equalizer),
            title: const Text('Gapless playback'),
            subtitle: const Text('Enabled by default — seamless transition between tracks'),
            trailing: Icon(Icons.check_circle, color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _showDurationPicker(BuildContext context, WidgetRef ref, int current) {
    final options = [0, 10, 20, 30, 45, 60, 90, 120];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Text('Minimum song duration',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
              ...options.map((seconds) => RadioListTile<int>(
                    value: seconds,
                    groupValue: current,
                    title: Text(seconds == 0
                        ? 'No filter (show all)'
                        : seconds < 60
                            ? '${seconds} seconds'
                            : '${seconds ~/ 60} minute${seconds >= 120 ? "s" : ""}'),
                    onChanged: (val) {
                      ref.read(minSongDurationProvider.notifier).update(val!);
                      Navigator.pop(ctx);
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
