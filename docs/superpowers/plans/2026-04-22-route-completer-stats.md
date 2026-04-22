# Route Completer Stats & Verified Completers List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Maintain three per-route distinct-user counters (`participantCount`, `completerCount`, `verifiedCompleterCount`) via the existing `$inc` hooks in `user_stats.py`, and expose a paginated list of verified completers on the route detail screen.

**Architecture:** Add a new embedded `CompleterStats` field on `Route`. Extend `on_activity_created` / `on_activity_deleted` in `app/services/user_stats.py` to issue a Route `$inc` inside the already-atomic 0↔1 bucket-transition block. Add a new `GET /routes/{id}/verified-completers` endpoint with cursor pagination. On mobile, add a new section below `WorkoutLogPanel` that shows the verified-completer count and a horizontal avatar row; tapping the `+N 더 보기` chip opens a paginated bottom sheet.

**Tech Stack:** FastAPI · Beanie (MongoDB) · pymongo · pytest / mongomock_motor (backend); Flutter · hooks_riverpod (mobile); ARB files for i18n.

**Spec:** `docs/superpowers/specs/2026-04-22-route-completer-stats-design.md`

**Naming convention (load-bearing):** MongoDB collection and field names are **camelCase**. Python class fields are **snake_case**. The mapping is handled by `model_config` aliases on Pydantic/Beanie models. Every string passed to `$inc`, `$set`, `$match`, aggregation pipelines, cursor parsing, or index definitions is camelCase.

---

## File Structure

**Backend (`services/api`)**
- Modify: `app/models/route.py` — add `CompleterStats` class + `Route.completer_stats` field.
- Modify: `app/models/activity.py` — add compound index on `UserRouteStats` for verified-completers query.
- Modify: `app/services/user_stats.py` — extend `on_activity_created` / `on_activity_deleted` with Route `$inc`.
- Modify: `app/routers/routes.py` — add `GET /routes/{route_id}/verified-completers`.
- Create: `scripts/backfill_route_completer_stats.py` — idempotent backfill.
- Modify: `tests/services/test_user_stats.py` — Route counter assertions on create/delete.
- Create: `tests/routers/test_routes_verified_completers.py` — endpoint tests.
- Create: `tests/scripts/test_backfill_route_completer_stats.py` — backfill tests.

**Mobile (`apps/mobile`)**
- Modify: `lib/models/route_data.dart` — add `CompleterStats` class + `RouteData.completerStats` field.
- Create: `lib/models/verified_completer.dart` — item + page response model.
- Create: `lib/services/verified_completers_service.dart` — `GET /routes/{id}/verified-completers` client.
- Create: `lib/widgets/common/user_avatar.dart` — circular-avatar-only widget extracted from `OwnerBadge` fallback logic.
- Create: `lib/widgets/viewers/verified_completers_row.dart` — horizontal fit-only row with `+N 더 보기` chip.
- Create: `lib/widgets/sheets/verified_completers_sheet.dart` — paginated bottom sheet.
- Modify: `lib/pages/viewers/route_viewer.dart` — mount the new row below `WorkoutLogPanel`.
- Modify: `lib/l10n/app_ko.arb`, `app_en.arb`, `app_ja.arb`, `app_es.arb` — add 3 keys.

**Verification commands**
- Backend tests: `cd services/api && pytest <path>::<name> -v`
- Mobile static analysis: `cd apps/mobile && flutter analyze`
- Mobile i18n regen (after ARB edits): `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`

---

## Task 1: Data Model — `CompleterStats` on `Route`

**Files:**
- Modify: `services/api/app/models/route.py:40-77`
- Test: `services/api/tests/services/test_user_stats.py` (add new test at end of "data model" section)

- [ ] **Step 1: Write the failing roundtrip test**

Append to `services/api/tests/services/test_user_stats.py`:

```python
@pytest.mark.asyncio
async def test_route_completer_stats_roundtrip(mongo_db):
    from app.models.route import CompleterStats

    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    assert route.completer_stats.participant_count == 0
    assert route.completer_stats.completer_count == 0
    assert route.completer_stats.verified_completer_count == 0

    await Route.get_pymongo_collection().update_one(
        {"_id": route.id},
        {"$inc": {
            "completerStats.participantCount": 3,
            "completerStats.completerCount": 2,
            "completerStats.verifiedCompleterCount": 1,
        }},
    )

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 3
    assert refreshed.completer_stats.completer_count == 2
    assert refreshed.completer_stats.verified_completer_count == 1
```

- [ ] **Step 2: Run the test and watch it fail**

```
cd services/api && pytest tests/services/test_user_stats.py::test_route_completer_stats_roundtrip -v
```

Expected: FAIL with `AttributeError: 'Route' object has no attribute 'completer_stats'` (or import error on `CompleterStats`).

- [ ] **Step 3: Add the model**

Edit `services/api/app/models/route.py`. Add near the existing `ActivityStats` import and before `Route`:

```python
class CompleterStats(BaseModel):
    model_config = model_config

    participant_count: int = 0
    completer_count: int = 0
    verified_completer_count: int = 0
```

Add to the `Route` document, directly after `activity_stats`:

```python
    completer_stats: CompleterStats = Field(default_factory=CompleterStats)
```

- [ ] **Step 4: Run test to verify it passes**

```
cd services/api && pytest tests/services/test_user_stats.py::test_route_completer_stats_roundtrip -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```
git add services/api/app/models/route.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): add CompleterStats embedded field to Route"
```

---

## Task 2: Service — Route `$inc` on 0↔1 transitions in `on_activity_created`

**Files:**
- Modify: `services/api/app/services/user_stats.py:151-222`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Write the failing test for 0→1 transition**

Append to `services/api/tests/services/test_user_stats.py`:

```python
@pytest.mark.asyncio
async def test_on_activity_created_increments_route_completer_stats_on_first_verified(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(return_value=1))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    activity = await _insert_activity(
        user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True
    )
    await on_activity_created(activity, route)

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 1
    assert refreshed.completer_stats.completer_count == 1
    assert refreshed.completer_stats.verified_completer_count == 1
