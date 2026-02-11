import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/token_service.dart';
import 'dart:async'; // Timer를 위해 추가

class GuideBubble {
  final BuildContext context;
  final GlobalKey targetKey;
  final String message;
  final int autoDismissSeconds;
  final String? prefKey;
  
  OverlayEntry? _overlayEntry;
  AnimationController? _animationController;
  Animation<double>? _animation;
  Timer? _dismissTimer;
  bool _isDisposed = false;

  GuideBubble({
    required this.context,
    required this.targetKey,
    required this.message,
    this.autoDismissSeconds = 60,
    this.prefKey,
  });

  void _ensureInitialized() {
    if (_animationController != null) return;
    final overlay = Overlay.of(context);
    _animationController = AnimationController(
      vsync: overlay,
      duration: const Duration(milliseconds: 500),
    );
    _animation = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _animationController!, curve: Curves.easeOut));
  }

  void dispose() {
    _isDisposed = true;
    _dismissTimer?.cancel();
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }
    _animationController?.dispose();
  }

  void removeOverlay() {
    if (_isDisposed || _overlayEntry == null || _animationController == null) {
      return;
    }

    _animationController!.forward().then((_) {
      if (!_isDisposed && _overlayEntry != null) {
        _overlayEntry?.remove();
        _overlayEntry = null;
      }
    }).catchError((error) {
      if (_overlayEntry != null) {
        _overlayEntry?.remove();
        _overlayEntry = null;
      }
    });
  }

  void removeOverlayImmediately() {
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      if (!_isDisposed) {
        _animationController?.reset();
      }
    }
  }

  Future<bool> checkAndShow() async {
    if (prefKey != null) {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = await TokenService.getRefreshToken();

      if (refreshToken != null) {
        final hasShown = prefs.getBool('${prefKey}_$refreshToken') ?? false;
        if (hasShown) {
          return false; // 이미 가이드를 보여줬으면 표시하지 않음
        }
      }
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) { // 추가: 이미 dispose된 경우 show 하지 않음
        show();
      }
    });
    
    return true;
  }

  void show() {
    if (_isDisposed) return;

    final RenderBox? renderBox = targetKey.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox == null) return;

    _ensureInitialized();

    final position = renderBox.localToGlobal(Offset.zero);

    final screenSize = MediaQuery.of(context).size;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: position.dy + 55,
        left: screenSize.width * 0.5 - 50,
        child: AnimatedBuilder(
          animation: _animation!,
          builder: (context, child) {
            if (_isDisposed) {
              return const SizedBox.shrink();
            }
            return Opacity(
              opacity: _animation!.value,
              child: child,
            );
          },
          child: Material(
            color: Colors.transparent,
            child: CustomPaint(
              painter: BubblePainter(color: Colors.blue[600]!),
              child: IntrinsicWidth(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                  constraints: const BoxConstraints(
                    minWidth: 140,
                    maxWidth: 220,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    message,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    textAlign: TextAlign.center,
                    softWrap: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 가이드 말풍선을 제일 낮은 z-index로 삽입
    final overlay = Overlay.of(context);
    overlay.insert(_overlayEntry!);

    // 설정된 시간 후에 가이드 풍선 제거
    _dismissTimer?.cancel(); // 기존 타이머가 있다면 취소
    _dismissTimer = Timer(Duration(seconds: autoDismissSeconds), () {
      if (!_isDisposed && _overlayEntry != null) { // 타이머 콜백 시점에도 확인
        removeOverlay();
      }
    });
  }

  Future<void> markAsShown() async {
    if (prefKey != null) {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = await TokenService.getRefreshToken();
      
      if (refreshToken != null) {
        await prefs.setBool('${prefKey}_$refreshToken', true);
      }
    }
  }
}

class BubblePainter extends CustomPainter {
  final ui.Color color;

  BubblePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final path = Path();

    // 말풍선 본체는 아래에 배치
    final RRect rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 10, size.width, size.height - 10),
      const Radius.circular(8),
    );

    // 꼬리를 왼쪽에 배치 (왼쪽 가장자리에서 30픽셀 떨어진 위치)
    path.addRRect(rect);
    
    final double arrowPosition = 30.0; // 왼쪽에서 30픽셀 위치
    
    path.moveTo(arrowPosition - 10, 10);
    path.lineTo(arrowPosition, 0);
    path.lineTo(arrowPosition + 10, 10);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
} 