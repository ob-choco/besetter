import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:dots_indicator/dots_indicator.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/image_data.dart';
import '../../providers/images_provider.dart';
import 'image_card.dart';
import 'edit_mode_dialog.dart';

class ImageCarousel extends HookConsumerWidget {
  final VoidCallback? onInteraction;

  const ImageCarousel({
    super.key,
    this.onInteraction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagesAsync = ref.watch(imagesProvider);
    final pageController = usePageController();
    final currentPage = useState(0.0);

    useEffect(() {
      void listener() {
        currentPage.value = pageController.page ?? 0;
      }
      pageController.addListener(listener);
      return () => pageController.removeListener(listener);
    }, [pageController]);

    return imagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Text(AppLocalizations.of(context)!.errorOccurred),
      ),
      data: (images) {
        if (images.isEmpty) {
          return _buildWelcomeSection(context);
        }
        return _buildCarousel(
          context,
          images,
          pageController,
          currentPage.value,
          onInteraction,
        );
      },
    );
  }

  Widget _buildWelcomeSection(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context)!.setProblemAtGymNow,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(
          height: MediaQuery.of(context).size.width * 0.4,
        ),
      ],
    );
  }

  Widget _buildCarousel(
    BuildContext context,
    List<ImageData> images,
    PageController pageController,
    double currentPage,
    VoidCallback? onInteraction,
  ) {
    final int totalPages = (images.length / 3).ceil().clamp(0, 3);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context)!.setRouteWithRecentPhoto,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: MediaQuery.of(context).size.width * 0.4,
          child: PageView.builder(
            controller: pageController,
            itemCount: totalPages,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, pageIndex) {
              final startIndex = pageIndex * 3;
              final endIndex = (startIndex + 3).clamp(0, images.length);
              final pageImages = images.sublist(startIndex, endIndex);

              if (pageIndex == 2) {
                return _buildLastPage(context, pageImages, onInteraction);
              }

              return _buildPage(context, pageImages, onInteraction);
            },
          ),
        ),
        const SizedBox(height: 8),
        if (totalPages > 0)
          DotsIndicator(
            dotsCount: totalPages,
            position: currentPage.toInt().clamp(0, totalPages - 1),
            decorator: DotsDecorator(
              activeColor: Theme.of(context).primaryColor,
              size: const Size.square(6.0),
              activeSize: const Size.square(6.0),
              spacing: const EdgeInsets.all(4.0),
            ),
          ),
      ],
    );
  }

  Widget _buildPage(
    BuildContext context,
    List<ImageData> pageImages,
    VoidCallback? onInteraction,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          ...pageImages.map((image) => Expanded(
                child: ImageCard(
                  image: image,
                  onTap: () {
                    onInteraction?.call();
                    showDialog(
                      context: context,
                      barrierDismissible: true,
                      builder: (context) => EditModeDialog(image: image),
                    );
                  },
                ),
              )),
          ...List.generate(
            3 - pageImages.length,
            (_) => const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.0),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: SizedBox(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastPage(
    BuildContext context,
    List<ImageData> pageImages,
    VoidCallback? onInteraction,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          ...pageImages.take(2).map((image) => Expanded(
                child: ImageCard(
                  image: image,
                  onTap: () {
                    onInteraction?.call();
                    showDialog(
                      context: context,
                      barrierDismissible: true,
                      builder: (context) => EditModeDialog(image: image),
                    );
                  },
                ),
              )),
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/images'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Card(
                    child: Container(
                      color: Colors.grey[200],
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_circle_outline, size: 32),
                            const SizedBox(height: 4),
                            Text(
                              AppLocalizations.of(context)!.viewMore,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
