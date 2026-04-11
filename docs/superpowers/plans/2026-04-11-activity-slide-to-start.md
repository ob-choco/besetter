# Activity Slide-to-Start & API Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify Activity API (remove STARTED status and PATCH endpoint) and add slide-to-start / timer / confirmation UI to the Route Viewer mobile screen.

**Architecture:** API becomes stateless — client runs timer locally, POSTs final result (completed/attempted) with startedAt/endedAt. Mobile adds three widgets (SlideToStart, TimerPanel, Confirmation) orchestrated by a parent ActivityPanel widget placed between hold list and route info in RouteViewer.

**Tech Stack:** FastAPI + Beanie (API), Flutter + Riverpod + Hooks (Mobile), geolocator (GPS), confetti (already installed)

---

## File Structure

### API (Modify)
| File | Responsibility |
|---|---|
| `services/api/app/models/activity.py` | Remove STARTED from ActivityStatus, update Activity default |
| `services/api/app/routers/activities.py` | Simplify POST, remove PATCH, remove auto-cancel |
| `services/api/tests/models/test_activity.py` | Update model tests |
| `services/api/tests/routers/test_activity_helpers.py` | Update helper tests |

### Mobile (Create/Modify)
| File | Responsibility |
|---|---|
| `apps/mobile/lib/services/activity_service.dart` | Activity POST/DELETE API calls |
| `apps/mobile/lib/widgets/viewers/slide_to_start.dart` | Swipe-to-start bar widget |
| `apps/mobile/lib/widgets/viewers/activity_timer_panel.dart` | Timer display + action buttons |
| `apps/mobile/lib/widgets/viewers/activity_confirmation.dart` | Post-record confirmation with confetti |
| `apps/mobile/lib/widgets/viewers/activity_panel.dart` | State machine orchestrating the 3 sub-widgets |
| `apps/mobile/lib/pages/viewers/route_viewer.dart` | Integrate ActivityPanel between holds and route info |
| `apps/mobile/pubspec.yaml` | Add geolocator dependency |
| `apps/mobile/android/app/src/main/AndroidManifest.xml` | Add location permission |
| `apps/mobile/ios/Runner/Info.plist` | Add location permission description |
| `apps/mobile/lib/l10n/app_en.arb` | Add English strings |
| `apps/mobile/lib/l10n/app_ko.arb` | Add Korean strings |
| `apps/mobile/lib/l10n/app_ja.arb` | Add Japanese strings |
| `apps/mobile/lib/l10n/app_es.arb` | Add Spanish strings |

---

### Task 1: API — Remove STARTED status and simplify model

**Files:**
- Modify: `services/api/app/models/activity.py`
- Modify: `services/api/tests/models/test_activity.py`

- [ ] **Step 1: Update ActivityStatus enum — remove STARTED**

In `services/api/app/models/activity.py`, change the enum from:

```python
class ActivityStatus(str, Enum):
    STARTED = "started"
    COMPLETED = "completed"
    ATTEMPTED = "attempted"
```

To:

```python
class ActivityStatus(str, Enum):
    COMPLETED = "completed"
    ATTEMPTED = "attempted"
```

- [ ] **Step 2: Update Activity model default — remove default status**

In the same file, change the `Activity` class field from:

```python
status: ActivityStatus = ActivityStatus.STARTED
```

To:

```python
status: ActivityStatus
```

Also change:

```python
ended_at: Optional[datetime] = None
duration: Optional[int] = None
```

To:

```python
ended_at: datetime
duration: int
```

Since all activities now have final status with times.

- [ ] **Step 3: Simplify index — remove status from compound index**

In the same file, change the `Activity.Settings.indexes` from:

```python
indexes = [
    IndexModel([("userId", ASCENDING), ("startedAt", ASCENDING)]),
    IndexModel([("routeId", ASCENDING), ("userId", ASCENDING), ("status", ASCENDING)]),
]
```

To:

```python
indexes = [
    IndexModel([("userId", ASCENDING), ("startedAt", ASCENDING)]),
    IndexModel([("routeId", ASCENDING), ("userId", ASCENDING)]),
]
```

- [ ] **Step 4: Update model tests**

Replace `services/api/tests/models/test_activity.py` entirely:

