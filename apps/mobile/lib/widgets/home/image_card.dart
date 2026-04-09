import 'package:flutter/material.dart';
import '../../models/image_data.dart';
import '../authorized_network_image.dart';

class ImageCard extends StatelessWidget {
  final ImageData image;
  final VoidCallback onTap;

  const ImageCard({
    super.key,
    required this.image,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: onTap,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AuthorizedNetworkImage(
                  imageUrl: image.url,
                  fit: BoxFit.cover,
                ),
                if (image.wallName != null &&
                    image.wallName!.isNotEmpty &&
                    image.place?.name != null &&
                    image.place!.name.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      color: Colors.black54,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            image.wallName!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            image.place!.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
