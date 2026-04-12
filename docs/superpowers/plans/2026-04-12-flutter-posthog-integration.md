# Flutter PostHog Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire PostHog Flutter SDK into the Besetter mobile app with native config, automatic screen tracking, session replay, native crash capture, and user identification driven by a new `id` field exposed from `/users/me`.

**Architecture:** PostHog initializes automatically from `Info.plist` / `AndroidManifest.xml` metadata (no Dart-side `setup()`). A thin `PosthogService` wrapper hides the SDK from callers. `main.dart` registers `PosthogObserver` for screen events and listens to `userProfileProvider` (identify) and `authProvider` (reset). Backend `/users/me` is extended to include `id: str` so the client has a stable distinct_id.

**Tech Stack:** Flutter 3.x, Dart, hooks_riverpod + riverpod_annotation, posthog_flutter ^4.10.0, FastAPI (Python) for `/users/me`, Beanie/MongoDB for the User model.

**Spec:** `docs/superpowers/specs/2026-04-12-flutter-posthog-integration-design.md`

**Verification commands used in this plan:**
- Backend: `cd services/api && uv run pytest tests/routers/test_users.py -v`
- Mobile analyze: `cd apps/mobile && flutter analyze`
- Mobile deps: `cd apps/mobile && flutter pub get`
- Mobile codegen: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`

---

## Task 1: Backend — expose `id` from `/users/me`

**Files:**
- Modify: `services/api/app/routers/users.py` (lines 27-34 and 41-56)
- Create: `services/api/tests/routers/test_users.py`

- [ ] **Step 1: Create the failing test file**

Create `services/api/tests/routers/test_users.py`:

```python
from types import SimpleNamespace

from bson import ObjectId

from app.routers.users import UserProfileResponse, _build_profile_response


def _make_user(
    *,
    id: ObjectId,
    name: str | None = None,
    email: str | None = None,
    bio: str | None = None,
    profile_image_url: str | None = None,
) -> SimpleNamespace:
    return SimpleNamespace(
        id=id,
        name=name,
        email=email,
        bio=bio,
        profile_image_url=profile_image_url,
    )


def test_user_profile_response_serializes_id():
    """UserProfileResponse should carry a string id field."""
    resp = UserProfileResponse(
        id="507f1f77bcf86cd799439011",
        name="alice",
        email=None,
        bio=None,
        profile_image_url=None,
    )
    dumped = resp.model_dump(by_alias=True)
    assert dumped["id"] == "507f1f77bcf86cd799439011"


def test_build_profile_response_populates_id_as_string():
    """_build_profile_response should stringify the user's ObjectId into `id`."""
    oid = ObjectId()
    user = _make_user(id=oid, name="alice", email="a@example.com")

    resp = _build_profile_response(user)

    assert resp.id == str(oid)
    assert resp.name == "alice"
    assert resp.email == "a@example.com"
    assert resp.profile_image_url is None


def test_build_profile_response_passes_through_nulls():
    """Missing optional fields should round-trip as None."""
    oid = ObjectId()
    user = _make_user(id=oid)

    resp = _build_profile_response(user)

    assert resp.id == str(oid)
    assert resp.name is None
    assert resp.email is None
    assert resp.bio is None
    assert resp.profile_image_url is None
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd services/api && uv run pytest tests/routers/test_users.py -v`
Expected: FAIL — `UserProfileResponse` has no `id` field, so the first test's keyword argument raises `ValidationError` and the second/third fail accessing `resp.id`.

- [ ] **Step 3: Add `id` to the response schema**

Edit `services/api/app/routers/users.py`, replacing the `UserProfileResponse` class (lines 27-33):

```python
class UserProfileResponse(BaseModel):
    model_config = model_config

    # Override the class-level to_camel alias generator, which maps
    # `id` -> `_id` for Beanie/Mongo. We want `id` on the wire.
    id: str = Field(alias="id")
    name: Optional[str] = None
    email: Optional[str] = None
    bio: Optional[str] = None
    profile_image_url: Optional[str] = None
```

(Requires `from pydantic import BaseModel, Field` — the existing import only has `BaseModel`.)

- [ ] **Step 4: Populate `id` in the builder**

In the same file, update `_build_profile_response` (lines 41-56). Replace the `return UserProfileResponse(...)` block with:

```python
    return UserProfileResponse(
        id=str(user.id),
        name=user.name,
        email=user.email,
        bio=user.bio,
        profile_image_url=signed_url,
    )
