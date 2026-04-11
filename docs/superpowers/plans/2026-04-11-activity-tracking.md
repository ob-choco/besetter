# Activity Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add workout activity tracking to the BESETTER climbing app — record route attempts with location verification, maintain per-route and per-user stats, and support calendar aggregation queries.

**Architecture:** New `Activity` and `UserRouteStats` Beanie Documents stored in MongoDB. Three REST endpoints (POST/PATCH/DELETE) nested under `/routes/{routeId}/activity`. Stats are maintained incrementally on both the Route document (global) and a per-user-per-route `UserRouteStats` document. The existing `_haversine` function in `places.py` is extracted to a shared utility for location verification.

**Tech Stack:** Python 3.11, FastAPI, Beanie (MongoDB ODM), Pydantic v2, pytest

---

## File Structure

| File | Responsibility |
|---|---|
| `services/api/app/core/geo.py` | **Create** — `haversine_distance()` extracted from places.py for reuse |
| `services/api/app/models/activity.py` | **Create** — `ActivityStatus`, `RouteSnapshot`, `ActivityStats`, `Activity`, `UserRouteStats` models |
| `services/api/app/models/route.py` | **Modify** — Add `activity_stats: ActivityStats` field to `Route` |
| `services/api/app/routers/activities.py` | **Create** — POST/PATCH/DELETE endpoints + stats helper |
| `services/api/app/routers/places.py` | **Modify** — Replace `_haversine` with import from `core/geo.py` |
| `services/api/app/routers/users.py` | **Modify** — Add Activity/UserRouteStats hard delete to account deletion |
| `services/api/app/main.py` | **Modify** — Register Activity/UserRouteStats models + activities router |
| `services/api/tests/core/__init__.py` | **Create** — empty |
| `services/api/tests/core/test_geo.py` | **Create** — haversine unit tests |
| `services/api/tests/models/__init__.py` | **Create** — empty |
| `services/api/tests/models/test_activity.py` | **Create** — model unit tests |

---

### Task 1: Extract haversine to shared utility

**Files:**
- Create: `services/api/app/core/geo.py`
- Modify: `services/api/app/routers/places.py:89-96`
- Create: `services/api/tests/core/__init__.py`
- Create: `services/api/tests/core/test_geo.py`

- [ ] **Step 1: Write the failing test**

Create `services/api/tests/core/__init__.py` (empty file).

Create `services/api/tests/core/test_geo.py`:

```python
from app.core.geo import haversine_distance


def test_haversine_same_point():
    assert haversine_distance(37.5665, 126.9780, 37.5665, 126.9780) == 0.0


def test_haversine_known_distance():
    # Seoul City Hall to Gangnam Station ≈ 8.9km
    d = haversine_distance(37.5665, 126.9780, 37.4979, 127.0276)
    assert 8800 < d < 9100


def test_haversine_short_distance():
    # Two points ~100m apart
    d = haversine_distance(37.5665, 126.9780, 37.5674, 126.9780)
    assert 90 < d < 110


def test_haversine_returns_metres():
    # Tokyo to Osaka ≈ 397km
    d = haversine_distance(35.6762, 139.6503, 34.6937, 135.5023)
    assert 390_000 < d < 405_000
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd services/api && python -m pytest tests/core/test_geo.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'app.core.geo'`

- [ ] **Step 3: Write the implementation**

Create `services/api/app/core/geo.py`:

```python
import math


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Return distance in metres between two (lat, lon) points."""
    R = 6_371_000  # Earth radius in metres
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd services/api && python -m pytest tests/core/test_geo.py -v`
Expected: All 4 tests PASS

- [ ] **Step 5: Update places.py to use shared haversine**

In `services/api/app/routers/places.py`, replace the `_haversine` function and its usage:

Remove lines 1-2 of the imports and the function definition (lines 89-96). Add import and update calls:

```python
# Add to imports (near top):
from app.core.geo import haversine_distance

# Remove the _haversine function definition entirely (lines 89-96)

# Replace all calls from _haversine(...) to haversine_distance(...)
# Line 218: change _haversine( to haversine_distance(
```

