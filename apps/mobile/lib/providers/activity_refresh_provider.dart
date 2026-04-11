import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set to true when an activity is created or deleted.
/// MY page checks this flag on tab entry and reloads if needed.
final activityDirtyProvider = StateProvider<bool>((ref) => false);