```python
from datetime import datetime, timezone
from app.models.activity import (
    ActivityStatus,
    RouteSnapshot,
    ActivityStats,
    Activity,
    UserRouteStats,
)


def test_activity_status_values():
    assert ActivityStatus.COMPLETED == "completed"
    assert ActivityStatus.ATTEMPTED == "attempted"
    assert len(ActivityStatus) == 2


def test_route_snapshot_minimal():
    snap = RouteSnapshot(
        grade_type="v_scale",
        grade="V7",
    )
    assert snap.title is None
    assert snap.grade_type == "v_scale"
    assert snap.grade == "V7"
    assert snap.place_id is None
    assert snap.image_url is None


def test_route_snapshot_full():
    snap = RouteSnapshot(
        title="Electric Drift",
        grade_type="v_scale",
        grade="V7",
        grade_color="#FF5722",
        place_name="Urban Apex Gym",
        image_url="https://example.com/img.jpg",
        overlay_image_url="https://example.com/overlay.jpg",
    )
    assert snap.title == "Electric Drift"
    assert snap.place_name == "Urban Apex Gym"


def test_activity_stats_defaults():
    stats = ActivityStats()
    assert stats.total_count == 0
    assert stats.total_duration == 0
    assert stats.completed_count == 0
    assert stats.completed_duration == 0
    assert stats.verified_completed_count == 0
    assert stats.verified_completed_duration == 0


def test_activity_stats_camel_case_alias():
    stats = ActivityStats()
    dumped = stats.model_dump(by_alias=True)
    assert "totalCount" in dumped
    assert "totalDuration" in dumped
    assert "completedCount" in dumped
    assert "verifiedCompletedCount" in dumped


def test_activity_completed():
    from bson import ObjectId
    snap = RouteSnapshot(grade_type="v_scale", grade="V7")
    now = datetime.now(tz=timezone.utc)
    activity = Activity(
        route_id=ObjectId(),
        user_id=ObjectId(),
        status=ActivityStatus.COMPLETED,
        location_verified=True,
        started_at=now,
        ended_at=now,
        duration=154,
        route_snapshot=snap,
        created_at=now,
    )
    assert activity.status == ActivityStatus.COMPLETED
    assert activity.duration == 154


def test_user_route_stats_defaults():
    from bson import ObjectId
    stats = UserRouteStats(
        user_id=ObjectId(),
        route_id=ObjectId(),
    )
    assert stats.total_count == 0
    assert stats.last_activity_at is None
```

- [ ] **Step 5: Run tests**

Run: `cd /Users/htjo/besetter && .venv/bin/python -m pytest services/api/tests/models/test_activity.py -v`
Expected: All 7 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add services/api/app/models/activity.py services/api/tests/models/test_activity.py
git commit -m "refactor(api): remove STARTED status from ActivityStatus, simplify Activity model"
```

---

### Task 2: API — Simplify POST endpoint, remove PATCH and auto-cancel

**Files:**
- Modify: `services/api/app/routers/activities.py`
- Modify: `services/api/tests/routers/test_activity_helpers.py`

- [ ] **Step 1: Rewrite the router file**

Replace the entire content of `services/api/app/routers/activities.py` with:

```python
from datetime import datetime, timezone
from typing import Optional

from beanie.odm.fields import PydanticObjectId
from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException
from fastapi import status as http_status
from pydantic import BaseModel, Field

from app.core.geo import haversine_distance
from app.dependencies import get_current_user
from app.models import model_config
from app.models.activity import (
    Activity,
    ActivityStatus,
    RouteSnapshot,
    UserRouteStats,
)
from app.models.image import Image
from app.models.place import Place
from app.models.route import Route
from app.models.user import User

router = APIRouter(prefix="/routes", tags=["activities"])

LOCATION_VERIFICATION_RADIUS_M = 300


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------


class CreateActivityRequest(BaseModel):
    model_config = model_config

    latitude: float
    longitude: float
    status: ActivityStatus
    started_at: datetime
    ended_at: datetime


class ActivityResponse(BaseModel):
    model_config = model_config

    id: PydanticObjectId
    route_id: PydanticObjectId
    status: ActivityStatus
    location_verified: bool
    started_at: datetime
    ended_at: datetime
    duration: int
    route_snapshot: RouteSnapshot
    created_at: datetime
    updated_at: Optional[datetime] = None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _compute_duration(started_at: datetime, ended_at: datetime) -> int:
    """Return duration in seconds between started_at and ended_at."""
    return int((ended_at - started_at).total_seconds())


