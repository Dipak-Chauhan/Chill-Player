import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../state/audio_state.dart';
import '../screens/now_playing_screen.dart';
import 'smooth_art_widget.dart';
import '../../services/settings_service.dart';
import '../../services/haptic_service.dart';

class MiniPlayerHero extends ConsumerWidget {
  const MiniPlayerHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final extraControls = ref.watch(extraControlsProvider);

    if (song == null) return const SizedBox.shrink();

    void openNowPlaying() {
      Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          reverseTransitionDuration: const Duration(milliseconds: 450),
          opaque: false,
          pageBuilder: (context, animation, secondaryAnimation) {
            return const NowPlayingScreen();
          },
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOutCubicEmphasized,
                  reverseCurve: Curves.easeInOutCubicEmphasized,
                );

                return FadeTransition(opacity: curved, child: child);
              },
        ),
      );
    }

    return GestureDetector(
      onTap: openNowPlaying,
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -300) {
          openNowPlaying();
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
      child: Container(
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36))),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                      Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.50),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.5,
                  ),
                ),
                child: Stack(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: Hero(
                            tag: 'player_art_hero',
                            child: SmoothArtWidget(
                              id: song.id,
                              size: 200,
                              isMini: true,
                              borderRadius: 32, // Morph smoothly
                              iconSize: 24,
                              isPlaying: isPlaying,
                            ),
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
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                song.artist,
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            onPressed: () {
                              ref.read(audioPlayerProvider).seekToPrevious();
                            },
                          ),
                        IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                          iconSize: 32,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          onPressed: () {
                            ref.read(isPlayingProvider.notifier).toggle();
                          },
                        ),
                        if (extraControls)
                          IconButton(
                            icon: const Icon(Icons.skip_next),
                            iconSize: 32,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            onPressed: () {
                              ref.read(audioPlayerProvider).seekToNext();
                            },
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
                          final posMs = position.inMilliseconds;
                          final progress = (posMs / durMs).clamp(0.0, 1.0);

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
                ), // Stack
              ), // Container (inner decoration)
            ), // BackdropFilter
          ), // ClipPath
        ), // Material
      ), // Container (boxShadow)
    ).animate().fadeIn(duration: 400.ms, curve: Curves.easeOut).slideY(begin: 1, duration: 400.ms, curve: Curves.easeOutExpo);
  }
}
