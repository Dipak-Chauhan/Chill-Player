import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/artist_image_widget.dart';
import '../../widgets/m3_loading_indicator.dart';
import '../../../state/smart_library.dart';
import 'artist_details_screen.dart';
import '../../widgets/list_entrance_animation.dart';

class ArtistsScreen extends ConsumerWidget {
  const ArtistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(smartArtistProvider);

    if (artists.isEmpty) {
      return const Center(child: M3LoadingIndicator(size: 40));
    }

    return ListEntranceAnimation(
      builder: (context, animation) {
        return GridView.builder(
          padding: const EdgeInsets.only(top: 16, bottom: 150, left: 16, right: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.8,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
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
                child: Material(
                  color: Theme.of(context).cardColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  elevation: 0,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistDetailsScreen(artist: artist)));
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ArtistImageWidget(
                              artistName: artist.name,
                              fallbackId: artist.fallbackImageId,
                              borderRadius: 16,
                              iconSize: 50,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  artist.name,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "${artist.albumNames.length} Albums | ${artist.songs.length} Tracks",
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