def _build_stats_inc(
    status: ActivityStatus,
    location_verified: bool,
    duration: int,
    sign: int = 1,
) -> dict:
    """Build a MongoDB $inc dict for activity_stats / UserRouteStats fields.

    sign=1 for increment, sign=-1 for decrement.
    """
    inc = {}
    inc["totalCount"] = sign
    inc["totalDuration"] = sign * duration

    if status == ActivityStatus.COMPLETED:
        inc["completedCount"] = sign
        inc["completedDuration"] = sign * duration
        if location_verified:
            inc["verifiedCompletedCount"] = sign
            inc["verifiedCompletedDuration"] = sign * duration

    return inc


async def _update_route_stats(route_id: PydanticObjectId, inc: dict) -> None:
    """Increment Route.activity_stats fields."""
    prefixed = {f"activityStats.{k}": v for k, v in inc.items()}
    await Route.find_one(Route.id == route_id).update({"$inc": prefixed})


async def _update_user_route_stats(
    user_id: PydanticObjectId,
    route_id: PydanticObjectId,
    inc: dict,
    activity_at: Optional[datetime] = None,
) -> None:
    """Upsert and increment UserRouteStats fields."""
    update_ops: dict = {"$inc": inc}
    if activity_at:
        update_ops["$set"] = {"lastActivityAt": activity_at}

    await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    ).upsert(
        update_ops,
        on_insert=UserRouteStats(
            user_id=user_id,
            route_id=route_id,
        ),
    )


def _activity_to_response(activity: Activity) -> ActivityResponse:
    """Convert Activity document to response model."""
    return ActivityResponse(
        id=activity.id,
        route_id=activity.route_id,
        status=activity.status,
        location_verified=activity.location_verified,
        started_at=activity.started_at,
        ended_at=activity.ended_at,
        duration=activity.duration,
        route_snapshot=activity.route_snapshot,
        created_at=activity.created_at,
        updated_at=activity.updated_at,
    )


async def _build_route_snapshot(route: Route) -> RouteSnapshot:
    """Build RouteSnapshot from Route, Image, and Place."""
    image = await Image.get(route.image_id)

    place_id = None
    place_name = None
    if image and image.place_id:
        place = await Place.get(image.place_id)
        if place:
            place_id = place.id
            place_name = place.name

    return RouteSnapshot(
        title=route.title,
        grade_type=route.grade_type,
        grade=route.grade,
        grade_color=route.grade_color,
        place_id=place_id,
        place_name=place_name,
        image_url=str(route.image_url) if route.image_url else None,
        overlay_image_url=str(route.overlay_image_url) if route.overlay_image_url else None,
    )


async def _verify_location(route: Route, latitude: float, longitude: float) -> bool:
    """Check if user's location is within 300m of the route's place."""
    image = await Image.get(route.image_id)
    if not image or not image.place_id:
        return False

    place = await Place.get(image.place_id)
    if not place or place.latitude is None or place.longitude is None:
        return False

    distance = haversine_distance(latitude, longitude, place.latitude, place.longitude)
    return distance <= LOCATION_VERIFICATION_RADIUS_M


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.post("/{route_id}/activity", status_code=http_status.HTTP_201_CREATED, response_model=ActivityResponse)
async def create_activity(
    route_id: str,
    request: CreateActivityRequest,
    current_user: User = Depends(get_current_user),
):
    # 1. Route 존재 확인
    route = await Route.find_one(
        Route.id == ObjectId(route_id),
        Route.is_deleted != True,
    )
    if not route:
        raise HTTPException(status_code=http_status.HTTP_404_NOT_FOUND, detail="Route not found")

    # 2. 위치 인증
    location_verified = await _verify_location(route, request.latitude, request.longitude)

    # 3. 스냅샷 생성
    snapshot = await _build_route_snapshot(route)

    # 4. duration 계산
    duration = _compute_duration(request.started_at, request.ended_at)

    # 5. Activity 생성
    now = datetime.now(tz=timezone.utc)
    activity = Activity(
        route_id=route.id,
        user_id=current_user.id,
        status=request.status,
        location_verified=location_verified,
        started_at=request.started_at,
        ended_at=request.ended_at,
        duration=duration,
        route_snapshot=snapshot,
        created_at=now,
    )
    await activity.save()

    # 6. Stats 갱신
    inc = _build_stats_inc(request.status, location_verified, duration, sign=1)
    await _update_route_stats(route.id, inc)
    await _update_user_route_stats(current_user.id, route.id, inc, activity_at=now)

    return _activity_to_response(activity)


