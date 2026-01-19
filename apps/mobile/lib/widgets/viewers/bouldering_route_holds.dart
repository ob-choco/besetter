import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:ui' as ui;
import '../../models/route_data.dart';

class BoulderingRouteHolds extends StatefulWidget {
  final Map<int, BoulderingHold> holds;
  final Map<int, ui.Image?> croppedImages;
  final Function(List<int>) onHighlightHolds;
  final String? selectedType;
  final Function(String?)? onTypeSelected;

  const BoulderingRouteHolds({
    Key? key,
    required this.holds,
    required this.croppedImages,
    required this.onHighlightHolds,
    this.selectedType,
    this.onTypeSelected,
  }) : super(key: key);

  @override
  State<BoulderingRouteHolds> createState() => _BoulderingRouteHoldsState();
}

class _BoulderingRouteHoldsState extends State<BoulderingRouteHolds> {
  void _selectHoldType(String type) {
    final newType = widget.selectedType == type ? null : type;
    widget.onTypeSelected?.call(newType);
    
    if (newType == null) {
      widget.onHighlightHolds([]);
    } else {
      final selectedHolds = widget.holds.entries
          .where((entry) => entry.value.type == type)
          .map((entry) => entry.key)
          .toList();
      widget.onHighlightHolds(selectedHolds);
    }
  }

  Widget _buildHoldButton(String type, String assetPath, String label) {
    final isSelected = widget.selectedType == type;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _selectHoldType(type),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    assetPath,
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(
                      isSelected ? Colors.blue : Colors.black54,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.blue : Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildHoldButton('starting', 'assets/icons/start_icon.svg', 'Start'),
          _buildHoldButton('finishing', 'assets/icons/top_icon.svg', 'Top'),
          _buildHoldButton('normal', 'assets/icons/hold_icon.svg', 'Hold'),
          _buildHoldButton('feetOnly', 'assets/icons/foot_icon.svg', 'Foot'),
        ],
      ),
    );
  }
}
