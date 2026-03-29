import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/token_service.dart';
import '../widgets/confetti.dart';
import '../widgets/hold_editor_button.dart';
import '../widgets/home/wall_image_carousel.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  static const String _hasShownConfettiKey = 'has_shown_confetti_';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorButtonKey = useMemoized(() => GlobalKey());

    // Confetti 체크
    useEffect(() {
      _checkAndShowConfetti(context);
      return null;
    }, []);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Your Climbing Walls',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            const Expanded(
              child: WallImageCarousel(),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: HoldEditorButton(
                buttonKey: editorButtonKey,
                buttonLabel: 'Take Wall Photo',
                buttonIcon: Icons.camera_alt,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkAndShowConfetti(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = await TokenService.getRefreshToken();

    if (refreshToken != null) {
      final hasShown = prefs.getBool('$_hasShownConfettiKey$refreshToken') ?? false;

      if (!hasShown) {
        prefs.setBool('$_hasShownConfettiKey$refreshToken', true);
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => const ConfettiDialogWidget(),
          );
        }
      }
    }
  }
}
