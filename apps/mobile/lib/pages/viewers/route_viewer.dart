import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

import '../../models/route_data.dart';
import '../../models/polygon_data.dart';
import '../../services/http_client.dart';
import '../../widgets/viewers/bouldering_route_image_viewer.dart';
import '../../widgets/viewers/endurance_route_image_viewer.dart';
import '../../widgets/viewers/endurance_route_holds.dart';
import '../../widgets/viewers/bouldering_route_holds.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';


class RouteViewer extends StatefulWidget {
  final RouteData routeData;

  const RouteViewer({
    required this.routeData,
    Key? key,
  }) : super(key: key);

  @override
  _RouteViewerState createState() => _RouteViewerState();
}

class _RouteViewerState extends State<RouteViewer> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _imageUrl;
  double _scale = 1.0;
  late TransformationController _transformationController;
  List<Polygon> _polygons = [];
  ui.Image? _uiImage;
  Size? _imageSize;
  Map<int, ui.Image?> _croppedImages = {};
  late File _processedImage;
  bool _isDisposed = false;
  List<Future<void>> _pendingOperations = [];
  bool _imagesLoaded = false;
  List<int> _highlightedHoldIds = [];
  bool _showHoldOrder = true;
  String? _selectedHoldType;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _imageUrl = widget.routeData.imageUrl;
    _transformationController = TransformationController();
    _polygons = widget.routeData.polygons ?? [];
    _loadImage();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      late final Uint8List bytes;
      final fileName = _imageUrl.split('/').last.split('?').first;
      final tempDir = await getTemporaryDirectory();
      final cacheFile = File('${tempDir.path}/$fileName');

      if (await cacheFile.exists()) {
        bytes = await cacheFile.readAsBytes();
      } else {
        final response = await AuthorizedHttpClient.getImage(_imageUrl);
        if (response.statusCode != 200) {
          throw Exception('Failed to load image: ${response.statusCode}');
        }

        bytes = response.bodyBytes;
        await cacheFile.writeAsBytes(bytes);
      }

      _processedImage = cacheFile;

      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      if (!mounted) return;

      setState(() {
        _uiImage = frameInfo.image;
        _imageSize = Size(_uiImage!.width.toDouble(), _uiImage!.height.toDouble());
        _initializeCroppedImages();
      });
    } catch (e) {
      print('Error loading image: $e');
    }
  }

  Future<void> _initializeCroppedImages() async {
    if (_imageSize == null || _uiImage == null) {
      print('Image is not loaded yet.');
      return;
    }

    setState(() {
      _imagesLoaded = false;
    });

    for (var polygon in _polygons) {
      await _cropPolygonImage(polygon);
    }

    if (mounted) {
      setState(() {
        _imagesLoaded = true;
      });
    }
  }

  Future<void> _cropPolygonImage(Polygon polygon) async {
    if (_isDisposed) return;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (var point in polygon.points) {
      final adjustedPoint = _adjustPoint(point, _imageSize!.width, _imageSize!.height);
      minX = math.min(minX, adjustedPoint[0]);
      minY = math.min(minY, adjustedPoint[1]);
      maxX = math.max(maxX, adjustedPoint[0]);
      maxY = math.max(maxY, adjustedPoint[1]);
    }

    final boundingWidth = (maxX - minX).ceil();
    final boundingHeight = (maxY - minY).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final path = Path();

    if (polygon.points.isNotEmpty) {
      final firstPoint = _adjustPoint(polygon.points[0], _imageSize!.width, _imageSize!.height);
      path.moveTo(firstPoint[0] - minX, firstPoint[1] - minY);

      for (var i = 1; i < polygon.points.length; i++) {
        final point = _adjustPoint(polygon.points[i], _imageSize!.width, _imageSize!.height);
        path.lineTo(point[0] - minX, point[1] - minY);
      }
      path.close();
    }

    final boundingRect = Rect.fromLTWH(0, 0, boundingWidth.toDouble(), boundingHeight.toDouble());
    canvas.saveLayer(boundingRect, Paint());
    canvas.clipPath(path);

    canvas.drawImageRect(
      _uiImage!,
      Rect.fromLTWH(minX, minY, boundingWidth.toDouble(), boundingHeight.toDouble()),
      boundingRect,
      Paint(),
    );

    canvas.restore();

    final picture = recorder.endRecording();
    final img = await picture.toImage(boundingWidth, boundingHeight);

    final operation = Future(() async {
      if (!_isDisposed && mounted) {
        setState(() {
          _croppedImages[polygon.polygonId] = img;
        });
      }
    });

    _pendingOperations.add(operation);
    await operation;
    _pendingOperations.remove(operation);
  }

  List<double> _adjustPoint(List<int> point, double imageWidth, double imageHeight) {
    final x = (point[0] / imageWidth) * _uiImage!.width;
    final y = (point[1] / imageHeight) * _uiImage!.height;
    return [x, y];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.viewRoute),
        actions: [
          if (widget.routeData.type == RouteType.endurance)
            IconButton(
              icon: Icon(_showHoldOrder ? Icons.visibility : Icons.visibility_off),
              onPressed: () {
                setState(() {
                  _showHoldOrder = !_showHoldOrder;
                });
              },
              tooltip: AppLocalizations.of(context)!.displayHoldOrder,
            ),
        ],
      ),
      body: _uiImage != null && _imageSize != null
          ? SingleChildScrollView(
              child: Column(
                children: [
                  // 이미지 뷰어
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final screenWidth = MediaQuery.of(context).size.width;
                      final imageRatio = _imageSize!.width / _imageSize!.height;
                      final imageHeight = screenWidth / imageRatio;

                      return SizedBox(
                        width: screenWidth,
                        height: imageHeight,
                        child: widget.routeData.type == RouteType.endurance
                            ? EnduranceRouteImageViewer(
                                processedImage: _processedImage,
                                imageSize: _imageSize,
                                polygons: _polygons,
                                holds: widget.routeData.enduranceHolds ?? [],
                                selectedOrder: _getSelectedOrder(),
                                onPolygonTap: (_) {},
                                onBackgroundTap: () {
                                  setState(() {
                                    _highlightedHoldIds = [];
                                    _selectedHoldType = null;
                                  });
                                },
                                transformationController: _transformationController,
                                onInteractionUpdate: () {
                                  setState(() {
                                    _scale = _transformationController.value.getMaxScaleOnAxis();
                                  });
                                },
                                onOrderTap: null,
                                highlightedHoldIds: _highlightedHoldIds,
                                showHoldOrder: _showHoldOrder,
                              )
                            : BoulderingRouteImageViewer(
                                processedImage: _processedImage,
                                imageSize: _imageSize,
                                polygons: _polygons,
                                onPolygonTap: (_) {},
                                onBackgroundTap: () {
                                  setState(() {
                                    _highlightedHoldIds = [];
                                    _selectedHoldType = null;
                                  });
                                },
                                transformationController: _transformationController,
                                onInteractionUpdate: () {
                                  setState(() {
                                    _scale = _transformationController.value.getMaxScaleOnAxis();
                                  });
                                },
                                holds: _getHoldProperties(),
                                getHoldColor: (polygonId) => _getHoldColor(polygonId, _highlightedHoldIds),
                              ),
                      );
                    },
                  ),
                  // 홀드 목록
                  if (_imagesLoaded)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                      ),
                      child: widget.routeData.type == RouteType.endurance
                          ? EnduranceRouteHolds(
                              holds: widget.routeData.enduranceHolds ?? [],
                              croppedImages: _croppedImages,
                              onHighlightHolds: (holdIds) {
                                setState(() {
                                  _highlightedHoldIds = holdIds;
                                });
                              },
                            )
                          : BoulderingRouteHolds(
                              holds: _getHoldProperties(),
                              croppedImages: _croppedImages,
                              onHighlightHolds: (holdIds) {
                                setState(() {
                                  _highlightedHoldIds = holdIds;
                                });
                              },
                              selectedType: _selectedHoldType,
                              onTypeSelected: (type) {
                                setState(() {
                                  _selectedHoldType = type;
                                });
                              },
                            ),
                    ),
                  // 탭바와 탭 컨텐츠
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 등급 정보를 더 강조하는 상단 섹션
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                // 등급 표시
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.routeData.gradeType,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.routeData.grade,
                                        style: const TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // 색상과 점수를 함께 표시
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (widget.routeData.gradeColor != null)
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: Color(int.parse('0x${widget.routeData.gradeColor}')),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.grey.shade200,
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.1),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (widget.routeData.gradeScore != null) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.primary,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${widget.routeData.gradeScore}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // 암장 정보 섹션
                          if (widget.routeData.gymName != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        size: 20,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          widget.routeData.gymName!,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.routeData.wallName != null) ...[
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 28),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.landscape,
                                            size: 16,
                                            color: Colors.grey.shade600,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            widget.routeData.wallName!,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (widget.routeData.wallExpirationDate != null) ...[
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 28),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.event,
                                            size: 16,
                                            color: Colors.grey.shade600,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '~${widget.routeData.wallExpirationDate!.toString().split(' ')[0]}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const Center(
              child: CircularProgressIndicator(),
            ),
    );
  }

  // 홀드 속성 맵 생성 메서드 추가
  Map<int, BoulderingHold> _getHoldProperties() {
    if (widget.routeData.boulderingHolds == null) return {};

    return Map.fromEntries(
      widget.routeData.boulderingHolds!.map(
        (hold) => MapEntry(hold.polygonId, hold),
      ),
    );
  }

  // 홀드 색상 반환 메서드 수정
  Color _getHoldColor(int polygonId, List<int> highlightedHoldIds) {
    if (highlightedHoldIds.isNotEmpty && !highlightedHoldIds.contains(polygonId)) {
      return Colors.transparent;
    }

    final holds = widget.routeData.boulderingHolds;
    if (holds == null) return Colors.transparent;

    final hold = holds.firstWhere(
      (h) => h.polygonId == polygonId,
      orElse: () => BoulderingHold(polygonId: polygonId, type: 'normal'),
    );

    return hold.type == 'starting'
        ? Colors.green.withOpacity(0.3)
        : hold.type == 'finishing'
            ? Colors.red.withOpacity(0.3)
            : Colors.blue.withOpacity(0.3);
  }

  // 선택된 순서 맵 생성 메서드 추가
  Map<int, List<int>> _getSelectedOrder() {
    if (widget.routeData.enduranceHolds == null) return {};

    Map<int, List<int>> orderMap = {};
    for (var i = 0; i < widget.routeData.enduranceHolds!.length; i++) {
      final hold = widget.routeData.enduranceHolds![i];
      final order = i + 1;
      if (orderMap.containsKey(hold.polygonId)) {
        orderMap[hold.polygonId]!.add(order);
      } else {
        orderMap[hold.polygonId] = [order];
      }
    }
    return orderMap;
  }
}
