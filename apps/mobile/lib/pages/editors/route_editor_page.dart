import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

import '../../models/polygon_data.dart';
import '../../services/http_client.dart';
import '../../widgets/editors/endurance_route_editor.dart';
import '../../widgets/editors/bouldering_route_editor.dart';
import '../../widgets/editors/route_information_input_widget.dart';
import '../../models/image_data.dart';
import '../../models/route_data.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../viewers/route_viewer.dart';

enum RouteEditModeType {
  bouldering,
  endurance;

  String getModeName(BuildContext context) {
    switch (this) {
      case RouteEditModeType.bouldering:
        return AppLocalizations.of(context)!.boulderingMode;
      case RouteEditModeType.endurance:
        return AppLocalizations.of(context)!.enduranceMode;
    }
  }
}

enum EditType {
  create,
  edit;
}

class RouteEditorPage extends StatefulWidget {
  final ImageData? image;
  final PolygonData? polygonData;
  final String? routeId;

  final RouteEditModeType initialMode;
  final EditType editType;

  const RouteEditorPage({
    this.image,
    this.polygonData,
    this.routeId,
    this.initialMode = RouteEditModeType.bouldering,
    this.editType = EditType.create,
    Key? key,
  }) : super(key: key);

  @override
  _RouteEditorPageState createState() => _RouteEditorPageState();
}

class _RouteEditorPageState extends State<RouteEditorPage> {
  ImageData? _imageData;
  String? _imageUrl;
  late TransformationController _transformationController;
  List<Polygon> _polygons = [];
  ui.Image? _uiImage;
  Size? _imageSize;
  List<ui.Image?> _croppedImages = [];
  late File _processedImage;
  bool _isDisposed = false;
  List<Future<void>> _pendingOperations = [];
  bool _imagesLoaded = false;

  RouteEditModeType _currentModeType = RouteEditModeType.bouldering;

  GradeType? _selectedGradeType;
  String? _selectedGrade;
  Color? _selectedGradeColor;
  int? _gradeScore;
  String? _gradeError;
  String? _title;
  String? _description;

  // 저장 중인지 여부를 나타내는 상태 추가
  bool _isSaving = false;

  // 로딩 상태를 관리하는 변수 추가
  bool _isLoading = false;

  final GlobalKey<BoulderingRouteEditorState> _boulderingRouteEditorKey = GlobalKey();
  final GlobalKey<EnduranceRouteEditorState> _enduranceRouteEditorKey = GlobalKey();

  bool _showHoldOrder = true;

  RouteData? _initialRouteData;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _currentModeType = widget.initialMode;

