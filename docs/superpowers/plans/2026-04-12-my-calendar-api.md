# MY Page Calendar API Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace mock calendar and recent workout data on the MY page with real API-backed data, using 3 new endpoints and timezone-aware aggregation.

**Architecture:** 3 API endpoints on a new `/my` router (last-activity-date, monthly-summary, daily-routes) using MongoDB aggregation pipelines. Activity model gets a `timezone` field. Flutter MY page calendar becomes dynamic with month navigation, caching, and API integration via `flutter_timezone`.

**Tech Stack:** FastAPI + Beanie + MongoDB Aggregation, Flutter (HookConsumerWidget, flutter_timezone, flutter_hooks)

---

## File Structure

| File | Responsibility |
|------|---------------|
| `services/api/app/models/activity.py` | Add `timezone` field to Activity |
| `services/api/app/routers/activities.py` | Add `timezone` to CreateActivityRequest and create_activity |
| `services/api/app/routers/my.py` | **New** — 3 endpoints: last-activity-date, monthly-summary, daily-routes |
| `services/api/app/main.py` | Register new `my` router |
| `services/api/tests/routers/test_my.py` | **New** — Unit tests for response schemas and timezone helpers |
| `apps/mobile/pubspec.yaml` | Add `flutter_timezone` dependency |
| `apps/mobile/lib/services/activity_service.dart` | Add timezone param to createActivity, add 3 new service methods |
| `apps/mobile/lib/pages/my_page.dart` | Replace mock calendar/workout with API-backed widgets |
| `apps/mobile/lib/l10n/app_ko.arb` | Add new i18n keys |
| `apps/mobile/lib/l10n/app_en.arb` | Add new i18n keys |
| `apps/mobile/lib/l10n/app_ja.arb` | Add new i18n keys |
| `apps/mobile/lib/l10n/app_es.arb` | Add new i18n keys |

---

### Task 1: Add timezone field to Activity model

**Files:**
- Modify: `services/api/app/models/activity.py:42-54`

- [ ] **Step 1: Add timezone field to Activity model**

In `services/api/app/models/activity.py`, add `timezone` to the `Activity` class. Use `Optional[str]` since existing documents lack this field:

```python
class Activity(Document):
    model_config = model_config

    route_id: PydanticObjectId
    user_id: PydanticObjectId
    status: ActivityStatus
    location_verified: bool = False
    started_at: datetime
    ended_at: datetime
    duration: float
    timezone: Optional[str] = None  # IANA timezone, e.g. "Asia/Seoul"
    route_snapshot: RouteSnapshot
    created_at: datetime
    updated_at: Optional[datetime] = None
```

- [ ] **Step 2: Add timezone to CreateActivityRequest and create_activity**

In `services/api/app/routers/activities.py`, add `timezone: str` to `CreateActivityRequest`:

```python
class CreateActivityRequest(BaseModel):
    model_config = model_config

    latitude: float
    longitude: float
    status: ActivityStatus
    started_at: datetime
    ended_at: datetime
    timezone: str
```

In the `create_activity` endpoint function, pass `timezone` when creating the Activity:

```python
    activity = Activity(
        route_id=route.id,
        user_id=current_user.id,
        status=request.status,
        location_verified=location_verified,
        started_at=request.started_at,
        ended_at=request.ended_at,
        duration=duration,
        timezone=request.timezone,
        route_snapshot=snapshot,
        created_at=now,
    )
```

- [ ] **Step 3: Run existing tests**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/ -v`
Expected: All existing tests PASS (new field is Optional with default, so no breakage)

- [ ] **Step 4: Commit**

```bash
git add services/api/app/models/activity.py services/api/app/routers/activities.py
git commit -m "feat(api): add timezone field to Activity model and CreateActivityRequest"
```

---

### Task 2: Create /my router with last-activity-date endpoint

**Files:**
- Create: `services/api/app/routers/my.py`
- Modify: `services/api/app/main.py:5,46-54`
- Create: `services/api/tests/routers/test_my.py`

- [ ] **Step 1: Write the test for LastActivityDateResponse and timezone helper**

Create `services/api/tests/routers/test_my.py`:

```python
from datetime import datetime, timezone as tz, timedelta

from app.routers.my import (
    LastActivityDateResponse,
    _to_local_date_str,
    _month_utc_range,
    _day_utc_range,
)


def test_last_activity_date_response_schema():
    """LastActivityDateResponse should serialize with camelCase alias."""
    resp = LastActivityDateResponse(last_activity_date="2026-04-10")
    dumped = resp.model_dump(by_alias=True)
    assert dumped["lastActivityDate"] == "2026-04-10"


def test_last_activity_date_response_null():
    """LastActivityDateResponse should allow null."""
    resp = LastActivityDateResponse(last_activity_date=None)
    dumped = resp.model_dump(by_alias=True)
    assert dumped["lastActivityDate"] is None


def test_to_local_date_str_kst():
    """UTC datetime should convert to KST date string."""
    # 2026-04-10 15:30 UTC = 2026-04-11 00:30 KST
    utc_dt = datetime(2026, 4, 10, 15, 30, 0, tzinfo=tz.utc)
    result = _to_local_date_str(utc_dt, "Asia/Seoul")
    assert result == "2026-04-11"


