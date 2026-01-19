import 'package:flutter/material.dart';

/// 위젯에 떨리는 애니메이션 효과를 적용하는 위젯입니다.
///
/// [shakeTrigger]가 true로 변경될 때마다 애니메이션이 재생됩니다.
class ShakeAnimationWidget extends StatefulWidget {
  /// 애니메이션을 적용할 자식 위젯입니다.
  final Widget child;
  /// 애니메이션을 트리거하는 플래그입니다. 이 값이 true로 변경되면 애니메이션이 시작됩니다.
  final bool shakeTrigger;
  /// 애니메이션 지속 시간입니다.
  final Duration duration;
  /// 애니메이션의 떨림 강도 (픽셀 단위)입니다.
  final double shakeIntensity;

  const ShakeAnimationWidget({
    Key? key,
    required this.child,
    required this.shakeTrigger,
    this.duration = const Duration(milliseconds: 500),
    this.shakeIntensity = 5.0,
  }) : super(key: key);

  @override
  _ShakeAnimationWidgetState createState() => _ShakeAnimationWidgetState();
}

class _ShakeAnimationWidgetState extends State<ShakeAnimationWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    final intensity = widget.shakeIntensity;
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: intensity), weight: 1),
      TweenSequenceItem(tween: Tween(begin: intensity, end: -intensity), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -intensity, end: intensity), weight: 2),
      TweenSequenceItem(tween: Tween(begin: intensity, end: -intensity), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -intensity, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    // 초기 shakeTrigger 값이 true일 경우 애니메이션 시작
    if (widget.shakeTrigger) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(covariant ShakeAnimationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // shakeTrigger가 true로 변경되었을 때 애니메이션 시작
    if (widget.shakeTrigger && !oldWidget.shakeTrigger) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_animation.value, 0),
          child: widget.child, // AnimatedBuilder의 child 대신 widget.child를 사용
        );
      },
      // child: widget.child, // AnimatedBuilder의 child 파라미터는 최적화를 위해 사용될 수 있지만, 여기서는 builder 내에서 직접 widget.child를 참조해도 괜찮습니다.
    );
  }
} 