```

- [ ] **Step 2: Write failing test — second activity from same user does NOT re-increment**

Append:

```python
@pytest.mark.asyncio
async def test_on_activity_created_second_activity_same_user_does_not_reincrement_route_counters(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    a1 = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(
        user_id, route.id,
        status=ActivityStatus.COMPLETED, location_verified=True,
        started_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
    )
    await on_activity_created(a2, route)

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 1
    assert refreshed.completer_stats.completer_count == 1
    assert refreshed.completer_stats.verified_completer_count == 1
```

- [ ] **Step 3: Write failing test — attempted-only increments participant only**

Append:

```python
@pytest.mark.asyncio
async def test_on_activity_created_attempted_only_increments_participant(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(return_value=1))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    activity = await _insert_activity(
        user_id, route.id, status=ActivityStatus.ATTEMPTED, location_verified=False
    )
    await on_activity_created(activity, route)

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 1
    assert refreshed.completer_stats.completer_count == 0
    assert refreshed.completer_stats.verified_completer_count == 0
```

- [ ] **Step 4: Run the three tests and watch them fail**

```
cd services/api && pytest tests/services/test_user_stats.py -v -k "increments_route_completer_stats or does_not_reincrement_route or attempted_only_increments_participant"
```

Expected: 3 FAIL — no Route $inc is happening yet, so `participant_count` etc. stay at 0.

- [ ] **Step 5: Implement the Route `$inc` in `on_activity_created`**

Edit `services/api/app/services/user_stats.py`. Add this mapping constant with the other `_*_DB_FIELDS` dicts (around line 151-170):

```python
_ROUTE_COMPLETER_DB_FIELDS = {
    "total_count": "completerStats.participantCount",
    "completed_count": "completerStats.completerCount",
    "verified_completed_count": "completerStats.verifiedCompleterCount",
}
```

Inside `on_activity_created` (around line 208-220), after the existing per-bucket transition block, before the `await _update_user_stats(...)` call, add:

```python
        route_inc: dict[str, int] = {}
        for bucket in BUCKET_FIELDS:
            if before[bucket] == 0 and after[bucket] >= 1:
                route_inc[_ROUTE_COMPLETER_DB_FIELDS[bucket]] = 1
        if route_inc:
            await Route.get_pymongo_collection().update_one(
                {"_id": activity.route_id},
                {"$inc": route_inc},
            )
```

The `try/except Exception` wrapper around the entire `on_activity_created` body stays; a Route update failure is already swallowed.

- [ ] **Step 6: Run tests to verify they pass**

```
cd services/api && pytest tests/services/test_user_stats.py -v -k "increments_route_completer_stats or does_not_reincrement_route or attempted_only_increments_participant"
```

Expected: 3 PASS.

- [ ] **Step 7: Run the full user_stats test file to verify no regressions**

```
cd services/api && pytest tests/services/test_user_stats.py -v
```

Expected: all green.

- [ ] **Step 8: Commit**

```
git add services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): maintain Route.completerStats on activity creation"
```

---

## Task 3: Service — Route `$inc` on 1↔0 transitions in `on_activity_deleted`

**Files:**
- Modify: `services/api/app/services/user_stats.py:225-276`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Write failing test — sole activity deletion decrements all three counters**

Append to `services/api/tests/services/test_user_stats.py`:

```python
@pytest.mark.asyncio
async def test_on_activity_deleted_decrements_route_completer_stats(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 1]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    activity = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(activity, route)

    await on_activity_deleted(activity, route)
    await activity.delete()

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 0
    assert refreshed.completer_stats.completer_count == 0
    assert refreshed.completer_stats.verified_completer_count == 0
```

- [ ] **Step 2: Write failing test — deletion when user still has another activity for the same route does NOT decrement**

Append:

```python
@pytest.mark.asyncio
async def test_on_activity_deleted_leaves_route_counters_when_user_still_has_other_activity(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2, 2]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    a1 = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(
        user_id, route.id,
        status=ActivityStatus.COMPLETED, location_verified=True,
        started_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
    )
    await on_activity_created(a2, route)

    await on_activity_deleted(a2, route)
    await a2.delete()

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 1
    assert refreshed.completer_stats.completer_count == 1
    assert refreshed.completer_stats.verified_completer_count == 1
```

- [ ] **Step 3: Run tests and watch them fail**

```
cd services/api && pytest tests/services/test_user_stats.py -v -k "decrements_route_completer_stats or leaves_route_counters_when_user"
```

Expected: 2 FAIL. The first one fails because decrement logic is not yet present; the second passes accidentally only if counters are all 1 after two creates — so both fail in a consistent way.

- [ ] **Step 4: Implement the Route `$inc` (decrement) in `on_activity_deleted`**

Edit `services/api/app/services/user_stats.py`. Inside `on_activity_deleted` (around line 237-244), right after the existing per-bucket decrement block and before the `urs_doc_dropped` check, add:

```python
        route_inc: dict[str, int] = {}
        for bucket in BUCKET_FIELDS:
            if before[bucket] >= 1 and after[bucket] == 0:
                route_inc[_ROUTE_COMPLETER_DB_FIELDS[bucket]] = -1
        if route_inc:
            await Route.get_pymongo_collection().update_one(
                {"_id": activity.route_id},
                {"$inc": route_inc},
            )
```

- [ ] **Step 5: Run tests to verify they pass**

```
cd services/api && pytest tests/services/test_user_stats.py -v -k "decrements_route_completer_stats or leaves_route_counters_when_user"
```

Expected: 2 PASS.

- [ ] **Step 6: Run the full user_stats test file to verify no regressions**

```
cd services/api && pytest tests/services/test_user_stats.py -v
```

Expected: all green.

- [ ] **Step 7: Commit**

```
git add services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): decrement Route.completerStats on activity deletion"
```

---

## Task 4: Service — error swallowing still works when Route `$inc` fails

**Files:**
- Test: `services/api/tests/services/test_user_stats.py`
- (No code changes — we verify the existing `try/except Exception` wrapper covers the new call.)

- [ ] **Step 1: Write test**

Append to `services/api/tests/services/test_user_stats.py`:

```python
@pytest.mark.asyncio
async def test_on_activity_created_swallows_route_inc_errors(mongo_db, monkeypatch, caplog):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(return_value=1))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    async def _boom(*args, **kwargs):
        raise RuntimeError("simulated route inc failure")

    # Patch only the Route collection's update_one; UserRouteStats flow stays healthy.
    route_collection = Route.get_pymongo_collection()
    monkeypatch.setattr(route_collection, "update_one", _boom)

    activity = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)

    with caplog.at_level("ERROR"):
        await on_activity_created(activity, route)  # must not raise

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is not None  # UserRouteStats upsert succeeded
    assert any("on_activity_created failed" in r.message for r in caplog.records)