def test_to_local_date_str_same_day():
    """UTC datetime in the middle of day should stay same day in KST."""
    # 2026-04-10 05:00 UTC = 2026-04-10 14:00 KST
    utc_dt = datetime(2026, 4, 10, 5, 0, 0, tzinfo=tz.utc)
    result = _to_local_date_str(utc_dt, "Asia/Seoul")
    assert result == "2026-04-10"


def test_month_utc_range_kst():
    """Month range for April 2026 in KST should start at Mar 31 15:00 UTC."""
    start, end = _month_utc_range(2026, 4, "Asia/Seoul")
    # April 1 00:00 KST = March 31 15:00 UTC
    assert start == datetime(2026, 3, 31, 15, 0, 0, tzinfo=tz.utc)
    # May 1 00:00 KST = April 30 15:00 UTC
    assert end == datetime(2026, 4, 30, 15, 0, 0, tzinfo=tz.utc)


def test_day_utc_range_kst():
    """Day range for 2026-04-10 in KST."""
    start, end = _day_utc_range("2026-04-10", "Asia/Seoul")
    # April 10 00:00 KST = April 9 15:00 UTC
    assert start == datetime(2026, 4, 9, 15, 0, 0, tzinfo=tz.utc)
    # April 11 00:00 KST = April 10 15:00 UTC
    assert end == datetime(2026, 4, 10, 15, 0, 0, tzinfo=tz.utc)


def test_day_utc_range_end_of_month():
    """Day range for last day of month should work correctly."""
    start, end = _day_utc_range("2026-04-30", "Asia/Seoul")
    # April 30 00:00 KST = April 29 15:00 UTC
    assert start == datetime(2026, 4, 29, 15, 0, 0, tzinfo=tz.utc)
    # May 1 00:00 KST = April 30 15:00 UTC
    assert end == datetime(2026, 4, 30, 15, 0, 0, tzinfo=tz.utc)


def test_day_utc_range_feb_28():
    """Day range for Feb 28 in non-leap year."""
    start, end = _day_utc_range("2027-02-28", "Asia/Seoul")
    assert start == datetime(2027, 2, 27, 15, 0, 0, tzinfo=tz.utc)
    # March 1 00:00 KST = Feb 28 15:00 UTC
    assert end == datetime(2027, 2, 28, 15, 0, 0, tzinfo=tz.utc)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/routers/test_my.py -v`
Expected: FAIL — `app.routers.my` does not exist

- [ ] **Step 3: Implement the my router with helpers and last-activity-date endpoint**

Create `services/api/app/routers/my.py`:

```python
from datetime import datetime, timezone
from typing import Optional
from zoneinfo import ZoneInfo

from bson import ObjectId
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from app.dependencies import get_current_user
from app.models import model_config
from app.models.activity import Activity
from app.models.user import User

router = APIRouter(prefix="/my", tags=["my"])

DEFAULT_TIMEZONE = "Asia/Seoul"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _to_local_date_str(utc_dt: datetime, tz_name: str) -> str:
    """Convert a UTC datetime to a YYYY-MM-DD string in the given timezone."""
    local_dt = utc_dt.astimezone(ZoneInfo(tz_name))
    return local_dt.strftime("%Y-%m-%d")


def _month_utc_range(year: int, month: int, tz_name: str) -> tuple[datetime, datetime]:
    """Return (start, end) in UTC for a given year/month in the given timezone.

    start = first moment of the month in tz_name, converted to UTC
    end   = first moment of the NEXT month in tz_name, converted to UTC
    """
    tz_info = ZoneInfo(tz_name)
    local_start = datetime(year, month, 1, tzinfo=tz_info)

    if month == 12:
        local_end = datetime(year + 1, 1, 1, tzinfo=tz_info)
    else:
        local_end = datetime(year, month + 1, 1, tzinfo=tz_info)

    return (
        local_start.astimezone(timezone.utc),
        local_end.astimezone(timezone.utc),
    )


def _day_utc_range(date_str: str, tz_name: str) -> tuple[datetime, datetime]:
    """Return (start, end) in UTC for a given date string (YYYY-MM-DD) in the given timezone."""
    from datetime import timedelta

    tz_info = ZoneInfo(tz_name)
    year, month, day = map(int, date_str.split("-"))
    local_start = datetime(year, month, day, tzinfo=tz_info)
    local_end = local_start + timedelta(days=1)

    return (
        local_start.astimezone(timezone.utc),
        local_end.astimezone(timezone.utc),
    )


# ---------------------------------------------------------------------------
# Response schemas
# ---------------------------------------------------------------------------


class LastActivityDateResponse(BaseModel):
    model_config = model_config

    last_activity_date: Optional[str] = None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("/last-activity-date", response_model=LastActivityDateResponse)
async def get_last_activity_date(
    timezone_param: str = Query(alias="timezone", default=DEFAULT_TIMEZONE),
    current_user: User = Depends(get_current_user),
):
    activity = (
        await Activity.find(Activity.user_id == current_user.id)
        .sort([("startedAt", -1)])
        .limit(1)
        .to_list()
    )

    if not activity:
        return LastActivityDateResponse()

    date_str = _to_local_date_str(activity[0].started_at, timezone_param)
    return LastActivityDateResponse(last_activity_date=date_str)
