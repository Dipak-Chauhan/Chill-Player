import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animations/animations.dart';
import '../../state/audio_state.dart';
import '../screens/now_playing_screen.dart';
import 'expand_player_route.dart';
import 'smooth_art_widget.dart';
import '../../services/settings_service.dart';
import '../../services/haptic_service.dart';

class MiniPlayerHero extends ConsumerWidget {
  const MiniPlayerHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();

    // Container transform: the mini-player surface expands into the full Now
    // Playing screen and collapses back into it.
    return OpenContainer(
      tappable: false,
      transitionType: ContainerTransitionType.fade,
      transitionDuration: const Duration(milliseconds: 420),
      closedColor: Colors.transparent,
      openColor: Colors.black,
      middleColor: Colors.black,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(36),
      ),
      clipBehavior: Clip.antiAlias,
      openBuilder: (context, _) => const NowPlayingScreen(),
      closedBuilder: (context, openContainer) =>
          _buildMini(context, ref, song, openContainer),
    );
  }

  Widget _buildMini(
    BuildContext context,
    WidgetRef ref,
    dynamic song,
    VoidCallback open,
  ) {
    final isPlaying = ref.watch(isPlayingProvider);
    final extraControls = ref.watch(extraControlsProvider);

    return GestureDetector(
      onTap: open,
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -300) {
          open();
        } else if (details.primaryVelocity! > 300) {
          HapticService.heavy();
          ref.read(currentSongProvider.notifier).stop();
        }
      },
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -300) {
          HapticService.medium();
          ref.read(audioPlayerProvider).seekToNext();
        } else if (details.primaryVelocity! > 300) {
          HapticService.medium();
          ref.read(audioPlayerProvider).seekToPrevious();
        }
      },
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          height: 72,
          clipBehavior: Clip.antiAlias,
          // Near-opaque frosted surface (no live BackdropFilter) so the mini
          // player is cheap to scroll behind and to morph in the transition.
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  const SizedBox(width: 8),
                  SizedBox(
                    key: miniArtKey,
                    width: 56,
                    height: 56,
                    child: SmoothArtWidget(
                      id: song.id,
                      size: 200,
                      isMini: true,
                      borderRadius: 32,
                      iconSize: 24,
                      isPlaying: isPlaying,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          song.title,
                          key: miniTitleKey,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          song.artist,
                          key: miniArtistKey,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (extraControls)
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      iconSize: 32,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      onPressed: () =>
                          ref.read(audioPlayerProvider).seekToPrevious(),
                    ),
                  IconButton(
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    iconSize: 32,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    onPressed: () =>
                        ref.read(isPlayingProvider.notifier).toggle(),
                  ),
                  if (extraControls)
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      iconSize: 32,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      onPressed: () =>
                          ref.read(audioPlayerProvider).seekToNext(),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Consumer(
                  builder: (context, ref, child) {
                    final position = ref.watch(playbackPositionProvider);
                    final durMs = song.duration.inMilliseconds > 0
                        ? song.duration.inMilliseconds
                        : 1;
                    final progress = (position.inMilliseconds / durMs).clamp(
                      0.0,
                      1.0,
                    );
                    return LinearProgressIndicator(
                      value: progress,
                      minHeight: 2.5,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