```

- [ ] **Step 2: Run the test**

```
cd services/api && pytest tests/services/test_user_stats.py::test_on_activity_created_swallows_route_inc_errors -v
```

Expected: PASS (the existing outer `try/except Exception` already catches it and logs via `logger.exception`).

- [ ] **Step 3: Commit**

```
git add services/api/tests/services/test_user_stats.py
git commit -m "test(api): verify Route \$inc failures are swallowed by on_activity_created"
```

---

## Task 5: Add compound index on `UserRouteStats` for verified-completers query

**Files:**
- Modify: `services/api/app/models/activity.py:79-91`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Write failing index-presence test**

Append to `services/api/tests/services/test_user_stats.py`:

```python
@pytest.mark.asyncio
async def test_user_route_stats_has_verified_completers_index(mongo_db):
    indexes = await UserRouteStats.get_pymongo_collection().index_information()
    assert "routeId_1_verifiedCompletedCount_-1_lastActivityAt_-1__id_-1" in indexes
```

- [ ] **Step 2: Run test and watch it fail**

```
cd services/api && pytest tests/services/test_user_stats.py::test_user_route_stats_has_verified_completers_index -v
```

Expected: FAIL — index not present.

- [ ] **Step 3: Add the index**

Edit `services/api/app/models/activity.py`. Inside `UserRouteStats.Settings.indexes`, append:

```python
            IndexModel(
                [
                    ("routeId", ASCENDING),
                    ("verifiedCompletedCount", DESCENDING),
                    ("lastActivityAt", DESCENDING),
                    ("_id", DESCENDING),
                ],
                name="routeId_1_verifiedCompletedCount_-1_lastActivityAt_-1__id_-1",
                partialFilterExpression={"verifiedCompletedCount": {"$gte": 1}},
            ),
```

- [ ] **Step 4: Run the test**

```
cd services/api && pytest tests/services/test_user_stats.py::test_user_route_stats_has_verified_completers_index -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```
git add services/api/app/models/activity.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): index UserRouteStats for verified-completers queries"
```

---

## Task 6: Endpoint — `GET /routes/{route_id}/verified-completers`

**Files:**
- Modify: `services/api/app/routers/routes.py` (append endpoint near the bottom of the file, after the existing route handlers)
- Create: `services/api/tests/routers/test_routes_verified_completers.py`

- [ ] **Step 1: Create the test file with a failing empty-list test**

Create `services/api/tests/routers/test_routes_verified_completers.py`:

```python
"""Tests for GET /routes/{id}/verified-completers."""

from __future__ import annotations

import base64
from datetime import datetime, timezone as dt_tz
from typing import Optional
from unittest.mock import patch

import pytest
import pytest_asyncio
from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from fastapi.testclient import TestClient
from mongomock_motor import AsyncMongoMockClient

from app.main import app
from app.dependencies import get_current_user
from app.models.activity import UserRouteStats
from app.models.image import Image
from app.models.place import Place
from app.models.route import Route, RouteType, Visibility
from app.models.user import User


pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient(tz_aware=True)
    db = client.get_database("besetter-test")
    await init_beanie(
        database=db,
        document_models=[User, Route, Image, Place, UserRouteStats],
    )
    yield db


async def _seed_user(*, profile_id: str = "owner", is_deleted: bool = False) -> User:
    now = datetime(2026, 4, 22, tzinfo=dt_tz.utc)
    user = User(
        profile_id=profile_id,
        profile_image_url=None if is_deleted else f"https://cdn/{profile_id}.jpg",
        is_deleted=is_deleted,
        created_at=now,
        updated_at=now,
    )
    await user.insert()
    return user


async def _seed_route(owner: User, visibility: Visibility = Visibility.PUBLIC) -> Route:
    route = Route(
        type=RouteType.BOULDERING,
        grade_type="v_scale",
        grade="V4",
        visibility=visibility,
        image_id=PydanticObjectId(),
        hold_polygon_id=PydanticObjectId(),
        user_id=owner.id,
        image_url="https://example.com/a.jpg",
    )
    await route.insert()
    return route


async def _seed_urs(
    *,
    user: User,
    route: Route,
    verified_count: int,
    last_activity_at: datetime,
) -> UserRouteStats:
    doc = UserRouteStats(
        user_id=user.id,
        route_id=route.id,
        total_count=verified_count,
        completed_count=verified_count,
        verified_completed_count=verified_count,
        last_activity_at=last_activity_at,
    )
    await doc.insert()
    return doc


def _override_auth(user: User):
    async def _fake():
        return user
    app.dependency_overrides[get_current_user] = _fake


def _clear_overrides():
    app.dependency_overrides.pop(get_current_user, None)


async def test_returns_empty_when_no_completers(mongo_db):
    owner = await _seed_user(profile_id="owner")
    route = await _seed_route(owner)
    _override_auth(owner)
    try:
        with TestClient(app) as client:
            resp = client.get(f"/routes/{route.id}/verified-completers")
        assert resp.status_code == 200
        body = resp.json()
        assert body["data"] == []
        assert body["meta"]["nextToken"] is None
    finally:
        _clear_overrides()
```

- [ ] **Step 2: Run the test and watch it fail**

```
cd services/api && pytest tests/routers/test_routes_verified_completers.py -v
```

Expected: FAIL with 404 (endpoint not registered).

- [ ] **Step 3: Add the endpoint**

Edit `services/api/app/routers/routes.py`. Append these at the bottom of the file (after the last existing handler, but inside the module):

