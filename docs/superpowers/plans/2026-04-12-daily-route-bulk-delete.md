# Daily Route Bulk Delete + Activity-Timezone Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 일일 운동 기록 카드에서 루트 단위 일괄 삭제를 추가하고, `my/*` 집계 엔드포인트가 각 활동의 저장된 `timezone` 필드를 기준으로 그룹핑하도록 리팩터링한다.

**Architecture:** 세 GET 엔드포인트의 aggregation pipeline을 "쿼리 timezone으로 UTC 범위 계산" 방식에서 "`(userId, startedAt)` 인덱스를 타는 ±14h UTC superset pre-filter → `$addFields localDate/localYearMonth` (활동 자신의 `$timezone` 참조) → `$match` 재확인" 방식으로 바꾼다. 신규 `DELETE /my/daily-routes/{routeId}?date=...` 엔드포인트가 같은 필터 원리로 매칭 활동을 찾아 hard delete + stats 감산한다. 모바일은 카드 우상단 ⋮ 메뉴로 트리거하고 로컬 state만 갱신한다.

**Tech Stack:** FastAPI + Beanie ODM (MongoDB) + Pytest (backend), Flutter + hooks_riverpod + Dart (mobile), 기존 `AuthorizedHttpClient` HTTP 헬퍼.

---

## File Structure

**Backend (`services/api`)**

| 파일 | 변경 |
|---|---|
| `app/routers/my.py` | UTC superset 헬퍼 추가 (`_day_utc_superset`, `_month_utc_superset`), `_merge_incs` 추가, `get_daily_routes`/`get_monthly_summary`/`get_last_activity_date` 리팩터, 신규 `DELETE /my/daily-routes/{route_id}` 엔드포인트 |
| `tests/routers/test_my.py` | superset 헬퍼 유닛 테스트, `_merge_incs` 유닛 테스트 |

**Mobile (`apps/mobile`)**

| 파일 | 변경 |
|---|---|
| `lib/services/activity_service.dart` | `getDailyRoutes`/`getMonthlySummary`/`getLastActivityDate`에서 `timezone` 파라미터 제거. `deleteDailyRouteGroup` 신규 |
| `lib/pages/my_page.dart` | `timezone` hook state 및 `FlutterTimezone` 호출 제거, `loadDailyRoutes`/`loadMonthlySummary` 시그니처 정리, `_DailyRouteCard`에 ⋮ `PopupMenuButton` + `onDeleteConfirmed` 콜백 prop 추가, `MyPage`에 `handleRouteGroupDelete` 추가 |

---

## Task 1: Backend — UTC superset 헬퍼

**Files:**
- Modify: `services/api/app/routers/my.py` (추가)
- Modify: `services/api/tests/routers/test_my.py` (추가)

- [ ] **Step 1: Write failing tests**

Append to `services/api/tests/routers/test_my.py`:

```python
from datetime import datetime, timezone as tz

from app.routers.my import _day_utc_superset, _month_utc_superset


def test_day_utc_superset_basic():
    """±14h padded window around a calendar day in UTC."""
    start, end = _day_utc_superset("2026-04-12")
    assert start == datetime(2026, 4, 11, 10, 0, 0, tzinfo=tz.utc)
    assert end == datetime(2026, 4, 13, 14, 0, 0, tzinfo=tz.utc)


def test_day_utc_superset_year_boundary():
    """Year rollover should not break the window."""
    start, end = _day_utc_superset("2026-01-01")
    assert start == datetime(2025, 12, 31, 10, 0, 0, tzinfo=tz.utc)
    assert end == datetime(2026, 1, 2, 14, 0, 0, tzinfo=tz.utc)


def test_month_utc_superset_basic():
    """±14h padded window around a calendar month in UTC."""
    start, end = _month_utc_superset(2026, 4)
    assert start == datetime(2026, 3, 31, 10, 0, 0, tzinfo=tz.utc)
    assert end == datetime(2026, 5, 1, 14, 0, 0, tzinfo=tz.utc)


def test_month_utc_superset_year_boundary():
    """December should roll over to next January correctly."""
    start, end = _month_utc_superset(2026, 12)
    assert start == datetime(2026, 11, 30, 10, 0, 0, tzinfo=tz.utc)
    assert end == datetime(2027, 1, 1, 14, 0, 0, tzinfo=tz.utc)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/htjo/besetter/services/api && pytest tests/routers/test_my.py::test_day_utc_superset_basic tests/routers/test_my.py::test_month_utc_superset_basic -v`

Expected: ImportError or AttributeError — helpers not yet defined.

- [ ] **Step 3: Implement the helpers**

In `services/api/app/routers/my.py`, add the following two functions right after the existing `_day_utc_range` function (around line 60). Use the existing `timedelta` import pattern:

