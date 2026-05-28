import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/settings_service.dart';

class ThemesSettingsScreen extends ConsumerWidget {
  const ThemesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final amoledMode = ref.watch(amoledModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Themes & Colors'),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'light', label: Text('Light')),
                ButtonSegment(value: 'dark', label: Text('Dark')),
                ButtonSegment(value: 'system', label: Text('System')),
              ],
              selected: {themeMode},
              onSelectionChanged: (Set<String> newSelection) {
                ref.read(themeModeProvider.notifier).update(newSelection.first);
              },
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Material You themes'),
            subtitle: const Text('Material You custom themes for all android versions.'),
            value: true, 
            onChanged: (val) {},
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          SwitchListTile(
            title: const Text('Use extra dark colors'),
            subtitle: const Text('Use darker colors for small battery savings on AMOLED screens.'),
            value: amoledMode,
            onChanged: (val) => ref.read(amoledModeProvider.notifier).update(val),
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: Text(
              'Live Palette (Dynamic Color)',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildSwatch(context, 'Primary', Theme.of(context).colorScheme.primary),
                  _buildSwatch(context, 'Secondary', Theme.of(context).colorScheme.secondary),
                  _buildSwatch(context, 'Tertiary', Theme.of(context).colorScheme.tertiary),
                  _buildSwatch(context, 'Container', Theme.of(context).colorScheme.primaryContainer),
                  _buildSwatch(context, 'Error', Theme.of(context).colorScheme.error),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwatch(BuildContext context, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: color,
            radius: 24,
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