```python
class VerifiedCompleterItem(BaseModel):
    model_config = model_config

    user: "OwnerView"
    verified_completed_count: int
    last_activity_at: datetime


class VerifiedCompletersMeta(BaseModel):
    model_config = model_config

    next_token: Optional[str] = None


class VerifiedCompletersResponse(BaseModel):
    model_config = model_config

    data: List[VerifiedCompleterItem]
    meta: VerifiedCompletersMeta


def _encode_verified_completers_cursor(
    verified_count: int, last_activity_at: datetime, doc_id: str
) -> str:
    ts = last_activity_at.astimezone(timezone.utc).isoformat() if last_activity_at else ""
    raw = f"{verified_count}|{ts}|{doc_id}"
    return base64.b64encode(raw.encode()).decode()


def _decode_verified_completers_cursor(cursor: str) -> tuple[int, datetime, ObjectId]:
    try:
        raw = base64.b64decode(cursor.encode()).decode()
        verified_str, ts_str, id_str = raw.split("|")
        return (
            int(verified_str),
            datetime.fromisoformat(ts_str),
            ObjectId(id_str),
        )
    except Exception:
        raise HTTPException(status_code=422, detail={"errorCode": "INVALID_CURSOR"})


@router.get(
    "/{route_id}/verified-completers",
    response_model=VerifiedCompletersResponse,
)
async def get_verified_completers(
    route_id: str,
    limit: int = Query(20, ge=1, le=50),
    cursor: Optional[str] = Query(None),
    current_user: User = Depends(get_current_user),
):
    route = await Route.find_one(
        Route.id == ObjectId(route_id),
        Route.is_deleted != True,
    )
    if not route:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Route not found")
    if not _can_access_route(route, current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"reason": "private"},
        )

    match_stage: Dict[str, Any] = {
        "routeId": ObjectId(route_id),
        "verifiedCompletedCount": {"$gte": 1},
    }
    if cursor is not None:
        c_count, c_ts, c_id = _decode_verified_completers_cursor(cursor)
        match_stage["$or"] = [
            {"verifiedCompletedCount": {"$lt": c_count}},
            {"verifiedCompletedCount": c_count, "lastActivityAt": {"$lt": c_ts}},
            {
                "verifiedCompletedCount": c_count,
                "lastActivityAt": c_ts,
                "_id": {"$lt": c_id},
            },
        ]

    pipeline: List[Dict[str, Any]] = [
        {"$match": match_stage},
        {"$sort": {
            "verifiedCompletedCount": -1,
            "lastActivityAt": -1,
            "_id": -1,
        }},
        {"$limit": limit + 1},
        {
            "$lookup": {
                "from": "users",
                "localField": "userId",
                "foreignField": "_id",
                "as": "_user",
            }
        },
        {"$addFields": {"_user": {"$arrayElemAt": ["$_user", 0]}}},
    ]

    collection = UserRouteStats.get_pymongo_collection()
    rows = [doc async for doc in collection.aggregate(pipeline)]

    has_more = len(rows) > limit
    rows = rows[:limit]

    data: List[VerifiedCompleterItem] = []
    for row in rows:
        u = row.get("_user")
        if u is None:
            owner = OwnerView(
                user_id=row["userId"],
                profile_id=None,
                profile_image_url=None,
                is_deleted=True,
            )
        else:
            is_deleted = bool(u.get("isDeleted", False))
            owner = OwnerView(
                user_id=u["_id"],
                profile_id=None if is_deleted else u.get("profileId"),
                profile_image_url=None if is_deleted else u.get("profileImageUrl"),
                is_deleted=is_deleted,
            )
        data.append(
            VerifiedCompleterItem(
                user=owner,
                verified_completed_count=row["verifiedCompletedCount"],
                last_activity_at=row["lastActivityAt"],
            )
        )

    next_token: Optional[str] = None
    if has_more and rows:
        last = rows[-1]
        next_token = _encode_verified_completers_cursor(
            last["verifiedCompletedCount"], last["lastActivityAt"], str(last["_id"])
        )

    return VerifiedCompletersResponse(
        data=data, meta=VerifiedCompletersMeta(next_token=next_token)
    )
```

Add the needed imports at the top of `routes.py` if not already present:

```python
from datetime import datetime, timezone
from app.models.user import OwnerView
```

(The file already imports `datetime`; add `timezone` next to it. `OwnerView` may need to be added.)

- [ ] **Step 4: Run the empty-list test**

```
cd services/api && pytest tests/routers/test_routes_verified_completers.py::test_returns_empty_when_no_completers -v
```

Expected: PASS.

- [ ] **Step 5: Add ordering/pagination test**

Append to `tests/routers/test_routes_verified_completers.py`:

```python
async def test_sorts_by_verified_count_desc_then_last_activity_desc(mongo_db):
    owner = await _seed_user(profile_id="owner")
    route = await _seed_route(owner)

    u1 = await _seed_user(profile_id="u1")
    u2 = await _seed_user(profile_id="u2")
    u3 = await _seed_user(profile_id="u3")

    t0 = datetime(2026, 4, 20, 10, 0, tzinfo=dt_tz.utc)
    # u1: count 5 (tie with u2, older → later in sort)
    await _seed_urs(user=u1, route=route, verified_count=5,
                    last_activity_at=datetime(2026, 4, 20, 8, 0, tzinfo=dt_tz.utc))
    # u2: count 5 (tie with u1, newer → first)
    await _seed_urs(user=u2, route=route, verified_count=5, last_activity_at=t0)
    # u3: count 2
    await _seed_urs(user=u3, route=route, verified_count=2, last_activity_at=t0)

    _override_auth(owner)
    try:
        with TestClient(app) as client:
            resp = client.get(f"/routes/{route.id}/verified-completers?limit=10")
    finally:
        _clear_overrides()

    assert resp.status_code == 200
    data = resp.json()["data"]
    assert [item["user"]["profileId"] for item in data] == ["u2", "u1", "u3"]


async def test_pagination_round_trip(mongo_db):
    owner = await _seed_user(profile_id="owner")
    route = await _seed_route(owner)

    for i in range(5):
        u = await _seed_user(profile_id=f"u{i}")
        await _seed_urs(
            user=u, route=route,
            verified_count=5 - i,
            last_activity_at=datetime(2026, 4, 20, 10, i, tzinfo=dt_tz.utc),
        )

    _override_auth(owner)
    try:
        with TestClient(app) as client:
            page1 = client.get(f"/routes/{route.id}/verified-completers?limit=2").json()
            assert len(page1["data"]) == 2
            assert page1["meta"]["nextToken"] is not None

            page2 = client.get(
                f"/routes/{route.id}/verified-completers"
                f"?limit=2&cursor={page1['meta']['nextToken']}"
            ).json()
            assert len(page2["data"]) == 2

            page3 = client.get(
                f"/routes/{route.id}/verified-completers"
                f"?limit=2&cursor={page2['meta']['nextToken']}"
            ).json()
            assert len(page3["data"]) == 1
            assert page3["meta"]["nextToken"] is None

            ordered = [
                item["user"]["profileId"]
                for page in (page1, page2, page3)
                for item in page["data"]
            ]
            assert ordered == ["u0", "u1", "u2", "u3", "u4"]
    finally:
        _clear_overrides()


async def test_private_route_non_owner_gets_403(mongo_db):
    owner = await _seed_user(profile_id="owner")
    other = await _seed_user(profile_id="other")
    route = await _seed_route(owner, visibility=Visibility.PRIVATE)

    _override_auth(other)
    try:
        with TestClient(app) as client:
            resp = client.get(f"/routes/{route.id}/verified-completers")
        assert resp.status_code == 403
    finally:
        _clear_overrides()


async def test_deleted_user_serialized_with_null_fields(mongo_db):
    owner = await _seed_user(profile_id="owner")
    gone = await _seed_user(profile_id="gone", is_deleted=True)
    route = await _seed_route(owner)
    await _seed_urs(
        user=gone, route=route, verified_count=3,
        last_activity_at=datetime(2026, 4, 20, 10, 0, tzinfo=dt_tz.utc),
    )

    _override_auth(owner)
    try:
        with TestClient(app) as client:
            resp = client.get(f"/routes/{route.id}/verified-completers")
    finally:
        _clear_overrides()

    assert resp.status_code == 200
    entry = resp.json()["data"][0]
    assert entry["user"]["isDeleted"] is True
    assert entry["user"].get("profileId") is None
    assert entry["user"].get("profileImageUrl") is None


async def test_excludes_zero_verified_count_users(mongo_db):
    owner = await _seed_user(profile_id="owner")
    route = await _seed_route(owner)

    u1 = await _seed_user(profile_id="u1")
    u2 = await _seed_user(profile_id="u2")

    # u1 has only attempts (verifiedCompletedCount = 0)
    await UserRouteStats(
        user_id=u1.id, route_id=route.id,
        total_count=3, completed_count=0, verified_completed_count=0,
        last_activity_at=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    ).insert()
    await _seed_urs(
        user=u2, route=route, verified_count=1,
        last_activity_at=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    )

    _override_auth(owner)
    try:
        with TestClient(app) as client:
            resp = client.get(f"/routes/{route.id}/verified-completers")
    finally:
        _clear_overrides()

    data = resp.json()["data"]
    assert [item["user"]["profileId"] for item in data] == ["u2"]
```