@router.delete("/{route_id}/activity/{activity_id}", status_code=http_status.HTTP_204_NO_CONTENT)
async def delete_activity(
    route_id: str,
    activity_id: str,
    current_user: User = Depends(get_current_user),
):
    # 1. Activity 존재 + 소유 확인
    activity = await Activity.find_one(
        Activity.id == ObjectId(activity_id),
        Activity.route_id == ObjectId(route_id),
        Activity.user_id == current_user.id,
    )
    if not activity:
        raise HTTPException(status_code=http_status.HTTP_404_NOT_FOUND, detail="Activity not found")

    # 2. Stats 감소
    inc = _build_stats_inc(activity.status, activity.location_verified, activity.duration, sign=-1)
    await _update_route_stats(activity.route_id, inc)
    await _update_user_route_stats(current_user.id, activity.route_id, inc)

    # 3. Hard delete
    await activity.delete()
```

- [ ] **Step 2: Update helper tests — remove STARTED test cases**

Replace `services/api/tests/routers/test_activity_helpers.py` entirely:

```python
from datetime import datetime, timezone
from app.routers.activities import _build_stats_inc, _compute_duration
from app.models.activity import ActivityStatus


# ---------------------------------------------------------------------------
# _compute_duration
# ---------------------------------------------------------------------------


def test_compute_duration_basic():
    start = datetime(2026, 4, 11, 14, 0, 0, tzinfo=timezone.utc)
    end = datetime(2026, 4, 11, 14, 5, 30, tzinfo=timezone.utc)
    assert _compute_duration(start, end) == 330


def test_compute_duration_zero():
    t = datetime(2026, 4, 11, 14, 0, 0, tzinfo=timezone.utc)
    assert _compute_duration(t, t) == 0


# ---------------------------------------------------------------------------
# _build_stats_inc — increment (sign=1)
# ---------------------------------------------------------------------------


def test_stats_inc_completed_unverified():
    inc = _build_stats_inc(ActivityStatus.COMPLETED, False, 300, sign=1)
    assert inc == {
        "totalCount": 1,
        "totalDuration": 300,
        "completedCount": 1,
        "completedDuration": 300,
    }


def test_stats_inc_completed_verified():
    inc = _build_stats_inc(ActivityStatus.COMPLETED, True, 300, sign=1)
    assert inc == {
        "totalCount": 1,
        "totalDuration": 300,
        "completedCount": 1,
        "completedDuration": 300,
        "verifiedCompletedCount": 1,
        "verifiedCompletedDuration": 300,
    }


def test_stats_inc_attempted():
    inc = _build_stats_inc(ActivityStatus.ATTEMPTED, False, 120, sign=1)
    assert inc == {
        "totalCount": 1,
        "totalDuration": 120,
    }


# ---------------------------------------------------------------------------
# _build_stats_inc — decrement (sign=-1)
# ---------------------------------------------------------------------------


def test_stats_dec_completed_verified():
    inc = _build_stats_inc(ActivityStatus.COMPLETED, True, 300, sign=-1)
    assert inc == {
        "totalCount": -1,
        "totalDuration": -300,
        "completedCount": -1,
        "completedDuration": -300,
        "verifiedCompletedCount": -1,
        "verifiedCompletedDuration": -300,
    }


def test_stats_dec_attempted():
    inc = _build_stats_inc(ActivityStatus.ATTEMPTED, True, 120, sign=-1)
    assert inc == {
        "totalCount": -1,
        "totalDuration": -120,
    }
```

- [ ] **Step 3: Run all tests**

Run: `cd /Users/htjo/besetter && .venv/bin/python -m pytest services/api/tests/ -v`
Expected: All tests PASS (model tests + helper tests + geo tests).

- [ ] **Step 4: Commit**

```bash
git add services/api/app/routers/activities.py services/api/tests/routers/test_activity_helpers.py
git commit -m "refactor(api): simplify POST, remove PATCH endpoint and auto-cancel logic"
```

---

### Task 3: Mobile — Add geolocator dependency and platform permissions

**Files:**
- Modify: `apps/mobile/pubspec.yaml`
- Modify: `apps/mobile/android/app/src/main/AndroidManifest.xml`
- Modify: `apps/mobile/ios/Runner/Info.plist`

- [ ] **Step 1: Add geolocator to pubspec.yaml**

In `apps/mobile/pubspec.yaml`, add after the `exif: ^3.3.0` line:

```yaml
  geolocator: ^13.0.2