```python
def _day_utc_superset(date_str: str) -> tuple[datetime, datetime]:
    """UTC window guaranteed to contain every activity whose local date
    (in its own stored timezone) equals date_str. Padded ±14h to cover
    every possible IANA offset."""
    from datetime import timedelta

    year, month, day = map(int, date_str.split("-"))
    naive_day_start = datetime(year, month, day, tzinfo=timezone.utc)
    naive_day_end = naive_day_start + timedelta(days=1)
    return (
        naive_day_start - timedelta(hours=14),
        naive_day_end + timedelta(hours=14),
    )


def _month_utc_superset(year: int, month: int) -> tuple[datetime, datetime]:
    """UTC window guaranteed to contain every activity whose local year/month
    (in its own stored timezone) equals year/month. Padded ±14h."""
    from datetime import timedelta

    naive_month_start = datetime(year, month, 1, tzinfo=timezone.utc)
    if month == 12:
        naive_month_end = datetime(year + 1, 1, 1, tzinfo=timezone.utc)
    else:
        naive_month_end = datetime(year, month + 1, 1, tzinfo=timezone.utc)
    return (
        naive_month_start - timedelta(hours=14),
        naive_month_end + timedelta(hours=14),
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/htjo/besetter/services/api && pytest tests/routers/test_my.py -v`

Expected: all tests pass (existing + 4 new).

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/my.py services/api/tests/routers/test_my.py
git commit -m "feat(api): add UTC superset helpers for activity-tz aggregation"
```

---

## Task 2: Backend — `_merge_incs` 헬퍼

**Files:**
- Modify: `services/api/app/routers/my.py` (추가)
- Modify: `services/api/tests/routers/test_my.py` (추가)

- [ ] **Step 1: Write failing tests**

Append to `services/api/tests/routers/test_my.py`:

```python
from app.routers.my import _merge_incs


def test_merge_incs_empty_list():
    assert _merge_incs([]) == {}


def test_merge_incs_single_dict():
    assert _merge_incs([{"totalCount": 1, "totalDuration": 30.5}]) == {
        "totalCount": 1,
        "totalDuration": 30.5,
    }


def test_merge_incs_overlapping_keys():
    merged = _merge_incs([
        {"totalCount": 1, "totalDuration": 10.0, "completedCount": 1},
        {"totalCount": 1, "totalDuration": 20.0},
        {"totalCount": 1, "totalDuration": 5.5, "completedCount": 1, "completedDuration": 5.5},
    ])
    assert merged == {
        "totalCount": 3,
        "totalDuration": 35.5,
        "completedCount": 2,
        "completedDuration": 5.5,
    }


def test_merge_incs_negative_signs():
    """Decrement dicts sum correctly."""
    assert _merge_incs([
        {"totalCount": -1, "totalDuration": -10.0},
        {"totalCount": -1, "totalDuration": -20.0},
    ]) == {"totalCount": -2, "totalDuration": -30.0}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/htjo/besetter/services/api && pytest tests/routers/test_my.py::test_merge_incs_empty_list -v`

Expected: ImportError — `_merge_incs` not yet defined.

- [ ] **Step 3: Implement the helper**

In `services/api/app/routers/my.py`, add after `_month_utc_superset`:

```python
def _merge_incs(incs: list[dict]) -> dict:
    """Merge multiple $inc dicts by summing values of common keys."""
    merged: dict = {}
    for inc in incs:
        for key, value in inc.items():
            merged[key] = merged.get(key, 0) + value
    return merged
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/htjo/besetter/services/api && pytest tests/routers/test_my.py -v`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/my.py services/api/tests/routers/test_my.py
git commit -m "feat(api): add _merge_incs helper for bulk stats updates"
```

---

## Task 3: Backend — `get_daily_routes` refactor

**Files:**
- Modify: `services/api/app/routers/my.py` (around lines 161-217)

