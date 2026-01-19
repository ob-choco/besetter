import 'package:flutter/material.dart';
import '../../models/polygon_data.dart';
import 'dart:math';
import 'package:flutter_svg/svg.dart';
import './bouldering_route_editor.dart';
import '../../models/route_data.dart';

extension ColorExtension on Color {
  String toHex() => '#${value.toRadixString(16).padLeft(8, '0').substring(2)}';
}

const Color neonLimeColor = Color.fromRGBO(188, 244, 33, 1.0);

class BoulderingRouteEditorPolygonClipper extends CustomClipper<Path> {
  final Polygon polygon;
  final Size imageSize;
  final Size containerSize;

  BoulderingRouteEditorPolygonClipper({
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

class BoulderingRouteEditorPolygonPainter extends CustomPainter {
  final Polygon polygon;
  final Size imageSize;
  final Size containerSize;
  final bool isSelected;
  final bool isEditingHold;
  final Color fillColor;
  final int? markingCount;

  BoulderingRouteEditorPolygonPainter({
    required this.polygon,
    required this.imageSize,
    required this.containerSize,
    required this.isSelected,
    required this.fillColor,
    this.isEditingHold = false,
    this.markingCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _getPolygonPath();

    // 먼저 홀드 채우기
    final paint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);

    // 마지막으로 홀드 테두리 그리기
    final strokePaint = Paint()
      ..color = isSelected ? neonLimeColor : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = isEditingHold ? 8.0 : (isSelected ? 4.0 : 1.0);
    canvas.drawPath(path, strokePaint);
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

class BoulderingRouteEditorHoldPropertyPainter extends CustomPainter {
  final Polygon polygon;
  final Size imageSize;
  final Size containerSize;
  final HoldProperty holdProperty;
  final PictureInfo? pictureInfo;

  BoulderingRouteEditorHoldPropertyPainter({
    required this.polygon,
    required this.imageSize,
    required this.containerSize,
    required this.holdProperty,
    this.pictureInfo,
  });

  List<Map<String, dynamic>> selectEdges(List<Map<String, dynamic>> edges, int startIndex, int targetLength,
      [int k = 1]) {
    List<Map<String, dynamic>> selectedEdges = [];
    int totalEdges = edges.length;
    int currentIndex = startIndex % totalEdges;

    // 첫 번째 edge 선택
    selectedEdges.add(edges[currentIndex]);

    while (selectedEdges.length < k) {
      double cumulativeLength = 0;

      // 다음 edge로 이동
      currentIndex = (currentIndex + 1) % totalEdges;

      // 누적 길이가 targetLength 이상이 될 때까지 진행
      while (cumulativeLength < targetLength) {
        cumulativeLength += edges[currentIndex]['length'] as double;
        currentIndex = (currentIndex + 1) % totalEdges;
      }

      // 현재 위치의 edge 선택
      int selectedIndex = (currentIndex - 1 + totalEdges) % totalEdges;
      selectedEdges.add(edges[selectedIndex]);

      // 선택된 edge의 길이가 targetLength와 같거나 큰 경우 다음 edge도 선택
      if (edges[selectedIndex]['length'] as double >= targetLength && selectedEdges.length < k) {
        currentIndex = (currentIndex + 1) % totalEdges;
        selectedEdges.add(edges[currentIndex]);
      }

      // 선택한 edge 개수가 k에 도달하면 종료
      if (selectedEdges.length >= k) {
        break;
      }
    }

    // 최대 k개의 edge 반환
    return selectedEdges.sublist(0, k);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (holdProperty.type == BoulderingHoldType.finishing) {
      final points = polygon.points.map((p) => _adjustPoint(p)).toList();
      if (points.isEmpty) return;

      // 중간 인덱스의 점과 다음 점으로 변을 구함
      final middleIndex = points.length ~/ 2;
      final p1 = points[middleIndex];
      final p2 = points[(middleIndex + 1) % points.length];

      // 변의 중간 지점 계산
      final centerX = (p1[0] + p2[0]) / 2;
      final centerY = (p1[1] + p2[1]) / 2;

      // 변의 법선 벡터 계산 (바깥쪽 방향)
      final dx = p2[0] - p1[0];
      final dy = p2[1] - p1[1];
      final length = sqrt(dx * dx + dy * dy);

      const scale = 6.0;
      final normalX = -dy / length * scale;
      final normalY = dx / length * scale;

      if (pictureInfo != null) {
        const svgSize = 15.0;

        // SVG를 폴리곤 변의 중간에서 바깥쪽으로 이동
        final drawX = centerX + normalX;
        final drawY = centerY + normalY;

        canvas.save();
        canvas.translate(drawX - svgSize / 2, drawY - svgSize / 2);
        canvas.scale(svgSize / pictureInfo!.size.width);
        canvas.drawPicture(pictureInfo!.picture);
        canvas.restore();
      }
      return;
    }

    final markingCount = holdProperty.markingCount;

    if (markingCount == null || markingCount <= 0) return;

    final points = polygon.points.map((p) => _adjustPoint(p)).toList();
    if (points.isEmpty) return;

    // 홀이프 속성 설정
    final tapePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    // 폴리곤의 각 변의 중점과 법선 벡터 계산
    List<Map<String, dynamic>> edges = [];
    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];

      // 변의 길이 계산
      final dx = p2[0] - p1[0];
      final dy = p2[1] - p1[1];
      final length = sqrt(dx * dx + dy * dy);

      if (length > 0) {
        // 변의 중점 계산
        final midX = (p1[0] + p2[0]) / 2;
        final midY = (p1[1] + p2[1]) / 2;

        // 바깥쪽을 향하는 단위 법선 벡터 계산
        final normalX = -dy / length;
        final normalY = dx / length;

        edges.add({
          'midPoint': [midX, midY],
          'normal': [normalX, normalY],
          'length': length,
        });
      }
    }

    final selectedEdges = selectEdges(edges, (edges.length / 2).round(), 10, markingCount);

    // 테이프 크기 설정
    final tapeWidth = 4.0; // 테이프 너비
    final tapeLength = 25.0; // 테이프 길이

    // 선택된 변들에 테이프 그리기
    for (var edge in selectedEdges) {
      final midPoint = edge['midPoint'] as List<double>;
      final normal = edge['normal'] as List<double>;
      // final normal = selectedEdges[0]['normal'] as List<double>;

      // 테이프의 네 꼭지점 계산
      final p1 = [midPoint[0] - (tapeWidth / 2) * normal[1], midPoint[1] + (tapeWidth / 2) * normal[0]];
      final p2 = [midPoint[0] + (tapeWidth / 2) * normal[1], midPoint[1] - (tapeWidth / 2) * normal[0]];
      final p3 = [p2[0] + tapeLength * normal[0], p2[1] + tapeLength * normal[1]];
      final p4 = [p1[0] + tapeLength * normal[0], p1[1] + tapeLength * normal[1]];

      // 테이프 그리기
      final tapePath = Path()
        ..moveTo(p1[0], p1[1])
        ..lineTo(p2[0], p2[1])
        ..lineTo(p3[0], p3[1])
        ..lineTo(p4[0], p4[1])
        ..close();

      canvas.drawPath(tapePath, tapePaint);
    }
  }

  List<double> _adjustPoint(List<int> point) {
    final x = (point[0] / imageSize.width) * containerSize.width;
    final y = (point[1] / imageSize.height) * containerSize.height;
    return [x, y];
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class BoulderingHoldVolumePolygon extends StatelessWidget {
  final Polygon polygon;
  final Size imageSize;
  final Size containerSize;
  final bool isSelected;
  final Function(int) onPolygonTap;
  final Function(int polygonId, int order)? onOrderTap;
  final bool isHoldEditMode;
  final bool isEditingHold;
  final Color fillColor;
  final HoldProperty? holdProperty;
  final PictureInfo? pictureInfo;

  const BoulderingHoldVolumePolygon({
    Key? key,
    required this.polygon,
    required this.imageSize,
    required this.containerSize,
    required this.isSelected,
    required this.onPolygonTap,
    required this.isHoldEditMode,
    required this.isEditingHold,
    required this.fillColor,
    this.onOrderTap,
    this.holdProperty,
    this.pictureInfo,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => onPolygonTap(polygon.polygonId),
            child: ClipPath(
              clipper: BoulderingRouteEditorPolygonClipper(
                polygon: polygon,
                imageSize: imageSize,
                containerSize: containerSize,
              ),
              child: CustomPaint(
                painter: BoulderingRouteEditorPolygonPainter(
                  polygon: polygon,
                  imageSize: imageSize,
                  containerSize: containerSize,
                  isSelected: isSelected,
                  isEditingHold: isEditingHold,
                  fillColor: fillColor,
                ),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          if (holdProperty != null)
            IgnorePointer(
              child: CustomPaint(
                painter: BoulderingRouteEditorHoldPropertyPainter(
                  polygon: polygon,
                  imageSize: imageSize,
                  containerSize: containerSize,
                  holdProperty: holdProperty!,
                  pictureInfo: pictureInfo,
                ),
                size: containerSize,
              ),
            ),
        ],
      ),
    );
  }
}