```

- [ ] **Step 2: Add Android location permission**

In `apps/mobile/android/app/src/main/AndroidManifest.xml`, add after the `<uses-permission android:name="android.permission.CAMERA"/>` line:

```xml
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

- [ ] **Step 3: Add iOS location permission description**

In `apps/mobile/ios/Runner/Info.plist`, add before the `<key>UIApplicationSupportsIndirectInputEvents</key>` line:

```xml
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>등반 시작 시 위치 인증을 위해 위치 접근 권한이 필요합니다.</string>
```

- [ ] **Step 4: Run flutter pub get**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter pub get`
Expected: Dependencies resolved successfully.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/android/app/src/main/AndroidManifest.xml apps/mobile/ios/Runner/Info.plist
git commit -m "feat(mobile): add geolocator dependency and location permissions"
```

---

### Task 4: Mobile — Add localization strings

**Files:**
- Modify: `apps/mobile/lib/l10n/app_en.arb`
- Modify: `apps/mobile/lib/l10n/app_ko.arb`
- Modify: `apps/mobile/lib/l10n/app_ja.arb`
- Modify: `apps/mobile/lib/l10n/app_es.arb`

- [ ] **Step 1: Add English strings**

Add these entries to the end of `apps/mobile/lib/l10n/app_en.arb` (before the closing `}`):

```json
  "slideToStart": "Start climbing!",
  "duration": "DURATION",
  "resetTimer": "Reset",
  "attempted": "Attempted",
  "completed": "Completed",
  "activitySent": "Sent!",
  "activityRecorded": "Recorded",
  "activityCompleted": "Completed",
  "activityAttempted": "Attempted",
  "activityDurationFormat": "{status} · {duration}",
  "@activityDurationFormat": {
    "placeholders": {
      "status": {"type": "String"},
      "duration": {"type": "String"}
    }
  },
  "activitySaveFailed": "Failed to save activity",
  "ok": "OK"
```

- [ ] **Step 2: Add Korean strings**

Add these entries to the end of `apps/mobile/lib/l10n/app_ko.arb` (before the closing `}`):

```json
  "slideToStart": "등반 시작!",
  "duration": "DURATION",
  "resetTimer": "리셋",
  "attempted": "미완등",
  "completed": "완등",
  "activitySent": "Sent!",
  "activityRecorded": "기록되었습니다",
  "activityCompleted": "완등",
  "activityAttempted": "미완등",
  "activityDurationFormat": "{status} · {duration}",
  "@activityDurationFormat": {
    "placeholders": {
      "status": {"type": "String"},
      "duration": {"type": "String"}
    }
  },
  "activitySaveFailed": "활동 저장에 실패했습니다",
  "ok": "확인"
```

- [ ] **Step 3: Add Japanese strings**

Add these entries to the end of `apps/mobile/lib/l10n/app_ja.arb` (before the closing `}`):

```json
  "slideToStart": "クライミング開始！",
  "duration": "DURATION",
  "resetTimer": "リセット",
  "attempted": "未完登",
  "completed": "完登",
  "activitySent": "Sent!",
  "activityRecorded": "記録されました",
  "activityCompleted": "完登",
  "activityAttempted": "未完登",
  "activityDurationFormat": "{status} · {duration}",
  "@activityDurationFormat": {
    "placeholders": {
      "status": {"type": "String"},
      "duration": {"type": "String"}
    }
  },
  "activitySaveFailed": "アクティビティの保存に失敗しました",
  "ok": "OK"
```

- [ ] **Step 4: Add Spanish strings**

Add these entries to the end of `apps/mobile/lib/l10n/app_es.arb` (before the closing `}`):

```json
  "slideToStart": "¡A escalar!",
  "duration": "DURATION",
  "resetTimer": "Reiniciar",
  "attempted": "Intentado",
  "completed": "Completado",
  "activitySent": "Sent!",
  "activityRecorded": "Registrado",
  "activityCompleted": "Completado",
  "activityAttempted": "Intentado",
  "activityDurationFormat": "{status} · {duration}",
  "@activityDurationFormat": {
    "placeholders": {
      "status": {"type": "String"},
      "duration": {"type": "String"}
    }
  },
  "activitySaveFailed": "Error al guardar la actividad",
  "ok": "OK"
```