No new unit tests — the existing `test_daily_routes_response_schema` and `test_daily_route_item_private_and_deleted_flags` tests must continue to pass unchanged (the schema isn't changing, only the pipeline).

- [ ] **Step 1: Replace the `get_daily_routes` handler**

In `services/api/app/routers/my.py`, replace the entire `get_daily_routes` function (around lines 161-217) with:

```python
@router.get("/daily-routes", response_model=DailyRoutesResponse)
async def get_daily_routes(
    date: str = Query(pattern=r"^\d{4}-\d{2}-\d{2}$"),
    current_user: User = Depends(get_current_user),
):
    utc_lo, utc_hi = _day_utc_superset(date)

    pipeline = [
        {"$match": {
            "userId": current_user.id,
            "startedAt": {"$gte": utc_lo, "$lt": utc_hi},
        }},
        {"$addFields": {
            "localDate": {
                "$dateToString": {
                    "format": "%Y-%m-%d",
                    "date": "$startedAt",
                    "timezone": {"$ifNull": ["$timezone", "UTC"]},
                }
            }
        }},
        {"$match": {"localDate": date}},
        {"$group": {
            "_id": "$routeId",
            "routeSnapshot": {"$first": "$routeSnapshot"},
            "totalCount": {"$sum": 1},
            "completedCount": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
            "attemptedCount": {"$sum": {"$cond": [{"$eq": ["$status", "attempted"]}, 1, 0]}},
            "totalDuration": {"$sum": "$duration"},
        }},
        {"$lookup": {
            "from": "routes",
            "localField": "_id",
            "foreignField": "_id",
            "as": "route",
            "pipeline": [
                {"$project": {"visibility": 1, "isDeleted": 1}},
            ],
        }},
        {"$set": {
            "routeVisibility": {
                "$ifNull": [{"$first": "$route.visibility"}, "public"],
            },
            "isDeleted": {
                "$ifNull": [{"$first": "$route.isDeleted"}, False],
            },
        }},
        {"$unset": "route"},
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

    collection = Activity.get_pymongo_collection()
    cursor = collection.aggregate(pipeline)
    results = await cursor.to_list(length=None)

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
            route_visibility=r.get("routeVisibility", "public"),
            is_deleted=r.get("isDeleted", False),
            total_count=r["totalCount"],
            completed_count=r["completedCount"],
            attempted_count=r["attemptedCount"],
            total_duration=r["totalDuration"],
        )
        for r in doc["routes"]
    ]

    return DailyRoutesResponse(summary=summary, routes=routes)
```

Key changes from the previous version:
1. `timezone_param` query parameter removed from signature
2. `_day_utc_superset(date)` instead of `_day_utc_range(date, timezone_param)`
3. Added `$addFields localDate` + second `$match` on `localDate == date`
4. `$addFields` uses `$ifNull: ["$timezone", "UTC"]` so rows with null `timezone` don't break the pipeline

- [ ] **Step 2: Run tests to confirm schema tests still pass**

Run: `cd /Users/htjo/besetter/services/api && pytest tests/routers/test_my.py -v`

Expected: all tests pass (including the existing `test_daily_routes_response_schema`).

- [ ] **Step 3: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/my.py
git commit -m "refactor(api): group daily-routes by each activity's own timezone"
```

---

## Task 4: Backend — `get_monthly_summary` refactor

**Files:**
- Modify: `services/api/app/routers/my.py` (around lines 133-158)

- [ ] **Step 1: Replace the `get_monthly_summary` handler**

In `services/api/app/routers/my.py`, replace the entire `get_monthly_summary` function with:

```python
@router.get("/monthly-summary", response_model=MonthlySummaryResponse)
async def get_monthly_summary(
    year: int = Query(ge=2026),
    month: int = Query(ge=1, le=12),
    current_user: User = Depends(get_current_user),
):
    utc_lo, utc_hi = _month_utc_superset(year, month)
    year_month = f"{year:04d}-{month:02d}"

    pipeline = [
        {"$match": {
            "userId": current_user.id,
            "startedAt": {"$gte": utc_lo, "$lt": utc_hi},
        }},
        {"$addFields": {
            "localYearMonth": {
                "$dateToString": {
                    "format": "%Y-%m",
                    "date": "$startedAt",
                    "timezone": {"$ifNull": ["$timezone", "UTC"]},
                }
            },
            "localDay": {
                "$dayOfMonth": {
                    "date": "$startedAt",
                    "timezone": {"$ifNull": ["$timezone", "UTC"]},
                }
            },
        }},
        {"$match": {"localYearMonth": year_month}},
        {"$group": {"_id": "$localDay"}},
        {"$sort": {"_id": 1}},
    ]

    collection = Activity.get_pymongo_collection()
    cursor = collection.aggregate(pipeline)
    results = await cursor.to_list(length=None)
    active_dates = [doc["_id"] for doc in results]

    return MonthlySummaryResponse(active_dates=active_dates)
```

Key changes:
1. `timezone_param` query parameter removed
2. `_month_utc_superset(year, month)` pre-filter
3. `$addFields` computes `localYearMonth` + `localDay` using each activity's own `$timezone`
4. `$match localYearMonth == year_month` to confirm the row really belongs to this month
5. Group by `localDay`

- [ ] **Step 2: Run tests**

Run: `cd /Users/htjo/besetter/services/api && pytest tests/routers/test_my.py -v`

Expected: all tests pass. Schema tests (`test_monthly_summary_response_schema`, `test_monthly_summary_response_empty`) stay unchanged.

- [ ] **Step 3: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/my.py
git commit -m "refactor(api): group monthly-summary by each activity's own timezone"
```

---

## Task 5: Backend — `get_last_activity_date` refactor

**Files:**
- Modify: `services/api/app/routers/my.py` (around lines 114-130)

- [ ] **Step 1: Replace the `get_last_activity_date` handler**

In `services/api/app/routers/my.py`, replace the entire `get_last_activity_date` function with:

```python
@router.get("/last-activity-date", response_model=LastActivityDateResponse)
async def get_last_activity_date(
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

    a = activity[0]
    tz_name = a.timezone or "UTC"
    date_str = _to_local_date_str(a.started_at, tz_name)
    return LastActivityDateResponse(last_activity_date=date_str)
```

Key changes:
1. `timezone_param` query parameter removed
2. Uses each activity's own stored `a.timezone` (with `"UTC"` fallback)
3. Re-uses the existing `_to_local_date_str` helper

- [ ] **Step 2: Run tests**

Run: `cd /Users/htjo/besetter/services/api && pytest tests/routers/test_my.py -v`

Expected: all tests pass. The existing `test_last_activity_date_response_schema` / `test_last_activity_date_response_null` schema tests are unaffected.

- [ ] **Step 3: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/my.py
git commit -m "refactor(api): use activity.timezone for last-activity-date"
```

---

## Task 6: Backend — `DELETE /my/daily-routes/{route_id}` endpoint

**Files:**
- Modify: `services/api/app/routers/my.py` (add imports + new endpoint)

No unit test — handler requires DB. Policy logic is in `_merge_incs` (already tested) and the pipeline uses the same pattern as `get_daily_routes`.

- [ ] **Step 1: Add imports**

In `services/api/app/routers/my.py`, at the top of the file, ensure these imports exist. The existing imports already include `from fastapi import APIRouter, Depends, Query` — update to add `HTTPException` and `status` and `Path`:

```python
from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
```

Add the activity model and router helpers (these should live next to `from app.models.activity import Activity, RouteSnapshot`):

```python
from app.models.activity import Activity, ActivityStatus, RouteSnapshot
from app.models.user_route_stats import UserRouteStats
from app.routers.activities import (
    _build_stats_inc,
    _update_route_stats,
    _update_user_route_stats,
)
```

Note: Check whether `UserRouteStats` is at `app.models.user_route_stats` — if it lives elsewhere (e.g., `app.models.__init__`), adjust the import path. You can grep for the existing import in `activities.py`:
```bash
grep -n "UserRouteStats" /Users/htjo/besetter/services/api/app/routers/activities.py | head -3
```
and mirror that path.

- [ ] **Step 2: Add the DELETE endpoint**

At the bottom of `services/api/app/routers/my.py`, add:

```python
@router.delete("/daily-routes/{route_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_daily_route_group(
    route_id: str = Path(...),
    date: str = Query(pattern=r"^\d{4}-\d{2}-\d{2}$"),
    current_user: User = Depends(get_current_user),
):
    try:
        route_object_id = ObjectId(route_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid route_id format",
        )

    utc_lo, utc_hi = _day_utc_superset(date)

    pipeline = [
        {"$match": {
            "userId": current_user.id,
            "routeId": route_object_id,
            "startedAt": {"$gte": utc_lo, "$lt": utc_hi},
        }},
        {"$addFields": {
            "localDate": {
                "$dateToString": {
                    "format": "%Y-%m-%d",
                    "date": "$startedAt",
                    "timezone": {"$ifNull": ["$timezone", "UTC"]},
                }
            }
        }},
        {"$match": {"localDate": date}},
        {"$project": {
            "_id": 1,
            "status": 1,
            "locationVerified": 1,
            "duration": 1,
        }},
    ]

    collection = Activity.get_pymongo_collection()
    cursor = collection.aggregate(pipeline)
    matched = await cursor.to_list(length=None)

    if not matched:
        return

    activity_ids = [m["_id"] for m in matched]
    incs = [
        _build_stats_inc(
            ActivityStatus(m["status"]),
            m.get("locationVerified", False),
            m.get("duration", 0.0),
            sign=-1,
        )
        for m in matched
    ]
    merged_inc = _merge_incs(incs)

    # 1. Hard delete activities first (conservative drift direction).
    await collection.delete_many({"_id": {"$in": activity_ids}})

    # 2. Then apply the cumulative stats decrement.
    await _update_route_stats(route_object_id, merged_inc)
    await _update_user_route_stats(current_user.id, route_object_id, merged_inc)

    # 3. Clean up empty UserRouteStats doc (same rule as single DELETE).
    user_stats = await UserRouteStats.find_one(
        UserRouteStats.user_id == current_user.id,
        UserRouteStats.route_id == route_object_id,
    )
    if (
        user_stats
        and user_stats.total_count <= 0
        and user_stats.completed_count <= 0
        and user_stats.verified_completed_count <= 0
    ):
        await user_stats.delete()
```

Note: `ObjectId` must be available. Check the existing imports — `my.py` already has `from bson import ObjectId` (at the top). If not, add it.

- [ ] **Step 3: Run full backend test suite**

Run: `cd /Users/htjo/besetter/services/api && pytest tests/ -v`

Expected: no regressions. Pre-existing failures (2 failed / 7 errors in thumbnail/activity tests) are unrelated and may persist — do not attempt to fix them.

- [ ] **Step 4: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/my.py
git commit -m "feat(api): add DELETE /my/daily-routes/{routeId} bulk endpoint"
```

---

## Task 7: Mobile — ActivityService + my_page timezone cleanup

**Files:**
- Modify: `apps/mobile/lib/services/activity_service.dart`
- Modify: `apps/mobile/lib/pages/my_page.dart`

This task touches two files together because removing `timezone` params from the service breaks all `my_page.dart` call sites — the two must ship together.

- [ ] **Step 1: Update `ActivityService.getLastActivityDate`**

In `apps/mobile/lib/services/activity_service.dart`, replace the `getLastActivityDate` method (around lines 100-115) with:

```dart
  /// Get the date of the user's most recent activity.
  static Future<String?> getLastActivityDate() async {
    final response = await AuthorizedHttpClient.get('/my/last-activity-date');

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['lastActivityDate'] as String?;
    } else {
      throw Exception('Failed to load last activity date. Status: ${response.statusCode}');
    }
  }
```

- [ ] **Step 2: Update `ActivityService.getMonthlySummary`**

In the same file, replace `getMonthlySummary` (around lines 117-137) with:

```dart
  /// Get the active dates (day numbers) for a given month.
  static Future<List<int>> getMonthlySummary({
    required int year,
    required int month,
  }) async {
    final uri = Uri.parse('/my/monthly-summary').replace(queryParameters: {
      'year': year.toString(),
      'month': month.toString(),
    });

    final response = await AuthorizedHttpClient.get(uri.toString());

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return List<int>.from(data['activeDates']);
    } else {
      throw Exception('Failed to load monthly summary. Status: ${response.statusCode}');
    }
  }
```

- [ ] **Step 3: Update `ActivityService.getDailyRoutes`**

In the same file, replace `getDailyRoutes` (around lines 139-156) with:

```dart
  /// Get route groups for a specific date.
  static Future<Map<String, dynamic>> getDailyRoutes({
    required String date,
  }) async {
    final uri = Uri.parse('/my/daily-routes').replace(queryParameters: {
      'date': date,
    });

    final response = await AuthorizedHttpClient.get(uri.toString());

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load daily routes. Status: ${response.statusCode}');
    }
  }
```

- [ ] **Step 4: Add `deleteDailyRouteGroup`**

In the same file, add a new method at the end of the `ActivityService` class (just before the closing `}`):

```dart
  /// Delete all of the current user's activities for (route, date).
  /// Date is a local date string (YYYY-MM-DD) — server resolves using each
  /// activity's stored timezone.
  static Future<void> deleteDailyRouteGroup({
    required String routeId,
    required String date,
  }) async {
    final uri = Uri.parse('/my/daily-routes/$routeId').replace(queryParameters: {
      'date': date,
    });

    final response = await AuthorizedHttpClient.delete(uri.toString());

    if (response.statusCode != 204) {
      throw Exception('Failed to delete daily route group. Status: ${response.statusCode}');
    }
  }
```

- [ ] **Step 5: Update `my_page.dart` — remove `timezone` hook state**

In `apps/mobile/lib/pages/my_page.dart`, delete the `timezone` hook state declaration (around line 43):

```dart
    final timezone = useState<String>('Asia/Seoul');
```

Remove that line entirely.

- [ ] **Step 6: Update `loadMonthlySummary` and `loadDailyRoutes` signatures + call sites**

In the same file, change the `loadMonthlySummary` function (around lines 56-71) to drop the `tz` parameter:

```dart
    Future<void> loadMonthlySummary(int year, int month) async {
      final cacheKey = '$year-${month.toString().padLeft(2, '0')}';
      if (!isCurrentMonth(year, month) && monthlySummaryCache.value.containsKey(cacheKey)) {
        activeDates.value = monthlySummaryCache.value[cacheKey]!;
        return;
      }
      try {
        final dates = await ActivityService.getMonthlySummary(year: year, month: month);
        activeDates.value = dates;
        if (!isCurrentMonth(year, month)) {
          monthlySummaryCache.value[cacheKey] = dates;
        }
      } catch (_) {
        activeDates.value = [];
      }
    }
```

Change `loadDailyRoutes` (around lines 74-92) to:

```dart
    Future<void> loadDailyRoutes(int year, int month, int day) async {
      final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      if (!isToday(year, month, day) && dailyRoutesCache.value.containsKey(dateStr)) {
        dailyRoutesData.value = dailyRoutesCache.value[dateStr];
        return;
      }
      dailyRoutesLoading.value = true;
      try {
        final data = await ActivityService.getDailyRoutes(date: dateStr);
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
```

- [ ] **Step 7: Update the initial load useEffect**

In `my_page.dart` around lines 95-115, replace the initial load block with:

```dart
    // Initial load
    useEffect(() {
      () async {
        final lastDate = await ActivityService.getLastActivityDate();
        if (lastDate != null) {
          final parts = lastDate.split('-').map(int.parse).toList();
          calendarYear.value = parts[0];
          calendarMonth.value = parts[1];
          selectedDay.value = parts[2];
          await Future.wait([
            loadMonthlySummary(parts[0], parts[1]),
            loadDailyRoutes(parts[0], parts[1], parts[2]),
          ]);
        } else {
          await loadMonthlySummary(now.year, now.month);
        }
        calendarLoading.value = false;
      }();
      return null;
    }, []);
```

Note the removals: `FlutterTimezone.getLocalTimezone()` call, `timezone.value = tz;`, and all `timezone:`/`tz` arguments.

- [ ] **Step 8: Update the refresh signal useEffect**

In `my_page.dart` around lines 118-128, replace with:

```dart
    // Reload when signaled (tab entry after activity change)
    useEffect(() {
      if (refreshSignal == 0) return null;
      monthlySummaryCache.value.clear();
      dailyRoutesCache.value.clear();
      loadMonthlySummary(calendarYear.value, calendarMonth.value);
      if (selectedDay.value != null) {
        loadDailyRoutes(calendarYear.value, calendarMonth.value, selectedDay.value!);
      }
      return null;
    }, [refreshSignal]);
```

- [ ] **Step 9: Update remaining call sites**

Update `goToPrevMonth` (around line 140) — change `loadMonthlySummary(newYear, newMonth, timezone.value);` to `loadMonthlySummary(newYear, newMonth);`.

Update `goToNextMonth` (around line 152) — change `loadMonthlySummary(newYear, newMonth, timezone.value);` to `loadMonthlySummary(newYear, newMonth);`.

Update `onDaySelected` (around line 157) — change `loadDailyRoutes(calendarYear.value, calendarMonth.value, day, timezone.value);` to `loadDailyRoutes(calendarYear.value, calendarMonth.value, day);`.

Update the `onReturn` callback inside the `_DailyRoutes` widget construction (around lines 289-300) — replace:

```dart
                  onReturn: () {
                    if (ref.read(activityDirtyProvider)) {
                      ref.read(activityDirtyProvider.notifier).state = false;
                      monthlySummaryCache.value.clear();
                      dailyRoutesCache.value.clear();
                      final tz = timezone.value;
                      loadMonthlySummary(calendarYear.value, calendarMonth.value, tz);
                      if (selectedDay.value != null) {
                        loadDailyRoutes(calendarYear.value, calendarMonth.value, selectedDay.value!, tz);
                      }
                    }
                  },
```

with:

```dart
                  onReturn: () {
                    if (ref.read(activityDirtyProvider)) {
                      ref.read(activityDirtyProvider.notifier).state = false;
                      monthlySummaryCache.value.clear();
                      dailyRoutesCache.value.clear();
                      loadMonthlySummary(calendarYear.value, calendarMonth.value);
                      if (selectedDay.value != null) {
                        loadDailyRoutes(calendarYear.value, calendarMonth.value, selectedDay.value!);
                      }
                    }
                  },
```

- [ ] **Step 10: Remove unused `flutter_timezone` import**

At the top of `apps/mobile/lib/pages/my_page.dart`, remove the line:

```dart
import 'package:flutter_timezone/flutter_timezone.dart';
```

(Do not remove from `activity_panel.dart` — it still uses `FlutterTimezone` when creating new activities.)

- [ ] **Step 11: Run analyzer**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/services/activity_service.dart lib/pages/my_page.dart`

Expected: no NEW issues. Pre-existing infos (deprecated Color.value, use_build_context_synchronously, etc.) are acceptable.

- [ ] **Step 12: Commit**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/services/activity_service.dart apps/mobile/lib/pages/my_page.dart
git commit -m "refactor(mobile): drop timezone param from my/* service calls"
```

---

## Task 8: Mobile — `_DailyRouteCard` overflow menu + delete handler

**Files:**
- Modify: `apps/mobile/lib/pages/my_page.dart`

- [ ] **Step 1: Add `onDeleteConfirmed` prop to `_DailyRouteCard`**

In `apps/mobile/lib/pages/my_page.dart`, update the `_DailyRouteCard` class declaration (around line 764) to add a new required callback:

```dart
class _DailyRouteCard extends StatelessWidget {
  final Map<String, dynamic> route;
  final String Function(double) formatDuration;
  final VoidCallback? onReturn;
  final Future<void> Function(String routeId) onDeleteConfirmed;

  const _DailyRouteCard({
    required this.route,
    required this.formatDuration,
    required this.onDeleteConfirmed,
    this.onReturn,
  });
```

- [ ] **Step 2: Add a helper to show the confirm dialog + trigger delete**

Inside `_DailyRouteCard` (just before `build`), add:

```dart
  Future<void> _confirmAndDelete(BuildContext context, String routeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('액티비티 삭제'),
        content: const Text('해당 루트의 액티비티가 모두 삭제 됩니다. 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '삭제',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await onDeleteConfirmed(routeId);
  }
```

- [ ] **Step 3: Insert the ⋮ menu into the card**

In the same `_DailyRouteCard.build` method, find the inner `Column` that renders grade/title/placeName/(blocked badge) — it's inside an `Expanded > SizedBox > Padding > Column` structure around line 822. Change the top `Row` that wraps grade/title/place so that the grade+title+place column is wrapped in `Expanded`, and add a `PopupMenuButton` sibling to its right:

Currently the structure is approximately:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    // Top: grade + title + place
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [ /* grade badge */, /* title */, /* place */, if (isBlocked) ... ],
    ),
    // Bottom: stat boxes row
    Row( ... ),
  ],
),
```

Change the top section to a Row with an Expanded inner column and a PopupMenuButton:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    // Top: grade + title + place + overflow menu
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // grade badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(color: gradeColor, borderRadius: BorderRadius.circular(6)),
                child: Text(grade, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(height: 6),
              Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF2C2F30))),
              const SizedBox(height: 2),
              Text(placeName, style: const TextStyle(fontSize: 12, color: Color(0xFF595C5D))),
              if (isBlocked) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(blockedIcon, style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    Text(
                      blockedText,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8A8F94),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          width: 32,
          height: 32,
          child: PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF8A8F94)),
            onSelected: (value) {
              if (value == 'delete') {
                _confirmAndDelete(context, routeId);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'delete',
                child: Text('삭제하기', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ],
    ),
    // Bottom: stat boxes row
    Row(
      children: [
        Expanded(child: _StatBox(value: '$completedCount', label: l10n.completed.toUpperCase(), valueColor: const Color(0xFF0066FF))),
        Expanded(child: _StatBox(value: '$attemptedCount', label: l10n.attempted.toUpperCase())),
        Expanded(child: _StatBox(value: formatDuration(totalDuration), label: 'DURATION')),
      ],
    ),
  ],
),
```

