import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/polygon_data.dart';
import 'endurance_route_editor_polygon_widget.dart';
import 'endurance_route_editor.dart';
import 'zoom_scale_indicator.dart';
import 'dart:async';

class EnduranceRouteEditorImageViewer extends StatefulWidget {
  final File processedImage;
  final Size? imageSize;
  final List<Polygon> polygons;
  final List<SelectedHold> selectedHolds;
  final Map<int, List<int>> selectedOrder;
  final Function(int) onPolygonTap;
  final VoidCallback onBackgroundTap;
  final TransformationController transformationController;
  final Function(int, int)? onOrderTap;
  final int? editingHoldId;
  final HoldEditMode holdEditMode;
  final bool showHoldOrder;

  const EnduranceRouteEditorImageViewer({
    Key? key,
    required this.processedImage,
    required this.imageSize,
    required this.polygons,
    required this.selectedHolds,
    required this.selectedOrder,
    required this.onPolygonTap,
    required this.onBackgroundTap,
    required this.transformationController,
    required this.onOrderTap,
    required this.editingHoldId,
    this.holdEditMode = HoldEditMode.none,
    required this.showHoldOrder,
  }) : super(key: key);

  @override
  State<EnduranceRouteEditorImageViewer> createState() => _EnduranceRouteEditorImageViewerState();
}

class _EnduranceRouteEditorImageViewerState extends State<EnduranceRouteEditorImageViewer> {
  double _scale = 1.0;
  bool _showScale = false;
  Timer? _scaleTimer;

  @override
  void dispose() {
    _scaleTimer?.cancel();
    super.dispose();
  }

  void _updateScale() {
    final scale = widget.transformationController.value.getMaxScaleOnAxis();
    setState(() {
      _scale = scale;
      _showScale = true;
    });

    _scaleTimer?.cancel();
    _scaleTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showScale = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = MediaQuery.of(context).size.width;
            final imageRatio = widget.imageSize!.width / widget.imageSize!.height;
            final imageHeight = screenWidth / imageRatio;

            return GestureDetector(
              onTapDown: (_) => widget.onBackgroundTap(),
              child: SizedBox(
                width: screenWidth,
                height: imageHeight,
                child: InteractiveViewer(
                  transformationController: widget.transformationController,
                  minScale: 1.0,
                  maxScale: 3.0,
                  onInteractionUpdate: (_) => _updateScale(),
                  child: Stack(
                    children: [
                      Image.file(
                        widget.processedImage,
                        width: screenWidth,
                        height: imageHeight,
                        fit: BoxFit.contain,
                      ),
                      ...widget.polygons
                          .where((polygon) => polygon.isDeleted != true)
                          .map((polygon) => EnduranceRouteEditorPolygon(
                                polygon: polygon,
                                imageSize: widget.imageSize!,
                                containerSize: Size(screenWidth, imageHeight),
                                isSelected: widget.selectedHolds.any((h) => h.polygonId == polygon.polygonId),
                                selectedOrder: widget.selectedOrder,
                                onPolygonTap: widget.onPolygonTap,
                                onOrderTap: widget.onOrderTap,
                                isEditingHold: polygon.polygonId == widget.editingHoldId,
                                holdEditMode: widget.holdEditMode,
                                transformationController: widget.transformationController,
                                showHoldOrder: widget.showHoldOrder,
                              )),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        ZoomScaleIndicator(
          showScale: _showScale,
          scale: _scale,
        ),
      ],
    );
  }
}
