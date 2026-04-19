import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'main_tab_provider.g.dart';

@riverpod
class MainTabIndex extends _$MainTabIndex {
  @override
  int build() => 0;

  void set(int index) {
    if (index < 0 || index > 2) return;
    state = index;
  }
}