```

- [ ] **Step 4: Register router in main.py**

In `services/api/app/main.py`, add the import and include the router:

Add import at line 5 area:
```python
from app.routers import activities, authentications, hold_polygons, places, share, well_known, my
```

Add router inclusion after existing routers (around line 54):
```python
app.include_router(my.router)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/routers/test_my.py -v`
Expected: All 8 tests PASS

- [ ] **Step 6: Commit**

```bash
git add services/api/app/routers/my.py services/api/app/main.py services/api/tests/routers/test_my.py
git commit -m "feat(api): add /my router with last-activity-date endpoint and timezone helpers"
```

---

### Task 3: Add monthly-summary endpoint

**Files:**
- Modify: `services/api/app/routers/my.py`
- Modify: `services/api/tests/routers/test_my.py`

- [ ] **Step 1: Write the test for MonthlySummaryResponse**

Add to `services/api/tests/routers/test_my.py`:

```python
from app.routers.my import MonthlySummaryResponse


def test_monthly_summary_response_schema():
    """MonthlySummaryResponse should serialize with camelCase alias."""
    resp = MonthlySummaryResponse(active_dates=[1, 5, 9, 12])
    dumped = resp.model_dump(by_alias=True)
    assert dumped["activeDates"] == [1, 5, 9, 12]


def test_monthly_summary_response_empty():
    """MonthlySummaryResponse should handle empty list."""
    resp = MonthlySummaryResponse(active_dates=[])
    dumped = resp.model_dump(by_alias=True)
    assert dumped["activeDates"] == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/routers/test_my.py::test_monthly_summary_response_schema -v`
Expected: FAIL — `MonthlySummaryResponse` not found

- [ ] **Step 3: Implement monthly-summary endpoint**

Add to `services/api/app/routers/my.py`:

Response schema (add after `LastActivityDateResponse`):
```python
class MonthlySummaryResponse(BaseModel):
    model_config = model_config

    active_dates: list[int] = []
```

Endpoint (add after `get_last_activity_date`):
```python
@router.get("/monthly-summary", response_model=MonthlySummaryResponse)
async def get_monthly_summary(
    year: int = Query(ge=2026),
    month: int = Query(ge=1, le=12),
    timezone_param: str = Query(alias="timezone", default=DEFAULT_TIMEZONE),
    current_user: User = Depends(get_current_user),
):
    start_utc, end_utc = _month_utc_range(year, month, timezone_param)

    pipeline = [
        {"$match": {
            "userId": current_user.id,
            "startedAt": {"$gte": start_utc, "$lt": end_utc},
        }},
        {"$group": {
            "_id": {"$dayOfMonth": {"date": "$startedAt", "timezone": timezone_param}},
        }},
        {"$sort": {"_id": 1}},
    ]

    results = await Activity.aggregate(pipeline).to_list()
    active_dates = [doc["_id"] for doc in results]

    return MonthlySummaryResponse(active_dates=active_dates)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/routers/test_my.py -v`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/my.py services/api/tests/routers/test_my.py
git commit -m "feat(api): add monthly-summary endpoint with timezone-aware aggregation"
```

---

### Task 4: Add daily-routes endpoint

**Files:**
- Modify: `services/api/app/routers/my.py`
- Modify: `services/api/tests/routers/test_my.py`

- [ ] **Step 1: Write the test for DailyRoutesResponse schema**

Add to `services/api/tests/routers/test_my.py`:

```python
from app.routers.my import (
    DailyRoutesResponse,
    DailySummary,
    DailyRouteItem,
)
from app.models.activity import RouteSnapshot


def test_daily_routes_response_schema():
    """DailyRoutesResponse should serialize with camelCase aliases."""
    snapshot = RouteSnapshot(
        title="Morning Light",
        grade_type="v_grade",
        grade="V4",
        grade_color="#4CAF50",
        place_name="Urban Apex Gym",
    )
    route_item = DailyRouteItem(
        route_id="507f1f77bcf86cd799439011",
        route_snapshot=snapshot,
        total_count=3,
        completed_count=2,
        attempted_count=1,
        total_duration=845.50,
    )
    summary = DailySummary(
        total_count=3,
        completed_count=2,
        attempted_count=1,
        total_duration=845.50,
        route_count=1,
    )
    resp = DailyRoutesResponse(summary=summary, routes=[route_item])
    dumped = resp.model_dump(by_alias=True)

    assert dumped["summary"]["totalCount"] == 3
    assert dumped["summary"]["routeCount"] == 1
    assert len(dumped["routes"]) == 1
    assert dumped["routes"][0]["routeId"] == "507f1f77bcf86cd799439011"
    assert dumped["routes"][0]["routeSnapshot"]["gradeType"] == "v_grade"
    assert dumped["routes"][0]["completedCount"] == 2
    assert dumped["routes"][0]["totalDuration"] == 845.50


def test_daily_routes_response_empty():
    """DailyRoutesResponse with no data should have zero summary and empty routes."""
    summary = DailySummary()
    resp = DailyRoutesResponse(summary=summary, routes=[])
    dumped = resp.model_dump(by_alias=True)
    assert dumped["summary"]["totalCount"] == 0
    assert dumped["routes"] == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/routers/test_my.py::test_daily_routes_response_schema -v`
