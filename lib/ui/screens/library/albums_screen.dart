import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../widgets/smooth_art_widget.dart';
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
            childAspectRatio: 0.70, // Slightly taller to fit text comfortably
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            final cardWidget = Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: Theme.of(context).colorScheme.surfaceContainer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumDetailsScreen(album: album)));
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 1.0,
                      child: Hero(
                        tag: 'album_${album.name}',
                        child: SmoothArtWidget(
                          id: album.fallbackImageId,
                          size: 400,
                          isMini: true,
                          artworkType: ArtworkType.AUDIO,
                          borderRadius: 0,
                          iconSize: 50,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            album.name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            album.albumArtist.isEmpty ? "Unknown Artist" : album.albumArtist,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
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
