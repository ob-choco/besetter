import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/polygon_data.dart';
import '../../models/route_data.dart';
import 'endurance_route_polygon_widget.dart';

class EnduranceRouteImageViewer extends StatelessWidget {
  final File processedImage;
  final Size? imageSize;
  final List<Polygon> polygons;
  final List<EnduranceHold> holds;
  final Map<int, List<int>> selectedOrder;
  final Function(int) onPolygonTap;
  final VoidCallback onBackgroundTap;
  final TransformationController transformationController;
  final VoidCallback onInteractionUpdate;
  final Function(int, int)? onOrderTap;
  final List<int> highlightedHoldIds;
  final bool showHoldOrder;

  const EnduranceRouteImageViewer({
    Key? key,
    required this.processedImage,
    required this.imageSize,
    required this.polygons,
    required this.holds,
    required this.selectedOrder,
    required this.onPolygonTap,
    required this.onBackgroundTap,
    required this.transformationController,
    required this.onInteractionUpdate,
    required this.onOrderTap,
    required this.highlightedHoldIds,
    required this.showHoldOrder,
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
                      ...polygons.where((polygon) => polygon.isDeleted != true).map((polygon) {
                        final isHighlighted = highlightedHoldIds.isEmpty ||
                            highlightedHoldIds.contains(polygon.polygonId);
                        final isActiveHighlight = highlightedHoldIds.isNotEmpty &&
                            highlightedHoldIds.contains(polygon.polygonId);
                        return EnduranceRoutePolygon(
                          polygon: polygon,
                          imageSize: imageSize!,
                          containerSize: Size(screenWidth, imageHeight),
                          onPolygonTap: onPolygonTap,
                          selectedOrder: selectedOrder,
                          onOrderTap: onOrderTap,
                          isHighlighted: isHighlighted,
                          isActiveHighlight: isActiveHighlight,
                          transformationController: transformationController,
                          showHoldOrder: showHoldOrder,
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