Expected: FAIL — `DailyRoutesResponse` not found

- [ ] **Step 3: Implement daily-routes endpoint**

Add response schemas to `services/api/app/routers/my.py` (after `MonthlySummaryResponse`):

```python
class DailySummary(BaseModel):
    model_config = model_config

    total_count: int = 0
    completed_count: int = 0
    attempted_count: int = 0
    total_duration: float = 0
    route_count: int = 0


class DailyRouteItem(BaseModel):
    model_config = model_config

    route_id: str
    route_snapshot: RouteSnapshot
    total_count: int
    completed_count: int
    attempted_count: int
    total_duration: float


class DailyRoutesResponse(BaseModel):
    model_config = model_config

    summary: DailySummary
    routes: list[DailyRouteItem]
```

Add the import for `RouteSnapshot` at the top of the file:
```python
from app.models.activity import Activity, RouteSnapshot
```

Add endpoint:
```python
@router.get("/daily-routes", response_model=DailyRoutesResponse)
async def get_daily_routes(
    date: str = Query(pattern=r"^\d{4}-\d{2}-\d{2}$"),
    timezone_param: str = Query(alias="timezone", default=DEFAULT_TIMEZONE),
    current_user: User = Depends(get_current_user),
):
    start_utc, end_utc = _day_utc_range(date, timezone_param)

    pipeline = [
        {"$match": {
            "userId": current_user.id,
            "startedAt": {"$gte": start_utc, "$lt": end_utc},
        }},
        {"$group": {
            "_id": "$routeId",
            "routeSnapshot": {"$first": "$routeSnapshot"},
            "totalCount": {"$sum": 1},
            "completedCount": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
            "attemptedCount": {"$sum": {"$cond": [{"$eq": ["$status", "attempted"]}, 1, 0]}},
            "totalDuration": {"$sum": "$duration"},
        }},
        {"$group": {
            "_id": None,
            "routes": {"$push": "$$ROOT"},
            "totalCount": {"$sum": "$totalCount"},
            "completedCount": {"$sum": "$completedCount"},
            "attemptedCount": {"$sum": "$attemptedCount"},
            "totalDuration": {"$sum": "$totalDuration"},
            "routeCount": {"$sum": 1},
        }},
    ]

    results = await Activity.aggregate(pipeline).to_list()

    if not results:
        return DailyRoutesResponse(summary=DailySummary(), routes=[])

    doc = results[0]
    summary = DailySummary(
        total_count=doc["totalCount"],
        completed_count=doc["completedCount"],
        attempted_count=doc["attemptedCount"],
        total_duration=doc["totalDuration"],
        route_count=doc["routeCount"],
    )
    routes = [
        DailyRouteItem(
            route_id=str(r["_id"]),
            route_snapshot=RouteSnapshot(**r["routeSnapshot"]),
            total_count=r["totalCount"],
            completed_count=r["completedCount"],
            attempted_count=r["attemptedCount"],
            total_duration=r["totalDuration"],
        )
        for r in doc["routes"]
    ]

    return DailyRoutesResponse(summary=summary, routes=routes)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/routers/test_my.py -v`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/my.py services/api/tests/routers/test_my.py
git commit -m "feat(api): add daily-routes endpoint with 2-stage aggregation"
```

---

### Task 5: Add flutter_timezone dependency and update ActivityService

**Files:**
- Modify: `apps/mobile/pubspec.yaml`
- Modify: `apps/mobile/lib/services/activity_service.dart`

- [ ] **Step 1: Add flutter_timezone to pubspec.yaml**

In `apps/mobile/pubspec.yaml`, add under `dependencies` (after `geolocator`):

```yaml
  flutter_timezone: ^3.0.1
```

- [ ] **Step 2: Run flutter pub get**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter pub get`
Expected: Package resolved successfully

- [ ] **Step 3: Add timezone param to createActivity and add 3 new methods**

In `apps/mobile/lib/services/activity_service.dart`, update `createActivity` to accept and send timezone:

```dart
  static Future<Map<String, dynamic>> createActivity({
    required String routeId,
    required String status,
    required DateTime startedAt,
    required DateTime endedAt,
    required double latitude,
    required double longitude,
    required String timezone,
  }) async {
    final body = {
      'status': status,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'timezone': timezone,
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
```

Add 3 new methods at the end of the class:

