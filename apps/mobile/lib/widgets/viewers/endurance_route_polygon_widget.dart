import 'package:flutter/material.dart';
import '../../models/polygon_data.dart';

const Color neonLimeColor = Color.fromRGBO(188, 244, 33, 1.0);

class EnduranceRoutePolygonClipper extends CustomClipper<Path> {
  final Polygon polygon;
  final Size imageSize;
  final Size containerSize;

  EnduranceRoutePolygonClipper({
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
  final bool isHighlighted;

  EnduranceRouteEditorPolygonPainter({
    required this.polygon,
    required this.imageSize,
    required this.containerSize,
    required this.isHighlighted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = neonLimeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isHighlighted ? 6.0 : 2.0;

    if (isHighlighted) {
      final highlightPaint = Paint()
        ..color = neonLimeColor.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawPath(_getPolygonPath(), highlightPaint);
    }

    final path = _getPolygonPath();
    canvas.drawPath(path, paint);
  }

  Path _getPolygonPath() {
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// HoldVolumePolygon 위젯을 추가합니다.
class EnduranceRoutePolygon extends StatelessWidget {
  final Polygon polygon;
  final Size imageSize;
  final Size containerSize;
  final Function(int) onPolygonTap;
  final Map<int, List<int>> selectedOrder;
  final Function(int, int)? onOrderTap;
  final bool isHighlighted;
  final TransformationController transformationController;
  final bool showHoldOrder;

  const EnduranceRoutePolygon({
    Key? key,
    required this.polygon,
    required this.imageSize,
    required this.containerSize,
    required this.onPolygonTap,
    required this.selectedOrder,
    required this.onOrderTap,
    required this.isHighlighted,
    required this.transformationController,
    required this.showHoldOrder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          ClipPath(
            clipper: EnduranceRoutePolygonClipper(
              polygon: polygon,
              imageSize: imageSize,
              containerSize: containerSize,
            ),
            child: CustomPaint(
              painter: EnduranceRouteEditorPolygonPainter(
                polygon: polygon,
                imageSize: imageSize,
                containerSize: containerSize,
                isHighlighted: isHighlighted,
              ),
              child: GestureDetector(
                onTap: () => onPolygonTap(polygon.polygonId),
                child: Container(
                  color: isHighlighted ? neonLimeColor.withOpacity(0.3) : Colors.transparent,
                ),
              ),
            ),
          ),
          if (showHoldOrder)
            Builder(
              builder: (context) {
                // 폴리곤의 중심점 계산
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
    );
  }

  Widget _buildSingleOrderCircle(int order) {
    final scale = transformationController.value.getMaxScaleOnAxis();
    final size = 18 / scale;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.red,
          width: 2 / scale,
        ),
      ),
      child: Center(
        child: Text(
          order.toString(),
          style: TextStyle(
            color: Colors.black.withOpacity(1.0),
            fontSize: 10 / scale,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
