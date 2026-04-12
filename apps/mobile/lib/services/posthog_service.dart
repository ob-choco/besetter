import 'package:posthog_flutter/posthog_flutter.dart';

/// Thin wrapper around the PostHog Flutter SDK.
///
/// Keep call sites free of direct `posthog_flutter` imports so we can
/// swap, stub, or disable analytics in one place.
class PosthogService {
  static final _posthog = Posthog();

  static Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
  }) {
    return _posthog.identify(
      userId: userId,
      userProperties: userProperties,
    );
  }

  static Future<void> reset() => _posthog.reset();

  static Future<void> capture(
    String event, {
    Map<String, Object>? properties,
  }) {
    return _posthog.capture(
      eventName: event,
      properties: properties,
    );
  }
}