```dart
  /// Get the date of the user's most recent activity.
  static Future<String?> getLastActivityDate({
    required String timezone,
  }) async {
    final uri = Uri.parse('/my/last-activity-date')
        .replace(queryParameters: {'timezone': timezone});

    final response = await AuthorizedHttpClient.get(uri.toString());

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['lastActivityDate'] as String?;
    } else {
      throw Exception('Failed to load last activity date. Status: ${response.statusCode}');
    }
  }

  /// Get the active dates (day numbers) for a given month.
  static Future<List<int>> getMonthlySummary({
    required int year,
    required int month,
    required String timezone,
  }) async {
    final uri = Uri.parse('/my/monthly-summary').replace(queryParameters: {
      'year': year.toString(),
      'month': month.toString(),
      'timezone': timezone,
    });

    final response = await AuthorizedHttpClient.get(uri.toString());

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return List<int>.from(data['activeDates']);
    } else {
      throw Exception('Failed to load monthly summary. Status: ${response.statusCode}');
    }
  }

  /// Get route groups for a specific date.
  static Future<Map<String, dynamic>> getDailyRoutes({
    required String date,
    required String timezone,
  }) async {
    final uri = Uri.parse('/my/daily-routes').replace(queryParameters: {
      'date': date,
      'timezone': timezone,
    });

    final response = await AuthorizedHttpClient.get(uri.toString());

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load daily routes. Status: ${response.statusCode}');
    }
  }
```

- [ ] **Step 4: Run flutter analyze**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze`
Expected: No issues found

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock apps/mobile/lib/services/activity_service.dart
git commit -m "feat(mobile): add flutter_timezone dep and calendar service methods"
```

---

### Task 6: Update ActivityPanel to send timezone

**Files:**
- Modify: `apps/mobile/lib/widgets/viewers/activity_panel.dart:1-10,96-111`

- [ ] **Step 1: Import flutter_timezone and pass timezone in createActivity call**

In `apps/mobile/lib/widgets/viewers/activity_panel.dart`:

Add import at the top:
```dart
import 'package:flutter_timezone/flutter_timezone.dart';
```

In the `_onFinish` method, get timezone and pass it to createActivity. Update the method to get timezone before the API call:

```dart
  Future<void> _onFinish(bool completed) async {
    final endedAt = DateTime.now();
    final elapsed = endedAt.difference(_startedAt!);

    final status = completed ? 'completed' : 'attempted';

    try {
      final timezone = await FlutterTimezone.getLocalTimezone();

      await ActivityService.createActivity(
        routeId: widget.routeId,
        status: status,
        startedAt: _startedAt!,
        endedAt: endedAt,
        latitude: _latitude,
        longitude: _longitude,
        timezone: timezone,
      );
```

The rest of `_onFinish` stays the same.

- [ ] **Step 2: Run flutter analyze**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/activity_panel.dart
git commit -m "feat(mobile): send timezone when creating activity"
```

---

### Task 7: Add i18n keys for calendar and daily routes

**Files:**
- Modify: `apps/mobile/lib/l10n/app_ko.arb`
- Modify: `apps/mobile/lib/l10n/app_en.arb`
- Modify: `apps/mobile/lib/l10n/app_ja.arb`
- Modify: `apps/mobile/lib/l10n/app_es.arb`

- [ ] **Step 1: Add i18n keys to all 4 ARB files**

Add before the closing `}` in each file.

**app_ko.arb:**
```json
  "dailyWorkoutSummary": "{count}회 운동 | 완등 {completed} | 미완등 {attempted}",
  "@dailyWorkoutSummary": {
    "placeholders": {
      "count": {"type": "int"},
      "completed": {"type": "int"},
      "attempted": {"type": "int"}
    }
  },
  "routeAttemptsSummary": "완등 {completed} / 미완등 {attempted}",
  "@routeAttemptsSummary": {
    "placeholders": {
      "completed": {"type": "int"},
      "attempted": {"type": "int"}
    }
  },
  "noActivitiesYet": "아직 운동 기록이 없습니다",
  "noActivitiesOnDay": "이 날에는 운동 기록이 없습니다",
  "totalDurationLabel": "총 {duration}",
  "@totalDurationLabel": {
    "placeholders": {
      "duration": {"type": "String"}
    }
  }
```

**app_en.arb:**
```json
  "dailyWorkoutSummary": "{count} sessions | Sent {completed} | Attempted {attempted}",
  "@dailyWorkoutSummary": {
    "placeholders": {
      "count": {"type": "int"},
      "completed": {"type": "int"},
      "attempted": {"type": "int"}
    }
  },
  "routeAttemptsSummary": "Sent {completed} / Attempted {attempted}",
  "@routeAttemptsSummary": {
    "placeholders": {
      "completed": {"type": "int"},
      "attempted": {"type": "int"}
    }
  },
  "noActivitiesYet": "No workout records yet",
  "noActivitiesOnDay": "No workouts on this day",
  "totalDurationLabel": "Total {duration}",
  "@totalDurationLabel": {
    "placeholders": {
      "duration": {"type": "String"}
    }
  }
```

**app_ja.arb:**
```json
  "dailyWorkoutSummary": "{count}回運動 | 完登 {completed} | 未完登 {attempted}",
  "@dailyWorkoutSummary": {
    "placeholders": {
      "count": {"type": "int"},
      "completed": {"type": "int"},
      "attempted": {"type": "int"}
    }
  },
  "routeAttemptsSummary": "完登 {completed} / 未完登 {attempted}",
  "@routeAttemptsSummary": {
    "placeholders": {
      "completed": {"type": "int"},
      "attempted": {"type": "int"}
    }
  },
  "noActivitiesYet": "まだトレーニング記録がありません",
  "noActivitiesOnDay": "この日のトレーニング記録はありません",
  "totalDurationLabel": "合計 {duration}",
  "@totalDurationLabel": {
    "placeholders": {
      "duration": {"type": "String"}
    }
  }