- [ ] **Step 6: Run the full endpoint test file**

```
cd services/api && pytest tests/routers/test_routes_verified_completers.py -v
```

Expected: all 5 tests PASS.

- [ ] **Step 7: Commit**

```
git add services/api/app/routers/routes.py services/api/tests/routers/test_routes_verified_completers.py
git commit -m "feat(api): add GET /routes/{id}/verified-completers"
```

---

## Task 7: Backfill script — `scripts/backfill_route_completer_stats.py`

**Files:**
- Create: `services/api/scripts/backfill_route_completer_stats.py`
- Create: `services/api/tests/scripts/test_backfill_route_completer_stats.py`

- [ ] **Step 1: Write failing test**

Create `services/api/tests/scripts/test_backfill_route_completer_stats.py`:

```python
"""Tests for scripts/backfill_route_completer_stats.py."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz

import pytest
import pytest_asyncio
from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from mongomock_motor import AsyncMongoMockClient

from app.models.activity import UserRouteStats
from app.models.route import Route, RouteType, Visibility
from app.models.user import User
from scripts.backfill_route_completer_stats import backfill_route


pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient(tz_aware=True)
    db = client.get_database("besetter-test")
    await init_beanie(
        database=db,
        document_models=[User, Route, UserRouteStats],
    )
    yield db


def _new_route(owner_id: PydanticObjectId) -> Route:
    return Route(
        type=RouteType.BOULDERING,
        grade_type="v_scale", grade="V3",
        visibility=Visibility.PUBLIC,
        image_id=PydanticObjectId(),
        hold_polygon_id=PydanticObjectId(),
        user_id=owner_id,
        image_url="https://example.com/x.jpg",
    )


async def test_backfill_computes_distinct_user_counts(mongo_db):
    owner_id = PydanticObjectId()
    route = _new_route(owner_id)
    await route.insert()

    # 3 users — u1 verified, u2 completed (unverified), u3 attempted only, u4 all-zero
    for total, completed, verified in [
        (5, 5, 5),   # u1: counts in all three buckets
        (3, 2, 0),   # u2: participant + completer
        (1, 0, 0),   # u3: participant only
    ]:
        await UserRouteStats(
            user_id=PydanticObjectId(),
            route_id=route.id,
            total_count=total,
            completed_count=completed,
            verified_completed_count=verified,
            last_activity_at=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
        ).insert()

    await backfill_route(route.id)

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 3
    assert refreshed.completer_stats.completer_count == 2
    assert refreshed.completer_stats.verified_completer_count == 1


async def test_backfill_is_idempotent(mongo_db):
    owner_id = PydanticObjectId()
    route = _new_route(owner_id)
    await route.insert()

    await UserRouteStats(
        user_id=PydanticObjectId(), route_id=route.id,
        total_count=1, completed_count=1, verified_completed_count=1,
        last_activity_at=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    ).insert()

    await backfill_route(route.id)
    await backfill_route(route.id)  # second run

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 1
    assert refreshed.completer_stats.completer_count == 1
    assert refreshed.completer_stats.verified_completer_count == 1


async def test_backfill_zeroes_when_no_user_route_stats(mongo_db):
    owner_id = PydanticObjectId()
    route = _new_route(owner_id)
    # Pretend a stale counter exists
    route.completer_stats.verified_completer_count = 7
    await route.insert()

    await backfill_route(route.id)

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 0
    assert refreshed.completer_stats.completer_count == 0
    assert refreshed.completer_stats.verified_completer_count == 0
```

- [ ] **Step 2: Run the test and watch it fail**

```
cd services/api && pytest tests/scripts/test_backfill_route_completer_stats.py -v
```

Expected: FAIL — module `scripts.backfill_route_completer_stats` does not exist.

- [ ] **Step 3: Implement the script**

Create `services/api/scripts/backfill_route_completer_stats.py`:

```python
"""Idempotent backfill for ``routes.completerStats``.

Recomputes per-route distinct-user counters from ``userRouteStats``. Safe to run
repeatedly. Exposes ``backfill_route`` for programmatic use (and tests) plus a
``main`` entry that iterates all routes.

Usage:
    python -m scripts.backfill_route_completer_stats                 # all routes
    python -m scripts.backfill_route_completer_stats --route-id X    # one route
"""

from __future__ import annotations

import argparse
import asyncio
import logging
from typing import Optional

from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from motor.motor_asyncio import AsyncIOMotorClient

from app.core.config import get
from app.models.activity import Activity, UserRouteStats
from app.models.hold_polygon import HoldPolygon
from app.models.image import Image
from app.models.notification import Notification
from app.models.open_id_nonce import OpenIdNonce
from app.models.place import Place, PlaceSuggestion
from app.models.route import Route
from app.models.user import User
from app.models.user_stats import UserStats


logger = logging.getLogger(__name__)


async def _compute_counts(route_id: PydanticObjectId) -> tuple[int, int, int]:
    collection = UserRouteStats.get_pymongo_collection()
    pipeline = [
        {"$match": {"routeId": route_id}},
        {
            "$group": {
                "_id": None,
                "participant": {"$sum": {"$cond": [{"$gte": ["$totalCount", 1]}, 1, 0]}},
                "completer": {"$sum": {"$cond": [{"$gte": ["$completedCount", 1]}, 1, 0]}},
                "verified": {"$sum": {"$cond": [{"$gte": ["$verifiedCompletedCount", 1]}, 1, 0]}},
            }
        },
    ]
    async for doc in collection.aggregate(pipeline):
        return int(doc["participant"]), int(doc["completer"]), int(doc["verified"])
    return 0, 0, 0


async def backfill_route(route_id: PydanticObjectId) -> None:
    """Recompute and $set ``completerStats`` for one route."""
    participant, completer, verified = await _compute_counts(route_id)
    await Route.get_pymongo_collection().update_one(
        {"_id": route_id},
        {"$set": {
            "completerStats.participantCount": participant,
            "completerStats.completerCount": completer,
            "completerStats.verifiedCompleterCount": verified,
        }},
    )


async def backfill_all() -> None:
    processed = 0
    async for route in Route.find_all():
        await backfill_route(route.id)
        processed += 1
        if processed % 100 == 0:
            logger.info("backfilled %d routes so far", processed)
    logger.info("backfill complete: %d routes", processed)


async def main(route_id: Optional[str] = None) -> None:
    client = AsyncIOMotorClient(get("mongodb.url"), tz_aware=True)
    try:
        db = client.get_database(get("mongodb.name"))
        await init_beanie(
            database=db,
            document_models=[
                OpenIdNonce, User, HoldPolygon, Image, Route, Place, PlaceSuggestion,
                Activity, UserRouteStats, Notification, UserStats,
            ],
        )
        if route_id is not None:
            await backfill_route(PydanticObjectId(route_id))
        else:
            await backfill_all()
    finally:
        client.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser()
    parser.add_argument("--route-id", dest="route_id", default=None)
    args = parser.parse_args()
    asyncio.run(main(args.route_id))
```