**Note:** The `PopupMenuButton` sits inside the outer `GestureDetector`, but it stops pointer events so tapping the ⋮ icon does not also trigger the card's `onTap` → route_viewer navigation.

- [ ] **Step 4: Add `handleRouteGroupDelete` to `MyPage`**

In `apps/mobile/lib/pages/my_page.dart`, inside the `MyPage.build` method, add a new function near the other handlers (e.g. right after `onDaySelected`). Paste this entire function:

```dart
    Future<void> handleRouteGroupDelete(String routeId) async {
      final year = calendarYear.value;
      final month = calendarMonth.value;
      final day = selectedDay.value;
      if (day == null) return;
      final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

      try {
        await ActivityService.deleteDailyRouteGroup(routeId: routeId, date: dateStr);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제에 실패했어요. 잠시 후 다시 시도해주세요.')),
        );
        return;
      }

      final data = dailyRoutesData.value;
      if (data == null) return;
      final routes = List<Map<String, dynamic>>.from(data['routes'] ?? []);
      final removedIndex = routes.indexWhere((r) => r['routeId'] == routeId);
      if (removedIndex == -1) return;
      final removed = routes.removeAt(removedIndex);

      final newSummary = Map<String, dynamic>.from(data['summary'] as Map);
      newSummary['totalCount'] = (newSummary['totalCount'] as int) - ((removed['totalCount'] as int?) ?? 0);
      newSummary['completedCount'] = (newSummary['completedCount'] as int) - ((removed['completedCount'] as int?) ?? 0);
      newSummary['attemptedCount'] = (newSummary['attemptedCount'] as int) - ((removed['attemptedCount'] as int?) ?? 0);
      newSummary['totalDuration'] = (newSummary['totalDuration'] as num).toDouble() - ((removed['totalDuration'] as num?)?.toDouble() ?? 0.0);
      newSummary['routeCount'] = (newSummary['routeCount'] as int) - 1;

      dailyRoutesCache.value.remove(dateStr);
      final monthKey = '$year-${month.toString().padLeft(2, '0')}';
      monthlySummaryCache.value.remove(monthKey);

      if (routes.isNotEmpty) {
        dailyRoutesData.value = {'summary': newSummary, 'routes': routes};
        return;
      }

      // This day is now empty — drop it from activeDates.
      final updatedActiveDates = [...activeDates.value]..remove(day);
      activeDates.value = updatedActiveDates;
      dailyRoutesData.value = null;

      // Prefer earlier days in same month.
      final previousDays = updatedActiveDates.where((d) => d < day).toList();
      if (previousDays.isNotEmpty) {
        final target = previousDays.reduce((a, b) => a > b ? a : b);
        selectedDay.value = target;
        await loadDailyRoutes(year, month, target);
        return;
      }

      // Then later days in same month.
      final nextDays = updatedActiveDates.where((d) => d > day).toList();
      if (nextDays.isNotEmpty) {
        final target = nextDays.reduce((a, b) => a < b ? a : b);
        selectedDay.value = target;
        await loadDailyRoutes(year, month, target);
        return;
      }

      // Otherwise jump to /last-activity-date.
      final lastDate = await ActivityService.getLastActivityDate();
      if (!context.mounted) return;
      if (lastDate == null) {
        selectedDay.value = null;
        return;
      }
      final parts = lastDate.split('-').map(int.parse).toList();
      calendarYear.value = parts[0];
      calendarMonth.value = parts[1];
      selectedDay.value = parts[2];
      await Future.wait([
        loadMonthlySummary(parts[0], parts[1]),
        loadDailyRoutes(parts[0], parts[1], parts[2]),
      ]);
    }
```

