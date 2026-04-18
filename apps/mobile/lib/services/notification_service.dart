import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import '../models/notification_data.dart';
import 'http_client.dart';

class NotificationListResult {
  final List<NotificationData> items;
  final DateTime? nextCursor;

  const NotificationListResult({
    required this.items,
    required this.nextCursor,
  });
}

class NotificationService {
  static Future<NotificationListResult> list({
    DateTime? before,
    int limit = 20,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (before != null) {
      query['before'] = before.toUtc().toIso8601String();
    }
    final qs = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final path = qs.isEmpty ? '/notifications' : '/notifications?$qs';

    final response = await AuthorizedHttpClient.get(
      path,
      extraHeaders: {
        'Accept-Language': PlatformDispatcher.instance.locale.languageCode,
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load notifications: ${response.statusCode}',
      );
    }
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final items = (decoded['items'] as List<dynamic>)
        .map((e) => NotificationData.fromJson(e as Map<String, dynamic>))
        .toList();
    final nextCursorStr = decoded['nextCursor'] as String?;
    final nextCursor =
        nextCursorStr == null ? null : DateTime.parse(nextCursorStr);
    return NotificationListResult(items: items, nextCursor: nextCursor);
  }

  /// Marks all notifications created at or before [before] as read.
  /// Returns the server's updated unreadNotificationCount.
  static Future<int> markRead(DateTime before) async {
    final response = await AuthorizedHttpClient.post(
      '/notifications/mark-read',
      body: {'before': before.toUtc().toIso8601String()},
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to mark notifications read: ${response.statusCode}',
      );
    }
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return (decoded['unreadNotificationCount'] as int?) ?? 0;
  }
}
