import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/user_stats_data.dart';
import '../services/http_client.dart';

part 'user_stats_provider.g.dart';

@Riverpod(keepAlive: true)
class UserStatsNotifier extends _$UserStatsNotifier {
  @override
  Future<UserStatsData> build() async {
    return _fetch();
  }

  Future<UserStatsData> _fetch() async {
    final response = await AuthorizedHttpClient.get('/my/user-stats');
    if (response.statusCode == 200) {
      return UserStatsData.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to load user stats');
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}