    // 에디트 모드일 경우 route 데이터부터 로드
    if (widget.editType == EditType.edit && widget.routeId != null) {
      _loadExistingRoute();
    } else {
      // 새로운 route 생성 시에는 기존 방식대로 초기화
      _initializeImageData();
    }
  }

  Future<void> _initializeImageData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.image != null) {
        setState(() {
          _imageData = widget.image;
          _imageUrl = widget.image!.url;
        });
      } else {
        try {
          final response = await AuthorizedHttpClient.get('/images/${widget.polygonData?.imageId}');
          if (response.statusCode == 200) {
            final imageData = ImageData.fromJson(
              jsonDecode(utf8.decode(response.bodyBytes)),
            );
            if (!mounted) return;
            setState(() {
              _imageData = imageData;
              _imageUrl = imageData.url;
            });
          } else {
            throw Exception('이미지를 불러오는데 실패했습니다: ${response.statusCode}');
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('이미지를 불러오는데 실패했습니다: $e')),
          );
        }
      }

      if (widget.polygonData == null) {
        await _initializePolygonData();
      } else {
        setState(() {
          _polygons = widget.polygonData!.polygons;
        });
      }

      await _loadImage();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initializePolygonData() async {
    if (_imageData == null) return;

    try {
      final response = await AuthorizedHttpClient.get('/hold-polygons/${_imageData!.holdPolygonId}');
      if (response.statusCode == 200) {
        final polygonData = PolygonData.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
        if (!mounted) return;
        setState(() {
          _polygons = polygonData.polygons;
        });
      } else {
        throw Exception('Failed to load hold polygon data: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadHoldPolygonData)),
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      late final Uint8List bytes;
      final fileName = _imageUrl!.split('/').last.split('?').first;
      final tempDir = await getTemporaryDirectory();
      final cacheFile = File('${tempDir.path}/$fileName');

      if (await cacheFile.exists()) {
        bytes = await cacheFile.readAsBytes();
      } else {
        final response = await http.get(Uri.parse(_imageUrl!));
        if (response.statusCode != 200) {
          throw Exception('Failed to load image: ${response.statusCode}');
        }

        bytes = response.bodyBytes;
        await cacheFile.writeAsBytes(bytes);
      }

      _processedImage = cacheFile;

      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      setState(() {
        _uiImage = frameInfo.image;
        _imageSize = Size(_uiImage!.width.toDouble(), _uiImage!.height.toDouble());
        _initializeCroppedImages();
      });
    } catch (e) {
      print('Image loading error: $e');
    }
  }

  Future<void> _initializeCroppedImages() async {
    if (_imageSize == null || _uiImage == null) {
      print('Image is not loaded yet.');
      return;
    }

    _croppedImages = List<ui.Image?>.filled(_polygons.length, null);

    setState(() {
      _imagesLoaded = false;
    });

    for (int i = 0; i < _polygons.length; i++) {
      await _cropPolygonImage(_polygons[i], i);
    }

    if (mounted) {
      setState(() {
        _imagesLoaded = true;
      });
    }
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

    // 경계 상자 크기의 영역을 투명하게 설
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

  // 저장 메서드 추가
  Future<void> _saveRoute() async {
    if (_selectedGrade == null) {
      setState(() {
        _gradeError = AppLocalizations.of(context)!.selectGrade;
      });
      return;
    }

    // 볼더링 모드 검증
    if (_currentModeType == RouteEditModeType.bouldering) {
      final boulderingHolds = _boulderingRouteEditorKey.currentState?.getSelectedHolds();
      if (boulderingHolds == null || boulderingHolds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.noHoldsSelected)),
        );
        return;
      }

      if (boulderingHolds.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.selectAtLeastTwoHolds)),
        );
        return;
      }

      bool hasStarting = false;
      bool hasFinishing = false;

      for (var hold in boulderingHolds.values) {
        if (hold.type == BoulderingHoldType.starting) hasStarting = true;
        if (hold.type == BoulderingHoldType.finishing) hasFinishing = true;
      }

      if (!hasStarting) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.selectAtLeastOneStartHold)),
        );
        return;
      }

      if (!hasFinishing) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.selectAtLeastOneTopHold)),
        );
        return;
      }
    }
    // 지구력 모드 검증
    else {
      final enduranceHolds = _enduranceRouteEditorKey.currentState?.getSelectedHolds();
      if (enduranceHolds == null || enduranceHolds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.noHoldsSelected)),
        );
        return;
      }

      if (enduranceHolds.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.selectAtLeastTwoHolds)),
        );
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final Map<String, dynamic> routeData = {
        'type': _currentModeType == RouteEditModeType.bouldering ? 'bouldering' : 'endurance',
        'imageId': _imageData!.id,
        'gradeType': _selectedGradeType!.value,
        'grade': _selectedGrade,
        'gradeScore': _gradeScore,
        'gradeColor': _selectedGradeColor?.value.toRadixString(16).padLeft(8, '0'),
        'title': _title,
        'description': _description,
      };

      // 볼더링 모드일 경우
      if (_currentModeType == RouteEditModeType.bouldering) {
        final boulderingHolds = _boulderingRouteEditorKey.currentState?.getSelectedHolds();
        if (boulderingHolds != null) {
          routeData['boulderingHolds'] = boulderingHolds.entries
              .map((entry) => {
                    'polygonId': entry.key,
                    'type': entry.value.type.toString().split('.').last,
                    'markingCount': entry.value.markingCount,
                    'checkpointScore': entry.value.checkpointScore,
                  })
              .toList();
        }
      }
      // 지구력 모드일 경우
      else {
        final enduranceHolds = _enduranceRouteEditorKey.currentState?.getSelectedHolds();
        if (enduranceHolds != null) {
          routeData['enduranceHolds'] = enduranceHolds
              .map((hold) => {
                    'polygonId': hold.polygonId,
                    'gripHand': hold.gripHand?.toString().split('.').last,
                  })
              .toList();
        }
      }

      if (widget.editType == EditType.create) {
        final response = await AuthorizedHttpClient.post(
          '/routes',
          body: routeData,
        );

        if (response.statusCode == 201) {
          if (!mounted) return;
          final routeData = RouteData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => RouteViewer(routeData: routeData),
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.routeSaved)),
          );
        } else {
          throw Exception('Route save failed: ${response.statusCode}');
        }
      } else if (widget.editType == EditType.edit) {
        final response = await AuthorizedHttpClient.patch(
          '/routes/${widget.routeId}',
          body: routeData,
        );

        if (response.statusCode == 200) {
          if (!mounted) return;
          final routeData = RouteData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => RouteViewer(routeData: routeData),
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.routeUpdated)),
          );
        } else {
          throw Exception('Route modify failed: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.failedSaveRoute}: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // 기존 루트 데이터를 로드하는 메서드 추가
  Future<void> _loadExistingRoute() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. 먼저 route 데이터를 가져옵니다
      final response = await AuthorizedHttpClient.get('/routes/${widget.routeId}');
      if (response.statusCode != 200) {
        throw Exception('${AppLocalizations.of(context)!.failedLoadRouteData}: ${response.statusCode}');
      }

      final routeData = RouteData.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );

      // 초기 데이터 저장
      _initialRouteData = routeData;

      if (!mounted) return;

      // 2. image와 holdPolygon 데이터를 병렬로 가져옵니다
      final futures = await Future.wait([
        AuthorizedHttpClient.get('/images/${routeData.imageId}'),
        AuthorizedHttpClient.get('/hold-polygons/${routeData.holdPolygonId}'),
      ]);

      final imageResponse = futures[0];
      final polygonResponse = futures[1];

      if (imageResponse.statusCode != 200) {
        throw Exception('${AppLocalizations.of(context)!.failedLoadImageData}: ${imageResponse.statusCode}');
      }
      if (polygonResponse.statusCode != 200) {
        throw Exception('${AppLocalizations.of(context)!.failedLoadHoldPolygonData}: ${polygonResponse.statusCode}');
      }

      final imageData = ImageData.fromJson(
        jsonDecode(utf8.decode(imageResponse.bodyBytes)),
      );
      final polygonData = PolygonData.fromJson(
        jsonDecode(utf8.decode(polygonResponse.bodyBytes)),
      );

      if (!mounted) return;

      // 3. 상태 업데이트
      setState(() {
        _imageData = imageData;
        _imageUrl = imageData.url;
        _polygons = polygonData.polygons;

        // route 관련 상태 업데이트
        _selectedGradeType = GradeType.values.firstWhere((type) => type.value == routeData.gradeType);
        _selectedGrade = routeData.grade;
        _selectedGradeColor = routeData.gradeColor != null ? Color(int.parse(routeData.gradeColor!, radix: 16)) : null;
        _gradeScore = routeData.gradeScore;
        _title = routeData.title;
        _description = routeData.description;
        _currentModeType =
            routeData.type == RouteType.bouldering ? RouteEditModeType.bouldering : RouteEditModeType.endurance;
      });

      // 4. 이미지 로드 시작
      await _loadImage();

      // 5. 이미지가 완전히 로드된 후에 홀드 데이터 설정
      await _waitForImagesLoaded();

      if (!mounted) return;

      // 6. 홀드 데이터 초기화
      if (routeData.type == RouteType.bouldering && routeData.boulderingHolds != null) {
        _boulderingRouteEditorKey.currentState?.initializeFromRouteData(routeData.boulderingHolds!);
      } else if (routeData.type == RouteType.endurance && routeData.enduranceHolds != null) {
        _enduranceRouteEditorKey.currentState?.initializeFromRouteData(routeData.enduranceHolds!);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.failedLoadRouteData}: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 이미지가 완전히 로드될 때까지 기다리는 헬퍼 메서드
  Future<void> _waitForImagesLoaded() async {
    while (!_imagesLoaded) {
      await Future.delayed(Duration(milliseconds: 100));
      if (!mounted) return;
    }
  }

  bool _hasUnsavedChanges() {
    if (widget.editType == EditType.create) {
      // 새로운 루트 생성 시
      if (_title != null || _description != null) {
        return true;
      }

      if (_currentModeType == RouteEditModeType.bouldering) {
        final boulderingHolds = _boulderingRouteEditorKey.currentState?.getSelectedHolds();
        return boulderingHolds != null && boulderingHolds.isNotEmpty;
      } else {
        final enduranceHolds = _enduranceRouteEditorKey.currentState?.getSelectedHolds();
        return enduranceHolds != null && enduranceHolds.isNotEmpty;
      }
    } else {
      if (_initialRouteData == null) return false;

      // 공통 변경사항 확인
      if (_selectedGradeType?.value != _initialRouteData!.gradeType ||
          _selectedGrade != _initialRouteData!.grade ||
          _gradeScore != _initialRouteData!.gradeScore ||
          _selectedGradeColor?.value.toRadixString(16).padLeft(8, '0') != _initialRouteData!.gradeColor ||
          _title != _initialRouteData!.title ||
          _description != _initialRouteData!.description) {
        return true;
      }

      // 모드별 홀드 변경사항 확인
      if (_currentModeType == RouteEditModeType.bouldering) {
        final currentHolds = _boulderingRouteEditorKey.currentState?.getSelectedHolds();
        if (currentHolds == null || _initialRouteData!.boulderingHolds == null) return false;

        // 홀드 개수가 다르면 변경사항 있음
        if (currentHolds.length != _initialRouteData!.boulderingHolds!.length) return true;

        // 각 홀드의 속성 비교
        for (var initialHold in _initialRouteData!.boulderingHolds!) {
          final currentHold = currentHolds[initialHold.polygonId];
          if (currentHold == null) return true;

          if (currentHold.type.toString().split('.').last != initialHold.type ||
              currentHold.markingCount != initialHold.markingCount ||
              currentHold.checkpointScore != initialHold.checkpointScore) {
            return true;
          }
        }
      } else {
        final currentHolds = _enduranceRouteEditorKey.currentState?.getSelectedHolds();
        if (currentHolds == null || _initialRouteData!.enduranceHolds == null) return false;

        // 홀드 개수가 다르면 변경사항 있음
        if (currentHolds.length != _initialRouteData!.enduranceHolds!.length) return true;

        // 순서와 속성을 모두 비교
        for (int i = 0; i < currentHolds.length; i++) {
          final currentHold = currentHolds[i];
          final initialHold = _initialRouteData!.enduranceHolds![i];

          if (currentHold.polygonId != initialHold.polygonId ||
              currentHold.gripHand?.toString().split('.').last != initialHold.gripHand) {
            return true;
          }
        }
      }

      return false;
    }
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
                      widget.editType == EditType.create
                          ? AppLocalizations.of(context)!.unsavedRouteWarning
                          : AppLocalizations.of(context)!.unsavedChangesWarning,
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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(AppLocalizations.of(context)!.routeEdit),
            SizedBox(width: 10),
            Text(
              _currentModeType.getModeName(context),
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
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
          if (_currentModeType == RouteEditModeType.endurance)
            IconButton(
              icon: Icon(_showHoldOrder ? Icons.visibility : Icons.visibility_off),
              onPressed: () {
                setState(() {
                  _showHoldOrder = !_showHoldOrder;
                });
              },
              tooltip: AppLocalizations.of(context)!.holdOrderDisplay,
            ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                if (_uiImage != null)
                  _currentModeType == RouteEditModeType.endurance
                      ? EnduranceRouteEditor(
                          key: _enduranceRouteEditorKey,
                          processedImage: _processedImage,
                          imageSize: _imageSize,
                          polygons: _polygons,
                          croppedImages: _croppedImages,
                          transformationController: _transformationController,
                          imagesLoaded: _imagesLoaded,
                          showHoldOrder: _showHoldOrder,
                        )
                      : BoulderingRouteEditor(
                          key: _boulderingRouteEditorKey,
                          processedImage: _processedImage,
                          imageSize: _imageSize,
                          polygons: _polygons,
                          croppedImages: _croppedImages,
                          transformationController: _transformationController,
                          imagesLoaded: _imagesLoaded,
                        ),
                SizedBox(height: 20),
                RouteInformationInput(
                  onGradeTypeChanged: (type) {
                    setState(() {
                      _selectedGradeType = type;
                    });
                  },
                  onGradeChanged: (grade) {
                    setState(() {
                      _selectedGrade = grade;
                      _gradeError = grade == null ? AppLocalizations.of(context)!.selectGrade : null;
                    });
                  },
                  onGradeColorChanged: (gradeColor) {
                    setState(() {
                      _selectedGradeColor = gradeColor;
                    });
                  },
                  onGradeScoreChanged: (gradeScore) {
                    setState(() {
                      _gradeScore = gradeScore;
                    });
                  },
                  onTitleChanged: (title) {
                    setState(() {
                      _title = title;
                    });
                  },
                  onDescriptionChanged: (description) {
                    setState(() {
                      _description = description;
                    });
                  },
                  selectedGradeType: _selectedGradeType,
                  selectedGrade: _selectedGrade,
                  selectedGradeColor: _selectedGradeColor,
                  gradeScore: _gradeScore,
                  gradeError: _gradeError,
                  title: _title,
                  description: _description,
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: FilledButton(
                    onPressed: _isSaving ? null : _saveRoute,
                    style: FilledButton.styleFrom(
                      minimumSize: Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSaving
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(AppLocalizations.of(context)!.saving),
                            ],
                          )
                        : Text(AppLocalizations.of(context)!.saveRoute),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.loadingRouteData,
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
