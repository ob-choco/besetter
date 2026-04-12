# Flutter PostHog Integration

**Date:** 2026-04-12
**Status:** Approved design, ready for plan
**Scope:** `apps/mobile` (Flutter app only)

## Goal

Add PostHog product analytics to the Flutter app alongside the existing Firebase Analytics. First release enables:

- Automatic screen tracking
- User identification wired to `authProvider`
- Session replay (with default masking)
- Native crash capture
- Application lifecycle events

No custom event taxonomy is defined in this spec — product events will be added incrementally in follow-up work. This spec covers only the SDK integration and wiring.

## Non-Goals

- Replacing or removing Firebase Analytics
- Defining a product event taxonomy
- Dashboards, feature flags, or A/B experiments configuration
- Backend (Node API) integration

## Project Configuration

- **PostHog project:** `378744`
- **Host:** `https://us.i.posthog.com` (US Cloud)
- **Client API key (public write key):** `phc_wLKorSH6QdipSfGhpBF2cw8xMc6JrUKYY3trjfwzjnJW`
- **Environment separation:** Single project/key for now (dev + prod share). Revisit if noise becomes a problem.

## Initialization Strategy

Use PostHog's **native configuration** approach (option A from brainstorming). The SDK auto-initializes from metadata declared in `Info.plist` (iOS) and `AndroidManifest.xml` (Android). No Dart-side `setup()` call in `main.dart`.

Rationale:
- Official PostHog recommendation for Flutter
- Keeps `main.dart` lean
- Avoids a second place to track SDK config alongside LineSDK / KakaoSdk

Trade-off: Dart-side env/runtime config (e.g., different keys per flavor) is harder. Acceptable because we use a single key.

## Package

Add to `apps/mobile/pubspec.yaml`:

```yaml
posthog_flutter: ^4.10.0
```

(Pin to the latest stable at implementation time; 4.x is the current major.)

## Native Configuration

### iOS — `apps/mobile/ios/Runner/Info.plist`

Add to the top-level `<dict>`:

```xml
<key>com.posthog.posthog.API_KEY</key>
<string>phc_wLKorSH6QdipSfGhpBF2cw8xMc6JrUKYY3trjfwzjnJW</string>
<key>com.posthog.posthog.POSTHOG_HOST</key>
<string>https://us.i.posthog.com</string>
<key>com.posthog.posthog.CAPTURE_APPLICATION_LIFECYCLE_EVENTS</key>
<true/>
<key>com.posthog.posthog.SESSION_REPLAY</key>
<true/>
<key>com.posthog.posthog.CAPTURE_NATIVE_CRASHES</key>
<true/>
```

### Android — `apps/mobile/android/app/src/main/AndroidManifest.xml`

Add inside `<application>`:

```xml
<meta-data android:name="com.posthog.posthog.API_KEY"
           android:value="phc_wLKorSH6QdipSfGhpBF2cw8xMc6JrUKYY3trjfwzjnJW" />
<meta-data android:name="com.posthog.posthog.POSTHOG_HOST"
           android:value="https://us.i.posthog.com" />
<meta-data android:name="com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS"
           android:value="true" />
<meta-data android:name="com.posthog.posthog.SESSION_REPLAY"
           android:value="true" />
<meta-data android:name="com.posthog.posthog.CAPTURE_NATIVE_CRASHES"
           android:value="true" />
```

> The exact metadata key names and value types (`<true/>` vs `android:value="true"`) follow the current `posthog_flutter` README. Implementation must verify against the installed package version — if keys have diverged, update this spec before proceeding.

## Dart-Side Wiring

### New file — `apps/mobile/lib/services/posthog_service.dart`

A thin static wrapper so callers do not import `posthog_flutter` directly. Keeps the SDK swappable and gives us one place to add no-op guards, debug logging, etc.

