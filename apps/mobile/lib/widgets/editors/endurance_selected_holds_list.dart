import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../../models/polygon_data.dart';
import 'endurance_route_editor.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/route_data.dart' show GripHand;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class EnduranceSelectedHoldsList extends StatelessWidget {
  final bool imagesLoaded;
  final List<SelectedHold> selectedHolds;
  final List<Polygon> polygons;
  final List<ui.Image?> croppedImages;
  final Map<int, List<int>> selectedOrder;
  final Function(int, int) onReorder;
  final Function(int) onGripHandTap;
  final Function(int) onHoldTap;

  const EnduranceSelectedHoldsList({
    Key? key,
    required this.imagesLoaded,
    required this.selectedHolds,
    required this.polygons,
    required this.croppedImages,
    required this.selectedOrder,
    required this.onReorder,
    required this.onGripHandTap,
    required this.onHoldTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: imagesLoaded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sequence Details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C2F30),
                        ),
                      ),
                      Text(
                        '${selectedHolds.length} holds total',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  alignment: Alignment.topLeft,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey.shade300,
                        width: 1.0,
                      ),
                    ),
                  ),
                  child: SizedBox(
                    height: 540,
                    child: selectedHolds.isEmpty
                        ? Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Text(
                              AppLocalizations.of(context)!.createEnduranceRouteInstruction,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ))
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (int column = 0; column * 10 < selectedHolds.length; column++)
                                  _buildColumn(column, (column + 1) * 10 >= selectedHolds.length),
                                if (selectedHolds.isNotEmpty && selectedHolds.length % 10 == 0)
                                  Container(
                                    width: 164,
                                    margin: EdgeInsets.only(right: 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [_buildDashedPlaceholder()],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            )
          : Center(child: Text(AppLocalizations.of(context)!.loading)),
    );
  }

  Widget _buildColumn(int column, bool isLastColumn) {
    final itemsInColumn = selectedHolds.skip(column * 10).take(10).toList();

    return Container(
      width: 164,
      height: 530,
      margin: EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...itemsInColumn
              .asMap()
              .entries
              .map((entry) => _buildHoldItem(entry.value, entry.key + 1 + column * 10))
              .whereType<Widget>()
              .toList(),
          if (isLastColumn && itemsInColumn.length < 10)
            _buildDashedPlaceholder(),
        ],
      ),
    );
  }

  Widget _buildEmptySlot() {
    return Container(
      height: 45,
      margin: EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget? _buildHoldItem(SelectedHold hold, int displayIndex) {
    final polygon = polygons.firstWhere((p) => p.polygonId == hold.polygonId);
    final index = polygons.indexOf(polygon);

    if (index >= 0 && index < croppedImages.length) {
      final croppedImage = croppedImages[index];
      if (croppedImage != null) {
        return DragTarget<int>(
          onWillAccept: (data) => data != null,
          onAccept: (draggedIndex) {
            onReorder(draggedIndex, displayIndex - 1);
          },
          builder: (context, candidateData, rejectedData) {
            return Container(
              height: 45,
              margin: EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: candidateData.isNotEmpty ? Colors.blue : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildItemRow(displayIndex, croppedImage, 45, 45),
            );
          },
        );
      }
    }
    return null;
  }

  Widget _buildDashedPlaceholder() {
    return Container(
      height: 45,
      margin: EdgeInsets.symmetric(vertical: 4),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: Colors.grey.shade300,
          strokeWidth: 2,
          dashWidth: 6,
          dashSpace: 4,
          borderRadius: 8,
        ),
        child: Container(),
      ),
    );
  }

  Widget _buildItemRow(int itemIndex, ui.Image croppedImage, double width, double height) {
    final hold = selectedHolds[itemIndex - 1];
    String handIconPath;

    double handIconSize;
    switch (hold.gripHand) {
      case GripHand.left:
        handIconPath = 'assets/icons/left_hand.svg';
        handIconSize = 32;
        break;
      case GripHand.right:
        handIconPath = 'assets/icons/right_hand.svg';
        handIconSize = 32;
        break;
      default:
        handIconPath = 'assets/icons/dot_hand.svg';
        handIconSize = 12;
    }

    return Container(
      color: Colors.grey[200],
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              itemIndex.toString(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: 12),
          GestureDetector(
            onTap: () => onHoldTap(itemIndex - 1),
            child: Container(
              width: width,
              height: height,
              child: RawImage(
                image: croppedImage,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Spacer(),
          GestureDetector(
            onTap: () => onGripHandTap(itemIndex - 1),
            child: SvgPicture.asset(
              handIconPath,
              width: handIconSize,
              height: handIconSize,
            ),
          ),
          Spacer(),
          Draggable<int>(
            data: itemIndex - 1,
            feedback: Material(
              elevation: 4,
              child: Container(
                width: width,
                height: height,
                child: RawImage(
                  image: croppedImage,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            child: Container(
              height: 38,
              width: 18,
              alignment: Alignment.center,
              child: SvgPicture.asset(
                'assets/icons/draggable_three_dot.svg',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final double borderRadius;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(borderRadius),
      ));

    final dashPath = Path();
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        dashPath.addPath(metric.extractPath(distance, end), Offset.zero);
        distance += dashWidth + dashSpace;
      }
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
