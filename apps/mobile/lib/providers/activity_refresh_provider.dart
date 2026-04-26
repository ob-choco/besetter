import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recent_climbed_routes_provider.dart';
import 'user_stats_provider.dart';

/// Set to true when an activity is created or deleted anywhere in the app.
/// Cleared by [flushActivityDirty] at navigation boundaries (back press,
/// tab switch).
final activityDirtyProvider = StateProvider<bool>((ref) => false);

/// Incremented by [flushActivityDirty]. MY page watches this to trigger
/// imperative reloads (monthly calendar summary, daily routes) that are not
/// backed by Riverpod providers.
final myPageRefreshCounterProvider = StateProvider<int>((ref) => 0);

/// If an activity mutation has occurred since the last flush, invalidate
/// every cache that depends on activity state and notify the MY page to
/// reload its imperative data. No-op when nothing is dirty.
///
/// Call this from navigation boundaries — back press out of a mutation
/// page, or bottom-nav tab switches — so downstream screens see fresh
/// data the next time they render.
void flushActivityDirty(ProviderContainer container) {
  if (!container.read(activityDirtyProvider)) return;
  container.read(activityDirtyProvider.notifier).state = false;
  container.invalidate(userStatsNotifierProvider);
  container.invalidate(recentClimbedRoutesProvider);
  container.read(myPageRefreshCounterProvider.notifier).state++;
}
