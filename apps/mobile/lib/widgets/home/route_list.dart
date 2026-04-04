import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../providers/routes_provider.dart';
import 'route_card.dart';

class RouteList extends HookConsumerWidget {
  final ScrollController? parentScrollController;
  final VoidCallback? onInteraction;

  const RouteList({
    super.key,
    this.parentScrollController,
    this.onInteraction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routesAsync = ref.watch(routesProvider());

    useEffect(() {
      void onScroll() {
        final controller = parentScrollController;
        if (controller == null) return;

        if (controller.position.pixels >= controller.position.maxScrollExtent * 0.8) {
          final state = routesAsync.valueOrNull;
          if (state != null && state.nextToken != null && !state.isLoadingMore) {
            ref.read(routesProvider().notifier).fetchMore();
          }
        }
      }

      parentScrollController?.addListener(onScroll);
      return () => parentScrollController?.removeListener(onScroll);
    }, [parentScrollController, routesAsync]);

    return routesAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => SliverToBoxAdapter(
        child: Center(child: Text('Error: $e')),
      ),
      data: (state) => SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == state.routes.length) {
              return (state.nextToken != null && state.isLoadingMore)
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: RouteCard(
                route: state.routes[index],
                onInteraction: onInteraction,
              ),
            );
          },
          childCount: state.routes.length +
              ((state.nextToken != null && state.isLoadingMore) ? 1 : 0),
        ),
      ),
    );
  }
}