```

Leave the signed-URL logic above it unchanged.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd services/api && uv run pytest tests/routers/test_users.py -v`
Expected: PASS (3 tests).

- [ ] **Step 6: Run the full router test suite to confirm no regression**

Run: `cd services/api && uv run pytest tests/routers/ -q`
Expected: PASS for all existing tests.

- [ ] **Step 7: Commit**

```bash
git add services/api/app/routers/users.py services/api/tests/routers/test_users.py
git commit -m "feat(api): expose user id from GET /users/me"
```

---

## Task 2: Backend deploy (manual gate)

This task is a **hand-off to the user**. Do not attempt to run `deploy.sh` from the subagent — it targets Cloud Run and is a production-affecting action that must be user-initiated.

- [ ] **Step 1: Notify user that backend is ready to deploy**

Report to the user:

> Task 1 committed. `/users/me` now returns `id`. This must be deployed to Cloud Run (`services/api/deploy.sh`, `besetter-api`, `asia-northeast3`) **before** the mobile client that depends on the new field is released. Old mobile clients will continue to work since they ignore unknown fields. Please run the deploy yourself and confirm when `/users/me` in prod returns `id`. I'll proceed with mobile-side tasks in the meantime — they do not require a running local backend to pass `flutter analyze`.

- [ ] **Step 2: Proceed to Task 3 without waiting**

Mobile tasks 3–9 can be implemented and analyzed in parallel with the backend deploy. Runtime verification (Task 9 manual step) is what requires the deployed backend.

---

## Task 3: Mobile — add posthog_flutter dependency

**Files:**
- Modify: `apps/mobile/pubspec.yaml:79` (end of the `dependencies:` block, after `wakelock_plus`)
- Modify: `apps/mobile/pubspec.lock` (regenerated)

- [ ] **Step 1: Add the dependency line**

Edit `apps/mobile/pubspec.yaml`. Locate the line `wakelock_plus: ^1.4.0` (line 81) and add immediately after it, still under `dependencies:`:

```yaml
  posthog_flutter: ^4.10.0
```

- [ ] **Step 2: Resolve dependencies**

Run: `cd apps/mobile && flutter pub get`
Expected: Resolves successfully. `pubspec.lock` is updated. If `posthog_flutter ^4.10.0` does not resolve (e.g. a newer major is out and the constraint needs a bump), bump to the latest stable `4.x` reported by `flutter pub outdated` and rerun.

- [ ] **Step 3: Confirm static analysis still passes**

Run: `cd apps/mobile && flutter analyze`
Expected: No new errors introduced by the dependency (there will be no code importing it yet).

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock
git commit -m "chore(mobile): add posthog_flutter dependency"
```

---

## Task 4: Mobile — iOS Info.plist metadata

**Files:**
- Modify: `apps/mobile/ios/Runner/Info.plist` (insert before closing `</dict>` on line 82)

- [ ] **Step 1: Insert PostHog metadata keys**

Edit `apps/mobile/ios/Runner/Info.plist`. Immediately before the closing `</dict>` (line 82, right after the existing `UISupportedInterfaceOrientations~ipad` array), insert:

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

Indentation is one tab character per line, matching the surrounding file (which uses tabs).

- [ ] **Step 2: Validate plist syntax**

Run: `plutil -lint apps/mobile/ios/Runner/Info.plist`
Expected: `apps/mobile/ios/Runner/Info.plist: OK`

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/ios/Runner/Info.plist
git commit -m "feat(mobile-ios): add posthog native config to Info.plist"
```

---

## Task 5: Mobile — Android manifest metadata