- [ ] **Step 4: Run the test**

```
cd services/api && pytest tests/scripts/test_backfill_route_completer_stats.py -v
```

Expected: all 3 PASS.

- [ ] **Step 5: Commit**

```
git add services/api/scripts/backfill_route_completer_stats.py services/api/tests/scripts/test_backfill_route_completer_stats.py
git commit -m "feat(api): add backfill_route_completer_stats script"
```

---

## Task 8: Mobile — `CompleterStats` model on `RouteData`

**Files:**
- Modify: `apps/mobile/lib/models/route_data.dart:4-208`

- [ ] **Step 1: Add the `CompleterStats` class and wire it into `RouteData`**

Edit `apps/mobile/lib/models/route_data.dart`. Immediately after `class OwnerInfo { ... }` (around line 30), add:

```dart
class CompleterStats {
  final int participantCount;
  final int completerCount;
  final int verifiedCompleterCount;

  const CompleterStats({
    this.participantCount = 0,
    this.completerCount = 0,
    this.verifiedCompleterCount = 0,
  });

  factory CompleterStats.fromJson(Map<String, dynamic> json) => CompleterStats(
        participantCount: (json['participantCount'] as int?) ?? 0,
        completerCount: (json['completerCount'] as int?) ?? 0,
        verifiedCompleterCount: (json['verifiedCompleterCount'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'participantCount': participantCount,
        'completerCount': completerCount,
        'verifiedCompleterCount': verifiedCompleterCount,
      };
}
```

Add the field to `RouteData`. Inside the field list (after `isDeleted` at line 93):

```dart
  final CompleterStats completerStats;
```

Add to the constructor (after `this.isDeleted = false,`):

```dart
    this.completerStats = const CompleterStats(),
```

In `RouteData.fromJson` (near line 172), add:

```dart
      completerStats: json['completerStats'] != null
          ? CompleterStats.fromJson(json['completerStats'] as Map<String, dynamic>)
          : const CompleterStats(),
```

In `RouteData.toJson` (near line 206, before the closing `};`), add:

```dart
        'completerStats': completerStats.toJson(),
```

- [ ] **Step 2: Run static analysis**

```
cd apps/mobile && flutter analyze
```

Expected: no new errors. (Existing warnings are fine.)

- [ ] **Step 3: Commit**

```
git add apps/mobile/lib/models/route_data.dart
git commit -m "feat(mobile): add CompleterStats field to RouteData"
```

---

## Task 9: Mobile — `VerifiedCompleter` model and service

**Files:**
- Create: `apps/mobile/lib/models/verified_completer.dart`
- Create: `apps/mobile/lib/services/verified_completers_service.dart`

- [ ] **Step 1: Create the model file**

Create `apps/mobile/lib/models/verified_completer.dart`:

```dart
import 'route_data.dart';

class VerifiedCompleter {
  final OwnerInfo user;
  final int verifiedCompletedCount;
  final DateTime lastActivityAt;

  const VerifiedCompleter({
    required this.user,
    required this.verifiedCompletedCount,
    required this.lastActivityAt,
  });

  factory VerifiedCompleter.fromJson(Map<String, dynamic> json) =>
      VerifiedCompleter(
        user: OwnerInfo.fromJson(json['user'] as Map<String, dynamic>),
        verifiedCompletedCount: json['verifiedCompletedCount'] as int,
        lastActivityAt: DateTime.parse(json['lastActivityAt'] as String),
      );
}

class VerifiedCompletersPage {
  final List<VerifiedCompleter> items;
  final String? nextToken;

  const VerifiedCompletersPage({required this.items, required this.nextToken});
}
```

- [ ] **Step 2: Create the service**

Create `apps/mobile/lib/services/verified_completers_service.dart`:

```dart
import 'dart:convert';

import '../models/verified_completer.dart';
import 'http_client.dart';

class VerifiedCompletersService {
  static Future<VerifiedCompletersPage> fetch({
    required String routeId,
    int limit = 20,
    String? cursor,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (cursor != null) {
      query['cursor'] = cursor;
    }
    final qs = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final path = '/routes/$routeId/verified-completers?$qs';

    final response = await AuthorizedHttpClient.get(path);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load verified completers: ${response.statusCode}',
      );
    }
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final items = (decoded['data'] as List<dynamic>)
        .map((e) => VerifiedCompleter.fromJson(e as Map<String, dynamic>))
        .toList();
    final meta = decoded['meta'] as Map<String, dynamic>? ?? const {};
    final nextToken = meta['nextToken'] as String?;
    return VerifiedCompletersPage(items: items, nextToken: nextToken);
  }
}
```

- [ ] **Step 3: Run static analysis**

```
cd apps/mobile && flutter analyze
```

Expected: no new errors.

- [ ] **Step 4: Commit**

```
git add apps/mobile/lib/models/verified_completer.dart apps/mobile/lib/services/verified_completers_service.dart
git commit -m "feat(mobile): add VerifiedCompleter model + service"
```

---

## Task 10: Mobile — shared `UserAvatar` widget

**Files:**
- Create: `apps/mobile/lib/widgets/common/user_avatar.dart`

