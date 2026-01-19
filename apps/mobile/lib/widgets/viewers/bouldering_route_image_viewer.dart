import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/polygon_data.dart';
import 'bouldering_route_polygon_widget.dart';
import '../../models/route_data.dart';

class BoulderingRouteImageViewer extends StatelessWidget {
  final File processedImage;
  final Size? imageSize;
  final List<Polygon> polygons;
  final Function(int) onPolygonTap;
  final VoidCallback onBackgroundTap;
  final TransformationController transformationController;
  final VoidCallback onInteractionUpdate;
  final Map<int, BoulderingHold> holds;
  final Color Function(int) getHoldColor;

  const BoulderingRouteImageViewer({
    Key? key,
    required this.processedImage,
    required this.imageSize,
    required this.polygons,
    required this.onPolygonTap,
    required this.onBackgroundTap,
    required this.transformationController,
    required this.onInteractionUpdate,
    required this.holds,
    required this.getHoldColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = MediaQuery.of(context).size.width;
            final imageRatio = imageSize!.width / imageSize!.height;
            final imageHeight = screenWidth / imageRatio;

            return GestureDetector(
              onTapDown: (_) => onBackgroundTap(),
              child: SizedBox(
                width: screenWidth,
                height: imageHeight,
                child: InteractiveViewer(
                  transformationController: transformationController,
                  minScale: 1.0,
                  maxScale: 3.0,
                  onInteractionUpdate: (_) => onInteractionUpdate(),
                  child: Stack(
                    children: [
                      Image.file(
                        processedImage,
                        width: screenWidth,
                        height: imageHeight,
                        fit: BoxFit.contain,
                      ),
                      ...polygons.map((polygon) {
                        final fillColor = getHoldColor(polygon.polygonId);
                        final isHighlighted = fillColor != Colors.transparent;

                        return BoulderingRoutePolygon(
                          polygon: polygon,
                          imageSize: imageSize!,
                          containerSize: Size(screenWidth, imageHeight),
                          fillColor: fillColor,
                          onPolygonTap: onPolygonTap,
                          hold: holds[polygon.polygonId]!,
                          isHighlighted: isHighlighted,
                        );
                      }),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
