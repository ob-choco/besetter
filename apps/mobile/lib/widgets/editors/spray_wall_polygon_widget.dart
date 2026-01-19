import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/polygon_data.dart';

const editingColor = Color.fromARGB(255, 211, 211, 211);
const neonPurpleColor = Color(0xFF8A00C4);
const neonBlueColor = Color(0xFF1F51FF);

class SprayWallPolygonClipper extends CustomClipper<Path> {
  final Polygon polygon;
  final Size imageSize;
  final Size containerSize;

  SprayWallPolygonClipper({
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

class SprayWallPolygonPainter extends CustomPainter {
  final Polygon polygon;
  final Size imageSize;
  final Size containerSize;
  final bool isSelected;

  SprayWallPolygonPainter({
    required this.polygon,
    required this.imageSize,
    required this.containerSize,
    required this.isSelected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isSelected ? Colors.red : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

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

// HoldVolumePolygon 위젯을 추가합니.
class SprayWallHoldVolumePolygon extends StatelessWidget {
  final Polygon polygon;
  final Size imageSize;
  final Size containerSize;
  final bool isSelected;
  final VoidCallback? onTap;

  const SprayWallHoldVolumePolygon({
    Key? key,
    required this.polygon,
    required this.imageSize,
    required this.containerSize,
    required this.isSelected,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onTap,
        child: ClipPath(
          clipper: SprayWallPolygonClipper(
            polygon: polygon,
            imageSize: imageSize,
            containerSize: containerSize,
          ),
          child: CustomPaint(
            painter: SprayWallPolygonPainter(
              polygon: polygon,
              imageSize: imageSize,
              containerSize: containerSize,
              isSelected: isSelected,
            ),
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

// DraggableCircle 클래스를 수정합니다
class SprayWallDraggableCircle extends StatelessWidget {
  final Offset position;
  final double radius;
  final Function(DragUpdateDetails) onDragUpdate;
  final Function(DragUpdateDetails, int) onResizeUpdate;
  final VoidCallback onDelete;
  final Function() onResizeStart;
  final Function() onResizeEnd;
  final bool isEditing;
  final VoidCallback? onTap;

  const SprayWallDraggableCircle({
    Key? key,
    required this.position,
    required this.radius,
    required this.onDragUpdate,
    required this.onResizeUpdate,
    required this.onDelete,
    required this.onResizeStart,
    required this.onResizeEnd,
    this.isEditing = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 정사각형 테두리 (편집 모드일 때만)
        if (isEditing)
          Positioned(
            left: position.dx - radius,
            top: position.dy - radius,
            child: Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                border: Border.all(
                  color: editingColor,
                  width: 1,
                ),
              ),
            ),
          ),
        // 메인 원
        Positioned(
          left: position.dx - radius,
          top: position.dy - radius,
          child: GestureDetector(
            onTap: !isEditing ? onTap : null,
            onPanUpdate: isEditing ? onDragUpdate : null,
            child: Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: neonBlueColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        // 크기 조절 컨트롤 포인트들 (편집 모드일 때만)
        if (isEditing)
          ...List.generate(4, (index) {
            // 각 꼭지점의 위치 계산
            late double controlX;
            late double controlY;

            switch (index) {
              case 0: // 좌상단
                controlX = position.dx - radius;
                controlY = position.dy - radius;
                break;
              case 1: // 우상단
                controlX = position.dx + radius;
                controlY = position.dy - radius;
                break;
              case 2: // 우하단
                controlX = position.dx + radius;
                controlY = position.dy + radius;
                break;
              case 3: // 좌하단
                controlX = position.dx - radius;
                controlY = position.dy + radius;
                break;
            }

            return Positioned(
              left: controlX - 4,
              top: controlY - 4,
              child: GestureDetector(
                onPanStart: (_) => onResizeStart(),
                onPanUpdate: (details) => onResizeUpdate(details, index),
                onPanEnd: (_) => onResizeEnd(),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: editingColor, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        // 삭제 버튼 (편집 모드일 때만)
        if (isEditing)
          Positioned(
            // 가로 위치 조정 (16 -> 12)
            left: position.dx - 12,
            top: position.dy - radius < 32  // 36 -> 32로 수정
                ? position.dy + radius + 8
                : position.dy - radius - 32, // 36 -> 32로 수정
            child: Container(
              padding: EdgeInsets.all(3),  // 4 -> 3으로 수정
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: editingColor, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: GestureDetector(
                onTap: onDelete,
                behavior: HitTestBehavior.translucent,
                child: Icon(Icons.delete_outline_rounded, size: 14, color: Colors.black),  // 18 -> 14로 수정
              ),
            ),
          ),
      ],
    );
  }
}