- [ ] **Step 1: Create the widget**

Create `apps/mobile/lib/widgets/common/user_avatar.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/route_data.dart';

class UserAvatar extends StatelessWidget {
  final OwnerInfo owner;
  final double size;

  const UserAvatar({super.key, required this.owner, this.size = 40});

  @override
  Widget build(BuildContext context) {
    if (owner.isDeleted) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.person_off_outlined,
          size: size * 0.6,
          color: Colors.grey[500],
        ),
      );
    }

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: owner.profileImageUrl != null
            ? CachedNetworkImage(
                imageUrl: owner.profileImageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _initial(),
                errorWidget: (_, __, ___) => _initial(),
              )
            : _initial(),
      ),
    );
  }

  Widget _initial() {
    final initial = (owner.profileId ?? '?').substring(0, 1).toUpperCase();
    return Container(
      color: const Color(0xFFE6ECFB),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: const Color(0xFF1E4BD8),
          fontWeight: FontWeight.w700,
          fontSize: size * 0.35,
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run static analysis**

```
cd apps/mobile && flutter analyze
```

Expected: no new errors.

- [ ] **Step 3: Commit**

```
git add apps/mobile/lib/widgets/common/user_avatar.dart
git commit -m "feat(mobile): extract UserAvatar widget (shared with OwnerBadge)"
```

---

## Task 11: Mobile — i18n strings for verified completers

**Files:**
- Modify: `apps/mobile/lib/l10n/app_ko.arb`
- Modify: `apps/mobile/lib/l10n/app_en.arb`
- Modify: `apps/mobile/lib/l10n/app_ja.arb`
- Modify: `apps/mobile/lib/l10n/app_es.arb`

- [ ] **Step 1: Add three keys to `app_ko.arb`**

Edit `apps/mobile/lib/l10n/app_ko.arb`. After the existing `"viewMore"` entry (near line 181), insert:

```json
  "verifiedCompletersTitle": "인증된 완등자",
  "verifiedCompletersCount": "{count}명",
  "@verifiedCompletersCount": {
    "placeholders": { "count": { "type": "int" } }
  },
  "verifiedCompletersMore": "+{count} 더 보기",
  "@verifiedCompletersMore": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 2: Add the same three keys to `app_en.arb`**

At the mirrored position, insert:

```json
  "verifiedCompletersTitle": "Verified Completers",
  "verifiedCompletersCount": "{count}",
  "@verifiedCompletersCount": {
    "placeholders": { "count": { "type": "int" } }
  },
  "verifiedCompletersMore": "+{count} more",
  "@verifiedCompletersMore": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 3: Add the same three keys to `app_ja.arb`**

```json
  "verifiedCompletersTitle": "認定完登者",
  "verifiedCompletersCount": "{count}人",
  "@verifiedCompletersCount": {
    "placeholders": { "count": { "type": "int" } }
  },
  "verifiedCompletersMore": "+{count} もっと見る",
  "@verifiedCompletersMore": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 4: Add the same three keys to `app_es.arb`**

```json
  "verifiedCompletersTitle": "Escaladores verificados",
  "verifiedCompletersCount": "{count}",
  "@verifiedCompletersCount": {
    "placeholders": { "count": { "type": "int" } }
  },
  "verifiedCompletersMore": "+{count} más",
  "@verifiedCompletersMore": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 5: Regenerate Flutter localizations**

```
cd apps/mobile && dart run build_runner build --delete-conflicting-outputs
```

Expected: `gen_l10n` regenerates without errors. (This project already runs code generation per `apps/mobile/CLAUDE.md`.)

- [ ] **Step 6: Run static analysis**

```
cd apps/mobile && flutter analyze
```

Expected: no new errors.

- [ ] **Step 7: Commit**

```
git add apps/mobile/lib/l10n/
git commit -m "i18n(mobile): add verified-completers strings (ko/en/ja/es)"
```

---

## Task 12: Mobile — `VerifiedCompletersSheet` paginated bottom sheet

**Files:**
- Create: `apps/mobile/lib/widgets/sheets/verified_completers_sheet.dart`

- [ ] **Step 1: Create the sheet widget**

Create `apps/mobile/lib/widgets/sheets/verified_completers_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../models/verified_completer.dart';
import '../../services/verified_completers_service.dart';
import '../common/user_avatar.dart';

class VerifiedCompletersSheet extends StatefulWidget {
  final String routeId;
  final int totalCount;

  const VerifiedCompletersSheet({
    super.key,
    required this.routeId,
    required this.totalCount,
  });

  static Future<void> show(
    BuildContext context, {
    required String routeId,
    required int totalCount,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => VerifiedCompletersSheet(
        routeId: routeId,
        totalCount: totalCount,
      ),
    );
  }

  @override
  State<VerifiedCompletersSheet> createState() =>
      _VerifiedCompletersSheetState();
}

