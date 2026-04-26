import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/activity_refresh_provider.dart';
import '../providers/main_tab_provider.dart';
import '../providers/user_provider.dart';
import 'home.dart';
import 'routes_page.dart';
import 'my_page.dart';

class MainTabPage extends HookConsumerWidget {
  const MainTabPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(mainTabIndexProvider);
    final unreadCount = ref.watch(userProfileProvider).whenOrNull(
              data: (u) => u.unreadNotificationCount,
            ) ??
        0;

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: const [
          HomePage(),
          RoutesPage(),
          MyPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          flushActivityDirty(ProviderScope.containerOf(context));
          ref.read(mainTabIndexProvider.notifier).set(index);
        },
        items: [
          BottomNavigationBarItem(
            icon: Badge.count(
              count: unreadCount,
              isLabelVisible: unreadCount > 0,
              child: const Icon(Icons.home),
            ),
            label: AppLocalizations.of(context)!.navHome,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.terrain),
            label: AppLocalizations.of(context)!.navRoutes,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: AppLocalizations.of(context)!.navMy,
          ),
        ],
      ),
    );
  }
}
