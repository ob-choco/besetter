import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;

import '../../models/polygon_data.dart';
import 'bouldering_route_editor_image_viewer.dart';
import 'bouldering_hold_edit_menu.dart';
import '../../models/route_data.dart';

const Color neonLimeColor = Color.fromRGBO(188, 244, 33, 1.0);

class HoldProperty {
  BoulderingHoldType type;
  int? markingCount; // starting 홀드일 때만 사용
  int? checkpointScore; // checkpoint1, checkpoint2일 때만 사용

  HoldProperty({
    this.type = BoulderingHoldType.normal,
    this.markingCount,
    this.checkpointScore,
  });
}

class BoulderingRouteEditor extends StatefulWidget {
  final File processedImage;
  final Size? imageSize;
  final List<Polygon> polygons;
  final List<ui.Image?> croppedImages;
  final TransformationController transformationController;
  final bool imagesLoaded;

  const BoulderingRouteEditor({
    Key? key,
    required this.processedImage,
    required this.imageSize,
    required this.polygons,
    required this.croppedImages,
    required this.transformationController,
    required this.imagesLoaded,
  }) : super(key: key);

  @override
  State<BoulderingRouteEditor> createState() => BoulderingRouteEditorState();
}

class BoulderingRouteEditorState extends State<BoulderingRouteEditor> {
  Map<int, HoldProperty> _selectedHolds = {};
  bool _isHoldEditMode = false;
  int? _editingHoldId;
  bool _isMarkingCountMode = false;

  int get _totalMarkingCount {
    int total = 0;
    for (var property in _selectedHolds.values) {
      if (property.markingCount != null) {
        total += property.markingCount!;
      }
    }
    return total;
  }

  int get _totalFeetMarkingCount {
    int total = 0;
    for (var entry in _selectedHolds.entries) {
      if (entry.value.type == BoulderingHoldType.feetOnly && entry.value.markingCount != null) {
        total += entry.value.markingCount!;
      }
    }
    return total;
  }

  void _adjustMarkingsForNewCount(int holdId, int newCount) {
    final holdProperty = _selectedHolds[holdId]!;
    final isFeetOnly = holdProperty.type == BoulderingHoldType.feetOnly;
    final maxAllowed = isFeetOnly ? 2 : 4;

    // 요청된 마킹 수가 해당 홀드의 최대 허용치를 초과하는지 확인
    int requestedCount = newCount.clamp(0, maxAllowed);

    // feetOnly 홀드의 마킹 조정
    if (isFeetOnly && requestedCount > 0) {
      for (var entry in _selectedHolds.entries.toList()) {
        if (entry.key != holdId &&
            entry.value.type == BoulderingHoldType.feetOnly &&
            entry.value.markingCount != null &&
            entry.value.markingCount! > 0) {
          if (entry.value.markingCount == 1 && requestedCount == 1) {
            break;
          }
          int newCount = entry.value.markingCount! - requestedCount;
          entry.value.markingCount = newCount < 0 ? 0 : newCount;
          break;
        }
      }

      // starting 홀드의 마킹 개수 합 (현재 홀드 제외)
      int totalStartingMarkings = 0;
      for (var entry in _selectedHolds.entries) {
        if (entry.key != holdId &&
            (entry.value.type == BoulderingHoldType.starting) &&
            entry.value.markingCount != null) {
          totalStartingMarkings += entry.value.markingCount!;
        }
      }

      // feetOnly 홀드의 마킹 개수 합 (현재 홀드 제외)
      int totalFeetMarkings = _totalFeetMarkingCount;
      if (isFeetOnly && holdProperty.markingCount != null) {
        totalFeetMarkings -= holdProperty.markingCount!;
      }

      // 총 마킹 개수가 4를 초과하는 경우
      if (totalStartingMarkings + totalFeetMarkings + requestedCount > 4) {
        // starting 홀드의 마킹 개수를 차감
        int excessCount = totalStartingMarkings + totalFeetMarkings + requestedCount - 4;
        for (var entry in _selectedHolds.entries.toList()) {
          if (excessCount <= 0) break;
          if (entry.key != holdId &&
              entry.value.type == BoulderingHoldType.starting &&
              entry.value.markingCount != null) {
            int currentMarkings = entry.value.markingCount!;
            int reduction = currentMarkings.clamp(0, excessCount);
            entry.value.markingCount = currentMarkings - reduction;
            if (entry.value.markingCount == 0) {
              entry.value.type = BoulderingHoldType.normal;
            }
            excessCount -= reduction;
          }
        }
      }
      // 최종 마킹 수 설정
      holdProperty.markingCount = requestedCount;
      return;
    }

    // 현재 홀드의 기존 마킹 수를 제외한 총 마킹 수 계산
    int currentTotal = _totalMarkingCount;
    if (holdProperty.markingCount != null) {
      currentTotal -= holdProperty.markingCount!;
    }

    // 새로운 마킹 수를 추가했을 때 총 마킹 수가 4를 초과하는 경우
    if (currentTotal + requestedCount > 4) {
      // 다른 홀드들의 마킹을 조정
      int excessCount = currentTotal + requestedCount - 4;

      // feetOnly 홀드부터 마킹 제거
      for (var entry in _selectedHolds.entries.toList()) {
        if (excessCount <= 0) break;
        if (entry.key != holdId &&
            entry.value.type == BoulderingHoldType.feetOnly &&
            entry.value.markingCount != null) {
          int currentMarkings = entry.value.markingCount!;
          int reduction = currentMarkings.clamp(0, excessCount);
          entry.value.markingCount = currentMarkings - reduction;
          excessCount -= reduction;
          currentTotal -= reduction;
        }
      }

      // 여전히 초과하는 경우 starting 홀드의 마킹 제거
      if (excessCount > 0) {
        for (var entry in _selectedHolds.entries.toList()) {
          if (excessCount <= 0) break;
          if (entry.key != holdId &&
              (entry.value.type == BoulderingHoldType.starting) &&
              entry.value.markingCount != null) {
            int currentMarkings = entry.value.markingCount!;
            int reduction = currentMarkings.clamp(0, excessCount);
            entry.value.markingCount = currentMarkings - reduction;
            if (entry.value.markingCount == 0) {
              entry.value.type = BoulderingHoldType.normal;
            }
            excessCount -= reduction;
            currentTotal -= reduction;
          }
        }
      }
    }

    // 최종 마킹 수 설정
    holdProperty.markingCount = requestedCount;

    // normal 홀드에 마킹이 있으면 starting으로 변경
    if (holdProperty.type == BoulderingHoldType.normal && requestedCount > 0) {
      holdProperty.type = BoulderingHoldType.starting;
    }
  }

