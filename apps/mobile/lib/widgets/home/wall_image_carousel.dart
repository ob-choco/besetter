import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:carousel_slider/carousel_slider.dart';
import '../../providers/images_provider.dart';
import 'wall_card.dart';

class WallImageCarousel extends ConsumerWidget {
  const WallImageCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagesAsync = ref.watch(imagesProvider);

    return imagesAsync.when(
      loading: () => const SizedBox(
        height: 400,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => const SizedBox(
        height: 400,
        child: Center(child: Text('Error loading images')),
      ),
      data: (images) {
        if (images.isEmpty) {
          return _buildEmptyState(context);
        }

        final itemCount = images.length + 1;

        return CarouselSlider.builder(
          itemCount: itemCount,
          itemBuilder: (context, index, realIndex) {
            if (index == images.length) {
              return _buildViewMoreCard(context);
            }
            return WallCard(image: images[index]);
          },
          options: CarouselOptions(
            height: 420,
            enlargeCenterPage: true,
            enlargeFactor: 0.2,
            viewportFraction: 0.85,
            enableInfiniteScroll: false,
            padEnds: true,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No wall photos yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Take a wall photo to get started!',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewMoreCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/images'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, size: 48, color: Colors.grey[600]),
              const SizedBox(height: 12),
              Text(
                'View More',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