- [ ] **Step 5: Verify with flutter analyze**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze`
Expected: No errors (warnings OK).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/l10n/
git commit -m "feat(mobile): add activity tracking localization strings"
```

---

### Task 5: Mobile — Create ActivityService

**Files:**
- Create: `apps/mobile/lib/services/activity_service.dart`

- [ ] **Step 1: Create the service file**

Create `apps/mobile/lib/services/activity_service.dart`:

```dart
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
```

- [ ] **Step 2: Verify**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/services/activity_service.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/services/activity_service.dart
git commit -m "feat(mobile): add ActivityService for POST/DELETE API calls"
```

---

### Task 6: Mobile — Create SlideToStart widget

**Files:**
- Create: `apps/mobile/lib/widgets/viewers/slide_to_start.dart`

- [ ] **Step 1: Create the widget**

Create `apps/mobile/lib/widgets/viewers/slide_to_start.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SlideToStart extends StatefulWidget {
  final VoidCallback onSlideComplete;

  const SlideToStart({
    required this.onSlideComplete,
    Key? key,
  }) : super(key: key);

  @override
  State<SlideToStart> createState() => _SlideToStartState();
}

class _SlideToStartState extends State<SlideToStart> {
  double _dragPosition = 0.0;
  bool _isDragging = false;