Specifically in `places.py`:
- Remove `import math` (line 3) — no longer needed after removing `_haversine`
- Remove the `_haversine` function (lines 89-96)
- Add `from app.core.geo import haversine_distance` to imports
- Change line 218: `distance = haversine_distance(latitude, longitude, place.latitude, place.longitude) if place.latitude and place.longitude else None`

- [ ] **Step 6: Verify existing tests still pass**

Run: `cd services/api && python -m pytest tests/ -v`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add services/api/app/core/geo.py services/api/app/routers/places.py services/api/tests/core/
git commit -m "refactor: extract haversine to shared core/geo module"
```

---

### Task 2: Create Activity, UserRouteStats, and ActivityStats models

**Files:**
- Create: `services/api/app/models/activity.py`
- Modify: `services/api/app/models/route.py:1-72`
- Create: `services/api/tests/models/__init__.py`
- Create: `services/api/tests/models/test_activity.py`

- [ ] **Step 1: Write the failing test**

Create `services/api/tests/models/__init__.py` (empty file).

Create `services/api/tests/models/test_activity.py`:

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
    assert ActivityStatus.STARTED == "started"
    assert ActivityStatus.COMPLETED == "completed"
    assert ActivityStatus.ATTEMPTED == "attempted"


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


def test_activity_default_status():
    """Activity defaults to STARTED status."""
    from bson import ObjectId

    snap = RouteSnapshot(grade_type="v_scale", grade="V7")
    now = datetime.now(tz=timezone.utc)
    activity = Activity(
        route_id=ObjectId(),
        user_id=ObjectId(),
        location_verified=True,
        started_at=now,
        route_snapshot=snap,
        created_at=now,
    )
    assert activity.status == ActivityStatus.STARTED
    assert activity.ended_at is None
    assert activity.duration is None


def test_user_route_stats_defaults():
    from bson import ObjectId

    stats = UserRouteStats(
        user_id=ObjectId(),
        route_id=ObjectId(),
    )
    assert stats.total_count == 0
    assert stats.last_activity_at is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd services/api && python -m pytest tests/models/test_activity.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'app.models.activity'`

- [ ] **Step 3: Create the activity models file**

Create `services/api/app/models/activity.py`:

```python
from datetime import datetime
from enum import Enum
from typing import Optional

from beanie import Document
from beanie.odm.fields import PydanticObjectId
from pydantic import BaseModel, Field
from pymongo import ASCENDING, IndexModel

from . import model_config


class ActivityStatus(str, Enum):
    STARTED = "started"
    COMPLETED = "completed"
    ATTEMPTED = "attempted"


class RouteSnapshot(BaseModel):
    model_config = model_config

    title: Optional[str] = None
    grade_type: str
    grade: str
    grade_color: Optional[str] = None
    place_id: Optional[PydanticObjectId] = None
    place_name: Optional[str] = None
    image_url: Optional[str] = None
    overlay_image_url: Optional[str] = None


class ActivityStats(BaseModel):
    model_config = model_config

    total_count: int = 0
    total_duration: int = 0
    completed_count: int = 0
    completed_duration: int = 0
    verified_completed_count: int = 0
    verified_completed_duration: int = 0


class Activity(Document):
    model_config = model_config

    route_id: PydanticObjectId
    user_id: PydanticObjectId
    status: ActivityStatus = ActivityStatus.STARTED
    location_verified: bool = False
    started_at: datetime
    ended_at: Optional[datetime] = None
    duration: Optional[int] = None
    route_snapshot: RouteSnapshot
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Settings:
        name = "activities"
        indexes = [
            IndexModel([("userId", ASCENDING), ("startedAt", ASCENDING)]),
            IndexModel([("routeId", ASCENDING), ("userId", ASCENDING), ("status", ASCENDING)]),
        ]
        keep_nulls = True


class UserRouteStats(Document):
    model_config = model_config

    user_id: PydanticObjectId
    route_id: PydanticObjectId
    total_count: int = 0
    total_duration: int = 0
    completed_count: int = 0
    completed_duration: int = 0
    verified_completed_count: int = 0
    verified_completed_duration: int = 0
    last_activity_at: Optional[datetime] = None

    class Settings:
        name = "userRouteStats"
        indexes = [
            IndexModel(
                [("userId", ASCENDING), ("routeId", ASCENDING)],
                unique=True,
            ),
        ]
        keep_nulls = True
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd services/api && python -m pytest tests/models/test_activity.py -v`
Expected: All 8 tests PASS

