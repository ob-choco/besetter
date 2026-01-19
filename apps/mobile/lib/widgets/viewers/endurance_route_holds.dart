import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../../models/route_data.dart';

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

class _EnduranceRouteHoldsState extends State<EnduranceRouteHolds> {
  final ScrollController _scrollController = ScrollController();
  int _currentHighlightedIndex = 0;
  double _currentOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 첫 번째 홀드가 중앙에 오도록 초기 스크롤 위치 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final screenWidth = MediaQuery.of(context).size.width;
      _scrollController.jumpTo(-screenWidth / 2 + 29); // 58/2 = 29 (아이템의 절반)
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = 58.0; // 50 + 좌우 마진(4*2)
    // padding을 고려한 실제 중앙 위치 계산 (홀드 선택용)
    final centerPosition = _scrollController.offset + (screenWidth / 2) - (screenWidth / 2 - 29);
    final newIndex = (centerPosition / itemWidth).floor();
    
    if (newIndex != _currentHighlightedIndex && 
        newIndex >= 0 && 
        newIndex < widget.holds.length) {
      setState(() {
        _currentHighlightedIndex = newIndex;
        widget.onHighlightHolds([widget.holds[newIndex].polygonId]);
      });
    } else {
      // 선택된 홀드가 변경되지 않더라도 스케일 애니메이션을 위해 setState 호출
      setState(() {});
    }
  }

  double _calculateScale(int index) {
    const double maxScale = 1.5; // 최대 확대 비율
    const double baseScale = 1.0; // 기본 크기 비율
    const double influenceRange = 116.0; // 영향을 미치는 범위 (픽셀) (58 * 2)
    
    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = 58.0;
    
    // 스크롤 뷰의 중심점 위치 계산
    final scrollViewCenter = _scrollController.offset + (screenWidth / 2);
    
    // 현재 아이템의 중심점 위치 계산 (padding 고려)
    final itemCenter = (index * itemWidth) + (itemWidth / 2) + (screenWidth / 2 - 29);
    
    // 실제 픽셀 거리 계산
    final distanceFromCenter = (scrollViewCenter - itemCenter).abs();
    
    if (distanceFromCenter >= influenceRange) return baseScale;
    
    // 가우시안 분포와 유사한 크기 계산
    final scale = baseScale + (maxScale - baseScale) * 
        (1 - (distanceFromCenter / influenceRange)).clamp(0.0, 1.0);
    
    return scale;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth / 2 - 29,
            ),
            itemCount: widget.holds.length,
            itemBuilder: (context, index) {
              final hold = widget.holds[index];
              final image = widget.croppedImages[hold.polygonId];
              final scale = _calculateScale(index);
              
              return Transform(
                transform: Matrix4.identity()
                  ..translate(
                    -15.0 * (1 - scale), // X축 이동 (왼쪽으로)
                    0.0,
                    100.0 * (scale - 1), // Z축 위치 조정
                  ),
                child: Container(
                  width: 50 * scale + 8, // 기본 너비 + 여유 공간
                  child: Stack(
                    clipBehavior: Clip.none, // 자식 위젯이 부모 영역을 벗어날 수 있도록 함
                    children: [
                      Positioned(
                        left: -8.0 * (1 - scale), // 겹침 효과를 위한 위치 조정
                        child: Column(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOutCubic,
                              width: 50 * scale,
                              height: 50 * scale,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: index == _currentHighlightedIndex 
                                      ? Colors.red 
                                      : Colors.grey,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white,
                                    blurRadius: 5 * scale,
                                    offset: Offset(2 * scale, 2 * scale),
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
                                      child: CircularProgressIndicator(),
                                    ),
                            ),
                            Transform.translate(
                              offset: Offset(-4.0 * (1 - scale), 0),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: index == _currentHighlightedIndex 
                                      ? Colors.red 
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
