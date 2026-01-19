import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'bouldering_route_editor.dart';
import 'dart:ui' as ui;
import '../../models/route_data.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class BoulderingHoldEditMenu extends StatefulWidget {
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  final Function(BoulderingHoldType) onTypeChange;
  final bool isMarkingCountMode;
  final Function(int) onMarkingCountSelect;
  final VoidCallback onEnterMarkingMode;
  final VoidCallback onExitMarkingMode;
  final Map<int, HoldProperty> selectedHolds;
  final HoldProperty? holdProperty;
  final int? editingHoldId;
  final ui.Image? croppedImage;
  final bool isHoldEditMode;

  const BoulderingHoldEditMenu({
    Key? key,
    required this.onDelete,
    required this.onCancel,
    required this.onTypeChange,
    required this.isMarkingCountMode,
    required this.onMarkingCountSelect,
    required this.onEnterMarkingMode,
    required this.onExitMarkingMode,
    required this.selectedHolds,
    required this.holdProperty,
    required this.editingHoldId,
    this.croppedImage,
    required this.isHoldEditMode,
  }) : super(key: key);

  @override
  State<BoulderingHoldEditMenu> createState() => _BoulderingHoldEditMenuState();
}

class _BoulderingHoldEditMenuState extends State<BoulderingHoldEditMenu> {
  @override
  Widget build(BuildContext context) {
    if (widget.isMarkingCountMode) {
      return _buildMarkingCountButtons();
    }
    if (widget.isHoldEditMode) {
      return _buildMainMenu();
    }
    return Container(
      width: MediaQuery.of(context).size.width,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
              width: 48,
              height: 48,
              margin: EdgeInsets.only(left: 16, right: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              )),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMarkingCountButtons() {
    final isFeetOnly = widget.holdProperty!.type == BoulderingHoldType.feetOnly;
    final maxCount = isFeetOnly ? 2 : 4;

    return Container(
      width: MediaQuery.of(context).size.width,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            margin: EdgeInsets.only(left: 16, right: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: widget.croppedImage != null
                ? RawImage(
                    image: widget.croppedImage,
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ...List.generate(
                  maxCount,
                  (index) => Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      onPressed: () => widget.onMarkingCountSelect(index + 1),
                      icon: SvgPicture.asset(
                        isFeetOnly
                            ? 'assets/icons/foot_${index + 1}marking.svg'
                            : 'assets/icons/${index + 1}marking.svg',
                        width: 36,
                        height: 36,
                      ),
                      iconSize: 36,
                      tooltip: '${index + 1}개',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onExitMarkingMode,
                  icon: SvgPicture.asset(
                    'assets/icons/cancel_button.svg',
                    width: 36,
                    height: 36,
                  ),
                  iconSize: 36,
                  tooltip: AppLocalizations.of(context)!.cancel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainMenu() {
    final bool isFeetOnly = widget.holdProperty!.type == BoulderingHoldType.feetOnly;
    final bool isStarting = widget.holdProperty!.type == BoulderingHoldType.starting;
    final bool isFinishing = widget.holdProperty!.type == BoulderingHoldType.finishing;
    final bool isFeetOnlyAndHasMarking =
        isFeetOnly && widget.holdProperty!.markingCount != null && widget.holdProperty!.markingCount! > 0;

    return Container(
      width: MediaQuery.of(context).size.width,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            margin: EdgeInsets.only(left: 16, right: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: widget.croppedImage != null
                ? RawImage(
                    image: widget.croppedImage,
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: () {
                    if (isFinishing) {
                      return;
                    }
                    widget.onEnterMarkingMode();
                  },
                  icon: SvgPicture.asset(
                    'assets/icons/start_button.svg',
                    width: 48,
                    height: 48,
                    colorFilter: ColorFilter.mode(
                      isFinishing
                          ? Colors.grey.withOpacity(0.3)
                          : isStarting || isFeetOnlyAndHasMarking
                              ? Colors.blue
                              : Colors.black,
                      BlendMode.srcIn,
                    ),
                  ),
                  iconSize: 48,
                  tooltip: AppLocalizations.of(context)!.setStartPoint,
                ),
                IconButton(
                  onPressed: () {
                    if (isFeetOnly || isStarting) {
                      return;
                    }

                    if (isFinishing) {
                      widget.onTypeChange(BoulderingHoldType.normal);
                    } else {
                      for (var entry in widget.selectedHolds.entries) {
                        if (entry.key != widget.editingHoldId && entry.value.type == BoulderingHoldType.finishing) {
                          entry.value.type = BoulderingHoldType.normal;
                        }
                      }
                      widget.onTypeChange(BoulderingHoldType.finishing);
                    }
                  },
                  icon: SvgPicture.asset(
                    'assets/icons/top_button.svg',
                    width: 48,
                    height: 48,
                    colorFilter: ColorFilter.mode(
                      isFeetOnly || isStarting
                          ? Colors.grey.withOpacity(0.3)
                          : isFinishing
                              ? Colors.blue
                              : Colors.black,
                      BlendMode.srcIn,
                    ),
                  ),
                  iconSize: 48,
                  tooltip: isFinishing
                      ? AppLocalizations.of(context)!.deselectTopHold
                      : AppLocalizations.of(context)!.selectTopHold,
                ),
                IconButton(
                  onPressed: () {
                    if (isFinishing) {
                      return;
                    }
                    if (isFeetOnly) {
                      if (widget.holdProperty!.markingCount != null && widget.holdProperty!.markingCount! > 0) {
                        widget.onTypeChange(BoulderingHoldType.starting);
                      } else {
                        widget.onTypeChange(BoulderingHoldType.normal);
                      }
                      return;
                    }

                    var currentMarkings = widget.holdProperty!.markingCount ?? 0;
                    if (currentMarkings > 2) {
                      currentMarkings = 2;
                    }

                    if (currentMarkings > 0) {
                      int tempMarkings = currentMarkings;
                      for (var entry in widget.selectedHolds.entries) {
                        if (entry.key != widget.editingHoldId &&
                            entry.value.type == BoulderingHoldType.feetOnly &&
                            entry.value.markingCount != null &&
                            entry.value.markingCount! > 0) {
                          if (entry.value.markingCount == 1 && currentMarkings == 1) {
                            break;
                          }

                          int newCount = entry.value.markingCount! - tempMarkings;
                          tempMarkings -= entry.value.markingCount!;
                          entry.value.markingCount = newCount < 0 ? 0 : newCount;

                          if (tempMarkings <= 0) break;
                        }
                      }

                      widget.holdProperty!.markingCount = currentMarkings;
                    }
                    widget.onTypeChange(BoulderingHoldType.feetOnly);
                  },
                  icon: SvgPicture.asset(
                    'assets/icons/foot_button.svg',
                    width: 48,
                    height: 48,
                    colorFilter: ColorFilter.mode(
                      isFinishing
                          ? Colors.grey.withOpacity(0.3)
                          : isFeetOnly
                              ? Colors.blue
                              : Colors.black,
                      BlendMode.srcIn,
                    ),
                  ),
                  iconSize: 48,
                  tooltip: isFeetOnly
                      ? AppLocalizations.of(context)!.deselectFootHold
                      : AppLocalizations.of(context)!.selectFootHold,
                ),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: SvgPicture.asset(
                    'assets/icons/delete_button.svg',
                    width: 48,
                    height: 48,
                  ),
                  iconSize: 48,
                  tooltip: AppLocalizations.of(context)!.delete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
