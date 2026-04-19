import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/user_provider.dart';
import '../services/token_service.dart';
import '../widgets/confetti.dart';
import '../widgets/hold_editor_button.dart';
import '../widgets/home/wall_image_carousel.dart';
import 'notifications_page.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  static const String _hasShownConfettiKey = 'has_shown_confetti_';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorButtonKey = useMemoized(() => GlobalKey());
    final unreadNotifCount = ref.watch(userProfileProvider).whenOrNull(
              data: (u) => u.unreadNotificationCount,
            ) ??
        0;

    // Confetti 체크
    useEffect(() {
      _checkAndShowConfetti(context);
      return null;
    }, []);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 8, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 36, color: Colors.black),
                        children: [
                          const TextSpan(text: 'Your\n'),
                          TextSpan(
                            text: AppLocalizations.of(context)!.wallsTitle,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Badge.count(
                      count: unreadNotifCount,
                      isLabelVisible: unreadNotifCount > 0,
                      child: const Icon(
                        Icons.notifications_outlined,
                        color: Color(0xFF2C2F30),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationsPage()),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Expanded(
              child: WallImageCarousel(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: HoldEditorButton(
                buttonKey: editorButtonKey,
                buttonLabel: AppLocalizations.of(context)!.takeWallPhoto,
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