- [ ] **Step 5: Add ActivityStats to Route model**

In `services/api/app/models/route.py`, add import and field:

Add to imports (after existing imports):
```python
from app.models.activity import ActivityStats
```

Add field to `Route` class (after `overlay_completed_at` field, before `created_at`):
```python
    activity_stats: ActivityStats = Field(default_factory=ActivityStats)
```

- [ ] **Step 6: Run all tests**

Run: `cd services/api && python -m pytest tests/ -v`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add services/api/app/models/activity.py services/api/app/models/route.py services/api/tests/models/
git commit -m "feat: add Activity, UserRouteStats, ActivityStats models"
```

---

### Task 3: Register new models in main.py

**Files:**
- Modify: `services/api/app/main.py:1-52`

- [ ] **Step 1: Add imports for new models**

In `services/api/app/main.py`, add after the existing model imports (after line 12):

```python
from app.models.activity import Activity as ActivityModel
from app.models.activity import UserRouteStats as UserRouteStatsModel
```

- [ ] **Step 2: Add models to Beanie init**

In the `init_beanie` call (line 28), add the new models to the `document_models` list:

Change:
```python
document_models=[OpenIdNonceModel, UserModel, HoldPolygonModel, ImageModel, RouteModel, PlaceModel, PlaceSuggestionModel],
```

To:
```python
document_models=[OpenIdNonceModel, UserModel, HoldPolygonModel, ImageModel, RouteModel, PlaceModel, PlaceSuggestionModel, ActivityModel, UserRouteStatsModel],
```

- [ ] **Step 3: Commit**

```bash
git add services/api/app/main.py
git commit -m "feat: register Activity and UserRouteStats in Beanie init"
```

---

### Task 4: Create activities router — POST endpoint

**Files:**
- Create: `services/api/app/routers/activities.py`
- Modify: `services/api/app/main.py`

- [ ] **Step 1: Create the activities router file**

Create `services/api/app/routers/activities.py`:

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
    ActivityStats,
    ActivityStatus,
    RouteSnapshot,
    UserRouteStats,
)
from app.models.image import Image
from app.models.place import Place
from app.models.route import Route
from app.models.user import User
from app.core.gcs import generate_signed_url, extract_blob_path_from_url

router = APIRouter(prefix="/routes", tags=["activities"])

LOCATION_VERIFICATION_RADIUS_M = 300
AUTO_CANCEL_MAX_DURATION_S = 3600


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------


class CreateActivityRequest(BaseModel):
    model_config = model_config

    latitude: float
    longitude: float
    status: Optional[ActivityStatus] = None
    ended_at: Optional[datetime] = None


class UpdateActivityRequest(BaseModel):
    model_config = model_config

    status: ActivityStatus
    ended_at: datetime


class ActivityResponse(BaseModel):
    model_config = model_config

    id: PydanticObjectId
    route_id: PydanticObjectId
    status: ActivityStatus
    location_verified: bool
    started_at: datetime
    ended_at: Optional[datetime] = None
    duration: Optional[int] = None
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
    duration: Optional[int],
    sign: int = 1,
) -> dict:
    """Build a MongoDB $inc dict for activity_stats / UserRouteStats fields.

    sign=1 for increment, sign=-1 for decrement.
    """
    inc = {}
    inc["totalCount"] = sign

    if duration is not None:
        inc["totalDuration"] = sign * duration

    if status == ActivityStatus.COMPLETED:
        inc["completedCount"] = sign
        if duration is not None:
            inc["completedDuration"] = sign * duration
        if location_verified:
            inc["verifiedCompletedCount"] = sign
            if duration is not None:
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
    if not place or not place.latitude or not place.longitude:
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

    # 2. 상태 및 endedAt 유효성
    req_status = request.status or ActivityStatus.STARTED
    if req_status in (ActivityStatus.COMPLETED, ActivityStatus.ATTEMPTED) and request.ended_at is None:
        raise HTTPException(
            status_code=http_status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="endedAt is required when status is completed or attempted",
        )

    # 3. 위치 인증
    location_verified = await _verify_location(route, request.latitude, request.longitude)

    # 4. 자동취소: 같은 route + user의 기존 "started" Activity
    now = datetime.now(tz=timezone.utc)
    existing_started = await Activity.find(
        Activity.route_id == route.id,
        Activity.user_id == current_user.id,
        Activity.status == ActivityStatus.STARTED,
    ).to_list()

    for old in existing_started:
        raw_duration = int((now - old.started_at).total_seconds())
        capped_duration = min(raw_duration, AUTO_CANCEL_MAX_DURATION_S)
        old.status = ActivityStatus.ATTEMPTED
        old.ended_at = now
        old.duration = capped_duration
        old.updated_at = now
        await old.save()

        # 자동취소 stats: total_count는 이미 +1 되어 있으므로 duration만 추가
        auto_inc = {}
        if capped_duration > 0:
            auto_inc["totalDuration"] = capped_duration
        if auto_inc:
            await _update_route_stats(route.id, auto_inc)
            await _update_user_route_stats(current_user.id, route.id, auto_inc)

    # 5. 스냅샷 생성
    snapshot = await _build_route_snapshot(route)

    # 6. duration 계산
    duration = None
    if req_status in (ActivityStatus.COMPLETED, ActivityStatus.ATTEMPTED):
        duration = _compute_duration(now, request.ended_at)

    # 7. Activity 생성
    activity = Activity(
        route_id=route.id,
        user_id=current_user.id,
        status=req_status,
        location_verified=location_verified,
        started_at=now,
        ended_at=request.ended_at if req_status != ActivityStatus.STARTED else None,
        duration=duration,
        route_snapshot=snapshot,
        created_at=now,
    )
    await activity.save()

    # 8. Stats 갱신
    inc = _build_stats_inc(req_status, location_verified, duration, sign=1)
    await _update_route_stats(route.id, inc)
    await _update_user_route_stats(current_user.id, route.id, inc, activity_at=now)

    return _activity_to_response(activity)
```