  static const double _handleSize = 48.0;
  static const double _padding = 4.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxDrag = trackWidth - _handleSize - _padding * 2;

        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF0052D0),
            borderRadius: BorderRadius.circular(9999),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.1),
                blurRadius: 15,
                offset: Offset(0, 10),
                spreadRadius: -3,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Center label
              Center(
                child: Text(
                  AppLocalizations.of(context)!.slideToStart,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              // Draggable handle
              Positioned(
                left: _padding + _dragPosition,
                child: GestureDetector(
                  onHorizontalDragStart: (_) {
                    setState(() => _isDragging = true);
                  },
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragPosition = (_dragPosition + details.delta.dx)
                          .clamp(0.0, maxDrag);
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    if (_dragPosition >= maxDrag * 0.85) {
                      widget.onSlideComplete();
                    }
                    setState(() {
                      _dragPosition = 0.0;
                      _isDragging = false;
                    });
                  },
                  child: Container(
                    width: _handleSize,
                    height: _handleSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        '»',
                        style: TextStyle(
                          color: Color(0xFF0052D0),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Verify**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/widgets/viewers/slide_to_start.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/slide_to_start.dart
git commit -m "feat(mobile): add SlideToStart swipe bar widget"
```

---

### Task 7: Mobile — Create ActivityTimerPanel widget

**Files:**
- Create: `apps/mobile/lib/widgets/viewers/activity_timer_panel.dart`

- [ ] **Step 1: Create the widget**

Create `apps/mobile/lib/widgets/viewers/activity_timer_panel.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ActivityTimerPanel extends StatefulWidget {
  final DateTime startedAt;
  final VoidCallback onReset;
  final VoidCallback onAttempted;
  final VoidCallback onCompleted;

  const ActivityTimerPanel({
    required this.startedAt,
    required this.onReset,
    required this.onAttempted,
    required this.onCompleted,
    Key? key,
  }) : super(key: key);

  @override
  State<ActivityTimerPanel> createState() => _ActivityTimerPanelState();
}

class _ActivityTimerPanelState extends State<ActivityTimerPanel> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _updateElapsed();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateElapsed();
    });
  }

  void _updateElapsed() {
    if (!mounted) return;
    setState(() {
      _elapsed = DateTime.now().difference(widget.startedAt);
    });
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE6E8EA)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.08),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(25, 33, 25, 25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Duration label
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4ADE80).withOpacity(0.75),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                l10n.duration,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF595C5D),
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Timer display
          Text(
            _formatDuration(_elapsed),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2C2F30),
              letterSpacing: -1.8,
            ),
          ),
          const SizedBox(height: 24),
          // Action buttons
          Row(
            children: [
              // Reset button
              Expanded(
                child: _ActionButton(
                  icon: Icons.refresh,
                  color: const Color(0xFF595C5D),
                  backgroundColor: const Color(0xFFE6E8EA),
                  onTap: widget.onReset,
                ),
              ),
              const SizedBox(width: 12),
              // Attempted button
              Expanded(
                child: _ActionButton(
                  icon: Icons.close,
                  color: const Color(0xFF595C5D),
                  backgroundColor: const Color(0xFFE6E8EA),
                  onTap: widget.onAttempted,
                ),
              ),
              const SizedBox(width: 12),
              // Completed button
              Expanded(
                flex: 2,
                child: _ActionButton(
                  icon: Icons.check_circle_outline,
                  label: l10n.completed,
                  color: Colors.white,
                  backgroundColor: const Color(0xFF0066FF),
                  onTap: widget.onCompleted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    this.label,
    required this.color,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: label != null
              ? const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.05),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 17),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(
                label!,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/widgets/viewers/activity_timer_panel.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/activity_timer_panel.dart
git commit -m "feat(mobile): add ActivityTimerPanel widget with live timer and action buttons"
```

---

### Task 8: Mobile — Create ActivityConfirmation widget

**Files:**
- Create: `apps/mobile/lib/widgets/viewers/activity_confirmation.dart`

- [ ] **Step 1: Create the widget**

Create `apps/mobile/lib/widgets/viewers/activity_confirmation.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ActivityConfirmation extends StatelessWidget {
  final bool isCompleted;
  final Duration elapsed;
  final VoidCallback onDismiss;

  const ActivityConfirmation({
    required this.isCompleted,
    required this.elapsed,
    required this.onDismiss,
    Key? key,
  }) : super(key: key);

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}분 ${seconds}초';
    }
    return '${seconds}초';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final statusText = isCompleted ? l10n.activityCompleted : l10n.activityAttempted;
    // TODO: 추후 첫 완등이면 "Flash!" / "Onsight!", 이후 완등이면 "Sent!" / "Crushed it!" / "Allez!" 등 랜덤
    final titleText = isCompleted ? l10n.activitySent : l10n.activityRecorded;

    return Container(
      decoration: BoxDecoration(
        color: isCompleted ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        border: Border.all(
          color: isCompleted ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isCompleted ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCompleted ? Icons.check : Icons.close,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          // Title
          Text(
            titleText,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isCompleted ? const Color(0xFF166534) : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 4),
          // Duration
          Text(
            l10n.activityDurationFormat(statusText, _formatDuration(elapsed)),
            style: TextStyle(
              fontSize: 13,
              color: isCompleted ? const Color(0xFF16A34A) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),
          // OK button
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                backgroundColor: isCompleted
                    ? const Color(0xFF22C55E).withOpacity(0.1)
                    : const Color(0xFFE2E8F0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                l10n.ok,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isCompleted ? const Color(0xFF166534) : const Color(0xFF475569),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/widgets/viewers/activity_confirmation.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/activity_confirmation.dart
git commit -m "feat(mobile): add ActivityConfirmation widget"
```

---

### Task 9: Mobile — Create ActivityPanel orchestrator widget

**Files:**
- Create: `apps/mobile/lib/widgets/viewers/activity_panel.dart`

- [ ] **Step 1: Create the orchestrator widget**

Create `apps/mobile/lib/widgets/viewers/activity_panel.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../services/activity_service.dart';
import 'slide_to_start.dart';
import 'activity_timer_panel.dart';
import 'activity_confirmation.dart';

enum _PanelState { slider, timer, confirmation }

class ActivityPanel extends StatefulWidget {
  final String routeId;

  const ActivityPanel({
    required this.routeId,
    Key? key,
  }) : super(key: key);

  @override
  State<ActivityPanel> createState() => _ActivityPanelState();
}

class _ActivityPanelState extends State<ActivityPanel> {
  _PanelState _state = _PanelState.slider;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  bool _lastWasCompleted = false;
  Timer? _autoDismissTimer;

  late ConfettiController _confettiController;

  // GPS coordinates captured at slide time
  double _latitude = 0.0;
  double _longitude = 0.0;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  Future<void> _captureLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          return; // latitude/longitude stay 0.0
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      _latitude = position.latitude;
      _longitude = position.longitude;
    } catch (_) {
      // GPS failure is not blocking — locationVerified will be false
    }
  }

  void _onSlideComplete() async {
    await _captureLocation();
    if (!mounted) return;
    setState(() {
      _startedAt = DateTime.now();
      _state = _PanelState.timer;
    });
  }

  void _onReset() {
    setState(() {
      _startedAt = DateTime.now();
    });
  }

  Future<void> _onFinish(bool completed) async {
    final endedAt = DateTime.now();
    final elapsed = endedAt.difference(_startedAt!);
    final status = completed ? 'completed' : 'attempted';

    try {
      await ActivityService.createActivity(
        routeId: widget.routeId,
        status: status,
        startedAt: _startedAt!,
        endedAt: endedAt,
        latitude: _latitude,
        longitude: _longitude,
      );

      if (!mounted) return;

      setState(() {
        _elapsed = elapsed;
        _lastWasCompleted = completed;
        _state = _PanelState.confirmation;
      });

      if (completed) {
        _confettiController.play();
      }

      // Auto-dismiss after 2 seconds
      _autoDismissTimer?.cancel();
      _autoDismissTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _state == _PanelState.confirmation) {
          _dismiss();
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.activitySaveFailed),
        ),
      );
    }
  }

  void _dismiss() {
    _autoDismissTimer?.cancel();
    setState(() {
      _startedAt = null;
      _latitude = 0.0;
      _longitude = 0.0;
      _state = _PanelState.slider;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: _buildPanel(),
        ),
        // Confetti overlay
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            numberOfParticles: 20,
            maxBlastForce: 30,
            minBlastForce: 10,
            gravity: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildPanel() {
    switch (_state) {
      case _PanelState.slider:
        return SlideToStart(onSlideComplete: _onSlideComplete);
      case _PanelState.timer:
        return ActivityTimerPanel(
          startedAt: _startedAt!,
          onReset: _onReset,
          onAttempted: () => _onFinish(false),
          onCompleted: () => _onFinish(true),
        );
      case _PanelState.confirmation:
        return ActivityConfirmation(
          isCompleted: _lastWasCompleted,
          elapsed: _elapsed,
          onDismiss: _dismiss,
        );
    }
  }
}
```

- [ ] **Step 2: Verify**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/widgets/viewers/activity_panel.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/activity_panel.dart
git commit -m "feat(mobile): add ActivityPanel state machine with GPS, confetti, and auto-dismiss"
```

---

### Task 10: Mobile — Integrate ActivityPanel into RouteViewer

**Files:**
- Modify: `apps/mobile/lib/pages/viewers/route_viewer.dart`

- [ ] **Step 1: Add import**

At the top of `apps/mobile/lib/pages/viewers/route_viewer.dart`, add after the existing imports:

```dart
import '../../widgets/viewers/activity_panel.dart';
```

- [ ] **Step 2: Insert ActivityPanel between hold list and route info**

In the `build` method, find this section (around line 310-316):

```dart
                    ),
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    height: 1,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  // Route information
```

Replace it with:

```dart
                    ),
                  // Activity panel (slide-to-start / timer / confirmation)
                  ActivityPanel(routeId: widget.routeData.id),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    height: 1,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  // Route information
```

- [ ] **Step 3: Verify**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/pages/viewers/route_viewer.dart
git commit -m "feat(mobile): integrate ActivityPanel into RouteViewer"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] 1.1 ActivityStatus — STARTED removed (Task 1)
- [x] 1.2 POST simplified — startedAt/endedAt required, status required (Task 2)
- [x] 1.3 PATCH removed (Task 2)
- [x] 1.4 DELETE unchanged (Task 2)
- [x] 1.5 Stats matrix updated — `_build_stats_inc` always receives duration (Task 2)
- [x] 1.6 Index simplified (Task 1)
- [x] 2.1 Widget placement between holds and route info (Task 10)
- [x] 2.2 State transitions: slider → timer → confirmation → slider (Task 9)
- [x] 2.3 SlideToStart bar with swipe gesture (Task 6)
- [x] 2.4 Timer panel with ↻/✕/✓ buttons (Task 7)
- [x] 2.5 Confirmation with "Sent!" / "기록되었습니다" + confetti + 2s auto-dismiss + OK button (Task 8, 9)
- [x] 2.6 GPS location capture at slide time (Task 9)
- [x] 2.7 Error handling — snackbar on POST failure, GPS failure graceful (Task 9)
- [x] 3. File structure matches spec (all files listed)
- [x] confetti package already installed, geolocator added (Task 3)
- [x] Localization in 4 languages (Task 4)

**Placeholder scan:** No TBD/TODO except the spec-required TODO comment for future Flash/Onsight messages.

**Type consistency:** `onSlideComplete`, `onReset`, `onAttempted`, `onCompleted` callbacks are `VoidCallback` throughout. `ActivityService.createActivity` parameters match POST body fields. `_formatDuration` exists in both TimerPanel and Confirmation (each formats differently — timer as HH:MM:SS, confirmation as "N분 N초").
