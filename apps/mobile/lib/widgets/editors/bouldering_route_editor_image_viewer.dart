import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/polygon_data.dart';
import 'bouldering_route_editor_polygon_widget.dart';
import 'bouldering_route_editor.dart';
import 'package:flutter_svg/svg.dart';
import 'zoom_scale_indicator.dart';
import 'dart:async';

class BoulderingRouteEditorImageViewer extends StatefulWidget {
  final File processedImage;
  final Size? imageSize;
  final List<Polygon> polygons;
  final Function(int) onPolygonTap;
  final VoidCallback onBackgroundTap;
  final TransformationController transformationController;
  final bool isHoldEditMode;
  final int? editingHoldId;
  final Map<int, HoldProperty> selectedHolds;
  final Color Function(int) getHoldColor;

  const BoulderingRouteEditorImageViewer({
    Key? key,
    required this.processedImage,
    required this.imageSize,
    required this.polygons,
    required this.onPolygonTap,
    required this.onBackgroundTap,
    required this.transformationController,
    required this.isHoldEditMode,
    required this.editingHoldId,
    required this.selectedHolds,
    required this.getHoldColor,
  }) : super(key: key);

  @override
  State<BoulderingRouteEditorImageViewer> createState() => _BoulderingRouteEditorImageViewerState();
}

class _BoulderingRouteEditorImageViewerState extends State<BoulderingRouteEditorImageViewer> {
  PictureInfo? pictureInfo;
  double _scale = 1.0;
  bool _showScale = false;
  Timer? _scaleTimer;

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

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

  Future<void> _loadSvg() async {
    final String svgString = await DefaultAssetBundle.of(context).loadString('assets/icons/top_mark.svg');
    final String coloredSvg =
        svgString.replaceAll('#000000', Colors.black.toHex()).replaceAll('#ffffff', Colors.white.toHex());
    pictureInfo = await vg.loadPicture(SvgStringLoader(coloredSvg), null);
    setState(() {});
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
                          .map((polygon) => BoulderingHoldVolumePolygon(
                                polygon: polygon,
                                imageSize: widget.imageSize!,
                                containerSize: Size(screenWidth, imageHeight),
                                isSelected: widget.selectedHolds.containsKey(polygon.polygonId),
                                fillColor: widget.getHoldColor(polygon.polygonId),
                                onPolygonTap: widget.onPolygonTap,
                                isHoldEditMode: widget.isHoldEditMode,
                                isEditingHold: polygon.polygonId == widget.editingHoldId,
                                holdProperty: widget.selectedHolds[polygon.polygonId],
                                pictureInfo: pictureInfo,
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
