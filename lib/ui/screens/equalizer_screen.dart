import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../state/audio_state.dart';
import '../widgets/m3_loading_indicator.dart';
import 'dart:math';

class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equalizer = ref.watch(androidEqualizerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
      ),
      body: FutureBuilder<AndroidEqualizerParameters>(
        future: equalizer.parameters,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: M3LoadingIndicator(size: 40));
          }

          final parameters = snapshot.data!;
          return StreamBuilder<bool>(
            stream: equalizer.enabledStream,
            initialData: equalizer.enabled,
            builder: (context, enabledSnapshot) {
              final isEnabled = enabledSnapshot.data ?? false;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: FilterChip(
                      selected: isEnabled,
                      label: Text(isEnabled ? 'Equalizer ON' : 'Equalizer OFF', style: const TextStyle(fontWeight: FontWeight.bold)),
                      onSelected: (val) => equalizer.setEnabled(val),
                      showCheckmark: false,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: StadiumBorder(side: BorderSide(color: Theme.of(context).colorScheme.primary)),
                      selectedColor: Theme.of(context).colorScheme.primaryContainer,
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(parameters.bands.length, (index) {
                        final band = parameters.bands[index];
                        return Expanded(
                          child: Column(
                            children: [
                              StreamBuilder<double>(
                                stream: band.gainStream,
                                initialData: band.gain,
                                builder: (context, gainSnapshot) {
                                  final gain = gainSnapshot.data ?? 0.0;
                                  return Expanded(
                                    child: RotatedBox(
                                      quarterTurns: 3,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 12, // Thicker tracks for M3 feel
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10, pressedElevation: 8),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                                          activeTrackColor: Theme.of(context).colorScheme.primary,
                                          inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        ),
                                        child: Slider(
                                          min: parameters.minDecibels,
                                          max: parameters.maxDecibels,
                                          value: max(parameters.minDecibels, min(parameters.maxDecibels, gain)),
                                          onChanged: isEnabled ? (val) {
                                            band.setGain(val);
                                          } : null,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '${(band.centerFrequency / 1000).round()} Hz',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
