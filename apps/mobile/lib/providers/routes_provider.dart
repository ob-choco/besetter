import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/route_data.dart';
import '../models/paginated_response.dart';
import '../services/http_client.dart';

part 'routes_provider.g.dart';

class RoutesState {
  final List<RouteData> routes;
  final String? nextToken;
  final bool isLoadingMore;

  const RoutesState({
    this.routes = const [],
    this.nextToken,
    this.isLoadingMore = false,
  });

  RoutesState copyWith({
    List<RouteData>? routes,
    String? nextToken,
    bool? isLoadingMore,
  }) {
    return RoutesState(
      routes: routes ?? this.routes,
      nextToken: nextToken,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

@riverpod
class Routes extends _$Routes {
  @override
  Future<RoutesState> build() async {
    return _fetchInitial();
  }

  Future<RoutesState> _fetchInitial() async {
    final queryParams = {
      'sort': 'createdAt:desc',
      'limit': '4',
    };
    final uri = Uri.parse('/routes').replace(queryParameters: queryParams);
    final response = await AuthorizedHttpClient.get(uri.toString());

    if (response.statusCode == 200) {
      final result = PaginatedResponse.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
        (json) => RouteData.fromJson(json),
      );
      return RoutesState(
        routes: result.data,
        nextToken: result.nextToken,
      );
    } else {
      throw Exception('Failed to load routes');
    }
  }

  Future<void> fetchMore() async {
    final current = state.valueOrNull;
    if (current == null || current.nextToken == null || current.isLoadingMore) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final queryParams = {
        'sort': 'createdAt:desc',
        'limit': '4',
        'next': current.nextToken!,
      };
      final uri = Uri.parse('/routes').replace(queryParameters: queryParams);
      final response = await AuthorizedHttpClient.get(uri.toString());

      if (response.statusCode == 200) {
        final result = PaginatedResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
          (json) => RouteData.fromJson(json),
        );
        state = AsyncData(RoutesState(
          routes: [...current.routes, ...result.data],
          nextToken: result.nextToken,
          isLoadingMore: false,
        ));
      } else {
        state = AsyncData(current.copyWith(isLoadingMore: false));
        throw Exception('Failed to load more routes');
      }
    } catch (e) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
      rethrow;
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<bool> deleteRoute(String routeId) async {
    try {
      final response = await AuthorizedHttpClient.delete('/routes/$routeId');
      if (response.statusCode == 204) {
        await refresh();
        ref.invalidate(routesTotalCountProvider);
        return true;
      } else {
        throw Exception('Failed to delete route');
      }
    } catch (e) {
      debugPrint('Error deleting route: $e');
      return false;
    }
  }
}

@riverpod
Future<int> routesTotalCount(RoutesTotalCountRef ref) async {
  final response = await AuthorizedHttpClient.get('/routes/count');
  if (response.statusCode == 200) {
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['totalCount'] as int;
  }
  throw Exception('Failed to fetch total count');
}
