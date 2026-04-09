import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

import '../../models/polygon_data.dart';
import '../../models/place_data.dart';
import '../../services/exif_service.dart';
import '../../services/http_client.dart';
import '../../widgets/editors/spray_wall_edit_menu.dart';
import '../../widgets/editors/spray_wall_polygon_widget.dart';
import '../../widgets/editors/spray_wall_information_input_widget.dart';
import '../../pages/editors/route_editor_page.dart';
import '../../models/image_data.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class AddingHold {
  final String type;
  Offset position;
  double radius;
  bool isEditing;

  AddingHold({
    this.type = 'circle',
    required this.position,
    required this.radius,
    this.isEditing = false,
  });
}

class SprayWallEditorPage extends StatefulWidget {
  final File? imageFile;
  final ImageData? image;
  final PolygonData polygonData;

  const SprayWallEditorPage({
    this.imageFile,
    this.image,
    required this.polygonData,
    Key? key,
  })  : assert(imageFile != null || image != null, 'Image file or image info is required.'),
        assert(!(imageFile != null && image != null), 'Image file and image info cannot be provided simultaneously.'),
        super(key: key);

  @override
  _SprayWallEditorPageState createState() => _SprayWallEditorPageState();
}

class _SprayWallEditorPageState extends State<SprayWallEditorPage> {
  File? _imageFile;
  String? _imageUrl;
  double _scale = 1.0;
  bool _showScale = false;
  Timer? _scaleTimer;
  late TransformationController _transformationController;
  List<Polygon> _polygons = [];
  ui.Image? _uiImage;
  int? _selectedPolygonId;
  List<Map<String, dynamic>> _jsonPatchOperations = [];
  Size? _imageSize;
  List<ui.Image?> _croppedImages = [];
  late File _processedImage;
  bool _isDisposed = false;
  List<Future<void>> _pendingOperations = []; // 진행 중인 작업을 추적

  double? _initialRadius;
  Offset? _initialDragPosition;

  PlaceData? _selectedPlace;
  double? _exifLatitude;
  double? _exifLongitude;
  final TextEditingController _wallNameController = TextEditingController();
  String? _wallNameError;
  DateTime? _wallExpirationDate;
  bool _isGymInfoInvalid = false; // Gym 정보 유효성 상태 추가
  bool _isDateInvalid = false; // 날짜 유효성 상태 추가 (필요시 사용)

  List<AddingHold> _addingHolds = [];
  HoldEditMode _editMode = HoldEditMode.none; // 편집 모드 상태 변수 추가

  bool _isSaving = false;
  bool _showGlassOverlay = true;

  @override
  void initState() {
    super.initState();
    _imageFile = widget.imageFile;
    _imageUrl = widget.image?.url;
    _transformationController = TransformationController();
    _loadImage();
    setState(() {
      _polygons = widget.polygonData.polygons;
      _wallNameController.text = widget.polygonData.wallName ?? '';
      _wallExpirationDate = widget.polygonData.wallExpirationDate;
      _selectedPlace = widget.polygonData.place;
    });
    _extractExifGps();
  }

