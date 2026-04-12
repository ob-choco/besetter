import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SlideToStart extends StatefulWidget {
  final VoidCallback onSlideComplete;

  const SlideToStart({
    required this.onSlideComplete,
    Key? key,
  }) : super(key: key);

  @override
  State<SlideToStart> createState() => _SlideToStartState();
}

class _SlideToStartState extends State<SlideToStart> {
  double _dragPosition = 0.0;

  static const double _handleSize = 48.0;
  static const double _padding = 4.0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 2 / 3,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            final maxDrag = trackWidth - _handleSize - _padding * 2;

            return Container(
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF0052D0),
                borderRadius: BorderRadius.circular(9999),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.1),
                    blurRadius: 15,
                    offset: Offset(0, 10),
                    spreadRadius: -3,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Center label
                  Center(
                    child: Text(
                      AppLocalizations.of(context)!.slideToStart,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  // Draggable handle
                  Positioned(
                    left: _padding + _dragPosition,
                    child: GestureDetector(
                      onHorizontalDragStart: (_) {},
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _dragPosition = (_dragPosition + details.delta.dx)
                              .clamp(0.0, maxDrag);
                        });
                      },
                      onHorizontalDragEnd: (_) {
                        if (_dragPosition >= maxDrag * 0.85) {
                          widget.onSlideComplete();
                        }
                        setState(() {
                          _dragPosition = 0.0;
                        });
                      },
                      child: Container(
                        width: _handleSize,
                        height: _handleSize,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            '»',
                            style: TextStyle(
                              color: Color(0xFF0052D0),
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
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
        ),
      ),
    );
  }
}