class _VerifiedCompletersSheetState extends State<VerifiedCompletersSheet> {
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  final List<VerifiedCompleter> _items = [];

  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _cursor;
  Object? _initialError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    try {
      final page = await VerifiedCompletersService.fetch(
        routeId: widget.routeId,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.nextToken;
        _hasMore = page.nextToken != null;
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _initialError = e;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await VerifiedCompletersService.fetch(
        routeId: widget.routeId,
        limit: _pageSize,
        cursor: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextToken;
        _hasMore = page.nextToken != null;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mediaHeight = MediaQuery.of(context).size.height;

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.verifiedCompletersTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Text(
                  l10n.verifiedCompletersCount(widget.totalCount),
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(child: _buildBody(l10n, mediaHeight)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, double _) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_initialError != null) {
      return Center(child: Text(l10n.failedToLoadData));
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      itemBuilder: (ctx, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final item = _items[index];
        return _Row(item: item);
      },
    );
  }
}

class _Row extends StatelessWidget {
  final VerifiedCompleter item;
  const _Row({required this.item});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final handle = item.user.isDeleted
        ? l10n.deletedUser
        : (item.user.profileId != null ? '@${item.user.profileId}' : '');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          UserAvatar(owner: item.user, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              handle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: item.user.isDeleted ? Colors.grey[500] : Colors.black87,
                fontStyle:
                    item.user.isDeleted ? FontStyle.italic : FontStyle.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x33F97316)),
            ),
            child: Text(
              '${item.verifiedCompletedCount}',
              style: const TextStyle(
                color: Color(0xFFF97316),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run static analysis**

```
cd apps/mobile && flutter analyze
```

Expected: no new errors.

- [ ] **Step 3: Commit**

```
git add apps/mobile/lib/widgets/sheets/verified_completers_sheet.dart
git commit -m "feat(mobile): add VerifiedCompletersSheet with pagination"
```

---

## Task 13: Mobile — `VerifiedCompletersRow` horizontal fit-only row

**Files:**
- Create: `apps/mobile/lib/widgets/viewers/verified_completers_row.dart`

- [ ] **Step 1: Create the widget**

Create `apps/mobile/lib/widgets/viewers/verified_completers_row.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../models/verified_completer.dart';
import '../../services/verified_completers_service.dart';
import '../common/user_avatar.dart';
import '../sheets/verified_completers_sheet.dart';

class VerifiedCompletersRow extends StatefulWidget {
  final String routeId;
  final int totalCount;

  const VerifiedCompletersRow({
    super.key,
    required this.routeId,
    required this.totalCount,
  });

  @override
  State<VerifiedCompletersRow> createState() => _VerifiedCompletersRowState();
}

class _VerifiedCompletersRowState extends State<VerifiedCompletersRow> {
  static const double _avatarSize = 40;
  static const double _gap = 8;
  static const double _chipReserve = 96;
  static const int _previewLimit = 10;

  List<VerifiedCompleter> _preview = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await VerifiedCompletersService.fetch(
        routeId: widget.routeId,
        limit: _previewLimit,
      );
      if (!mounted) return;
      setState(() {
        _preview = page.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _openSheet() {
    VerifiedCompletersSheet.show(
      context,
      routeId: widget.routeId,
      totalCount: widget.totalCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.totalCount <= 0) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${l10n.verifiedCompletersTitle} 🏅',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '· ${l10n.verifiedCompletersCount(widget.totalCount)}',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const SizedBox(
              height: _avatarSize,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_error != null)
            SizedBox(
              height: _avatarSize,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(l10n.failedToLoadData,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ),
            )
          else
            LayoutBuilder(builder: (ctx, constraints) {
              final width = constraints.maxWidth;
              final remainder = (widget.totalCount - _preview.length).clamp(0, 1 << 30);
              final needsChip = widget.totalCount > _preview.length || remainder > 0;
              final usable = needsChip ? (width - _chipReserve) : width;
              final maxFit = ((usable + _gap) / (_avatarSize + _gap)).floor();
              final showCount = maxFit.clamp(0, _preview.length);
              final overflow = widget.totalCount - showCount;
              return SizedBox(
                height: _avatarSize,
                child: Row(
                  children: [
                    for (var i = 0; i < showCount; i++) ...[
                      GestureDetector(
                        onTap: _openSheet,
                        child: UserAvatar(
                          owner: _preview[i].user,
                          size: _avatarSize,
                        ),
                      ),
                      if (i != showCount - 1) const SizedBox(width: _gap),
                    ],
                    if (overflow > 0) ...[
                      const SizedBox(width: _gap),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: InkWell(
                            onTap: _openSheet,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F5F5),
                                border:
                                    Border.all(color: const Color(0xFFE0E0E0)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                l10n.verifiedCompletersMore(overflow),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run static analysis**

```
cd apps/mobile && flutter analyze
```

Expected: no new errors.

- [ ] **Step 3: Commit**

```
git add apps/mobile/lib/widgets/viewers/verified_completers_row.dart
git commit -m "feat(mobile): add VerifiedCompletersRow horizontal preview"
```

---

## Task 14: Mobile — mount row in `RouteViewer` below `WorkoutLogPanel`

**Files:**
- Modify: `apps/mobile/lib/pages/viewers/route_viewer.dart:320-340`

- [ ] **Step 1: Add import and mount the widget**

Edit `apps/mobile/lib/pages/viewers/route_viewer.dart`. Near the existing widget imports (around line 22-23), add:

```dart
import '../../widgets/viewers/verified_completers_row.dart';
```

Inside the build tree, immediately after `WorkoutLogPanel(...)` (currently line 330-333), insert:

```dart
                  VerifiedCompletersRow(
                    routeId: widget.routeData.id,
                    totalCount:
                        widget.routeData.completerStats.verifiedCompleterCount,
                  ),
```

- [ ] **Step 2: Run static analysis**

```
cd apps/mobile && flutter analyze
```

Expected: no new errors.

- [ ] **Step 3: Commit**

```
git add apps/mobile/lib/pages/viewers/route_viewer.dart
git commit -m "feat(mobile): show VerifiedCompletersRow under WorkoutLogPanel on route detail"
```

---

## Task 15: Final verification

- [ ] **Step 1: Run the full backend test suite touched by this change**

```
cd services/api && pytest tests/services/test_user_stats.py tests/routers/test_routes_verified_completers.py tests/scripts/test_backfill_route_completer_stats.py -v
```

Expected: all green.

- [ ] **Step 2: Run mobile static analysis once more**

```
cd apps/mobile && flutter analyze
```

Expected: clean.

- [ ] **Step 3: Reminder — run the backfill once after deploy**

When the backend is deployed, run once to populate existing routes:

```
cd services/api && python -m scripts.backfill_route_completer_stats
```

No commit here — this is an operational reminder.

---

## Self-Review Notes

**Spec coverage:**
- Data model (Route.completer_stats) → Task 1.
- 0↔1 `$inc` in on_activity_created / on_activity_deleted → Tasks 2, 3.
- Error swallowing check → Task 4.
- UserRouteStats index for verified-completers query → Task 5.
- `GET /routes/{id}/verified-completers` → Task 6.
- Backfill script → Task 7.
- Mobile model → Task 8.
- Mobile service → Task 9.
- Shared avatar widget → Task 10.
- i18n keys (ko/en/ja/es) → Task 11.
- Bottom sheet with pagination → Task 12.
- Horizontal fit-only row with `+N 더 보기` → Task 13.
- Route detail mount point → Task 14.
- Final verification → Task 15.

**Naming convention:** every DB field string in this plan (`completerStats.participantCount`, `verifiedCompletedCount`, `routeId`, `lastActivityAt`, cursor internals, index name) is camelCase. Python class fields (`participant_count`, `completer_stats`, `verified_completed_count`) are snake_case. Mapping is via Pydantic `model_config` aliases on the existing Beanie models.

**Type/signature consistency:**
- Python `CompleterStats` fields: `participant_count`, `completer_count`, `verified_completer_count` (consistent throughout).
- Dart `CompleterStats` fields: `participantCount`, `completerCount`, `verifiedCompleterCount` (Dart idiom).
- `VerifiedCompleter` dart model and `VerifiedCompleterItem` python schema both have: user (OwnerInfo/OwnerView), verifiedCompletedCount (int), lastActivityAt (datetime).
- Cursor format is self-consistent (encode/decode symmetric).