```

**app_es.arb:**
```json
  "dailyWorkoutSummary": "{count} sesiones | Completados {completed} | Intentados {attempted}",
  "@dailyWorkoutSummary": {
    "placeholders": {
      "count": {"type": "int"},
      "completed": {"type": "int"},
      "attempted": {"type": "int"}
    }
  },
  "routeAttemptsSummary": "Completados {completed} / Intentados {attempted}",
  "@routeAttemptsSummary": {
    "placeholders": {
      "completed": {"type": "int"},
      "attempted": {"type": "int"}
    }
  },
  "noActivitiesYet": "Aun no hay registros de entrenamiento",
  "noActivitiesOnDay": "No hay entrenamientos en este dia",
  "totalDurationLabel": "Total {duration}",
  "@totalDurationLabel": {
    "placeholders": {
      "duration": {"type": "String"}
    }
  }
```

- [ ] **Step 2: Run flutter analyze to verify ARB generation**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/l10n/app_ko.arb apps/mobile/lib/l10n/app_en.arb apps/mobile/lib/l10n/app_ja.arb apps/mobile/lib/l10n/app_es.arb
git commit -m "feat(i18n): add calendar and daily routes i18n keys"
```

---

### Task 8: Replace MY page mock calendar with API-backed calendar

**Files:**
- Modify: `apps/mobile/lib/pages/my_page.dart:372-538`

This task replaces the mock data and `_MonthlyCalendar` widget with a real API-backed calendar. The calendar state (year, month, selectedDay, activeDates) is managed in the parent `MyPage` and the calendar widget receives data as props.

- [ ] **Step 1: Remove mock data and update MyPage state**

In `apps/mobile/lib/pages/my_page.dart`:

Remove the mock data section (lines 372-386):
```dart
// DELETE: _mockWorkoutDays and _mockWorkouts
```

Add imports at the top of the file:
```dart
import 'package:flutter_timezone/flutter_timezone.dart';
import '../services/activity_service.dart';
```

Update the `MyPage` build method to manage calendar state. Replace the `selectedDay` useState and add new state variables. Update the body from the `data:` callback:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider);
    final isEditing = useState(false);
    final croppedImage = useState<File?>(null);
    final nameController = useTextEditingController();
    final bioController = useTextEditingController();
    final isSaving = useState(false);
    final l10n = AppLocalizations.of(context)!;

    // Calendar state
    final now = DateTime.now();
    final calendarYear = useState(now.year);
    final calendarMonth = useState(now.month);
    final selectedDay = useState<int?>(null);
    final activeDates = useState<List<int>>([]);
    final dailyRoutesData = useState<Map<String, dynamic>?>(null);
    final calendarLoading = useState(true);
    final dailyRoutesLoading = useState(false);
    final timezone = useState<String>('Asia/Seoul');

    // Caches (persist across rebuilds)
    final monthlySummaryCache = useRef(<String, List<int>>{});
    final dailyRoutesCache = useRef(<String, Map<String, dynamic>>{});

    // Helper: is current month
    bool isCurrentMonth(int y, int m) => y == now.year && m == now.month;

    // Helper: is today
    bool isToday(int y, int m, int d) => y == now.year && m == now.month && d == now.day;

    // Load monthly summary
    Future<void> loadMonthlySummary(int year, int month, String tz) async {
      final cacheKey = '$year-${month.toString().padLeft(2, '0')}';

      // Use cache for past months
      if (!isCurrentMonth(year, month) && monthlySummaryCache.value.containsKey(cacheKey)) {
        activeDates.value = monthlySummaryCache.value[cacheKey]!;
        return;
      }

      try {
        final dates = await ActivityService.getMonthlySummary(
          year: year,
          month: month,
          timezone: tz,
        );
        activeDates.value = dates;
        if (!isCurrentMonth(year, month)) {
          monthlySummaryCache.value[cacheKey] = dates;
        }
      } catch (_) {
        activeDates.value = [];
      }
    }

    // Load daily routes
    Future<void> loadDailyRoutes(int year, int month, int day, String tz) async {
      final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

      // Use cache for past dates (not today)
      if (!isToday(year, month, day) && dailyRoutesCache.value.containsKey(dateStr)) {
        dailyRoutesData.value = dailyRoutesCache.value[dateStr];
        return;
      }

      dailyRoutesLoading.value = true;
      try {
        final data = await ActivityService.getDailyRoutes(
          date: dateStr,
          timezone: tz,
        );
        dailyRoutesData.value = data;
        if (!isToday(year, month, day)) {
          dailyRoutesCache.value[dateStr] = data;
        }
      } catch (_) {
        dailyRoutesData.value = null;
      } finally {
        dailyRoutesLoading.value = false;
      }
    }

    // Initial load
    useEffect(() {
      () async {
        final tz = await FlutterTimezone.getLocalTimezone();
        timezone.value = tz;

        final lastDate = await ActivityService.getLastActivityDate(timezone: tz);

        if (lastDate != null) {
          final parts = lastDate.split('-').map(int.parse).toList();
          calendarYear.value = parts[0];
          calendarMonth.value = parts[1];
          selectedDay.value = parts[2];

          await Future.wait([
            loadMonthlySummary(parts[0], parts[1], tz),
            loadDailyRoutes(parts[0], parts[1], parts[2], tz),
          ]);
        } else {
          await loadMonthlySummary(now.year, now.month, tz);
        }

        calendarLoading.value = false;
      }();
      return null;
    }, []);

    // Month navigation handlers
    void goToPrevMonth() {
      int newYear = calendarYear.value;
      int newMonth = calendarMonth.value - 1;
      if (newMonth < 1) {
        newMonth = 12;
        newYear--;
      }
      // Min: April 2026
      if (newYear < 2026 || (newYear == 2026 && newMonth < 4)) return;

      calendarYear.value = newYear;
      calendarMonth.value = newMonth;
      selectedDay.value = null;
      dailyRoutesData.value = null;
      loadMonthlySummary(newYear, newMonth, timezone.value);
    }

    void goToNextMonth() {
      int newYear = calendarYear.value;
      int newMonth = calendarMonth.value + 1;
      if (newMonth > 12) {
        newMonth = 1;
        newYear++;
      }
      // Max: current month
      if (newYear > now.year || (newYear == now.year && newMonth > now.month)) return;

      calendarYear.value = newYear;
      calendarMonth.value = newMonth;
      selectedDay.value = null;
      dailyRoutesData.value = null;
      loadMonthlySummary(newYear, newMonth, timezone.value);
    }

    void onDaySelected(int day) {
      selectedDay.value = day;
      loadDailyRoutes(calendarYear.value, calendarMonth.value, day, timezone.value);
    }

    // ... rest of build method stays the same until the body content ...
