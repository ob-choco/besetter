import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../providers/images_provider.dart';
import 'wall_mini_card.dart';

class WallImageCarousel extends ConsumerWidget {
  const WallImageCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagesAsync = ref.watch(imagesProvider);

    return imagesAsync.when(
      loading: () => const SizedBox(
        height: 296,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => SizedBox(
        height: 296,
        child: Center(child: Text(AppLocalizations.of(context)!.errorLoadingImages)),
      ),
      data: (images) {
        if (images.isEmpty) return _buildEmptyState(context);

        return SizedBox(
          height: 296,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            itemCount: images.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index == images.length) return _buildMoreCard(context);
              return SizedBox(
                width: 240,
                child: WallMiniCard(image: images[index]),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return SizedBox(
      height: 296,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.noWallPhotosYet,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/images'),
      child: Container(
        width: 240,
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey[300]!, width: 1.5, style: BorderStyle.solid),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_forward, size: 28, color: Colors.grey[500]),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.viewMore,
                style: TextStyle(
                  fontSize: 12,
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