- [ ] **Step 5: Pass `handleRouteGroupDelete` down through `_DailyRoutes` and `_DailyRouteCard`**

First, add the new prop to `_DailyRoutes` (the list widget, around line 693):

```dart
class _DailyRoutes extends StatelessWidget {
  final Map<String, dynamic>? data;
  final bool loading;
  final int? selectedDay;
  final VoidCallback? onReturn;
  final Future<void> Function(String routeId) onDeleteConfirmed;

  const _DailyRoutes({
    required this.data,
    required this.loading,
    required this.selectedDay,
    required this.onDeleteConfirmed,
    this.onReturn,
  });
```

In the `_DailyRoutes.build` method, pass it through when constructing `_DailyRouteCard` (around line 754):

```dart
        ...routes.map((route) => _DailyRouteCard(
          route: route,
          formatDuration: _formatDuration,
          onReturn: onReturn,
          onDeleteConfirmed: onDeleteConfirmed,
        )),
```

Finally, at the call site in `MyPage.build` (around line 285) where `_DailyRoutes(...)` is created, add the new prop:

```dart
                _DailyRoutes(
                  data: dailyRoutesData.value,
                  loading: dailyRoutesLoading.value,
                  selectedDay: selectedDay.value,
                  onDeleteConfirmed: handleRouteGroupDelete,
                  onReturn: () {
                    if (ref.read(activityDirtyProvider)) {
                      ref.read(activityDirtyProvider.notifier).state = false;
                      monthlySummaryCache.value.clear();
                      dailyRoutesCache.value.clear();
                      loadMonthlySummary(calendarYear.value, calendarMonth.value);
                      if (selectedDay.value != null) {
                        loadDailyRoutes(calendarYear.value, calendarMonth.value, selectedDay.value!);
                      }
                    }
                  },
                ),
```