```

Then update the `data:` body to pass the new state to widgets:

```dart
        data: (user) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _ProfileHeader(
                user: user,
                isEditing: isEditing.value,
                croppedImage: croppedImage,
                nameController: nameController,
                bioController: bioController,
              ),
              const SizedBox(height: 32),
              if (calendarLoading.value)
                const Center(child: CircularProgressIndicator(strokeWidth: 2))
              else ...[
                _MonthlyCalendar(
                  year: calendarYear.value,
                  month: calendarMonth.value,
                  activeDates: activeDates.value,
                  selectedDay: selectedDay.value,
                  onDaySelected: onDaySelected,
                  onPrevMonth: goToPrevMonth,
                  onNextMonth: goToNextMonth,
                  canGoPrev: !(calendarYear.value == 2026 && calendarMonth.value == 4),
                  canGoNext: isCurrentMonth(calendarYear.value, calendarMonth.value) ? false : true,
                ),
                const SizedBox(height: 32),
                _DailyRoutes(
                  data: dailyRoutesData.value,
                  loading: dailyRoutesLoading.value,
                  selectedDay: selectedDay.value,
                ),
              ],
            ],
          ),
        ),
```

- [ ] **Step 2: Rewrite _MonthlyCalendar to accept props instead of mock data**

Replace the entire `_MonthlyCalendar` class (lines 390-538):

```dart
class _MonthlyCalendar extends StatelessWidget {
  final int year;
  final int month;
  final List<int> activeDates;
  final int? selectedDay;
  final ValueChanged<int> onDaySelected;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final bool canGoPrev;
  final bool canGoNext;

