import 'dart:convert';
import 'http_client.dart';

class ActivityService {
  /// Create an activity with final result (completed or attempted).
  ///
  /// [routeId] - The route this activity belongs to.
  /// [status] - "completed" or "attempted".
  /// [startedAt] - When the climb started (ISO 8601).
  /// [endedAt] - When the climb ended (ISO 8601).
  /// [latitude] - Current GPS latitude for location verification.
  /// [longitude] - Current GPS longitude for location verification.
  static Future<Map<String, dynamic>> createActivity({
    required String routeId,
    required String status,
    required DateTime startedAt,
    required DateTime endedAt,
    required double latitude,
    required double longitude,
  }) async {
    final body = {
      'status': status,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
    };

    final response = await AuthorizedHttpClient.post(
      '/routes/$routeId/activity',
      body: body,
    );

    if (response.statusCode == 201) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to create activity. Status: ${response.statusCode}');
    }
  }

  /// Delete an activity (hard delete).
  static Future<void> deleteActivity({
    required String routeId,
    required String activityId,
  }) async {
    final response = await AuthorizedHttpClient.delete(
      '/routes/$routeId/activity/$activityId',
    );

    if (response.statusCode != 204) {
      throw Exception('Failed to delete activity. Status: ${response.statusCode}');
    }
  }
}
