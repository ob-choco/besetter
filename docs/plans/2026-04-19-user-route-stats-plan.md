# userStats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Maintain per-user aggregate statistics in a new `userStats` MongoDB collection, updated via `$inc` hooks at activity and route mutation points, with a backfill script for reconciliation.

**Architecture:** New `UserStats` Beanie Document (per-user unique), touched by a new `app/services/user_stats.py` service with four public functions (`on_activity_created`, `on_activity_deleted`, `on_route_created`, `on_route_soft_deleted`). Routers call the service in fire-and-forget mode (errors are logged but swallowed). A `scripts/backfill_user_stats.py` utility (re)computes the doc from source collections.

**Tech Stack:** Python 3.10+, FastAPI, Beanie ODM, Motor async driver, MongoDB (`mongomock-motor` for tests), pytest.

**Spec:** `docs/2026-04-19-user-route-stats-design.md`

---

## File Map

### Create
- `services/api/app/models/user_stats.py` — `UserStats` Document + counter sub-models.
- `services/api/app/services/__init__.py` — empty package marker.
- `services/api/app/services/user_stats.py` — service module with the four public functions and internal helpers.
- `services/api/scripts/__init__.py` — empty package marker.
- `services/api/scripts/backfill_user_stats.py` — idempotent backfill utility.
- `services/api/tests/services/__init__.py` — empty package marker.
- `services/api/tests/services/conftest.py` — Mongo-backed pytest fixtures (uses `mongomock-motor`).
- `services/api/tests/services/test_user_stats.py` — unit/integration tests for the service.
- `services/api/tests/scripts/__init__.py` — empty package marker.
- `services/api/tests/scripts/test_backfill_user_stats.py` — backfill script tests.

### Modify
- `services/api/app/main.py` — register `UserStatsModel` with Beanie in `init_beanie(document_models=...)`.
- `services/api/app/routers/activities.py` — remove local `_update_user_route_stats`; call service after activity save/delete.
- `services/api/app/routers/routes.py` — call service after `create_route` and `delete_route` (soft-delete).
- `services/api/pyproject.toml` — add `mongomock-motor` to `[dependency-groups].dev`.

---

## Task 1: Add dev dependency `mongomock-motor` and Mongo-backed test fixtures

**Files:**
- Modify: `services/api/pyproject.toml` (dev group)
- Create: `services/api/tests/services/__init__.py`
- Create: `services/api/tests/services/conftest.py`

- [ ] **Step 1: Add mongomock-motor to dev deps**

Modify `services/api/pyproject.toml`:

```toml
[dependency-groups]
dev = [
    "pytest>=7.0.0",
    "pytest-asyncio>=0.21.0",
    "mongomock-motor>=0.0.29",
]
```

- [ ] **Step 2: Install**

Run: `cd services/api && uv sync`
Expected: no errors; `mongomock-motor` installed.

- [ ] **Step 3: Create empty package marker**

Create `services/api/tests/services/__init__.py` as empty file.

- [ ] **Step 4: Create fixture file**

Create `services/api/tests/services/conftest.py`:

```python
"""Fixtures that spin up an in-memory Mongo (mongomock-motor) and init Beanie.

Overrides the root conftest's ``sys.modules.setdefault("app.core.config", MagicMock())``
for this package: the service tests need the real config module available, but we
still avoid hitting real Mongo by pointing Beanie at a mongomock client.
"""

from __future__ import annotations

import pytest_asyncio
from beanie import init_beanie
from mongomock_motor import AsyncMongoMockClient

from app.models.activity import Activity, UserRouteStats
from app.models.route import Route
from app.models.user import User
from app.models.user_stats import UserStats


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient()
    db = client.get_database("besetter-test")
    await init_beanie(
        database=db,
        document_models=[User, Route, Activity, UserRouteStats, UserStats],
    )
    yield db
```

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/pyproject.toml services/api/uv.lock services/api/tests/services/__init__.py services/api/tests/services/conftest.py
git commit -m "test(api): add mongomock-motor fixture for service tests"
```

---

## Task 2: Add `UserStats` model

**Files:**
- Create: `services/api/app/models/user_stats.py`
- Modify: `services/api/app/main.py:13-14, 33`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Write the failing model test**

Create `services/api/tests/services/test_user_stats.py`:

```python
"""Tests for the UserStats model and user_stats service."""

from __future__ import annotations

import pytest
from beanie.odm.fields import PydanticObjectId

from app.models.user_stats import UserStats


@pytest.mark.asyncio
async def test_user_stats_roundtrip(mongo_db):
    user_id = PydanticObjectId()
    doc = UserStats(user_id=user_id)
    await doc.insert()

    fetched = await UserStats.find_one(UserStats.user_id == user_id)
    assert fetched is not None
    assert fetched.user_id == user_id
    assert fetched.activity.total_count == 0
    assert fetched.distinct_routes.completed_count == 0
    assert fetched.distinct_days == 0
    assert fetched.own_routes_activity.verified_completed_count == 0
    assert fetched.routes_created.total_count == 0
    assert fetched.routes_created.bouldering_count == 0
    assert fetched.routes_created.endurance_count == 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py::test_user_stats_roundtrip -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'app.models.user_stats'`.

- [ ] **Step 3: Write the model**

Create `services/api/app/models/user_stats.py`:

```python
from datetime import datetime
from typing import Optional

from beanie import Document
from beanie.odm.fields import PydanticObjectId
from pydantic import BaseModel
from pymongo import ASCENDING, IndexModel

from . import model_config


class ActivityCounters(BaseModel):
    model_config = model_config

    total_count: int = 0
    completed_count: int = 0
    verified_completed_count: int = 0


class RoutesCreatedCounters(BaseModel):
    model_config = model_config

    total_count: int = 0
    bouldering_count: int = 0
    endurance_count: int = 0


class UserStats(Document):
    model_config = model_config

    user_id: PydanticObjectId
    activity: ActivityCounters = ActivityCounters()
    distinct_routes: ActivityCounters = ActivityCounters()
    distinct_days: int = 0
    own_routes_activity: ActivityCounters = ActivityCounters()
    routes_created: RoutesCreatedCounters = RoutesCreatedCounters()
    updated_at: Optional[datetime] = None

    class Settings:
        name = "userStats"
        indexes = [
            IndexModel([("userId", ASCENDING)], unique=True),
        ]
        keep_nulls = True
```

- [ ] **Step 4: Register with Beanie in `main.py`**

Modify `services/api/app/main.py`. Add import after line 14:

```python
from app.models.user_stats import UserStats as UserStatsModel
```

Append `UserStatsModel` to the `document_models` list on line 33:

```python
document_models=[OpenIdNonceModel, UserModel, HoldPolygonModel, ImageModel, RouteModel, PlaceModel, PlaceSuggestionModel, ActivityModel, UserRouteStatsModel, NotificationModel, UserStatsModel],
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py::test_user_stats_roundtrip -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/models/user_stats.py services/api/app/main.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): add UserStats model"
```

---

## Task 3: Pure helper `_bucket_deltas`

**Files:**
- Create: `services/api/app/services/__init__.py`
- Create: `services/api/app/services/user_stats.py`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Add failing test**

Append to `services/api/tests/services/test_user_stats.py`:

```python
from app.models.activity import ActivityStatus
from app.services.user_stats import _bucket_deltas


