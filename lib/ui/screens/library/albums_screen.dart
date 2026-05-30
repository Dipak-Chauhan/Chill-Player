import 'dart:ui';
import 'package:flutter/material.dart';
import '../../widgets/smooth_art_widget.dart';
import '../../widgets/spring_button.dart';
import 'album_details_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/smart_library.dart';
import '../../widgets/list_entrance_animation.dart';

class AlbumsScreen extends ConsumerWidget {
  const AlbumsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(smartAlbumProvider);

    if (albums.isEmpty) return const Center(child: Text("Nothing found!"));

    final topPadding = MediaQuery.of(context).padding.top;
    return ListEntranceAnimation(
      builder: (context, animation) {
        return GridView.builder(
          padding: EdgeInsets.only(top: 80.0 + topPadding + 16, bottom: 150.0, left: 16.0, right: 16.0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.82, // Unified premium child aspect ratio matching library cards
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            
            final cardWidget = SpringButton(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumDetailsScreen(album: album)));
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
                      // 1. Bottom Layer: Full-Cover Art Background
                      Positioned.fill(
                        child: Hero(
                          tag: 'album_${album.name}',
                          child: SmoothArtWidget(
                            id: album.fallbackImageId,
                            size: 400,
                            borderRadius: 0,
                            iconSize: 40,
                          ),
                        ),
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

                      // 3. Top Layer: Frosted Glass Bottom Panel
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    album.name,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    album.albumArtist.isEmpty ? "Unknown Artist" : album.albumArtist,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.white.withValues(alpha: 0.75),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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

            final double start = (index * 0.04).clamp(0.0, 0.7);
            final double end = (start + 0.30).clamp(0.0, 1.0);
            final itemAnim = CurvedAnimation(
              parent: animation,
              curve: Interval(start, end, curve: Curves.easeOutQuad),
            );

            return FadeTransition(
              opacity: itemAnim,
              child: SlideTransition(
                position: itemAnim.drive(Tween<Offset>(
                  begin: const Offset(0.0, 0.08),
                  end: Offset.zero,
                )),
                child: cardWidget,
              ),
            );
          },
        );
      },
    );
  }
}