  const _MonthlyCalendar({
    required this.year,
    required this.month,
    required this.activeDates,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.canGoPrev,
    required this.canGoNext,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = l10n.localeName;

    // Calculate calendar grid
    final firstDayOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = firstDayOfMonth.weekday % 7; // Sunday = 0
    final totalCells = firstWeekday + daysInMonth;
    final weeks = (totalCells / 7).ceil();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Month name
    final monthDate = DateTime(year, month);
    final monthLabel = '${_monthName(month, locale)} $year';

    const dayHeaders = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A2C2F30),
            blurRadius: 24,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with month navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.monthlyProgress,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Color(0xFF2C2F30),
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: canGoPrev ? onPrevMonth : null,
                    child: Icon(
                      Icons.chevron_left,
                      size: 20,
                      color: canGoPrev ? const Color(0xFF0066FF) : const Color(0xFFDADDDF),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    monthLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF0066FF),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: canGoNext ? onNextMonth : null,
                    child: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: canGoNext ? const Color(0xFF0066FF) : const Color(0xFFDADDDF),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Day headers
          Row(
            children: dayHeaders
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            color: Color(0x99595C5D),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          // Calendar grid
          ...List.generate(weeks, (weekIndex) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: List.generate(7, (dayIndex) {
                  final dayNumber = weekIndex * 7 + dayIndex - firstWeekday + 1;
                  if (dayNumber < 1 || dayNumber > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 42));
                  }

                  final cellDate = DateTime(year, month, dayNumber);
                  final isFuture = cellDate.isAfter(today);
                  final hasWorkout = activeDates.contains(dayNumber);
                  final isSelected = selectedDay == dayNumber;
                  final canTap = hasWorkout && !isFuture;

                  return Expanded(
                    child: GestureDetector(
                      onTap: canTap ? () => onDaySelected(dayNumber) : null,
                      child: Container(
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: hasWorkout && !isFuture ? const Color(0x1A0066FF) : null,
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(color: const Color(0xFF0066FF), width: 2)
                              : null,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontWeight: hasWorkout ? FontWeight.w600 : FontWeight.w500,
                                fontSize: 14,
                                color: isFuture
                                    ? const Color(0x40595C5D)
                                    : isSelected
                                        ? const Color(0xFF0066FF)
                                        : hasWorkout
                                            ? const Color(0xFF2C2F30)
                                            : const Color(0x80595C5D),
                              ),
                            ),
                            if (hasWorkout && !isFuture)
                              Positioned(
                                bottom: 4,
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF0066FF),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
  }

  static String _monthName(int month, String locale) {
    const en = ['', 'January', 'February', 'March', 'April', 'May', 'June',
                'July', 'August', 'September', 'October', 'November', 'December'];
    const ko = ['', '1월', '2월', '3월', '4월', '5월', '6월',
                '7월', '8월', '9월', '10월', '11월', '12월'];
    const ja = ['', '1月', '2月', '3月', '4月', '5月', '6月',
                '7月', '8月', '9月', '10月', '11月', '12月'];
    const es = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

    if (locale.startsWith('ko')) return ko[month];
    if (locale.startsWith('ja')) return ja[month];
    if (locale.startsWith('es')) return es[month];
    return en[month];
  }
}
```

- [ ] **Step 3: Run flutter analyze**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze`
Expected: No issues found

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/pages/my_page.dart
git commit -m "feat(mobile): replace mock calendar with API-backed calendar"
```

---

### Task 9: Replace _RecentWorkout with _DailyRoutes widget

**Files:**
- Modify: `apps/mobile/lib/pages/my_page.dart:540-684`

This task replaces the `_RecentWorkout` and `_WorkoutCard` widgets with a `_DailyRoutes` widget that displays the API response.

- [ ] **Step 1: Remove _RecentWorkout and _WorkoutCard, add _DailyRoutes**

Remove the `_RecentWorkout` class and `_WorkoutCard` class entirely.

Add the new `_DailyRoutes` widget:

```dart
class _DailyRoutes extends StatelessWidget {
  final Map<String, dynamic>? data;
  final bool loading;
  final int? selectedDay;

  const _DailyRoutes({
    required this.data,
    required this.loading,
    required this.selectedDay,
  });

  String _formatDuration(double totalSeconds) {
    final minutes = (totalSeconds / 60).floor().toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).floor().toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (selectedDay == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.noActivitiesYet,
            style: const TextStyle(fontSize: 14, color: Color(0xFF595C5D)),
          ),
        ),
      );
    }

    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (data == null) {
      return const SizedBox.shrink();
    }

    final summary = data!['summary'] as Map<String, dynamic>;
    final routes = List<Map<String, dynamic>>.from(data!['routes'] ?? []);

    if (routes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            l10n.noActivitiesOnDay,
            style: const TextStyle(fontSize: 14, color: Color(0xFF595C5D)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Daily summary header
        Text(
          l10n.dailyWorkoutSummary(
            summary['totalCount'] as int,
            summary['completedCount'] as int,
            summary['attemptedCount'] as int,
          ),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Color(0xFF595C5D),
          ),
        ),
        const SizedBox(height: 16),
        // Route cards
        ...routes.map((route) => _DailyRouteCard(
          route: route,
          formatDuration: _formatDuration,
        )),
      ],
    );
  }
}

class _DailyRouteCard extends StatelessWidget {
  final Map<String, dynamic> route;
  final String Function(double) formatDuration;

  const _DailyRouteCard({
    required this.route,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final snapshot = route['routeSnapshot'] as Map<String, dynamic>;
    final title = snapshot['title'] as String? ?? '';
    final grade = snapshot['grade'] as String? ?? '';
    final gradeColorHex = snapshot['gradeColor'] as String?;
    final placeName = snapshot['placeName'] as String? ?? '';
    final imageUrl = snapshot['overlayImageUrl'] as String? ?? snapshot['imageUrl'] as String?;

    final completedCount = route['completedCount'] as int;
    final attemptedCount = route['attemptedCount'] as int;
    final totalDuration = (route['totalDuration'] as num).toDouble();

    final gradeColor = gradeColorHex != null
        ? Color(int.parse(gradeColorHex.replaceFirst('#', ''), radix: 16) | 0xFF000000)
        : const Color(0xFF0066FF);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A2C2F30),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Route image thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: Container(
                width: 80,
                height: 80,
                color: const Color(0xFFF0F0F0),
                child: imageUrl != null
                    ? Image.network(imageUrl, fit: BoxFit.cover)
                    : const Icon(Icons.terrain, color: Color(0xFFDADDDF)),
              ),
            ),
            // Route info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: gradeColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            grade,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2C2F30),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      placeName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF595C5D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          l10n.routeAttemptsSummary(completedCount, attemptedCount),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF595C5D),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          l10n.totalDurationLabel(formatDuration(totalDuration)),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF595C5D),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/pages/my_page.dart
git commit -m "feat(mobile): replace RecentWorkout with DailyRoutes widget"
```