- [ ] **Step 6: Run analyzer**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/pages/my_page.dart`

Expected: no NEW issues (pre-existing ones allowed).

- [ ] **Step 7: Commit**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/pages/my_page.dart
git commit -m "feat(mobile): bulk delete a day's route activities from card menu"
```

---

## Final verification

After all tasks complete, run both suites:

```bash
cd /Users/htjo/besetter/services/api && pytest tests/routers/test_my.py -v
cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/services/activity_service.dart lib/pages/my_page.dart
```

Both should pass with no regressions.

## Spec coverage check

| Spec item | Task |
|---|---|
| `_day_utc_superset` / `_month_utc_superset` helpers | Task 1 |
| `_merge_incs` helper | Task 2 |
| `GET /my/daily-routes` refactor (activity.timezone, drop query tz) | Task 3 |
| `GET /my/monthly-summary` refactor | Task 4 |
| `GET /my/last-activity-date` refactor | Task 5 |
| `DELETE /my/daily-routes/{routeId}?date=...` endpoint | Task 6 |
| Bulk stats decrement via cumulative `_merge_incs` | Task 6 |
| Activity delete first → stats decrement second ordering | Task 6 |
| UserRouteStats cleanup if all counts ≤ 0 | Task 6 |
| `ActivityService` timezone param removal + `deleteDailyRouteGroup` | Task 7 |
| `my_page.dart` timezone state + call site cleanup | Task 7 |
| `_DailyRouteCard` ⋮ menu + confirm dialog | Task 8 |
| `handleRouteGroupDelete` local state updates (cards, summary, activeDates, prev/next day, last-activity-date fallback) | Task 8 |
| Cache invalidation for affected month/day | Task 8 |