  @override
  void dispose() {
    _scaleTimer?.cancel();
    _wallNameController.dispose();
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      late final Uint8List bytes;
      if (_imageFile != null) {
        bytes = await _imageFile!.readAsBytes();
        _processedImage = _imageFile!;
      } else if (_imageUrl != null) {
        // URL에서 파일명(UUID) 추출
        final fileName = _imageUrl!.split('/').last.split('?').first;

        // 캐시 디렉토리에서 이미지 찾기
        final tempDir = await getTemporaryDirectory();
        final cacheFile = File('${tempDir.path}/$fileName');

        // 캐시된 파일이 있으면 사용, 없으면 다운로드
        if (await cacheFile.exists()) {
          bytes = await cacheFile.readAsBytes();
        } else {
          final response = await http.get(Uri.parse(_imageUrl!));
          if (response.statusCode != 200) {
            throw Exception('Failed to load image: ${response.statusCode}');
          }

          bytes = response.bodyBytes;
          // 캐시 저장
          await cacheFile.writeAsBytes(bytes);
        }

        _processedImage = cacheFile;
      }

      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      setState(() {
        _uiImage = frameInfo.image;
        _imageSize = Size(_uiImage!.width.toDouble(), _uiImage!.height.toDouble());
        _initializeCroppedImages();
      });
    } catch (e) {
      print('Image loading error: $e');
      // 에러 처리 로직 추가
    }
  }

  // 크롭 이미지를 초기화하는 메서드 추가
  Future<void> _initializeCroppedImages() async {
    if (_imageSize == null || _uiImage == null) {
      print('Image is not loaded yet.');
      return;
    }

    _croppedImages = List<ui.Image?>.filled(_polygons.length, null, growable: true);
    for (int i = 0; i < _polygons.length; i++) {
      await _cropPolygonImage(_polygons[i], i);
    }
  }

  Future<void> _extractExifGps() async {
    if (widget.imageFile != null) {
      final gps = await ExifService.extractGpsFromFile(widget.imageFile!);
      if (gps != null && mounted) {
        setState(() {
          _exifLatitude = gps.latitude;
          _exifLongitude = gps.longitude;
        });
      }
    } else if (widget.polygonData.latitude != null && widget.polygonData.longitude != null) {
      setState(() {
        _exifLatitude = widget.polygonData.latitude;
        _exifLongitude = widget.polygonData.longitude;
      });
    }
  }

  void _updateScale() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
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

  List<double> _adjustPoint(List<int> point, double imageWidth, double imageHeight) {
    final x = (point[0] / imageWidth) * _uiImage!.width;
    final y = (point[1] / imageHeight) * _uiImage!.height;
    return [x, y];
  }

  // 폴리곤 영역을 크롭하는 메서드 추가
  Future<void> _cropPolygonImage(Polygon polygon, int index) async {
    if (_isDisposed) return;

    // 폴리곤의 경계 상자 계산
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

    // 폴리곤 경로 생성 (경계 상자 기준으로 좌표 조정)
    if (polygon.points.isNotEmpty) {
      final firstPoint = _adjustPoint(polygon.points[0], _imageSize!.width, _imageSize!.height);
      path.moveTo(firstPoint[0] - minX, firstPoint[1] - minY);

      for (var i = 1; i < polygon.points.length; i++) {
        final point = _adjustPoint(polygon.points[i], _imageSize!.width, _imageSize!.height);
        path.lineTo(point[0] - minX, point[1] - minY);
      }
      path.close();
    }

    // 경계 상자 크기의 영역을 투명하게 설정
    final boundingRect = Rect.fromLTWH(0, 0, boundingWidth.toDouble(), boundingHeight.toDouble());
    canvas.saveLayer(boundingRect, Paint());

    // 폴리곤 영역만 클리핑
    canvas.clipPath(path);

    // 원본 이미지에서 경계 상자 영역만 그리기
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
          _croppedImages[index] = img;
        });
      }
    });

    _pendingOperations.add(operation);
    await operation;
    _pendingOperations.remove(operation);
  }

  void _onPolygonTap(int polygonId) {
    if (!mounted) return;

    setState(() {
      _showGlassOverlay = false;
      // 현재 편집 중인 addingHold가 있다면 편집 모드 해제
      if (_editMode == HoldEditMode.addingHold) {
        for (var hold in _addingHolds) {
          hold.isEditing = false;
        }
      }

      if (_selectedPolygonId == polygonId) {
        _selectedPolygonId = null;
        _editMode = HoldEditMode.none;
      } else {
        _selectedPolygonId = polygonId;
        _editMode = HoldEditMode.polygon;
      }
    });
  }

  void _cancelEdit() {
    setState(() {
      _selectedPolygonId = null;
      _editMode = HoldEditMode.none;
    });
  }

  void _deleteSelectedHold() {
    if (_selectedPolygonId == null) return;

    final polygonIndex = _polygons.indexWhere((p) => p.polygonId == _selectedPolygonId);
    if (polygonIndex != -1) {
      final polygon = _polygons[polygonIndex];
      final updatedPolygon = Polygon(
        polygonId: polygon.polygonId,
        points: polygon.points,
        type: polygon.type,
        score: polygon.score,
        isDeleted: true,
      );

      _jsonPatchOperations.add({
        "op": "replace",
        "path": "/polygons/$polygonIndex",
        "value": updatedPolygon.toJson(),
      });

      setState(() {
        _polygons[polygonIndex] = updatedPolygon;
      });
    }
    _editMode = HoldEditMode.none;
    _selectedPolygonId = null;
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    if (!_validateInputs()) {
      // _validateInputs 내부에서 setState를 호출하여 UI 업데이트
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final initialPlaceId = widget.polygonData.place?.id;
      final initialWallName = widget.polygonData.wallName ?? '';
      final initialWallExpirationDate = widget.polygonData.wallExpirationDate;

      final currentWallName = _wallNameController.text.trim();

      if (_selectedPlace != null && _selectedPlace!.id != initialPlaceId) {
        _jsonPatchOperations.add({
          "op": "replace",
          "path": "/placeId",
          "value": _selectedPlace!.id,
        });
      }

      if (currentWallName != initialWallName) {
        _jsonPatchOperations.add({
          "op": "replace",
          "path": "/wallName",
          "value": currentWallName,
        });
      }

      if (_wallExpirationDate != initialWallExpirationDate) {
        _jsonPatchOperations.add({
          "op": "replace",
          "path": "/wallExpirationDate",
          "value": _wallExpirationDate?.toIso8601String(),
        });
      }

      final nextPolygonId = _getNextPolygonId();
      for (var i = 0; i < _addingHolds.length; i++) {
        final hold = _addingHolds[i];
        final points = _createCirclePoints(hold.position, hold.radius, 32);
        final newPolygon = Polygon(
          polygonId: nextPolygonId + i,
          points: points,
          type: 'hold_feedback',
          feedbackStatus: 'pending',
        );

        _jsonPatchOperations.add({
          "op": "add",
          "path": "/polygons/-",
          "value": newPolygon.toJson(),
        });
      }

      if (_jsonPatchOperations.isEmpty) {
        return showDialog(
          context: context,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.wallCheckCompleteAndSetProblem,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildIconButton(
                          context: context,
                          icon: 'assets/icons/bouldering_button.svg',
                          label: 'BOULDERING',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RouteEditorPage(
                                  image: widget.image,
                                  polygonData: widget.polygonData,
                                  initialMode: RouteEditModeType.bouldering,
                                ),
                              ),
                              ModalRoute.withName('/'),
                            );
                          },
                        ),
                        _buildIconButton(
                          context: context,
                          icon: 'assets/icons/endurance_button.svg',
                          label: 'ENDURANCE',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RouteEditorPage(
                                  image: widget.image,
                                  polygonData: widget.polygonData,
                                  initialMode: RouteEditModeType.endurance,
                                ),
                              ),
                              ModalRoute.withName('/'),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      child: Text(AppLocalizations.of(context)!.goBack),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }

      final response = await AuthorizedHttpClient.patch(
        '/hold-polygons/${widget.polygonData.id}',
        body: _jsonPatchOperations,
      );

      if (response.statusCode == 204) {
        if (!mounted) return;

        showDialog(
          context: context,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.successfullyUpdatedAndSetProblem,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildIconButton(
                          context: context,
                          icon: 'assets/icons/bouldering_button.svg',
                          label: 'BOULDERING',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RouteEditorPage(
                                  image: widget.image,
                                  polygonData: widget.polygonData,
                                  initialMode: RouteEditModeType.bouldering,
                                ),
                              ),
                            );
                          },
                        ),
                        _buildIconButton(
                          context: context,
                          icon: 'assets/icons/endurance_button.svg',
                          label: 'ENDURANCE',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RouteEditorPage(
                                  image: widget.image,
                                  polygonData: widget.polygonData,
                                  initialMode: RouteEditModeType.endurance,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      child: Text(AppLocalizations.of(context)!.goBack),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      } else {
        throw Exception('Failed to save: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.errorWhileSaving}: $e')),
      );
    }
  }

  // 홀드 추가 모드 토글 메서드
  void _handleAddHoldButton() {
    setState(() {
      // 현재 상태와 관계없이 readyToAdd 모드로 전환
      _editMode = HoldEditMode.readyToAdd;

      // 모든 편집 상태 초기화
      _selectedPolygonId = null;
      for (var hold in _addingHolds) {
        hold.isEditing = false;
      }
    });
  }

  // 화면 탭 핸들
  void _handleTapUp(TapUpDetails details, Size imageSize) {
    if (_editMode == HoldEditMode.readyToAdd) {
      // readyToAdd 상태에서만 처리
      setState(() {
        _showGlassOverlay = false;
        // 기존 홀드들 편집 모드 해제
        for (var hold in _addingHolds) {
          hold.isEditing = false;
        }

        // 새 홀드 추가 (편집 모드로)
        _addingHolds.add(AddingHold(
          position: details.localPosition,
          radius: 20.0,
          isEditing: true,
        ));

        _editMode = HoldEditMode.addingHold; // 홀드 추가 후 편집 모드로 전환
      });
    }
  }

  // 새 홀드 확인

  // _SprayWallEditorPageState 클래스에 새로운 메서드 추가
  List<List<int>> _createCirclePoints(Offset center, double radius, int segments) {
    List<List<int>> points = [];
    for (int i = 0; i < segments; i++) {
      final angle = (2 * math.pi * i) / segments;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);

      // 이미지 크기 맞게 좌표 변환
      final imageX = (x / MediaQuery.of(context).size.width * _imageSize!.width).round();
      final imageY =
          (y / (MediaQuery.of(context).size.width / (_imageSize!.width / _imageSize!.height)) * _imageSize!.height)
              .round();

      points.add([imageX, imageY]);
    }
    return points;
  }

  int _getNextPolygonId() {
    if (_polygons.isEmpty) return 1;
    return _polygons.map((p) => p.polygonId).reduce(math.max) + 1;
  }

  // 유효성 검사 메서드 추가
  bool _validateInputs() {
    bool isValid = true;
    bool gymInfoInvalid = false;
    bool dateInvalid = false; // 날짜 관련 유효성 검사 필요 시 추가

    if (_selectedPlace == null) {
      isValid = false;
      gymInfoInvalid = true;
    }

    if (_wallNameController.text.trim().isEmpty) {
      _wallNameError = AppLocalizations.of(context)!.enterWallName;
      isValid = false;
      gymInfoInvalid = true;
    } else {
      _wallNameError = null;
    }

    // 예시: 날짜 유효성 검사 (필요한 경우 활성화)
    // if (_wallExpirationDate == null) {
    //   // _dateError = AppLocalizations.of(context)!.selectWallExpiryDate; // 에러 메시지 필요 시 추가
    //   isValid = false;
    //   dateInvalid = true;
    // } else {
    //   // _dateError = null;
    // }

    // setState를 호출하여 invalid 상태 업데이트 및 UI 재빌드 트리거
    setState(() {
      _isGymInfoInvalid = gymInfoInvalid;
      _isDateInvalid = dateInvalid; // 날짜 유효성 검사 결과 반영
    });

    return isValid;
  }

  // 아이콘 버튼 위젯 추가
  Widget _buildIconButton({
    required BuildContext context,
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SvgPicture.asset(
              icon,
              width: 60,
              height: 60,
            ),
          ),
        ],
      ),
    );
  }

  void _handleAddingHoldDragUpdate(DragUpdateDetails details, AddingHold hold) {
    setState(() {
      hold.position += details.delta;
    });
  }

  void _handleAddingHoldResize(DragUpdateDetails details, int cornerIndex, AddingHold hold) {
    if (_initialRadius == null || _initialDragPosition == null) {
      _initialRadius = hold.radius;
      _initialDragPosition = details.localPosition;
      return;
    }

    // 드래그 벡터 (현재 위치 - 시작 위치)
    final dragVector = details.localPosition - _initialDragPosition!;
    final dragDistance = dragVector.distance;

    // 각 꼭지점에서의 방향 판단
    int direction;
    switch (cornerIndex) {
      case 0: // 좌상단
        direction = (dragVector.dx > 0 || dragVector.dy > 0) ? -1 : 1;
        break;
      case 1: // 우상단
        direction = (dragVector.dx < 0 || dragVector.dy > 0) ? -1 : 1;
        break;
      case 2: // 우하단
        direction = (dragVector.dx < 0 || dragVector.dy < 0) ? -1 : 1;
        break;
      case 3: // 좌하단
        direction = (dragVector.dx > 0 || dragVector.dy < 0) ? -1 : 1;
        break;
      default:
        return;
    }

    setState(() {
      hold.radius = math.max(4.0, _initialRadius! + (dragDistance * direction));
    });
  }

  void _deleteAddingHold(AddingHold hold) {
    setState(() {
      _addingHolds.remove(hold);
      _editMode = HoldEditMode.none;
    });
  }

  void _handleAddingHoldTap(AddingHold tappedHold) {
    setState(() {
      _showGlassOverlay = false;
      // 현재 선택된 폴리곤이 있다면 선택 해제
      _selectedPolygonId = null;

      // 모든 홀드의 편집 모드 해제 후 선택된 홀드만 편집 모드로
      for (var hold in _addingHolds) {
        hold.isEditing = (hold == tappedHold);
      }
      _editMode = tappedHold.isEditing ? HoldEditMode.addingHold : HoldEditMode.none;
    });
  }

  // 빈 영역 탭 핸들러 추가
  void _handleBackgroundTap() {
    setState(() {
      _showGlassOverlay = false;
      // 모든 홀드의 편집 모드 해제
      for (var hold in _addingHolds) {
        hold.isEditing = false;
      }
      _editMode = HoldEditMode.none;
    });
  }

  bool _hasUnsavedChanges() {
    final initialPlaceId = widget.polygonData.place?.id;
    final initialWallName = widget.polygonData.wallName ?? '';
    final initialWallExpirationDate = widget.polygonData.wallExpirationDate;

    final currentWallName = _wallNameController.text.trim();

    return _selectedPlace?.id != initialPlaceId ||
        currentWallName != initialWallName ||
        _wallExpirationDate != initialWallExpirationDate ||
        _addingHolds.isNotEmpty ||
        _jsonPatchOperations.isNotEmpty;
  }

  Future<bool> _showUnsavedChangesDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.stopEditingPrompt,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)!.unsavedChanges,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                          ),
                          child: Text(
                            AppLocalizations.of(context)!.continueEditing,
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                          ),
                          child: Text(AppLocalizations.of(context)!.exit),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(AppLocalizations.of(context)!.sprayWallEdit),
            leading: IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () async {                
                await Future.wait(_pendingOperations);
                if (!mounted) return;

                if (_hasUnsavedChanges()) {
                  final shouldPop = await _showUnsavedChangesDialog();
                  if (shouldPop) {
                    if (!mounted) return;
                    Navigator.pop(context);
                  }
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            actions: [
              PopupMenuButton<String>(
                icon: Icon(Icons.menu),
                onSelected: (String value) {
                  if (value == 'add_hold') {
                    _handleAddHoldButton();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'add_hold',
                    child: Row(
                      children: [
                        Icon(Icons.add_circle_outline),
                        SizedBox(width: 8),
                        Text(AppLocalizations.of(context)!.addHold),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (_uiImage != null)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final screenWidth = MediaQuery.of(context).size.width;
                            final imageRatio = _imageSize!.width / _imageSize!.height;
                            final imageHeight = screenWidth / imageRatio;

                            return GestureDetector(
                              onTapUp: _editMode == HoldEditMode.readyToAdd
                                  ? (details) => _handleTapUp(details, Size(screenWidth, imageHeight))
                                  : null,
                              onTap: _editMode == HoldEditMode.readyToAdd ? null : _handleBackgroundTap,
                              child: Stack(
                                children: [
                                  SizedBox(
                                    width: screenWidth,
                                    height: imageHeight,
                                    child: InteractiveViewer(
                                      transformationController: _transformationController,
                                      minScale: 0.5,
                                      maxScale: 4.0,
                                      onInteractionUpdate: (details) {
                                        _updateScale();
                                      },
                                      child: Stack(
                                        children: [
                                          Image.file(
                                            _processedImage,
                                            width: screenWidth,
                                            height: imageHeight,
                                            fit: BoxFit.contain,
                                          ),
                                          ..._polygons
                                              .where((polygon) => polygon.isDeleted != true)
                                              .map((polygon) => SprayWallHoldVolumePolygon(
                                                    polygon: polygon,
                                                    imageSize: _imageSize!,
                                                    containerSize: Size(screenWidth, imageHeight),
                                                    isSelected: _selectedPolygonId == polygon.polygonId,
                                                    onTap: _editMode != HoldEditMode.readyToAdd
                                                        ? () => _onPolygonTap(polygon.polygonId)
                                                        : null,
                                                  )),
                                          ..._addingHolds.map((hold) => SprayWallDraggableCircle(
                                                position: hold.position,
                                                radius: hold.radius,
                                                isEditing: hold.isEditing,
                                                onTap: _editMode != HoldEditMode.readyToAdd
                                                    ? () => _handleAddingHoldTap(hold)
                                                    : null,
                                                onDragUpdate: (details) => _handleAddingHoldDragUpdate(details, hold),
                                                onResizeUpdate: (details, cornerIndex) =>
                                                    _handleAddingHoldResize(details, cornerIndex, hold),
                                                onDelete: () => _deleteAddingHold(hold),
                                                onResizeStart: () {
                                                  _initialRadius = null;
                                                  _initialDragPosition = null;
                                                },
                                                onResizeEnd: () {
                                                  _initialRadius = null;
                                                  _initialDragPosition = null;
                                                },
                                              )),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_showScale)
                                    Positioned(
                                      right: 16,
                                      bottom: 16,
                                      child: AnimatedOpacity(
                                        opacity: _showScale ? 1.0 : 0.0,
                                        duration: const Duration(milliseconds: 500),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.7),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '${AppLocalizations.of(context)!.zoomIn}: ${(_scale * 100).toStringAsFixed(0)}%',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_showGlassOverlay)
                                    Positioned(
                                      bottom: 24,
                                      left: 24,
                                      right: 24,
                                      child: GestureDetector(
                                        onTap: () => setState(() => _showGlassOverlay = false),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: BackdropFilter(
                                            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                            child: Container(
                                              padding: const EdgeInsets.all(17),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF5F6F7).withOpacity(0.6),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.white.withOpacity(0.2),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          AppLocalizations.of(context)!.activeEditing,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: Color(0xFF595C5D),
                                                            letterSpacing: 1.1,
                                                          ),
                                                        ),
                                                        Text(
                                                          AppLocalizations.of(context)!.tapHoldsToToggleSelection,
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.bold,
                                                            color: Color(0xFF2C2F30),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.close_rounded,
                                                    size: 20,
                                                    color: Color(0xFF595C5D),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        )
                      else
                        Center(child: CircularProgressIndicator()),
                      if (_editMode == HoldEditMode.readyToAdd)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            AppLocalizations.of(context)!.tapPositionToAdd,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      SprayWallEditMenu(
                        onDelete: _deleteSelectedHold,
                        croppedImage: _selectedPolygonId != null
                            ? _croppedImages[_polygons.indexWhere((p) => p.polygonId == _selectedPolygonId)]
                            : null,
                        editMode: _editMode,
                      ),
                      SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SprayWallInformationInput(
                              selectedPlace: _selectedPlace,
                              onPlaceChanged: (place) => setState(() {
                                _selectedPlace = place;
                                _isGymInfoInvalid = false;
                              }),
                              exifLatitude: _exifLatitude,
                              exifLongitude: _exifLongitude,
                              wallNameController: _wallNameController,
                              onWallNameChanged: (value) => setState(() {
                                _wallNameError = null;
                                _isGymInfoInvalid = false;
                              }),
                              onWallExpirationDateChanged: (date) => setState(() {
                                _wallExpirationDate = date;
                                _isDateInvalid = false;
                              }),
                              wallNameError: _wallNameError,
                              wallExpirationDate: _wallExpirationDate,
                              isGymInfoInvalid: _isGymInfoInvalid,
                              isDateInvalid: _isDateInvalid,
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: FilledButton(
                                  onPressed: _isSaving ? null : _saveChanges,
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: _isSaving
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : Text(
                                          AppLocalizations.of(context)!.sprayWallEditComplete,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isSaving)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}
