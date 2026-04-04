import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../../models/route_data.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class EnduranceRouteHolds extends StatefulWidget {
  final List<EnduranceHold> holds;
  final Map<int, ui.Image?> croppedImages;
  final Function(List<int>) onHighlightHolds;

  const EnduranceRouteHolds({
    Key? key,
    required this.holds,
    required this.croppedImages,
    required this.onHighlightHolds,
  }) : super(key: key);

  @override
  State<EnduranceRouteHolds> createState() => _EnduranceRouteHoldsState();
}

class _EnduranceRouteHoldsState extends State<EnduranceRouteHolds>
    with SingleTickerProviderStateMixin {
  double _scrollOffset = 0.0;
  int _currentHighlightedIndex = 0;
  late AnimationController _flingController;
  Animation<double>? _flingAnimation;

  static const double _baseSize = 70.0;
  static const double _itemWidth = 68.0;
  static const double _maxScale = 1.3;
  static const double _baseScale = 1.0;
  static const double _influenceRange = 136.0;

  double get _maxOffset =>
      _itemWidth * (widget.holds.length - 1).clamp(0, double.maxFinite);

  @override
  void initState() {
    super.initState();
    _flingController = AnimationController(vsync: this)
      ..addListener(() {
        if (_flingAnimation != null) {
          setState(() {
            _scrollOffset = _flingAnimation!.value;
            _updateCurrentIndex();
          });
        }
      });
  }

  @override
  void dispose() {
    _flingController.dispose();
    super.dispose();
  }

  void _updateCurrentIndex() {
    if (widget.holds.isEmpty) return;
    final newIndex =
        (_scrollOffset / _itemWidth).round().clamp(0, widget.holds.length - 1);
    if (newIndex != _currentHighlightedIndex) {
      _currentHighlightedIndex = newIndex;
      widget.onHighlightHolds([widget.holds[newIndex].polygonId]);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _flingController.stop();
    setState(() {
      _scrollOffset =
          (_scrollOffset - details.delta.dx).clamp(0.0, _maxOffset);
      _updateCurrentIndex();
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final velocity = -details.velocity.pixelsPerSecond.dx;
    final target = (_scrollOffset + velocity * 0.3).clamp(0.0, _maxOffset);
    final snappedTarget = (target / _itemWidth).round() * _itemWidth;
    final clampedTarget = snappedTarget.toDouble().clamp(0.0, _maxOffset);

    _flingAnimation = Tween<double>(
      begin: _scrollOffset,
      end: clampedTarget,
    ).animate(CurvedAnimation(
      parent: _flingController,
      curve: Curves.easeOutCubic,
    ));

    _flingController.duration = const Duration(milliseconds: 400);
    _flingController.forward(from: 0.0);
  }

  double _calculateScale(int index) {
    final distance = (_scrollOffset - index * _itemWidth).abs();
    if (distance >= _influenceRange) return _baseScale;
    return _baseScale +
        (_maxScale - _baseScale) *
            (1 - distance / _influenceRange).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.of(context)!.holdSequence,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2F30),
                ),
              ),
              Text(
                AppLocalizations.of(context)!.holdsTotalCapitalized(widget.holds.length),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF595C5D),
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onHorizontalDragUpdate: _onPanUpdate,
          onHorizontalDragEnd: _onPanEnd,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 130,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final centerX = constraints.maxWidth / 2;
                final visibleRange = centerX + _baseSize * _maxScale;

                // Collect visible items, sorted furthest-first so center renders last (on top)
                final indices = <int>[];
                for (int i = 0; i < widget.holds.length; i++) {
                  if ((i * _itemWidth - _scrollOffset).abs() <= visibleRange) {
                    indices.add(i);
                  }
                }
                indices.sort((a, b) {
                  final distA = (_scrollOffset - a * _itemWidth).abs();
                  final distB = (_scrollOffset - b * _itemWidth).abs();
                  return distB.compareTo(distA);
                });

                return Stack(
                  clipBehavior: Clip.none,
                  children: indices.map((index) {
                    final hold = widget.holds[index];
                    final image = widget.croppedImages[hold.polygonId];
                    final scale = _calculateScale(index);
                    final isCenter = index == _currentHighlightedIndex;
                    final scaledSize = _baseSize * scale;

                    final itemX = centerX +
                        (index * _itemWidth - _scrollOffset) -
                        scaledSize / 2;
                    final itemY = (105 - scaledSize) / 2;

                    return Positioned(
                      left: itemX,
                      top: itemY,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: scaledSize,
                            height: scaledSize,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: isCenter
                                    ? const Color(0xFF0066FF)
                                    : const Color(0xFFE6E8EA),
                                width: isCenter ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: image != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: RawImage(
                                      image: image,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isCenter
                                  ? const Color(0xFF0066FF)
                                  : const Color(0xFF595C5D),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
