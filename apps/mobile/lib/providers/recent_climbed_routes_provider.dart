import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/route_data.dart';
import '../services/http_client.dart';

part 'recent_climbed_routes_provider.g.dart';

@riverpod
Future<List<RouteData>> recentClimbedRoutes(Ref ref) async {
  final response = await AuthorizedHttpClient.get(
    '/my/recently-climbed-routes?limit=9',
  );
  if (response.statusCode != 200) {
    throw Exception(
      'Failed to load recently climbed routes (status ${response.statusCode})',
    );
  }
  final decoded = jsonDecode(utf8.decode(response.bodyBytes));
  final data = decoded['data'] as List<dynamic>;
  return data
      .map((e) => RouteData.fromJson(e as Map<String, dynamic>))
      .toList();
}
