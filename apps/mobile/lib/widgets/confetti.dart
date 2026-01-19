import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ConfettiDialogWidget extends StatefulWidget {
  const ConfettiDialogWidget({Key? key}) : super(key: key);

  @override
  _ConfettiDialogWidgetState createState() => _ConfettiDialogWidgetState();
}

class _ConfettiDialogWidgetState extends State<ConfettiDialogWidget> {
  late ConfettiController _confettiController;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    
    // confetti 애니메이션 설정
    _confettiController = ConfettiController(duration: const Duration(seconds: 10));
    
    // Overlay로 표시하기 위해 PostFrameCallback 사용
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showConfettiOverlay();
    });
  }

  void _showConfettiOverlay() {
    final overlay = Overlay.of(context, rootOverlay: true);
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black54, // 배경 음영
        child: Stack(
          children: [
            // confetti 애니메이션 배경
            Positioned.fill(
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                emissionFrequency: 0.05,
                numberOfParticles: 20,
                maxBlastForce: 20,
                minBlastForce: 5,
                gravity: 0.1,
                colors: const [
                  Colors.red,
                  Colors.blue,
                  Colors.green,
                  Colors.orange,
                  Colors.purple,
                ],
              ),
            ),
            // 중앙에 위치한 다이얼로그
            Center(
              child: AlertDialog(
                title: Text(AppLocalizations.of(context)!.welcome),
                content: Text(AppLocalizations.of(context)!.welcomeBetaMessage),
                actions: [
                  TextButton(
                    onPressed: () {
                      _overlayEntry?.remove();
                      _overlayEntry = null;
                      Navigator.of(context).pop();
                    },
                    child: Text(AppLocalizations.of(context)!.close),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    
    overlay.insert(_overlayEntry!);
    _confettiController.play();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 빈 컨테이너 반환 - 실제 UI는 오버레이로 표시됨
    return Container();
  }
}