  void _onMarkingCountSelect(int count) {
    if (_editingHoldId != null) {
      setState(() {
        _adjustMarkingsForNewCount(_editingHoldId!, count);
        _isMarkingCountMode = false;
      });
    }
  }

  void _enterMarkingCountMode() {
    setState(() {
      _isMarkingCountMode = true;
    });
  }

  void _exitMarkingCountMode() {
    setState(() {
      _isMarkingCountMode = false;
    });
  }

  void _onPolygonTap(int polygonId) {
    if (!mounted) return;

    setState(() {
      if (!_selectedHolds.containsKey(polygonId)) {
        _selectedHolds[polygonId] = HoldProperty();
      }
      _isHoldEditMode = true;
      _editingHoldId = polygonId;
    });
  }

  void _deleteSelectedHold() {
    if (_editingHoldId != null) {
      setState(() {
        _selectedHolds.remove(_editingHoldId);
        _isHoldEditMode = false;
        _editingHoldId = null;
      });
    }
  }

  void _cancelHoldEdit() {
    setState(() {
      _isHoldEditMode = false;
      _editingHoldId = null;
    });
  }

  Color _getHoldColor(int polygonId) {
    if (!_selectedHolds.containsKey(polygonId)) {
      return Colors.transparent;
    }

    final properties = _selectedHolds[polygonId]!;
    switch (properties.type) {
      case BoulderingHoldType.feetOnly:
        return Colors.blue.withOpacity(0.6);

      default:
        return neonLimeColor.withOpacity(0.6);
    }
  }

  void _onHoldTypeChange(BoulderingHoldType newType) {
    if (_editingHoldId != null && _selectedHolds.containsKey(_editingHoldId)) {
      setState(() {
        final holdProperty = _selectedHolds[_editingHoldId]!;
        holdProperty.type = newType;
      });
    }
  }

  void _handleBackgroundTap() {
    if (_isHoldEditMode) {
      setState(() {
        _isHoldEditMode = false;
        _editingHoldId = null;
      });
    }
  }

  Map<int, HoldProperty> getSelectedHolds() {
    return Map<int, HoldProperty>.from(_selectedHolds);
  }

  void initializeFromRouteData(List<BoulderingHold> boulderingHolds) {
    final holds = Map<int, HoldProperty>.fromEntries(
      boulderingHolds.map((hold) => MapEntry(
            hold.polygonId,
            HoldProperty(
              type: BoulderingHoldType.values.firstWhere((type) => type.toString().split('.').last == hold.type),
              markingCount: hold.markingCount,
              checkpointScore: hold.checkpointScore,
            ),
          )),
    );
    setState(() {
      _selectedHolds = holds;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BoulderingRouteEditorImageViewer(
          processedImage: widget.processedImage,
          imageSize: widget.imageSize,
          polygons: widget.polygons,
          onPolygonTap: _onPolygonTap,
          onBackgroundTap: _handleBackgroundTap,
          getHoldColor: _getHoldColor,
          transformationController: widget.transformationController,
          isHoldEditMode: _isHoldEditMode,
          editingHoldId: _editingHoldId,
          selectedHolds: _selectedHolds,
        ),
        BoulderingHoldEditMenu(
          onDelete: _deleteSelectedHold,
          onCancel: _cancelHoldEdit,
          onTypeChange: _onHoldTypeChange,
          isMarkingCountMode: _isMarkingCountMode,
          onMarkingCountSelect: _onMarkingCountSelect,
          onEnterMarkingMode: _enterMarkingCountMode,
          onExitMarkingMode: _exitMarkingCountMode,
          selectedHolds: _selectedHolds,
          holdProperty: _editingHoldId != null ? _selectedHolds[_editingHoldId] : null,
          editingHoldId: _editingHoldId,
          croppedImage: _editingHoldId != null ? widget.croppedImages[_editingHoldId!] : null,
          isHoldEditMode: _isHoldEditMode,
        ),
      ],
    );
  }
}