- [ ] **Step 2: Register the router in main.py**

In `services/api/app/main.py`, add import and router:

Add to imports:
```python
from app.routers import activities
```

Add router registration (after `app.include_router(places.router)`):
```python
app.include_router(activities.router)
```

- [ ] **Step 3: Run all tests**

Run: `cd services/api && python -m pytest tests/ -v`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add services/api/app/routers/activities.py services/api/app/main.py
git commit -m "feat: add POST /routes/{routeId}/activity endpoint"
```

---

### Task 5: Add PATCH endpoint

**Files:**
- Modify: `services/api/app/routers/activities.py`

- [ ] **Step 1: Add the PATCH endpoint**

Append to `services/api/app/routers/activities.py` (after the `create_activity` function):

```python
@router.patch("/{route_id}/activity/{activity_id}", response_model=ActivityResponse)
async def update_activity(
    route_id: str,
    activity_id: str,
    request: UpdateActivityRequest,
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

    # 2. 이미 종료된 건 수정 불가
    if activity.status != ActivityStatus.STARTED:
        raise HTTPException(
            status_code=http_status.HTTP_400_BAD_REQUEST,
            detail="Only activities with status 'started' can be updated",
        )

    # 3. status 유효성
    if request.status not in (ActivityStatus.COMPLETED, ActivityStatus.ATTEMPTED):
        raise HTTPException(
            status_code=http_status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Status must be 'completed' or 'attempted'",
        )

    # 4. duration 계산 + 업데이트
    now = datetime.now(tz=timezone.utc)
    duration = _compute_duration(activity.started_at, request.ended_at)
    activity.status = request.status
    activity.ended_at = request.ended_at
    activity.duration = duration
    activity.updated_at = now
    await activity.save()

    # 5. Stats 갱신 — PATCH는 이미 total_count +1 되어 있으므로 count 증가 없이 duration + completed 관련만
    inc: dict = {}
    inc["totalDuration"] = duration
    if request.status == ActivityStatus.COMPLETED:
        inc["completedCount"] = 1
        inc["completedDuration"] = duration
        if activity.location_verified:
            inc["verifiedCompletedCount"] = 1
            inc["verifiedCompletedDuration"] = duration

    await _update_route_stats(activity.route_id, inc)
    await _update_user_route_stats(current_user.id, activity.route_id, inc, activity_at=now)

    return _activity_to_response(activity)
```

- [ ] **Step 2: Run all tests**

Run: `cd services/api && python -m pytest tests/ -v`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add services/api/app/routers/activities.py
git commit -m "feat: add PATCH /routes/{routeId}/activity/{activityId} endpoint"
```

---

### Task 6: Add DELETE endpoint

**Files:**
- Modify: `services/api/app/routers/activities.py`

- [ ] **Step 1: Add the DELETE endpoint**

Append to `services/api/app/routers/activities.py` (after the `update_activity` function):

```python
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

- [ ] **Step 2: Run all tests**

Run: `cd services/api && python -m pytest tests/ -v`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add services/api/app/routers/activities.py
git commit -m "feat: add DELETE /routes/{routeId}/activity/{activityId} endpoint"
```

---

### Task 7: Add Activity hard delete to user account deletion

**Files:**
- Modify: `services/api/app/routers/users.py:114-142`

- [ ] **Step 1: Add imports**

In `services/api/app/routers/users.py`, add to imports:

```python
from app.models.activity import Activity, UserRouteStats
```

- [ ] **Step 2: Add hard delete to delete_account**

In the `delete_account` function, add after the HoldPolygon soft delete block (after line 135) and before the user soft delete:

```python
    # Activity hard delete
    await Activity.find(Activity.user_id == current_user.id).delete()

    # UserRouteStats hard delete
    await UserRouteStats.find(UserRouteStats.user_id == current_user.id).delete()
```

- [ ] **Step 3: Run all tests**

Run: `cd services/api && python -m pytest tests/ -v`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add services/api/app/routers/users.py
git commit -m "feat: hard delete Activity/UserRouteStats on user account deletion"
```

---

### Task 8: Write stats helper unit tests

**Files:**
- Create: `services/api/tests/routers/__init__.py`
- Create: `services/api/tests/routers/test_activity_helpers.py`

- [ ] **Step 1: Write unit tests for _build_stats_inc and _compute_duration**

Create `services/api/tests/routers/__init__.py` (empty file).

Create `services/api/tests/routers/test_activity_helpers.py`:

```python
from datetime import datetime, timezone, timedelta
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


def test_stats_inc_started():
    inc = _build_stats_inc(ActivityStatus.STARTED, False, None, sign=1)
    assert inc == {"totalCount": 1}


def test_stats_inc_started_verified():
    inc = _build_stats_inc(ActivityStatus.STARTED, True, None, sign=1)
    assert inc == {"totalCount": 1}


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


def test_stats_dec_started():
    inc = _build_stats_inc(ActivityStatus.STARTED, False, None, sign=-1)
    assert inc == {"totalCount": -1}


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

- [ ] **Step 2: Run tests**

Run: `cd services/api && python -m pytest tests/routers/test_activity_helpers.py -v`
Expected: All 10 tests PASS

- [ ] **Step 3: Run full test suite**

Run: `cd services/api && python -m pytest tests/ -v`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add services/api/tests/routers/
git commit -m "test: add unit tests for activity stats helpers"
```
