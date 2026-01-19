import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;

import '../../models/polygon_data.dart';
import 'endurance_route_editor_image_viewer.dart';
import 'endurance_selected_holds_list.dart';
import 'endurance_hold_edit_menu.dart';
import '../../models/route_data.dart' show EnduranceHold, GripHand;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

enum HoldEditMode {
  none,
  replace,
  add,
  edit;
}

class SelectedHold {
  final int polygonId;
  final GripHand? gripHand;

  SelectedHold({
    required this.polygonId,
    this.gripHand,
  });
}

class EnduranceRouteEditor extends StatefulWidget {
  final File processedImage;
  final Size? imageSize;
  final List<Polygon> polygons;
  final List<ui.Image?> croppedImages;
  final TransformationController transformationController;
  final bool imagesLoaded;
  final bool showHoldOrder;

  const EnduranceRouteEditor({
    Key? key,
    required this.processedImage,
    required this.imageSize,
    required this.polygons,
    required this.croppedImages,
    required this.transformationController,
    required this.imagesLoaded,
    required this.showHoldOrder,
  }) : super(key: key);

  @override
  State<EnduranceRouteEditor> createState() => EnduranceRouteEditorState();
}

class EnduranceRouteEditorState extends State<EnduranceRouteEditor> {
  List<SelectedHold> _selectedHolds = [];
  final Map<int, List<int>> _selectedOrder = {};
  HoldEditMode _holdEditMode = HoldEditMode.none;
  int? _editingHoldId;
  int? _editingOrder;

  void _onPolygonTap(int polygonId) {
    if (!mounted) return;

    if (_holdEditMode == HoldEditMode.replace || _holdEditMode == HoldEditMode.add) {
      _handleHoldAdd(polygonId);
      return;
    }

    if (_holdEditMode == HoldEditMode.edit) return;

    if (_canAddHoldAtEnd(polygonId)) {
      setState(() {
        _selectedHolds.add(SelectedHold(polygonId: polygonId));
        _selectedOrder.putIfAbsent(polygonId, () => []);
        _selectedOrder[polygonId]!.add(_selectedHolds.length);
      });
    }
  }

  void _handleHoldAdd(int polygonId) {
    final index = _editingOrder! - 1;
    final tempList = List<SelectedHold>.from(_selectedHolds);

    if (_holdEditMode == HoldEditMode.replace) {
      tempList[index] = SelectedHold(polygonId: polygonId);
    } else if (_holdEditMode == HoldEditMode.add) {
      tempList.insert(index, SelectedHold(polygonId: polygonId));
    }

    if (_canReorderHold(tempList, index)) {
      setState(() {
        _selectedHolds = tempList;
        _selectedOrder.clear();
        for (int i = 0; i < _selectedHolds.length; i++) {
          final holdId = _selectedHolds[i].polygonId;
          _selectedOrder.putIfAbsent(holdId, () => []);
          _selectedOrder[holdId]!.add(i + 1);
        }
        _holdEditMode = HoldEditMode.none;
        _editingHoldId = null;
        _editingOrder = null;
      });
    } else {
      setState(() {
        _holdEditMode = HoldEditMode.none;
      });
    }
  }

  void _cancelHoldAdd() {
    setState(() {
      _holdEditMode = HoldEditMode.edit;
    });
  }

  void _handleBackgroundTap() {
    if (_holdEditMode == HoldEditMode.edit) {
      setState(() {
        _holdEditMode = HoldEditMode.none;
        _editingHoldId = null;
        _editingOrder = null;
      });
    }
  }

  bool _checkConsecutiveHolds(int first, int second, int third) {
    return first == second && second == third;
  }

  bool _canAddHoldAtEnd(int holdId) {
    if (_selectedHolds.length < 2) return true;

    final lastHold = _selectedHolds.last.polygonId;
    final secondLastHold = _selectedHolds[_selectedHolds.length - 2].polygonId;

    if (lastHold == holdId && secondLastHold == holdId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.limitSameHoldConsecutive),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
    return true;
  }

  bool _canReorderHold(List<SelectedHold> sequence, int targetIndex) {
    bool checkThreeHolds(int index) {
      if (index < 0 || index + 2 >= sequence.length) return false;
      return _checkConsecutiveHolds(
          sequence[index].polygonId, sequence[index + 1].polygonId, sequence[index + 2].polygonId);
    }

    if (checkThreeHolds(targetIndex - 3) ||
        checkThreeHolds(targetIndex - 2) ||
        checkThreeHolds(targetIndex - 1) ||
        checkThreeHolds(targetIndex) ||
        checkThreeHolds(targetIndex + 1) ||
        checkThreeHolds(targetIndex + 2) ||
        checkThreeHolds(targetIndex + 3)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.limitSameHoldConsecutive),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
    return true;
  }

  void _handleReorder(int draggedIndex, int targetIndex) {
    final draggedHold = _selectedHolds[draggedIndex];
    final tempList = List<SelectedHold>.from(_selectedHolds);
    tempList.removeAt(draggedIndex);
    tempList.insert(targetIndex, draggedHold);

    if (_canReorderHold(tempList, targetIndex) && _canReorderHold(tempList, draggedIndex)) {
      setState(() {
        _selectedHolds = tempList;
        _selectedOrder.clear();
        for (int i = 0; i < _selectedHolds.length; i++) {
          final holdId = _selectedHolds[i].polygonId;
          _selectedOrder.putIfAbsent(holdId, () => []);
          _selectedOrder[holdId]!.add(i + 1);
        }
      });
    }
  }

