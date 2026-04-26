import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../main.dart' show container;
import '../providers/user_provider.dart';
import 'http_client.dart';

class PushService {
  static bool _initialized = false;
  static String? _fcmToken;
  static Timer? _refetchTimer;

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

    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      debugPrint('[Push] permission not granted, skipping FCM registration');
      return;
    }

    if (Platform.isIOS) {
      String? apnsToken;
      for (var i = 0; i < 10; i++) {
        apnsToken = await messaging.getAPNSToken();
        if (apnsToken != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      debugPrint('[Push] APNs token: $apnsToken');
      if (apnsToken == null) {
        // iOS Simulator (and some provisioning issues on devices) never deliver
        // an APNs token; calling getToken() in that state throws and blocks startup.
        debugPrint('[Push] APNs token unavailable, skipping FCM registration');
        return;
      }
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
      _scheduleProfileRefetch();
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('[Push] opened from background: data=${message.data}');
      _routeToHome();
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('[Push] opened from terminated: data=${initial.data}');
      _routeToHome();
    }
  }

  static void _scheduleProfileRefetch() {
    _refetchTimer?.cancel();
    _refetchTimer = Timer(const Duration(seconds: 1), () {
      try {
        container.invalidate(userProfileProvider);
      } catch (e) {
        debugPrint('[Push] profile refetch trigger failed: $e');
      }
    });
  }

  static void _routeToHome() {
    final nav = AuthorizedHttpClient.navigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamedAndRemoveUntil('/home', (route) => false);
  }

  static Future<void> registerWithServer() async {
    final token = _fcmToken;
    if (token == null) return;

    final locale = PlatformDispatcher.instance.locale.toLanguageTag();
    String? timezone;
    try {
      timezone = await FlutterTimezone.getLocalTimezone();
    } catch (e) {
      timezone = null; // server falls back to Asia/Seoul
    }

    try {
      final response = await AuthorizedHttpClient.post(
        '/my/devices',
        body: {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'locale': locale,
          if (timezone != null) 'timezone': timezone,
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
