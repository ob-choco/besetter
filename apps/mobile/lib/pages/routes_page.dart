import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/routes_provider.dart';
import '../providers/user_stats_provider.dart';
import '../widgets/home/route_list_item.dart';

class RoutesPage extends HookConsumerWidget {
  const RoutesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFilter = useState<String?>(null);
    final routesAsync = ref.watch(routesProvider(type: selectedFilter.value));
    final statsAsync = ref.watch(userStatsNotifierProvider);
    final stats = statsAsync.valueOrNull;
    final ownActivity = stats?.ownRoutesActivity;
    final routesCreated = stats?.routesCreated;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F7),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(routesProvider(type: selectedFilter.value).notifier).refresh(),
          child: CustomScrollView(
            slivers: [
              // 헤더: Your Routes
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 36, color: Colors.black),
                          children: [
                            TextSpan(text: 'Your\n'),
                            TextSpan(
                              text: l10n.routesTitle,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      if (ownActivity != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          l10n.routesTabSubtitle(
                            ownActivity.totalCount,
                            ownActivity.completedCount,
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // 필터 칩
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Row(
                    children: [
                      _FilterChip(
                        label: routesCreated == null
                            ? 'All'
                            : l10n.filterLabelWithCount('All', routesCreated.totalCount),
                        selected: selectedFilter.value == null,
                        onTap: () => selectedFilter.value = null,
                      ),
                      const SizedBox(width: 12),
                      _FilterChip(
                        label: routesCreated == null
                            ? 'Bouldering'
                            : l10n.filterLabelWithCount('Bouldering', routesCreated.boulderingCount),
                        selected: selectedFilter.value == 'bouldering',
                        onTap: () => selectedFilter.value = 'bouldering',
                      ),
                      const SizedBox(width: 12),
                      _FilterChip(
                        label: routesCreated == null
                            ? 'Endurance'
                            : l10n.filterLabelWithCount('Endurance', routesCreated.enduranceCount),
                        selected: selectedFilter.value == 'endurance',
                        onTap: () => selectedFilter.value = 'endurance',
                      ),
                    ],
                  ),
                ),
              ),
              // 루트 리스트
              routesAsync.when(
                loading: () => const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, st) => SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(AppLocalizations.of(context)!.failedToLoadRoutes),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => ref.invalidate(routesProvider(type: selectedFilter.value)),
                          child: Text(AppLocalizations.of(context)!.retry),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (routesState) {
                  if (routesState.routes.isEmpty) {
                    return SliverFillRemaining(
                      child: Center(
                        child: Text(
                          AppLocalizations.of(context)!.noRoutesYet,
                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          // 무한 스크롤
                          if (index >= routesState.routes.length - 2 &&
                              routesState.nextToken != null &&
                              !routesState.isLoadingMore) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              ref.read(routesProvider(type: selectedFilter.value).notifier).fetchMore();
                            });
                          }

                          // 로딩 인디케이터
                          if (index == routesState.routes.length) {
                            return routesState.isLoadingMore
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(child: CircularProgressIndicator()),
                                  )
                                : const SizedBox.shrink();
                          }

                          final route = routesState.routes[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: RouteListItem(route: route),
                          );
                        },
                        childCount: routesState.routes.length + 1,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: selected ? null : Border.all(color: Colors.grey[300]!),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
