import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:math' as math;

import '../../models/route_data.dart';
import '../../models/polygon_data.dart';
import '../../services/http_client.dart';
import '../../widgets/viewers/bouldering_route_image_viewer.dart';
import '../../widgets/viewers/endurance_route_image_viewer.dart';
import '../../widgets/viewers/endurance_route_holds.dart';
import '../../widgets/viewers/bouldering_route_holds.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../providers/activity_refresh_provider.dart'; // activityDirtyProvider
import '../../providers/recent_climbed_routes_provider.dart';
import '../../widgets/viewers/activity_panel.dart';
import '../../widgets/viewers/workout_log_panel.dart';
import '../../widgets/place_pending_badge.dart';


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
  // ignore: prefer_const_declarations
  final _workoutLogKey = GlobalKey();

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
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _handleShare,
          ),
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
                  // Activity panel (slide-to-start / timer / confirmation)
                  ActivityPanel(
                    routeId: widget.routeData.id,
                    onActivityCreated: (activityData) {
                      (_workoutLogKey.currentState as dynamic)?.addActivity(activityData);
                      final container = ProviderScope.containerOf(context);
                      container.read(activityDirtyProvider.notifier).state = true;
                      container.invalidate(recentClimbedRoutesProvider);
                    },
                  ),
                  // Workout log (stats + activity list)
                  WorkoutLogPanel(
                    key: _workoutLogKey,
                    routeId: widget.routeData.id,
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    height: 1,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  // Route information
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Grade Section
                        Container(
                          padding: const EdgeInsets.only(top: 6, bottom: 16),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: const Color(0xFFABADAE).withOpacity(0.2),
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (widget.routeData.gradeColor != null) ...[
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: Color(int.parse(widget.routeData.gradeColor!, radix: 16)),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          AppLocalizations.of(context)!.currentGrade,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF0052D0),
                                            letterSpacing: 2,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.routeData.grade,
                                      style: TextStyle(
                                        fontSize: 48,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF2C2F30),
                                        height: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.trending_up,
                                        size: 12,
                                        color: Color(0xFF465C7D),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        AppLocalizations.of(context)!.levelLabel(_getGradeLevel(context)['name']!).toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF465C7D),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    _getGradeLevel(context)['description']!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF595C5D),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Meta Information
                        if (widget.routeData.place != null)
                          _buildMetaRow(
                            icon: Icons.location_on_outlined,
                            label: AppLocalizations.of(context)!.gymLabel,
                            value: widget.routeData.place!.name,
                            trailing: widget.routeData.place!.isPending
                                ? const PlacePendingBadge()
                                : null,
                          ),
                        if (widget.routeData.wallName != null) ...[
                          const SizedBox(height: 24),
                          _buildMetaRow(
                            icon: Icons.grid_view_rounded,
                            label: AppLocalizations.of(context)!.sectorLabel,
                            value: widget.routeData.wallName!,
                          ),
                        ],
                        if (widget.routeData.wallExpirationDate != null) ...[
                          const SizedBox(height: 24),
                          _buildExpiryRow(),
                        ],
                        // Description
                        if (widget.routeData.description != null && widget.routeData.description!.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Color(0xFFEFF1F2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              widget.routeData.description!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF595C5D),
                                height: 1.625,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                      ],
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

  Widget _buildMetaRow({required IconData icon, required String label, required String value, Widget? trailing}) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Icon(icon, size: 20, color: Color(0xFF465C7D)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF595C5D),
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C2F30),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing,
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpiryRow() {
    final expiryDate = widget.routeData.wallExpirationDate!;
    final daysLeft = expiryDate.difference(DateTime.now()).inDays;
    final locale = AppLocalizations.of(context)!.localeName;
    final dateStr = DateFormat.yMMMMd(locale).format(expiryDate);

    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF465C7D)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.routeExpiry,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF595C5D),
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2F30),
                ),
              ),
            ],
          ),
        ),
        if (daysLeft >= 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFB5151).withOpacity(0.2),
              borderRadius: BorderRadius.circular(9999),
            ),
            child: Text(
              AppLocalizations.of(context)!.daysLeft(daysLeft),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9F0519),
                letterSpacing: -0.5,
              ),
            ),
          ),
      ],
    );
  }

  Map<String, String> _getGradeLevel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final gradeType = widget.routeData.gradeType;
    final grade = widget.routeData.grade;

    final levels = {
      'beginner': {'name': l10n.gradeBeginner, 'description': l10n.gradeBeginnerDesc},
      'novice': {'name': l10n.gradeNovice, 'description': l10n.gradeNoviceDesc},
      'intermediate': {'name': l10n.gradeIntermediate, 'description': l10n.gradeIntermediateDesc},
      'advanced': {'name': l10n.gradeAdvanced, 'description': l10n.gradeAdvancedDesc},
      'expert': {'name': l10n.gradeExpert, 'description': l10n.gradeExpertDesc},
      'elite': {'name': l10n.gradeElite, 'description': l10n.gradeEliteDesc},
      'pro': {'name': l10n.gradePro, 'description': l10n.gradeProDesc},
      'worldClass': {'name': l10n.gradeWorldClass, 'description': l10n.gradeWorldClassDesc},
      'legendary': {'name': l10n.gradeLegendary, 'description': l10n.gradeLegendaryDesc},
    };

    String levelKey;

    switch (gradeType) {
      case 'vScale':
        final n = int.tryParse(grade.replaceFirst('V', '')) ?? 0;
        if (n <= 1) levelKey = 'beginner';
        else if (n <= 3) levelKey = 'novice';
        else if (n <= 5) levelKey = 'intermediate';
        else if (n <= 7) levelKey = 'advanced';
        else if (n <= 9) levelKey = 'expert';
        else if (n <= 11) levelKey = 'elite';
        else if (n <= 13) levelKey = 'pro';
        else if (n <= 15) levelKey = 'worldClass';
        else levelKey = 'legendary';
        break;

      case 'yds':
        final numPart = grade.split('.').length > 1 ? grade.split('.')[1].replaceAll(RegExp(r'[a-d]'), '') : '0';
        final n = int.tryParse(numPart) ?? 0;
        if (n <= 7) levelKey = 'beginner';
        else if (n <= 9) levelKey = 'novice';
        else if (n == 10) levelKey = 'intermediate';
        else if (n == 11) levelKey = 'advanced';
        else if (n == 12) levelKey = 'expert';
        else if (n == 13) levelKey = 'elite';
        else if (n == 14) levelKey = 'pro';
        else levelKey = 'worldClass';
        break;

      case 'french':
        final n = int.tryParse(grade[0]) ?? 3;
        if (n <= 5) levelKey = 'beginner';
        else if (n == 6) levelKey = 'intermediate';
        else if (n == 7) levelKey = grade.startsWith('7c') ? 'expert' : 'advanced';
        else if (n == 8) levelKey = grade.startsWith('8c') ? 'pro' : 'elite';
        else levelKey = 'worldClass';
        break;

      case 'fontScale':
        final n = int.tryParse(grade[0]) ?? 3;
        if (n <= 5) levelKey = 'beginner';
        else if (n == 6) levelKey = 'intermediate';
        else if (n == 7) levelKey = grade.startsWith('7c') ? 'expert' : 'advanced';
        else if (n == 8) levelKey = 'elite';
        else levelKey = 'worldClass';
        break;

      default:
        levelKey = 'beginner';
    }

    return levels[levelKey]!;
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

  void _handleShare() {
    const baseUrl = 'https://besetter-api-371038003203.asia-northeast3.run.app';
    final shareUrl = '$baseUrl/share/routes/${widget.routeData.id}';
    Share.share(shareUrl);
  }
}
