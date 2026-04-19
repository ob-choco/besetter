import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../providers/main_tab_provider.dart';
import '../../providers/recent_climbed_routes_provider.dart';
import 'recent_climbed_route_card.dart';

class RecentClimbedRoutesSection extends ConsumerWidget {
  const RecentClimbedRoutesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(recentClimbedRoutesProvider);

    return async.when(
      loading: () => const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.failedLoadData,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(recentClimbedRoutesProvider),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
      data: (routes) {
        if (routes.isEmpty) return const _EmptyStateCard();
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              for (var i = 0; i < routes.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                RecentClimbedRouteCard(route: routes[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _EmptyStateCard extends ConsumerWidget {
  const _EmptyStateCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            const Text('🧗', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 12),
            Text(
              l10n.noClimbedRoutesYet,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F1A2E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.startFirstWorkoutHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () =>
                  ref.read(mainTabIndexProvider.notifier).set(1),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF1E4BD8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.viewRoutes,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward, size: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
