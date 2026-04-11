import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Incremented whenever an activity is created or deleted.
/// MY page watches this to know when to reload calendar data.
final activityRefreshProvider = StateProvider<int>((ref) => 0);