**Files:**
- Modify: `apps/mobile/android/app/src/main/AndroidManifest.xml` (inside `<application>`, after line 70's Google Maps meta-data)

- [ ] **Step 1: Insert PostHog meta-data entries**

Edit `apps/mobile/android/app/src/main/AndroidManifest.xml`. Immediately after the existing line:

```xml
        <meta-data android:name="com.google.android.geo.API_KEY" android:value="AIzaSyAsGDjU2C3MuFczysmeuiVbkyAegbtlqhQ"/>
```

and before the closing `</application>` tag, add:

```xml
        <meta-data android:name="com.posthog.posthog.API_KEY" android:value="phc_wLKorSH6QdipSfGhpBF2cw8xMc6JrUKYY3trjfwzjnJW"/>
        <meta-data android:name="com.posthog.posthog.POSTHOG_HOST" android:value="https://us.i.posthog.com"/>
        <meta-data android:name="com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS" android:value="true"/>
        <meta-data android:name="com.posthog.posthog.SESSION_REPLAY" android:value="true"/>
        <meta-data android:name="com.posthog.posthog.CAPTURE_NATIVE_CRASHES" android:value="true"/>
```

Use 8 spaces of leading indent to match the existing `<meta-data>` entry for `com.google.android.geo.API_KEY`.

- [ ] **Step 2: Validate manifest XML parses**

Run: `python3 -c "import xml.etree.ElementTree as ET; ET.parse('apps/mobile/android/app/src/main/AndroidManifest.xml'); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/android/app/src/main/AndroidManifest.xml
git commit -m "feat(mobile-android): add posthog native config to AndroidManifest"
```

---

## Task 6: Mobile — add `id` to `UserState`

**Files:**
- Modify: `apps/mobile/lib/providers/user_provider.dart` (class `UserState`, lines 8-43)

- [ ] **Step 1: Replace the `UserState` class**

Edit `apps/mobile/lib/providers/user_provider.dart`. Replace the entire `UserState` class (lines 8-43) with:

```dart
class UserState {
  final String id;
  final String? name;
  final String? email;
  final String? bio;
  final String? profileImageUrl;

  const UserState({
    required this.id,
    this.name,
    this.email,
    this.bio,
    this.profileImageUrl,
  });

  UserState copyWith({
    String? id,
    String? name,
    String? email,
    String? bio,
    String? profileImageUrl,
  }) {
    return UserState(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      bio: bio ?? this.bio,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    );
  }

  factory UserState.fromJson(Map<String, dynamic> json) {
    return UserState(
      id: json['id'] as String,
      name: json['name'] as String?,
      email: json['email'] as String?,
      bio: json['bio'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
    );
  }
}
```

The rest of the file (the `UserProfile` riverpod class, lines 45-87) is unchanged.

- [ ] **Step 2: Regenerate riverpod code**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: Completes without errors. `user_provider.g.dart` is regenerated (may be a no-op if the shape is unchanged).

- [ ] **Step 3: Run static analysis**

Run: `cd apps/mobile && flutter analyze`
Expected: PASS. If any call site constructs `UserState` directly without `id`, the analyzer will surface it — fix those call sites by either passing `id` or routing through `UserState.fromJson`. Based on a grep of the current repo, no such direct constructor calls exist, but the analyzer is the source of truth.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/providers/user_provider.dart apps/mobile/lib/providers/user_provider.g.dart
git commit -m "feat(mobile): add id field to UserState"
```

(If `user_provider.g.dart` is unchanged, drop it from the add list.)

---

## Task 7: Mobile — add `PosthogService` wrapper

**Files:**
- Create: `apps/mobile/lib/services/posthog_service.dart`

- [ ] **Step 1: Create the wrapper file**

Create `apps/mobile/lib/services/posthog_service.dart` with exactly this content:

```dart
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
```

- [ ] **Step 2: Run static analysis**

Run: `cd apps/mobile && flutter analyze`
Expected: PASS. If the `Posthog().identify(...)` signature in the installed `posthog_flutter` version differs (e.g. `distinctId` instead of `userId`, or a different property map type), the analyzer will flag it — adjust the wrapper to match the SDK surface, keeping the public method names on `PosthogService` unchanged so `main.dart` does not need to change.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/services/posthog_service.dart
git commit -m "feat(mobile): add PosthogService wrapper"
```

---

## Task 8: Mobile — wire PosthogObserver and identify/reset in `main.dart`

**Files:**
- Modify: `apps/mobile/lib/main.dart` (imports, `main()` function, `MaterialApp.navigatorObservers`)

- [ ] **Step 1: Add imports**

Edit `apps/mobile/lib/main.dart`. Add these imports alongside the existing imports at the top of the file:

```dart
import 'package:posthog_flutter/posthog_flutter.dart';
import 'services/posthog_service.dart';
import 'providers/user_provider.dart';
```

(`providers/auth_provider.dart` is already imported on line 19.)

- [ ] **Step 2: Add identify/reset listeners in `main()`**

Find this block (around lines 45-52):

```dart
  container = ProviderContainer();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );
```

Replace it with:

```dart
  container = ProviderContainer();

  // PostHog identify when we learn the user id from /users/me.
  container.listen<AsyncValue<UserState>>(
    userProfileProvider,
    (prev, next) {
      next.whenData((user) {
        if (prev?.value?.id != user.id) {
          PosthogService.identify(userId: user.id);
        }
      });
    },
    fireImmediately: true,
  );

  // PostHog reset on logout transition.
  container.listen<AsyncValue<AuthState>>(
    authProvider,
    (prev, next) {
      final wasLoggedIn = prev?.value?.isLoggedIn ?? false;
      final isLoggedIn = next.value?.isLoggedIn ?? false;
      if (wasLoggedIn && !isLoggedIn) {
        PosthogService.reset();
      }
    },
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );
```

- [ ] **Step 3: Register `PosthogObserver`**

Find the line in `MyApp.build`:

```dart
      navigatorObservers: [routeObserver],
```

Replace with:

```dart
      navigatorObservers: [routeObserver, PosthogObserver()],
```

- [ ] **Step 4: Run static analysis**

Run: `cd apps/mobile && flutter analyze`
Expected: PASS. Likely issues and their fixes:
- `The name 'userProfileProvider' isn't a top-level getter` → check the generated symbol name in `user_provider.g.dart` (riverpod_generator names it after the class, lowercased: `userProfileProvider`). Import path already added in Step 1.
- `AsyncValue<AuthState>` / `AsyncValue<UserState>` type mismatch → verify the generated provider's value type; adjust the generic.
- `PosthogObserver` not found → confirm the symbol name in the installed `posthog_flutter` version (recent versions export it from the top-level package).

Fix each reported issue, re-run `flutter analyze` until clean.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/main.dart
git commit -m "feat(mobile): wire posthog screen observer and identify/reset"
```

---

## Task 9: Final verification

**Files:** None modified in this task — pure verification.

- [ ] **Step 1: Re-run full static analysis**

Run: `cd apps/mobile && flutter analyze`
Expected: PASS with no errors and no new warnings.

- [ ] **Step 2: Re-run backend tests**

Run: `cd services/api && uv run pytest tests/routers/ -q`
Expected: PASS.

- [ ] **Step 3: Hand off manual runtime verification to the user**

Report to the user:

> All static checks pass. Manual runtime verification needed (requires a real device/simulator and the deployed backend from Task 2):
> 1. Backend deployed and `/users/me` returns `id` in prod — confirm before testing client.
> 2. Launch the app, log in, navigate between a few screens.
> 3. Open the PostHog project (id `378744`, US cloud) → Activity → Live events.
>    - Expect `$pageview`/`$screen` events as you navigate.
>    - Expect the session to be associated with `distinct_id = <your Mongo ObjectId>` after login.
>    - Expect `$identify` when logging in and `$opt_out`-style reset behavior when logging out.
> 4. Check Session Replay tab for a recording of the session (input/image masking on by default).
> 5. Force-crash native code if you want to verify crash capture (optional, not a gate).
>
> If any of the above is missing, check: (a) `flutter pub get` pulled the right version, (b) `Info.plist` / `AndroidManifest.xml` metadata actually landed in the built app, (c) `PosthogService.identify` is reached (add a temporary `print` if needed).

- [ ] **Step 4: Plan complete**

No further automated steps. Leave the branch in a reviewable state for the user to open a PR against `main`.

---

## Notes for the implementing agent

- **No git worktree:** The user elected to work directly on `main`. Commit per task as specified; do not squash.
- **Existing uncommitted changes:** At plan time, `git status` showed `AndroidManifest.xml`, `Podfile`, `AppDelegate.swift`, `place_selection_sheet.dart`, `pubspec.lock`, `pubspec.yaml` as modified. **Do not revert them.** The edits in Tasks 3–5 must be additive on top of whatever is there. If a conflict arises (e.g. the existing pubspec.yaml change already added a package), integrate rather than overwrite.
- **No worktree-level test suite for mobile:** `flutter test` is listed in CLAUDE.md as optional. The primary gate is `flutter analyze`. Do not invent new test files unless the task explicitly says so.
- **Never run `flutter build` or `flutter run`** per `apps/mobile/CLAUDE.md`.
- **Do not deploy the backend yourself.** `services/api/deploy.sh` is user-initiated only (see Task 2).