```dart
import 'package:posthog_flutter/posthog_flutter.dart';

class PosthogService {
  static final _posthog = Posthog();

  static Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
  }) =>
      _posthog.identify(userId: userId, userProperties: userProperties);

  static Future<void> reset() => _posthog.reset();

  static Future<void> capture(
    String event, {
    Map<String, Object>? properties,
  }) =>
      _posthog.capture(eventName: event, properties: properties);
}
```

### `main.dart` — two changes

**1. Register `PosthogObserver` alongside the existing `routeObserver`:**

```dart
navigatorObservers: [routeObserver, PosthogObserver()],
```

This is the SDK-provided `NavigatorObserver` that emits a `$screen` event on each route push/pop. Uses the route's `settings.name` — works cleanly with the named routes already defined in `MaterialApp.routes` and also with `MaterialPageRoute` pushes that carry a `RouteSettings(name: ...)`. Unnamed pushes will be captured with an empty name; we accept this and can retrofit names later where analytics matter.

**2. Wire identify/reset to `authProvider`:**

After `container = ProviderContainer()`, before `runApp`:

```dart
container.listen<AsyncValue<AuthState>>(
  authProvider,
  (prev, next) {
    next.whenData((auth) {
      final prevLoggedIn = prev?.value?.isLoggedIn ?? false;
      if (auth.isLoggedIn && auth.userId != null) {
        if (!prevLoggedIn || prev?.value?.userId != auth.userId) {
          PosthogService.identify(userId: auth.userId!);
        }
      } else if (prevLoggedIn) {
        PosthogService.reset();
      }
    });
  },
  fireImmediately: true,
);
```

(Exact field names — `isLoggedIn`, `userId` — must be verified against the current `authProvider` / `AuthState` during implementation. The logic is: on transition to logged-in call `identify`, on transition to logged-out call `reset`. Idempotent calls on the same state are avoided.)

`authProvider` itself is not modified.

## Session Replay & Masking

PostHog Flutter session replay defaults:
- All text inputs masked
- All images masked

This is sufficient for a v1. Additional wrapping with `PostHogMaskWidget` is deferred to a follow-up PR once we have session replay data and can identify which non-input widgets leak sensitive content. Candidate areas (to be evaluated then):
- `widgets/editors/place_selection_sheet.dart` — address/coordinate text
- `pages/image_list_page.dart` and route viewer photo previews
- Any user-provided free text on `my_page`

This spec does **not** commit to specific masking call sites. It commits only to "keep defaults on, evaluate after first session data lands."

## File Change Summary

| File | Change |
|---|---|
| `apps/mobile/pubspec.yaml` | Add `posthog_flutter` dependency |
| `apps/mobile/ios/Runner/Info.plist` | Add 5 PostHog meta keys |
| `apps/mobile/android/app/src/main/AndroidManifest.xml` | Add 5 PostHog `<meta-data>` entries inside `<application>` |
| `apps/mobile/lib/services/posthog_service.dart` | **NEW** — static wrapper |
| `apps/mobile/lib/main.dart` | Add `PosthogObserver` to `navigatorObservers`; add `container.listen(authProvider, …)` for identify/reset |

Nothing else is touched. `authProvider`, existing pages, Firebase setup — all unchanged.

## Verification

- `cd apps/mobile && flutter pub get`
- `cd apps/mobile && flutter analyze` — must pass
- Manual verification (post-merge, on a real device) that events arrive in the PostHog project 378744 dashboard. Not gated on CI.

## Risks & Open Questions

- **Android `AndroidManifest.xml` already has local modifications** (`git status` at spec time). Implementation must rebase cleanly on those.
- **iOS `Podfile` / `AppDelegate.swift` already have local modifications.** Verify no conflict with the `posthog_flutter` pod install.
- **API key in VCS:** This is the PostHog *client/write* key, which is designed to ship in clients. Not a secret. Safe to commit.
- **Duplicate analytics:** Running PostHog + Firebase Analytics simultaneously is fine; no deduplication work needed.