def test_bucket_deltas_attempted():
    assert _bucket_deltas(ActivityStatus.ATTEMPTED, location_verified=True, sign=1) == {
        "total_count": 1,
        "completed_count": 0,
        "verified_completed_count": 0,
    }


def test_bucket_deltas_completed_unverified():
    assert _bucket_deltas(ActivityStatus.COMPLETED, location_verified=False, sign=1) == {
        "total_count": 1,
        "completed_count": 1,
        "verified_completed_count": 0,
    }


def test_bucket_deltas_completed_verified():
    assert _bucket_deltas(ActivityStatus.COMPLETED, location_verified=True, sign=1) == {
        "total_count": 1,
        "completed_count": 1,
        "verified_completed_count": 1,
    }


def test_bucket_deltas_negative_sign():
    assert _bucket_deltas(ActivityStatus.COMPLETED, location_verified=True, sign=-1) == {
        "total_count": -1,
        "completed_count": -1,
        "verified_completed_count": -1,
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k bucket_deltas`
Expected: FAIL with `ModuleNotFoundError: No module named 'app.services'`.

- [ ] **Step 3: Create package marker**

Create `services/api/app/services/__init__.py` as empty file.

- [ ] **Step 4: Implement helper**

Create `services/api/app/services/user_stats.py`:

```python
"""User-level route statistics service.

Maintains the ``userStats`` collection via post-write ``$inc`` hooks at
activity and route mutation points. See
``docs/2026-04-19-user-route-stats-design.md`` for semantics.
"""

from __future__ import annotations

from app.models.activity import ActivityStatus


BUCKET_FIELDS = ("total_count", "completed_count", "verified_completed_count")


def _bucket_deltas(status: ActivityStatus, location_verified: bool, sign: int) -> dict[str, int]:
    """Return {total_count, completed_count, verified_completed_count} delta for one activity.

    ``sign`` is +1 on create, -1 on delete. A non-completed activity contributes
    only to ``total_count``; verified_completed requires both completed status
    and a verified location.
    """
    completed = 1 if status == ActivityStatus.COMPLETED else 0
    verified_completed = 1 if completed and location_verified else 0
    return {
        "total_count": sign,
        "completed_count": sign * completed,
        "verified_completed_count": sign * verified_completed,
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k bucket_deltas`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/services/__init__.py services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): add user_stats service scaffold with _bucket_deltas"
```

---

## Task 4: Pure helper `_local_date_str`

**Files:**
- Modify: `services/api/app/services/user_stats.py`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Add failing tests**

Append to `services/api/tests/services/test_user_stats.py`:

```python
from datetime import datetime, timezone as dt_tz

from app.models.activity import Activity, RouteSnapshot
from app.services.user_stats import _local_date_str


def _make_activity(started_at: datetime, tz: str | None) -> Activity:
    return Activity(
        route_id=PydanticObjectId(),
        user_id=PydanticObjectId(),
        status=ActivityStatus.COMPLETED,
        location_verified=False,
        started_at=started_at,
        ended_at=started_at,
        duration=0.0,
        timezone=tz,
        route_snapshot=RouteSnapshot(grade_type="v_scale", grade="V1"),
        created_at=started_at,
    )


def test_local_date_str_with_seoul_timezone_crosses_utc_midnight():
    # 2026-04-18T15:30Z == 2026-04-19 00:30 KST → "2026-04-19"
    started = datetime(2026, 4, 18, 15, 30, tzinfo=dt_tz.utc)
    activity = _make_activity(started, "Asia/Seoul")
    assert _local_date_str(activity) == "2026-04-19"


def test_local_date_str_with_utc_explicit():
    started = datetime(2026, 4, 19, 10, 0, tzinfo=dt_tz.utc)
    activity = _make_activity(started, "UTC")
    assert _local_date_str(activity) == "2026-04-19"


def test_local_date_str_with_none_falls_back_to_utc():
    started = datetime(2026, 4, 19, 10, 0, tzinfo=dt_tz.utc)
    activity = _make_activity(started, None)
    assert _local_date_str(activity) == "2026-04-19"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k local_date_str`
Expected: FAIL with `ImportError: cannot import name '_local_date_str'`.

- [ ] **Step 3: Implement helper**

Modify `services/api/app/services/user_stats.py`. Add imports at top:

```python
from zoneinfo import ZoneInfo

from app.models.activity import Activity, ActivityStatus
```

Append the helper:

```python
def _local_date_str(activity: Activity) -> str:
    """Return the activity's started_at local date in ISO ``YYYY-MM-DD`` form.

    Uses the activity's stored ``timezone`` field (IANA). Falls back to UTC
    when unset, matching the aggregation pattern used in ``routers/my.py``.
    """
    tz_name = activity.timezone or "UTC"
    return activity.started_at.astimezone(ZoneInfo(tz_name)).date().isoformat()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k local_date_str`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): add _local_date_str helper in user_stats service"
```

---

## Task 5: `_apply_user_route_stats_delta`

Returns `(before, after)` snapshots of UserRouteStats bucket counts for the given user/route. Atomic via `find_one_and_update(..., return_document=AFTER, upsert=True)`.

**Files:**
- Modify: `services/api/app/services/user_stats.py`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Add failing tests**

Append to `services/api/tests/services/test_user_stats.py`:

```python
from app.models.activity import UserRouteStats
from app.services.user_stats import _apply_user_route_stats_delta


@pytest.mark.asyncio
async def test_apply_urs_delta_inserts_first_time(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    deltas = {"total_count": 1, "completed_count": 1, "verified_completed_count": 0}

    before, after = await _apply_user_route_stats_delta(user_id, route_id, deltas)

    assert before == {"total_count": 0, "completed_count": 0, "verified_completed_count": 0}
    assert after == {"total_count": 1, "completed_count": 1, "verified_completed_count": 0}

    doc = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    )
    assert doc is not None
    assert doc.total_count == 1
    assert doc.completed_count == 1


@pytest.mark.asyncio
async def test_apply_urs_delta_increments_existing(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    deltas = {"total_count": 1, "completed_count": 0, "verified_completed_count": 0}

    await _apply_user_route_stats_delta(user_id, route_id, deltas)
    before, after = await _apply_user_route_stats_delta(user_id, route_id, deltas)

    assert before == {"total_count": 1, "completed_count": 0, "verified_completed_count": 0}
    assert after == {"total_count": 2, "completed_count": 0, "verified_completed_count": 0}


@pytest.mark.asyncio
async def test_apply_urs_delta_decrements_to_zero(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    await _apply_user_route_stats_delta(
        user_id, route_id, {"total_count": 1, "completed_count": 1, "verified_completed_count": 1}
    )

    before, after = await _apply_user_route_stats_delta(
        user_id, route_id, {"total_count": -1, "completed_count": -1, "verified_completed_count": -1}
    )

    assert before == {"total_count": 1, "completed_count": 1, "verified_completed_count": 1}
    assert after == {"total_count": 0, "completed_count": 0, "verified_completed_count": 0}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k apply_urs_delta`
Expected: FAIL with `ImportError`.

- [ ] **Step 3: Implement helper**

Modify `services/api/app/services/user_stats.py`. Add imports:

```python
from beanie.odm.fields import PydanticObjectId
from pymongo import ReturnDocument

from app.models.activity import UserRouteStats
```

Append:

```python
_URS_BUCKET_DB_FIELDS = {
    "total_count": "totalCount",
    "completed_count": "completedCount",
    "verified_completed_count": "verifiedCompletedCount",
}


async def _apply_user_route_stats_delta(
    user_id: PydanticObjectId,
    route_id: PydanticObjectId,
    deltas: dict[str, int],
) -> tuple[dict[str, int], dict[str, int]]:
    """Atomically apply ``$inc`` on UserRouteStats bucket counters for (user, route).

    Upserts the doc if missing. Returns ``(before, after)`` bucket counts as
    snake_case-keyed dicts. ``before = after - deltas``.
    """
    inc = {_URS_BUCKET_DB_FIELDS[k]: v for k, v in deltas.items()}

    collection = UserRouteStats.get_motor_collection()
    updated = await collection.find_one_and_update(
        {"userId": user_id, "routeId": route_id},
        {"$inc": inc, "$setOnInsert": {"userId": user_id, "routeId": route_id}},
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )

    after = {k: updated.get(_URS_BUCKET_DB_FIELDS[k], 0) for k in BUCKET_FIELDS}
    before = {k: after[k] - deltas[k] for k in BUCKET_FIELDS}
    return before, after
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k apply_urs_delta`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): add _apply_user_route_stats_delta helper"
```

---

## Task 6: `_recount_local_day`

Counts how many of a user's activities fall on a given local date (local = via each activity's stored timezone).

**Files:**
- Modify: `services/api/app/services/user_stats.py`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Add failing tests**

Append to `services/api/tests/services/test_user_stats.py`:

```python
from app.services.user_stats import _recount_local_day


@pytest.mark.asyncio
async def test_recount_local_day_counts_same_user_same_date(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    snap = RouteSnapshot(grade_type="v_scale", grade="V1")

    # Two activities on 2026-04-19 KST
    await Activity(
        route_id=route_id,
        user_id=user_id,
        status=ActivityStatus.COMPLETED,
        location_verified=True,
        started_at=datetime(2026, 4, 18, 15, 30, tzinfo=dt_tz.utc),
        ended_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
        duration=1800.0,
        timezone="Asia/Seoul",
        route_snapshot=snap,
        created_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
    ).insert()
    await Activity(
        route_id=route_id,
        user_id=user_id,
        status=ActivityStatus.ATTEMPTED,
        location_verified=False,
        started_at=datetime(2026, 4, 18, 20, 0, tzinfo=dt_tz.utc),  # 2026-04-19 05:00 KST
        ended_at=datetime(2026, 4, 18, 20, 30, tzinfo=dt_tz.utc),
        duration=1800.0,
        timezone="Asia/Seoul",
        route_snapshot=snap,
        created_at=datetime(2026, 4, 18, 20, 30, tzinfo=dt_tz.utc),
    ).insert()

    assert await _recount_local_day(user_id, "2026-04-19") == 2
    assert await _recount_local_day(user_id, "2026-04-18") == 0


@pytest.mark.asyncio
async def test_recount_local_day_ignores_other_users(mongo_db):
    user_id = PydanticObjectId()
    other_id = PydanticObjectId()
    snap = RouteSnapshot(grade_type="v_scale", grade="V1")
    started = datetime(2026, 4, 19, 1, 0, tzinfo=dt_tz.utc)
    await Activity(
        route_id=PydanticObjectId(),
        user_id=other_id,
        status=ActivityStatus.COMPLETED,
        location_verified=True,
        started_at=started,
        ended_at=started,
        duration=0.0,
        timezone="UTC",
        route_snapshot=snap,
        created_at=started,
    ).insert()

    assert await _recount_local_day(user_id, "2026-04-19") == 0


@pytest.mark.asyncio
async def test_recount_local_day_falls_back_to_utc_when_timezone_null(mongo_db):
    user_id = PydanticObjectId()
    snap = RouteSnapshot(grade_type="v_scale", grade="V1")
    started = datetime(2026, 4, 19, 23, 0, tzinfo=dt_tz.utc)  # still 2026-04-19 in UTC
    await Activity(
        route_id=PydanticObjectId(),
        user_id=user_id,
        status=ActivityStatus.COMPLETED,
        location_verified=True,
        started_at=started,
        ended_at=started,
        duration=0.0,
        timezone=None,
        route_snapshot=snap,
        created_at=started,
    ).insert()

    assert await _recount_local_day(user_id, "2026-04-19") == 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k recount_local_day`
Expected: FAIL with `ImportError`.

- [ ] **Step 3: Implement helper**

Modify `services/api/app/services/user_stats.py`. Append:

```python
async def _recount_local_day(user_id: PydanticObjectId, local_date_str: str) -> int:
    """Return how many of ``user_id``'s activities have ``_local_date_str`` equal to ``local_date_str``.

    Computes the local date server-side via Mongo's ``$dateToString`` using the
    activity's stored ``timezone`` (UTC fallback), and counts matches.
    """
    collection = Activity.get_motor_collection()
    pipeline = [
        {"$match": {"userId": user_id}},
        {
            "$addFields": {
                "_localDate": {
                    "$dateToString": {
                        "format": "%Y-%m-%d",
                        "date": "$startedAt",
                        "timezone": {"$ifNull": ["$timezone", "UTC"]},
                    }
                }
            }
        },
        {"$match": {"_localDate": local_date_str}},
        {"$count": "count"},
    ]
    cursor = collection.aggregate(pipeline)
    async for doc in cursor:
        return int(doc["count"])
    return 0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k recount_local_day`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): add _recount_local_day helper"
```

---

## Task 7: `on_activity_created`

**Files:**
- Modify: `services/api/app/services/user_stats.py`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Add failing tests**

Append to `services/api/tests/services/test_user_stats.py`:

```python
from app.models.route import Route, RouteType, Visibility
from app.services.user_stats import on_activity_created


def _make_route(owner_id: PydanticObjectId, type_: RouteType = RouteType.BOULDERING, is_deleted: bool = False) -> Route:
    return Route(
        type=type_,
        grade_type="v_scale",
        grade="V1",
        visibility=Visibility.PUBLIC,
        image_id=PydanticObjectId(),
        hold_polygon_id=PydanticObjectId(),
        user_id=owner_id,
        image_url="https://example.com/a.jpg",
        is_deleted=is_deleted,
    )


async def _insert_activity(
    user_id: PydanticObjectId,
    route_id: PydanticObjectId,
    *,
    status: ActivityStatus = ActivityStatus.COMPLETED,
    location_verified: bool = True,
    started_at: datetime | None = None,
    tz: str = "Asia/Seoul",
) -> Activity:
    started = started_at or datetime(2026, 4, 18, 15, 30, tzinfo=dt_tz.utc)
    activity = Activity(
        route_id=route_id,
        user_id=user_id,
        status=status,
        location_verified=location_verified,
        started_at=started,
        ended_at=started,
        duration=0.0,
        timezone=tz,
        route_snapshot=RouteSnapshot(grade_type="v_scale", grade="V1"),
        created_at=started,
    )
    await activity.insert()
    return activity


@pytest.mark.asyncio
async def test_on_activity_created_first_activity(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())  # someone else's route
    await route.insert()

    activity = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(activity, route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats is not None
    assert stats.activity.total_count == 1
    assert stats.activity.completed_count == 1
    assert stats.activity.verified_completed_count == 1
    assert stats.distinct_routes.total_count == 1
    assert stats.distinct_routes.completed_count == 1
    assert stats.distinct_routes.verified_completed_count == 1
    assert stats.distinct_days == 1
    assert stats.own_routes_activity.total_count == 0  # not user's own route


@pytest.mark.asyncio
async def test_on_activity_created_second_activity_same_route_same_day(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    a1 = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(
        user_id, route.id, status=ActivityStatus.ATTEMPTED, location_verified=False,
        started_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),  # same KST day
    )
    await on_activity_created(a2, route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.activity.total_count == 2
    assert stats.activity.completed_count == 1
    assert stats.activity.verified_completed_count == 1
    assert stats.distinct_routes.total_count == 1  # still same route
    assert stats.distinct_days == 1  # still same day


@pytest.mark.asyncio
async def test_on_activity_created_on_own_alive_route_increments_own_routes_activity(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id)  # own route
    await route.insert()

    activity = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(activity, route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.own_routes_activity.total_count == 1
    assert stats.own_routes_activity.completed_count == 1
    assert stats.own_routes_activity.verified_completed_count == 1


@pytest.mark.asyncio
async def test_on_activity_created_on_own_soft_deleted_route_skips_own_routes_activity(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, is_deleted=True)
    await route.insert()

    activity = await _insert_activity(user_id, route.id)
    await on_activity_created(activity, route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.own_routes_activity.total_count == 0
    assert stats.activity.total_count == 1  # still counted in the general activity bucket
    assert stats.distinct_routes.total_count == 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k on_activity_created`
Expected: FAIL with `ImportError`.

- [ ] **Step 3: Implement**

Modify `services/api/app/services/user_stats.py`. Add imports:

```python
import logging
from datetime import datetime, timezone

from app.models.route import Route, RouteType
from app.models.user_stats import UserStats


logger = logging.getLogger(__name__)
```

Add a private update helper (used by all `on_*` functions):

```python
async def _update_user_stats(user_id: PydanticObjectId, inc: dict[str, int]) -> None:
    """Run ``$inc`` against ``userStats`` for ``user_id``, upserting if missing.

    ``inc`` keys are dotted DB paths like ``activity.totalCount``.
    """
    if not inc:
        return
    collection = UserStats.get_motor_collection()
    await collection.update_one(
        {"userId": user_id},
        {
            "$inc": inc,
            "$set": {"updatedAt": datetime.now(tz=timezone.utc)},
            "$setOnInsert": {"userId": user_id},
        },
        upsert=True,
    )
```

Bucket-field DB-path helper constants:

```python
_ACTIVITY_BUCKET_DB_FIELDS = {
    "total_count": "activity.totalCount",
    "completed_count": "activity.completedCount",
    "verified_completed_count": "activity.verifiedCompletedCount",
}
_DISTINCT_ROUTES_DB_FIELDS = {
    "total_count": "distinctRoutes.totalCount",
    "completed_count": "distinctRoutes.completedCount",
    "verified_completed_count": "distinctRoutes.verifiedCompletedCount",
}
_OWN_ROUTES_ACTIVITY_DB_FIELDS = {
    "total_count": "ownRoutesActivity.totalCount",
    "completed_count": "ownRoutesActivity.completedCount",
    "verified_completed_count": "ownRoutesActivity.verifiedCompletedCount",
}
_ROUTES_CREATED_DB_FIELDS = {
    "total_count": "routesCreated.totalCount",
    "bouldering_count": "routesCreated.boulderingCount",
    "endurance_count": "routesCreated.enduranceCount",
}
```

Append the public function:

```python
async def on_activity_created(activity: Activity, route: Route) -> None:
    """Apply post-create userStats updates. Swallows all exceptions."""
    try:
        deltas = _bucket_deltas(activity.status, activity.location_verified, sign=1)
        before, after = await _apply_user_route_stats_delta(activity.user_id, activity.route_id, deltas)

        inc: dict[str, int] = {}
        for bucket, delta in deltas.items():
            if delta:
                inc[_ACTIVITY_BUCKET_DB_FIELDS[bucket]] = delta
            if before[bucket] == 0 and after[bucket] >= 1:
                inc[_DISTINCT_ROUTES_DB_FIELDS[bucket]] = 1
                if route.user_id == activity.user_id and not route.is_deleted:
                    inc[_OWN_ROUTES_ACTIVITY_DB_FIELDS[bucket]] = 1

        if await _recount_local_day(activity.user_id, _local_date_str(activity)) == 1:
            inc["distinctDays"] = 1

        await _update_user_stats(activity.user_id, inc)
    except Exception:
        logger.exception("on_activity_created failed for activity=%s", activity.id)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k on_activity_created`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): implement on_activity_created user_stats hook"
```

---

## Task 8: `on_activity_deleted`

**Files:**
- Modify: `services/api/app/services/user_stats.py`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Add failing tests**

Append to `services/api/tests/services/test_user_stats.py`:

```python
from app.services.user_stats import on_activity_deleted


@pytest.mark.asyncio
async def test_on_activity_deleted_sole_activity_clears_stats(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    activity = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(activity, route)

    await on_activity_deleted(activity, route)
    await activity.delete()  # mirror the real router flow (order does not matter for re-count)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.activity.total_count == 0
    assert stats.distinct_routes.total_count == 0
    assert stats.distinct_days == 0

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is None  # cleared once all buckets hit zero


@pytest.mark.asyncio
async def test_on_activity_deleted_leaves_distinct_days_when_sibling_remains(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    a1 = await _insert_activity(user_id, route.id)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(
        user_id, route.id, started_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
    )
    await on_activity_created(a2, route)

    await on_activity_deleted(a2, route)
    await a2.delete()

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.distinct_days == 1
    assert stats.distinct_routes.total_count == 1  # a1 still holds the route


@pytest.mark.asyncio
async def test_on_activity_deleted_skips_own_routes_activity_when_route_soft_deleted(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id)
    await route.insert()

    activity = await _insert_activity(user_id, route.id)
    await on_activity_created(activity, route)

    # Simulate a soft-delete that already decremented own_routes_activity.
    await UserStats.find_one(UserStats.user_id == user_id).update(
        {"$inc": {"ownRoutesActivity.totalCount": -1, "ownRoutesActivity.completedCount": -1, "ownRoutesActivity.verifiedCompletedCount": -1}}
    )
    route.is_deleted = True

    await on_activity_deleted(activity, route)
    await activity.delete()

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.own_routes_activity.total_count == 0  # stayed at 0, no double-decrement
    assert stats.own_routes_activity.completed_count == 0
    assert stats.own_routes_activity.verified_completed_count == 0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k on_activity_deleted`
Expected: FAIL with `ImportError`.

- [ ] **Step 3: Implement**

Modify `services/api/app/services/user_stats.py`. Append:

```python
async def on_activity_deleted(activity: Activity, route: Route) -> None:
    """Apply post-delete userStats updates. Swallows all exceptions.

    Re-count for ``distinct_days`` runs after the caller has already removed
    the activity doc in production. To keep the service self-consistent, we
    ignore this activity's own doc in the recount by subtracting one when
    we see it still present.
    """
    try:
        deltas = _bucket_deltas(activity.status, activity.location_verified, sign=-1)
        before, after = await _apply_user_route_stats_delta(activity.user_id, activity.route_id, deltas)

        inc: dict[str, int] = {}
        for bucket, delta in deltas.items():
            if delta:
                inc[_ACTIVITY_BUCKET_DB_FIELDS[bucket]] = delta
            if before[bucket] >= 1 and after[bucket] == 0:
                inc[_DISTINCT_ROUTES_DB_FIELDS[bucket]] = -1
                if route.user_id == activity.user_id and not route.is_deleted:
                    inc[_OWN_ROUTES_ACTIVITY_DB_FIELDS[bucket]] = -1

        # Drop an empty UserRouteStats doc (mirrors previous router behavior).
        if after["total_count"] == 0 and after["completed_count"] == 0 and after["verified_completed_count"] == 0:
            urs_doc = await UserRouteStats.find_one(
                UserRouteStats.user_id == activity.user_id,
                UserRouteStats.route_id == activity.route_id,
            )
            if urs_doc is not None:
                await urs_doc.delete()

        # distinct_days: the caller deletes the activity doc AFTER calling this
        # (see routers/activities.py:delete_activity), so when recount == 1 and
        # that remaining doc IS this one, treat as "now zero". Mongo's count
        # runs against current state: if activity is still present, counted;
        # if already deleted, not counted. We support both orderings by
        # subtracting 1 if the activity doc still exists.
        local_date = _local_date_str(activity)
        remaining = await _recount_local_day(activity.user_id, local_date)
        still_present = await Activity.find_one(Activity.id == activity.id) is not None
        effective = remaining - 1 if still_present else remaining
        if effective == 0:
            inc["distinctDays"] = -1

        await _update_user_stats(activity.user_id, inc)
    except Exception:
        logger.exception("on_activity_deleted failed for activity=%s", activity.id)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k on_activity_deleted`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): implement on_activity_deleted user_stats hook"
```

---

## Task 9: `on_route_created`

**Files:**
- Modify: `services/api/app/services/user_stats.py`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Add failing tests**

Append to `services/api/tests/services/test_user_stats.py`:

```python
from app.services.user_stats import on_route_created


@pytest.mark.asyncio
async def test_on_route_created_bouldering(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, type_=RouteType.BOULDERING)
    await route.insert()

    await on_route_created(route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.routes_created.total_count == 1
    assert stats.routes_created.bouldering_count == 1
    assert stats.routes_created.endurance_count == 0


@pytest.mark.asyncio
async def test_on_route_created_endurance(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, type_=RouteType.ENDURANCE)
    await route.insert()

    await on_route_created(route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.routes_created.total_count == 1
    assert stats.routes_created.bouldering_count == 0
    assert stats.routes_created.endurance_count == 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k on_route_created`
Expected: FAIL with `ImportError`.

- [ ] **Step 3: Implement**

Modify `services/api/app/services/user_stats.py`. Append:

```python
def _type_bucket(route_type: RouteType) -> str:
    if route_type == RouteType.BOULDERING:
        return "bouldering_count"
    if route_type == RouteType.ENDURANCE:
        return "endurance_count"
    raise ValueError(f"Unknown RouteType: {route_type!r}")


async def on_route_created(route: Route) -> None:
    """Apply post-create userStats updates for a route. Swallows all exceptions."""
    try:
        type_bucket = _type_bucket(route.type)
        inc = {
            _ROUTES_CREATED_DB_FIELDS["total_count"]: 1,
            _ROUTES_CREATED_DB_FIELDS[type_bucket]: 1,
        }
        await _update_user_stats(route.user_id, inc)
    except Exception:
        logger.exception("on_route_created failed for route=%s", route.id)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k on_route_created`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): implement on_route_created user_stats hook"
```

---

## Task 10: `on_route_soft_deleted`

**Files:**
- Modify: `services/api/app/services/user_stats.py`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Add failing tests**

Append to `services/api/tests/services/test_user_stats.py`:

```python
from app.services.user_stats import on_route_soft_deleted


@pytest.mark.asyncio
async def test_on_route_soft_deleted_decrements_routes_created(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, type_=RouteType.BOULDERING)
    await route.insert()
    await on_route_created(route)

    route.is_deleted = True
    await on_route_soft_deleted(route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.routes_created.total_count == 0
    assert stats.routes_created.bouldering_count == 0


@pytest.mark.asyncio
async def test_on_route_soft_deleted_decrements_own_routes_activity_per_bucket(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, type_=RouteType.BOULDERING)
    await route.insert()
    await on_route_created(route)

    # Own activity on own route → own_routes_activity all buckets at 1.
    a = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(a, route)

    route.is_deleted = True
    await on_route_soft_deleted(route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.own_routes_activity.total_count == 0
    assert stats.own_routes_activity.completed_count == 0
    assert stats.own_routes_activity.verified_completed_count == 0
    # routes_created also decremented, distinct_routes/activity unchanged
    assert stats.routes_created.total_count == 0
    assert stats.distinct_routes.total_count == 1
    assert stats.activity.total_count == 1


@pytest.mark.asyncio
async def test_on_route_soft_deleted_no_own_activity_leaves_own_routes_activity_untouched(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, type_=RouteType.ENDURANCE)
    await route.insert()
    await on_route_created(route)

    route.is_deleted = True
    await on_route_soft_deleted(route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.own_routes_activity.total_count == 0
    assert stats.routes_created.total_count == 0
    assert stats.routes_created.endurance_count == 0


@pytest.mark.asyncio
async def test_on_route_soft_deleted_only_decrements_buckets_ge_one(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, type_=RouteType.BOULDERING)
    await route.insert()
    await on_route_created(route)

    # Attempted (not completed) own activity: UserRouteStats has total=1 but completed=verified=0.
    a = await _insert_activity(user_id, route.id, status=ActivityStatus.ATTEMPTED, location_verified=False)
    await on_activity_created(a, route)

    route.is_deleted = True
    await on_route_soft_deleted(route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.own_routes_activity.total_count == 0  # decremented from 1
    assert stats.own_routes_activity.completed_count == 0  # stays at 0
    assert stats.own_routes_activity.verified_completed_count == 0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k on_route_soft_deleted`
Expected: FAIL with `ImportError`.

- [ ] **Step 3: Implement**

Modify `services/api/app/services/user_stats.py`. Append:

```python
async def on_route_soft_deleted(route: Route) -> None:
    """Apply post-soft-delete userStats updates for a route. Swallows all exceptions."""
    try:
        type_bucket = _type_bucket(route.type)
        inc: dict[str, int] = {
            _ROUTES_CREATED_DB_FIELDS["total_count"]: -1,
            _ROUTES_CREATED_DB_FIELDS[type_bucket]: -1,
        }

        urs = await UserRouteStats.find_one(
            UserRouteStats.user_id == route.user_id,
            UserRouteStats.route_id == route.id,
        )
        if urs is not None:
            bucket_values = {
                "total_count": urs.total_count,
                "completed_count": urs.completed_count,
                "verified_completed_count": urs.verified_completed_count,
            }
            for bucket, value in bucket_values.items():
                if value >= 1:
                    inc[_OWN_ROUTES_ACTIVITY_DB_FIELDS[bucket]] = -1

        await _update_user_stats(route.user_id, inc)
    except Exception:
        logger.exception("on_route_soft_deleted failed for route=%s", route.id)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k on_route_soft_deleted`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): implement on_route_soft_deleted user_stats hook"
```

---

## Task 11: Verify error swallowing

**Files:**
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Add test**

Append to `services/api/tests/services/test_user_stats.py`:

```python
from unittest.mock import patch


@pytest.mark.asyncio
async def test_on_activity_created_swallows_inner_errors(mongo_db, caplog):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id)
    await route.insert()
    activity = await _insert_activity(user_id, route.id)

    with patch(
        "app.services.user_stats._apply_user_route_stats_delta",
        side_effect=RuntimeError("boom"),
    ):
        caplog.clear()
        result = await on_activity_created(activity, route)

    assert result is None
    assert any("on_activity_created failed" in rec.message for rec in caplog.records)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    # No partial write: we bailed before any userStats write.
    assert stats is None


@pytest.mark.asyncio
async def test_on_route_created_swallows_inner_errors(mongo_db, caplog):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id)

    with patch(
        "app.services.user_stats._update_user_stats",
        side_effect=RuntimeError("boom"),
    ):
        caplog.clear()
        result = await on_route_created(route)

    assert result is None
    assert any("on_route_created failed" in rec.message for rec in caplog.records)
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k swallows`
Expected: PASS (2 tests).

(Nothing to implement — the `try/except logger.exception` wrappers were added in Tasks 7–10.)

- [ ] **Step 3: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/tests/services/test_user_stats.py
git commit -m "test(api): verify user_stats hooks swallow errors"
```

---

## Task 12: Wire service into `routers/activities.py`

Move `_update_user_route_stats` logic into the service (done in Task 7's `_apply_user_route_stats_delta`). Router now calls the service hooks.

**Files:**
- Modify: `services/api/app/routers/activities.py`

- [ ] **Step 1: Update imports**

Modify `services/api/app/routers/activities.py`. Add after existing imports (around line 23):

```python
from app.services import user_stats as user_stats_service
```

- [ ] **Step 2: Remove the router-local `_update_user_route_stats`**

Remove lines 131-158 (the `_update_user_route_stats` function) from `services/api/app/routers/activities.py`.

Keep the `UserRouteStats` import on line 18 — `get_my_stats` at L310-329 still reads `UserRouteStats` directly.

- [ ] **Step 3: Rewrite `create_activity` stats block**

Replace lines 270-273 (the three `_update_route_stats` / `_update_user_route_stats` calls, plus the comment/header) with:

```python
    # 6. Stats 갱신
    inc = _build_stats_inc(request.status, location_verified, duration, sign=1)
    await _update_route_stats(route.id, inc)
    await user_stats_service.on_activity_created(activity, route)
```

- [ ] **Step 4: Rewrite `delete_activity` stats block**

Replace lines 293-304 (from the `inc = ...` line through the UserRouteStats cleanup) with:

```python
    # 2. Stats 감소
    inc = _build_stats_inc(activity.status, activity.location_verified, activity.duration, sign=-1)
    await _update_route_stats(activity.route_id, inc)
    await user_stats_service.on_activity_deleted(activity, route)
```

Also fetch the `route` object at the top of `delete_activity` (it was previously only referenced by id). Insert after line 291 (`if not activity:` block):

```python
    route = await Route.find_one(Route.id == activity.route_id)
    if route is None:
        # Shouldn't happen under normal flow; bail out of the stats path but still delete the activity.
        await activity.delete()
        return
```

- [ ] **Step 5: Run existing activity tests**

Run: `cd services/api && uv run pytest tests/routers/ -v`
Expected: PASS (no regressions).

- [ ] **Step 6: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/activities.py
git commit -m "refactor(api): route activity mutations through user_stats service"
```

---

## Task 13: Wire service into `routers/routes.py`

**Files:**
- Modify: `services/api/app/routers/routes.py`

- [ ] **Step 1: Update imports**

Modify `services/api/app/routers/routes.py`. Add near other service imports:

```python
from app.services import user_stats as user_stats_service
```

- [ ] **Step 2: Add hook in `create_route`**

In `create_route`, after line 155 (`created_route = await route.save()`) and before line 157, insert:

```python
    await user_stats_service.on_route_created(created_route)
```

- [ ] **Step 3: Add hook in `delete_route`**

In `delete_route`, after line 583 (`await route.save()`), insert:

```python
    await user_stats_service.on_route_soft_deleted(route)
```

- [ ] **Step 4: Run existing route tests**

Run: `cd services/api && uv run pytest tests/routers/ -v`
Expected: PASS (no regressions).

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/routes.py
git commit -m "feat(api): call user_stats hooks on route create/soft-delete"
```

---

## Task 14: Backfill script

**Files:**
- Create: `services/api/scripts/__init__.py`
- Create: `services/api/scripts/backfill_user_stats.py`
- Create: `services/api/tests/scripts/__init__.py`
- Create: `services/api/tests/scripts/test_backfill_user_stats.py`

- [ ] **Step 1: Create script and test package markers**

Create empty files: `services/api/scripts/__init__.py`, `services/api/tests/scripts/__init__.py`.

- [ ] **Step 2: Write failing test**

Create `services/api/tests/scripts/test_backfill_user_stats.py`:

```python
"""Tests for the user_stats backfill script."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz

import pytest
from beanie.odm.fields import PydanticObjectId

from app.models.activity import Activity, ActivityStatus, RouteSnapshot, UserRouteStats
from app.models.route import Route, RouteType, Visibility
from app.models.user import User
from app.models.user_stats import UserStats
from scripts.backfill_user_stats import backfill_user


pytestmark = pytest.mark.asyncio


def _make_user() -> User:
    return User(
        auth_id="auth|x",
        name="X",
        email="x@example.com",
    )


def _make_route(owner_id: PydanticObjectId, type_: RouteType = RouteType.BOULDERING, is_deleted: bool = False) -> Route:
    return Route(
        type=type_,
        grade_type="v_scale",
        grade="V1",
        visibility=Visibility.PUBLIC,
        image_id=PydanticObjectId(),
        hold_polygon_id=PydanticObjectId(),
        user_id=owner_id,
        image_url="https://example.com/a.jpg",
        is_deleted=is_deleted,
    )


async def _seed_activity(
    user_id: PydanticObjectId,
    route_id: PydanticObjectId,
    *,
    status: ActivityStatus,
    location_verified: bool,
    started_at: datetime,
    tz: str = "Asia/Seoul",
) -> None:
    await Activity(
        route_id=route_id,
        user_id=user_id,
        status=status,
        location_verified=location_verified,
        started_at=started_at,
        ended_at=started_at,
        duration=0.0,
        timezone=tz,
        route_snapshot=RouteSnapshot(grade_type="v_scale", grade="V1"),
        created_at=started_at,
    ).insert()
    # Match the live path: keep UserRouteStats consistent for backfill counting.
    inc_total = 1
    inc_completed = 1 if status == ActivityStatus.COMPLETED else 0
    inc_verified = 1 if inc_completed and location_verified else 0
    await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    ).upsert(
        {"$inc": {"totalCount": inc_total, "completedCount": inc_completed, "verifiedCompletedCount": inc_verified}},
        on_insert=UserRouteStats(
            user_id=user_id,
            route_id=route_id,
            total_count=inc_total,
            completed_count=inc_completed,
            verified_completed_count=inc_verified,
        ),
    )


async def test_backfill_user_computes_all_counters(mongo_db):
    user = _make_user()
    await user.insert()

    # Two routes: one alive boulder, one soft-deleted endurance. Both owned by user.
    own_boulder = _make_route(owner_id=user.id, type_=RouteType.BOULDERING)
    own_endurance_deleted = _make_route(owner_id=user.id, type_=RouteType.ENDURANCE, is_deleted=True)
    other_route = _make_route(owner_id=PydanticObjectId(), type_=RouteType.BOULDERING)
    await own_boulder.insert()
    await own_endurance_deleted.insert()
    await other_route.insert()

    # Activities:
    # - 1 completed+verified on own_boulder (day 2026-04-19 KST)
    # - 1 attempted on own_boulder (same day)
    # - 1 completed (no verify) on other_route (day 2026-04-20 KST)
    await _seed_activity(
        user.id, own_boulder.id, status=ActivityStatus.COMPLETED, location_verified=True,
        started_at=datetime(2026, 4, 18, 15, 0, tzinfo=dt_tz.utc),
    )
    await _seed_activity(
        user.id, own_boulder.id, status=ActivityStatus.ATTEMPTED, location_verified=False,
        started_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
    )
    await _seed_activity(
        user.id, other_route.id, status=ActivityStatus.COMPLETED, location_verified=False,
        started_at=datetime(2026, 4, 19, 15, 0, tzinfo=dt_tz.utc),
    )

    await backfill_user(user.id)

    stats = await UserStats.find_one(UserStats.user_id == user.id)
    assert stats is not None
    assert stats.activity.total_count == 3
    assert stats.activity.completed_count == 2
    assert stats.activity.verified_completed_count == 1

    assert stats.distinct_routes.total_count == 2  # own_boulder + other_route
    assert stats.distinct_routes.completed_count == 2
    assert stats.distinct_routes.verified_completed_count == 1

    assert stats.distinct_days == 2

    # own_routes_activity scoped to currently-alive own routes.
    # own_boulder (alive) has completed+verified → all three buckets = 1.
    # own_endurance_deleted has no activity. other_route is not own.
    assert stats.own_routes_activity.total_count == 1
    assert stats.own_routes_activity.completed_count == 1
    assert stats.own_routes_activity.verified_completed_count == 1

    # routes_created: only alive routes counted.
    assert stats.routes_created.total_count == 1
    assert stats.routes_created.bouldering_count == 1
    assert stats.routes_created.endurance_count == 0


async def test_backfill_user_is_idempotent(mongo_db):
    user = _make_user()
    await user.insert()
    route = _make_route(owner_id=user.id)
    await route.insert()
    await _seed_activity(
        user.id, route.id, status=ActivityStatus.COMPLETED, location_verified=True,
        started_at=datetime(2026, 4, 18, 15, 0, tzinfo=dt_tz.utc),
    )

    await backfill_user(user.id)
    first = await UserStats.find_one(UserStats.user_id == user.id)
    await backfill_user(user.id)
    second = await UserStats.find_one(UserStats.user_id == user.id)

    assert first.model_dump(exclude={"updated_at", "id"}) == second.model_dump(exclude={"updated_at", "id"})
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd services/api && uv run pytest tests/scripts/test_backfill_user_stats.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'scripts.backfill_user_stats'`.

- [ ] **Step 4: Implement script**

Create `services/api/scripts/backfill_user_stats.py`:

```python
"""Idempotent backfill for the ``userStats`` collection.

Recomputes stats from ``activities`` / ``userRouteStats`` / ``routes`` per user.
Safe to run repeatedly. Exposes a ``backfill_user`` coroutine for programmatic
use (and tests) plus a ``main`` entry that iterates all users.

Usage:
    python -m scripts.backfill_user_stats              # all users
    python -m scripts.backfill_user_stats --user-id X  # one user
"""

from __future__ import annotations

import argparse
import asyncio
import logging
from datetime import datetime, timezone
from typing import Optional

from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from motor.motor_asyncio import AsyncIOMotorClient

from app.core.config import get
from app.models.activity import Activity, ActivityStatus, UserRouteStats
from app.models.notification import Notification
from app.models.hold_polygon import HoldPolygon
from app.models.image import Image
from app.models.open_id_nonce import OpenIdNonce
from app.models.place import Place, PlaceSuggestion
from app.models.route import Route
from app.models.user import User
from app.models.user_stats import (
    ActivityCounters,
    RoutesCreatedCounters,
    UserStats,
)


logger = logging.getLogger(__name__)


async def _activity_counters(user_id: PydanticObjectId) -> ActivityCounters:
    collection = Activity.get_motor_collection()
    pipeline = [
        {"$match": {"userId": user_id}},
        {
            "$group": {
                "_id": None,
                "total": {"$sum": 1},
                "completed": {
                    "$sum": {"$cond": [{"$eq": ["$status", ActivityStatus.COMPLETED.value]}, 1, 0]}
                },
                "verified_completed": {
                    "$sum": {
                        "$cond": [
                            {
                                "$and": [
                                    {"$eq": ["$status", ActivityStatus.COMPLETED.value]},
                                    {"$eq": ["$locationVerified", True]},
                                ]
                            },
                            1,
                            0,
                        ]
                    }
                },
            }
        },
    ]
    async for doc in collection.aggregate(pipeline):
        return ActivityCounters(
            total_count=doc["total"],
            completed_count=doc["completed"],
            verified_completed_count=doc["verified_completed"],
        )
    return ActivityCounters()


async def _distinct_routes_counters(user_id: PydanticObjectId) -> ActivityCounters:
    collection = UserRouteStats.get_motor_collection()
    pipeline = [
        {"$match": {"userId": user_id}},
        {
            "$group": {
                "_id": None,
                "total": {"$sum": {"$cond": [{"$gte": ["$totalCount", 1]}, 1, 0]}},
                "completed": {"$sum": {"$cond": [{"$gte": ["$completedCount", 1]}, 1, 0]}},
                "verified_completed": {
                    "$sum": {"$cond": [{"$gte": ["$verifiedCompletedCount", 1]}, 1, 0]}
                },
            }
        },
    ]
    async for doc in collection.aggregate(pipeline):
        return ActivityCounters(
            total_count=doc["total"],
            completed_count=doc["completed"],
            verified_completed_count=doc["verified_completed"],
        )
    return ActivityCounters()


async def _distinct_days(user_id: PydanticObjectId) -> int:
    collection = Activity.get_motor_collection()
    pipeline = [
        {"$match": {"userId": user_id}},
        {
            "$addFields": {
                "_localDate": {
                    "$dateToString": {
                        "format": "%Y-%m-%d",
                        "date": "$startedAt",
                        "timezone": {"$ifNull": ["$timezone", "UTC"]},
                    }
                }
            }
        },
        {"$group": {"_id": "$_localDate"}},
        {"$count": "days"},
    ]
    async for doc in collection.aggregate(pipeline):
        return int(doc["days"])
    return 0


async def _own_routes_activity_counters(user_id: PydanticObjectId) -> ActivityCounters:
    collection = UserRouteStats.get_motor_collection()
    pipeline = [
        {"$match": {"userId": user_id}},
        {
            "$lookup": {
                "from": "routes",
                "localField": "routeId",
                "foreignField": "_id",
                "as": "route",
            }
        },
        {"$unwind": "$route"},
        {"$match": {"route.userId": user_id, "route.isDeleted": {"$ne": True}}},
        {
            "$group": {
                "_id": None,
                "total": {"$sum": {"$cond": [{"$gte": ["$totalCount", 1]}, 1, 0]}},
                "completed": {"$sum": {"$cond": [{"$gte": ["$completedCount", 1]}, 1, 0]}},
                "verified_completed": {
                    "$sum": {"$cond": [{"$gte": ["$verifiedCompletedCount", 1]}, 1, 0]}
                },
            }
        },
    ]
    async for doc in collection.aggregate(pipeline):
        return ActivityCounters(
            total_count=doc["total"],
            completed_count=doc["completed"],
            verified_completed_count=doc["verified_completed"],
        )
    return ActivityCounters()


async def _routes_created_counters(user_id: PydanticObjectId) -> RoutesCreatedCounters:
    collection = Route.get_motor_collection()
    pipeline = [
        {"$match": {"userId": user_id, "isDeleted": {"$ne": True}}},
        {
            "$group": {
                "_id": None,
                "total": {"$sum": 1},
                "bouldering": {"$sum": {"$cond": [{"$eq": ["$type", "bouldering"]}, 1, 0]}},
                "endurance": {"$sum": {"$cond": [{"$eq": ["$type", "endurance"]}, 1, 0]}},
            }
        },
    ]
    async for doc in collection.aggregate(pipeline):
        return RoutesCreatedCounters(
            total_count=doc["total"],
            bouldering_count=doc["bouldering"],
            endurance_count=doc["endurance"],
        )
    return RoutesCreatedCounters()


async def backfill_user(user_id: PydanticObjectId) -> None:
    """Recompute and replace the ``userStats`` document for ``user_id``."""
    activity = await _activity_counters(user_id)
    distinct_routes = await _distinct_routes_counters(user_id)
    distinct_days = await _distinct_days(user_id)
    own_routes_activity = await _own_routes_activity_counters(user_id)
    routes_created = await _routes_created_counters(user_id)

    collection = UserStats.get_motor_collection()
    await collection.replace_one(
        {"userId": user_id},
        {
            "userId": user_id,
            "activity": activity.model_dump(by_alias=True),
            "distinctRoutes": distinct_routes.model_dump(by_alias=True),
            "distinctDays": distinct_days,
            "ownRoutesActivity": own_routes_activity.model_dump(by_alias=True),
            "routesCreated": routes_created.model_dump(by_alias=True),
            "updatedAt": datetime.now(tz=timezone.utc),
        },
        upsert=True,
    )


async def backfill_all() -> None:
    processed = 0
    async for user in User.find_all():
        await backfill_user(user.id)
        processed += 1
        if processed % 50 == 0:
            logger.info("backfilled %d users so far", processed)
    logger.info("backfill complete: %d users", processed)


async def main(user_id: Optional[str] = None) -> None:
    client = AsyncIOMotorClient(get("mongodb.url"), tz_aware=True)
    db = client.get_database(get("mongodb.name"))
    await init_beanie(
        database=db,
        document_models=[
            OpenIdNonce,
            User,
            HoldPolygon,
            Image,
            Route,
            Place,
            PlaceSuggestion,
            Activity,
            UserRouteStats,
            Notification,
            UserStats,
        ],
    )

    if user_id is not None:
        await backfill_user(PydanticObjectId(user_id))
    else:
        await backfill_all()

    client.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser()
    parser.add_argument("--user-id", dest="user_id", default=None)
    args = parser.parse_args()
    asyncio.run(main(args.user_id))
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/scripts/test_backfill_user_stats.py -v`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/scripts/__init__.py services/api/scripts/backfill_user_stats.py services/api/tests/scripts/__init__.py services/api/tests/scripts/test_backfill_user_stats.py
git commit -m "feat(api): add idempotent user_stats backfill script"
```

---

## Task 15: Final verification

- [ ] **Step 1: Run the full test suite**

Run: `cd services/api && uv run pytest -v`
Expected: PASS across all tests, including pre-existing ones.

- [ ] **Step 2: Sanity-check Beanie registration on app startup**

Run: `cd services/api && uv run python -c "from app.main import app; print('ok')"`
Expected: `ok` (no import errors).

- [ ] **Step 3: Commit (only if fixes were needed)**

If any issue surfaced in Steps 1–2 that required a fix, commit it:

```bash
cd /Users/htjo/besetter
git add -p  # review, then commit
git commit -m "fix(api): address user_stats integration issue"
```

Otherwise no commit.
