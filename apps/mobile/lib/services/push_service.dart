import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'http_client.dart';

class PushService {
  static bool _initialized = false;
  static String? _fcmToken;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[Push] permission: ${settings.authorizationStatus}');

    if (Platform.isIOS) {
      final apnsToken = await messaging.getAPNSToken();
      debugPrint('[Push] APNs token: $apnsToken');
    }

    _fcmToken = await messaging.getToken();
    debugPrint('[Push] FCM token: $_fcmToken');

    messaging.onTokenRefresh.listen((token) async {
      debugPrint('[Push] FCM token refreshed: $token');
      _fcmToken = token;
      await registerWithServer();
    });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint(
        '[Push] foreground: title=${message.notification?.title} '
        'body=${message.notification?.body} data=${message.data}',
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('[Push] opened from background: data=${message.data}');
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('[Push] opened from terminated: data=${initial.data}');
    }
  }

  static Future<void> registerWithServer() async {
    final token = _fcmToken;
    if (token == null) return;
    try {
      final response = await AuthorizedHttpClient.post(
        '/my/devices',
        body: {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
      debugPrint('[Push] POST /my/devices: ${response.statusCode}');
    } catch (e) {
      debugPrint('[Push] POST /my/devices failed: $e');
    }
  }

  static Future<void> unregisterFromServer() async {
    final token = _fcmToken;
    if (token == null) return;
    try {
      final response = await AuthorizedHttpClient.delete('/my/devices/$token');
      debugPrint('[Push] DELETE /my/devices: ${response.statusCode}');
    } catch (e) {
      debugPrint('[Push] DELETE /my/devices failed: $e');
    }
  }
}
