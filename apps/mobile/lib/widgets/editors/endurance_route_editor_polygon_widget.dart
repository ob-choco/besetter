import 'package:flutter/material.dart';
import '../../models/polygon_data.dart';
import 'endurance_route_editor.dart';

const Color neonLimeColor = Color.fromRGBO(188, 244, 33, 1.0);

class EnduranceRouteEditorPolygonClipper extends CustomClipper<Path> {
  final Polygon polygon;
  final Size imageSize;
  final Size containerSize;

  EnduranceRouteEditorPolygonClipper({
    required this.polygon,
    required this.imageSize,
    required this.containerSize,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    if (polygon.points.isNotEmpty) {
      final firstPoint = _adjustPoint(polygon.points[0]);
      path.moveTo(firstPoint[0], firstPoint[1]);
      for (var i = 1; i < polygon.points.length; i++) {
        final point = _adjustPoint(polygon.points[i]);
        path.lineTo(point[0], point[1]);
      }
      path.close();
    }
    return path;
  }

  List<double> _adjustPoint(List<int> point) {
    final x = (point[0] / imageSize.width) * containerSize.width;
    final y = (point[1] / imageSize.height) * containerSize.height;
    return [x, y];
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => true;
}

class EnduranceRouteEditorPolygonPainter extends CustomPainter {
  final Polygon polygon;
  final Size imageSize;
  final Size containerSize;
  final bool isSelected;
  final bool isEditingHold;

  EnduranceRouteEditorPolygonPainter({
    required this.polygon,
    required this.imageSize,
    required this.containerSize,
    required this.isSelected,
    this.isEditingHold = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isEditingHold ? neonLimeColor : (isSelected ? Colors.red : Colors.white)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isEditingHold ? 3.0 : 1.0;

    final path = Path();
    if (polygon.points.isNotEmpty) {
      final firstPoint = _adjustPoint(polygon.points[0]);
      path.moveTo(firstPoint[0], firstPoint[1]);
      for (var i = 1; i < polygon.points.length; i++) {
        final point = _adjustPoint(polygon.points[i]);
        path.lineTo(point[0], point[1]);
      }
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  List<double> _adjustPoint(List<int> point) {
    final x = (point[0] / imageSize.width) * containerSize.width;
    final y = (point[1] / imageSize.height) * containerSize.height;
    return [x, y];
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// HoldVolumePolygon 위젯을 추가합니다.
class EnduranceRouteEditorPolygon extends StatelessWidget {
  final Polygon polygon;
  final Size imageSize;
  final Size containerSize;
  final bool isSelected;
  final Function(int) onPolygonTap;
  final Function(int polygonId, int order)? onOrderTap;
  final Map<int, List<int>> selectedOrder;
  final bool isEditingHold;
  final HoldEditMode holdEditMode;
  final TransformationController transformationController;
  final bool showHoldOrder;

  const EnduranceRouteEditorPolygon({
    Key? key,
    required this.polygon,
    required this.imageSize,
    required this.containerSize,
    required this.isSelected,
    required this.onPolygonTap,
    required this.selectedOrder,
    required this.isEditingHold,
    required this.holdEditMode,
    this.onOrderTap,
    required this.transformationController,
    required this.showHoldOrder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: holdEditMode == HoldEditMode.edit ? null : () => onPolygonTap(polygon.polygonId),
        child: Stack(
          children: [
            ClipPath(
              clipper: EnduranceRouteEditorPolygonClipper(
                polygon: polygon,
                imageSize: imageSize,
                containerSize: containerSize,
              ),
              child: CustomPaint(
                painter: EnduranceRouteEditorPolygonPainter(
                  polygon: polygon,
                  imageSize: imageSize,
                  containerSize: containerSize,
                  isSelected: isSelected,
                  isEditingHold: isEditingHold,
                ),
                child: Container(color: Colors.transparent),
              ),
            ),
            if (isSelected && selectedOrder.containsKey(polygon.polygonId) && showHoldOrder)
              Builder(
                builder: (context) {
                  double centerX = 0;
                  double centerY = 0;
                  for (var point in polygon.points) {
                    final x = (point[0] / imageSize.width) * containerSize.width;
                    final y = (point[1] / imageSize.height) * containerSize.height;
                    centerX += x;
                    centerY += y;
                  }
                  centerX /= polygon.points.length;
                  centerY /= polygon.points.length;

                  final orders = selectedOrder[polygon.polygonId]!;
                  final scale = transformationController.value.getMaxScaleOnAxis();
                  final circleSize = 18 / scale;
                  final stackWidth = (18.0 + (orders.length - 1) * 5.0) / scale;

                  return Positioned(
                    left: centerX - (circleSize / 2),
                    top: centerY - (circleSize / 2),
                    child: orders.length == 1
                        ? GestureDetector(
                            onTap: () => onOrderTap?.call(polygon.polygonId, orders[0]),
                            child: _buildSingleOrderCircle(orders[0]),
                          )
                        : SizedBox(
                            width: stackWidth,
                            height: circleSize,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                for (var i = orders.length - 1; i >= 0; i--)
                                  Positioned(
                                    left: (i * 5.0) / scale,
                                    child: GestureDetector(
                                      onTap: () => onOrderTap?.call(polygon.polygonId, orders[orders.length - 1 - i]),
                                      child: _buildSingleOrderCircle(orders[orders.length - 1 - i]),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleOrderCircle(int order) {
    final bool isDimmed = holdEditMode == HoldEditMode.add || holdEditMode == HoldEditMode.replace;
    final scale = transformationController.value.getMaxScaleOnAxis();
    final size = 18 / scale;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(isDimmed ? 0.3 : 0.8),
        shape: BoxShape.circle,
        border: Border.all(
          color: isEditingHold ? neonLimeColor : Colors.red,
          width: (isEditingHold ? 3 : 2) / scale,
        ),
      ),
      child: Center(
        child: Text(
          order.toString(),
          style: TextStyle(
            color: Colors.black.withOpacity(isDimmed ? 0.3 : 1.0),
            fontSize: 10 / scale,
            fontWeight: isEditingHold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
