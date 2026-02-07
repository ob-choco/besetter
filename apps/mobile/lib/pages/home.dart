import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/routes_provider.dart';
import '../services/token_service.dart';
import '../widgets/hold_editor_button.dart';
import '../widgets/confetti.dart';
import '../widgets/guide_bubble.dart';
import '../widgets/home/image_carousel.dart';
import '../widgets/home/route_list.dart';
import './setting.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  static const String _hasShownConfettiKey = 'has_shown_confetti_';
  static const String _hasShownGuideKey = 'has_shown_guide';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollController = useScrollController();
    final editorButtonKey = useMemoized(() => GlobalKey());
    final guideBubble = useState<GuideBubble?>(null);
    final totalCountAsync = ref.watch(routesTotalCountProvider);

    // Guide bubble 초기화
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        guideBubble.value = GuideBubble(
          context: context,
          targetKey: editorButtonKey,
          message: AppLocalizations.of(context)!.uploadPhoto,
          autoDismissSeconds: 60,
          prefKey: _hasShownGuideKey,
        );
        guideBubble.value?.checkAndShow();
      });
      return () => guideBubble.value?.dispose();
    }, []);

    // Confetti 체크
    useEffect(() {
      _checkAndShowConfetti(context);
      return null;
    }, []);

    void handleInteraction() {
      guideBubble.value?.removeOverlay();
      guideBubble.value?.markAsShown();
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                icon: const Icon(Icons.menu),
                iconSize: 32,
                onPressed: () {
                  handleInteraction();
                  guideBubble.value?.removeOverlayImmediately();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsPage(),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Center(
                    child: HoldEditorButton(
                      buttonKey: editorButtonKey,
                      onTapDown: handleInteraction,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ImageCarousel(onInteraction: handleInteraction),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Text(
                        AppLocalizations.of(context)!.routeCard,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      totalCountAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (count) => Text(
                          ' $count',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              sliver: RouteList(
                parentScrollController: scrollController,
                onInteraction: handleInteraction,
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
