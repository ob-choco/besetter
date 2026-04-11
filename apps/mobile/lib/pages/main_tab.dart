import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/activity_refresh_provider.dart';
import 'home.dart';
import 'routes_page.dart';
import 'my_page.dart';

class MainTabPage extends HookConsumerWidget {
  const MainTabPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = useState(0);
    final myPageRefreshSignal = useState(0);

    return Scaffold(
      body: IndexedStack(
        index: currentIndex.value,
        children: [
          const HomePage(),
          const RoutesPage(),
          MyPage(refreshSignal: myPageRefreshSignal.value),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex.value,
        onTap: (index) {
          // When entering MY tab, check if activities changed
          if (index == 2 && ref.read(activityDirtyProvider)) {
            ref.read(activityDirtyProvider.notifier).state = false;
            myPageRefreshSignal.value++;
          }
          currentIndex.value = index;
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: AppLocalizations.of(context)!.navHome,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.list),
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