  void _onOrderTap(int holdId, int order) {
    setState(() {
      if (_holdEditMode == HoldEditMode.edit && _editingHoldId == holdId) {
        _holdEditMode = HoldEditMode.none;
        _editingHoldId = null;
        _editingOrder = null;
      } else {
        _holdEditMode = HoldEditMode.edit;
        _editingHoldId = holdId;
        _editingOrder = order;
      }
    });
  }

  void _deleteSelectedHold() {
    if (_editingHoldId != null && _editingOrder != null) {
      final tempList = List<SelectedHold>.from(_selectedHolds);
      int indexToRemove = _editingOrder! - 1;

      if (indexToRemove != -1) {
        tempList.removeAt(indexToRemove);

        bool hasConsecutiveHolds = false;
        for (int i = math.max(0, indexToRemove - 2); i <= math.min(tempList.length - 3, indexToRemove + 2); i++) {
          if (_checkConsecutiveHolds(tempList[i].polygonId, tempList[i + 1].polygonId, tempList[i + 2].polygonId)) {
            hasConsecutiveHolds = true;
            break;
          }
        }

        if (hasConsecutiveHolds) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.deleteNotAllowedDueToConsecutiveSameHolds),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        setState(() {
          _selectedHolds = tempList;
          _selectedOrder.clear();
          for (int i = 0; i < _selectedHolds.length; i++) {
            final holdId = _selectedHolds[i].polygonId;
            _selectedOrder.putIfAbsent(holdId, () => []);
            _selectedOrder[holdId]!.add(i + 1);
          }
          if (_selectedOrder[_editingHoldId]?.isEmpty ?? true) {
            _holdEditMode = HoldEditMode.none;
            _editingHoldId = null;
            _editingOrder = null;
          }
        });
      }
    }
  }

  void _onGripHandTap(int index) {
    setState(() {
      final currentHold = _selectedHolds[index];
      GripHand? nextGripHand;

      if (currentHold.gripHand == null) {
        nextGripHand = GripHand.left;
      } else if (currentHold.gripHand == GripHand.left) {
        nextGripHand = GripHand.right;
      } else {
        nextGripHand = null;
      }

      _selectedHolds[index] = SelectedHold(
        polygonId: currentHold.polygonId,
        gripHand: nextGripHand,
      );
    });
  }

  List<SelectedHold> getSelectedHolds() {
    return List<SelectedHold>.from(_selectedHolds);
  }

  void initializeFromRouteData(List<EnduranceHold> enduranceHolds) {
    final holds = enduranceHolds
        .map((hold) => SelectedHold(
              polygonId: hold.polygonId,
              gripHand: hold.gripHand,
            ))
        .toList();
    setState(() {
      _selectedHolds = holds;
      _selectedOrder.clear();
      for (int i = 0; i < _selectedHolds.length; i++) {
        final holdId = _selectedHolds[i].polygonId;
        _selectedOrder.putIfAbsent(holdId, () => []);
        _selectedOrder[holdId]!.add(i + 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EnduranceRouteEditorImageViewer(
          processedImage: widget.processedImage,
          imageSize: widget.imageSize,
          polygons: widget.polygons,
          selectedHolds: _selectedHolds,
          selectedOrder: _selectedOrder,
          onPolygonTap: _onPolygonTap,
          onBackgroundTap: _handleBackgroundTap,
          transformationController: widget.transformationController,
          onOrderTap: _onOrderTap,
          editingHoldId: _editingHoldId,
          holdEditMode: _holdEditMode,
          showHoldOrder: widget.showHoldOrder,
        ),
        EnduranceHoldEditMenu(
          orders: _selectedOrder[_editingHoldId] ?? [],
          initialSelectedOrder: _editingOrder,
          onOrderSelected: (order) {
            setState(() {
              _editingOrder = order;
            });
          },
          onReplace: () {
            setState(() {
              _holdEditMode = HoldEditMode.replace;
            });
          },
          onAdd: () {
            setState(() {
              _holdEditMode = HoldEditMode.add;
            });
          },
          onDelete: _deleteSelectedHold,
          croppedImage: _editingHoldId != null ? widget.croppedImages[_editingHoldId!] : null,
          editMode: _holdEditMode,
          onCancelHoldAdd: _cancelHoldAdd,
        ),
        EnduranceSelectedHoldsList(
          imagesLoaded: widget.imagesLoaded,
          selectedHolds: _selectedHolds,
          polygons: widget.polygons,
          croppedImages: widget.croppedImages,
          selectedOrder: _selectedOrder,
          onReorder: _handleReorder,
          onGripHandTap: _onGripHandTap,
          onHoldTap: (index) {
            setState(() {
              _holdEditMode = HoldEditMode.edit;
              _editingHoldId = _selectedHolds[index].polygonId;
              _editingOrder = index + 1;
            });
          },
        ),
      ],
    );
  }
}
