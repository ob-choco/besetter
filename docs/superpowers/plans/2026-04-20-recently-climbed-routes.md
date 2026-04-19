# 최근 운동한 루트 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "최근 운동한 루트" section on the mobile home screen, backed by a new `GET /my/recently-climbed-routes` API, with route-owner profile info shown on each card (also on MY page daily cards).

**Architecture:** First wire `UserRouteStats.lastActivityAt` (currently never updated) into the activity create/delete hooks. Then add a compound Mongo index `(userId, lastActivityAt desc)`, the new endpoint, and extend `/my/daily-routes` with `owner`. Mobile gets a new home-screen section, a shared `OwnerBadge`, and a Riverpod-backed tab-index provider so the "기록 전체" link can switch to the MY tab.

**Tech Stack:** FastAPI + Beanie (MongoDB), Flutter 3 + hooks_riverpod + riverpod_annotation, Pydantic v2 with `model_config` aliasing.

**Spec:** `docs/superpowers/specs/2026-04-20-recently-climbed-routes-design.md`

---

## File Structure

### API — create
- `services/api/tests/routers/test_my_recently_climbed_routes.py` — endpoint tests (service-level, using `mongo_db`)

### API — modify
- `services/api/app/services/user_stats.py` — `_apply_user_route_stats_delta` accepts `last_activity_at`; `on_activity_created` passes `activity.started_at`; `on_activity_deleted` recomputes on conflict.
- `services/api/app/models/activity.py` — add compound index `(userId, lastActivityAt -1)`.
- `services/api/app/models/user.py` — add `OwnerView` pydantic model.
- `services/api/app/routers/my.py` — add `RecentRouteView` / `RecentRoutesResponse` / `GET /my/recently-climbed-routes`; extend `DailyRouteItem` with `owner`; extend aggregate pipeline with `userId` projection + owner batch-lookup.
- `services/api/tests/services/test_user_stats.py` — update existing assertions; add tests for `$max` and recompute.
- `services/api/tests/models/test_activity.py:88` — narrow the "always null" assertion.
- `services/api/tests/services/conftest.py` — add `Image, Place` to Beanie init.
- `services/api/tests/routers/test_my.py` — add owner-field coverage for `/my/daily-routes`.

### Mobile — create
- `apps/mobile/lib/providers/main_tab_provider.dart` — `mainTabIndexProvider`.
- `apps/mobile/lib/providers/recent_climbed_routes_provider.dart` — provider for the home section.
- `apps/mobile/lib/widgets/common/owner_badge.dart` — shared owner badge.
- `apps/mobile/lib/widgets/home/recent_climbed_route_card.dart` — route-list-item clone w/ owner badge, no 3-dot menu.
- `apps/mobile/lib/widgets/home/recent_climbed_routes_section.dart` — section wrapper w/ loading / error / empty / data states.

### Mobile — modify
- `apps/mobile/lib/models/route_data.dart` — add `OwnerInfo` class; add `owner`, `isDeleted` fields to `RouteData`.
- `apps/mobile/lib/pages/main_tab.dart` — replace `useState(0)` with `mainTabIndexProvider`.
- `apps/mobile/lib/pages/home.dart` — insert "최근 운동한 루트" section after `WallImageCarousel`.
- `apps/mobile/lib/pages/my_page.dart` — `_DailyRouteCard`: add `OwnerBadge` below place line.
- `apps/mobile/lib/pages/viewers/route_viewer.dart` — invalidate `recentClimbedRoutesProvider` on activity create.
- `apps/mobile/lib/widgets/viewers/workout_log_panel.dart` — invalidate `recentClimbedRoutesProvider` on activity delete.
- `apps/mobile/lib/l10n/app_ko.arb` / `app_en.arb` / `app_ja.arb` / `app_es.arb` — add 7 keys.

---

## Phase 1 — API: `lastActivityAt` plumbing

### Task 1: Extend `_apply_user_route_stats_delta` with `last_activity_at` parameter

**Files:**
- Modify: `services/api/app/services/user_stats.py:75-107`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Write the failing test** — append to `services/api/tests/services/test_user_stats.py` (place above `test_apply_urs_delta_upsert_initializes_duration_fields`):

```python
@pytest.mark.asyncio
async def test_apply_urs_delta_sets_last_activity_at_on_insert(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    t = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)

    await _apply_user_route_stats_delta(
        user_id,
        route_id,
        {"total_count": 1, "completed_count": 0, "verified_completed_count": 0},
        last_activity_at=t,
    )

    doc = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    )
    assert doc is not None
    assert doc.last_activity_at == t


@pytest.mark.asyncio
async def test_apply_urs_delta_max_does_not_regress(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    newer = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    older = datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)

    await _apply_user_route_stats_delta(
        user_id, route_id,
        {"total_count": 1, "completed_count": 0, "verified_completed_count": 0},
        last_activity_at=newer,
    )
    await _apply_user_route_stats_delta(
        user_id, route_id,
        {"total_count": 1, "completed_count": 0, "verified_completed_count": 0},
        last_activity_at=older,
    )

    doc = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    )
    assert doc.last_activity_at == newer


@pytest.mark.asyncio
async def test_apply_urs_delta_no_last_activity_at_leaves_field_untouched(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    t = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)

    await _apply_user_route_stats_delta(
        user_id, route_id,
        {"total_count": 1, "completed_count": 0, "verified_completed_count": 0},
        last_activity_at=t,
    )
    await _apply_user_route_stats_delta(
        user_id, route_id,
        {"total_count": 1, "completed_count": 0, "verified_completed_count": 0},
        last_activity_at=None,
    )

    doc = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    )
    assert doc.last_activity_at == t
    assert doc.total_count == 2
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py::test_apply_urs_delta_sets_last_activity_at_on_insert tests/services/test_user_stats.py::test_apply_urs_delta_max_does_not_regress tests/services/test_user_stats.py::test_apply_urs_delta_no_last_activity_at_leaves_field_untouched -v`
Expected: FAIL with `TypeError: _apply_user_route_stats_delta() got an unexpected keyword argument 'last_activity_at'`

- [ ] **Step 3: Update `_apply_user_route_stats_delta` signature and body**

Replace `services/api/app/services/user_stats.py:75-107` with:

```python
async def _apply_user_route_stats_delta(
    user_id: PydanticObjectId,
    route_id: PydanticObjectId,
    deltas: dict[str, int],
    *,
    last_activity_at: datetime | None = None,
) -> tuple[dict[str, int], dict[str, int]]:
    """Atomically apply ``$inc`` on UserRouteStats bucket counters for (user, route).

    Upserts the doc if missing. Returns ``(before, after)`` bucket counts as
    snake_case-keyed dicts. ``before = after - deltas``.

    When ``last_activity_at`` is provided, applies ``$max`` so the stored
    timestamp never regresses (late-arriving activities cannot overwrite a
    newer one).
    """
    inc = {_URS_BUCKET_DB_FIELDS[k]: v for k, v in deltas.items()}

    update: dict = {
        "$inc": inc,
        "$setOnInsert": {
            "userId": user_id,
            "routeId": route_id,
            "totalDuration": 0,
            "completedDuration": 0,
            "verifiedCompletedDuration": 0,
        },
    }
    if last_activity_at is not None:
        update["$max"] = {"lastActivityAt": last_activity_at}

    collection = UserRouteStats.get_pymongo_collection()
    updated = await collection.find_one_and_update(
        {"userId": user_id, "routeId": route_id},
        update,
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )

    after = {k: updated.get(_URS_BUCKET_DB_FIELDS[k], 0) for k in BUCKET_FIELDS}
    before = {k: after[k] - deltas[k] for k in BUCKET_FIELDS}
    return before, after
```

Note: the `lastActivityAt` key is removed from `$setOnInsert` — when no activity is in play (e.g. a `Route` soft-delete pathway that happens not to call this fn today, future callers likewise), we simply leave the field unset and Pydantic will read it back as `None`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k "apply_urs"`
Expected: PASS for the three new tests AND existing `test_apply_urs_delta_upsert_initializes_duration_fields`, `test_apply_urs_delta_insert_sets_buckets`, `test_apply_urs_delta_returns_before_after`.

- [ ] **Step 5: Fix the stale assertion in the "upsert initializes duration fields" test**

In `services/api/tests/services/test_user_stats.py:206`, change `assert doc.last_activity_at is None` to:

```python
    assert doc.last_activity_at is None  # not passed → remains unset (None)
```

(The line is actually already correct because that test doesn't pass `last_activity_at`. Keep it; just verify it still passes.)

Re-run the entire test file:

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v`
Expected: All existing + new tests PASS.

- [ ] **Step 6: Commit**

```bash
git add services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): $max lastActivityAt in UserRouteStats delta helper"
```

---

### Task 2: Wire `on_activity_created` to pass `started_at`

**Files:**
- Modify: `services/api/app/services/user_stats.py:183-208`
- Test: `services/api/tests/services/test_user_stats.py`

- [ ] **Step 1: Write the failing test** — append to `services/api/tests/services/test_user_stats.py`:

```python
@pytest.mark.asyncio
async def test_on_activity_created_sets_last_activity_at(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(return_value=1))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    started = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    activity = await _insert_activity(user_id, route.id, started_at=started)
    await on_activity_created(activity, route)

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is not None
    assert urs.last_activity_at == started


@pytest.mark.asyncio
async def test_on_activity_created_later_activity_advances_last_activity_at(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    earlier = datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)
    later = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    a1 = await _insert_activity(user_id, route.id, started_at=earlier)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(user_id, route.id, started_at=later)
    await on_activity_created(a2, route)

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs.last_activity_at == later


@pytest.mark.asyncio
async def test_on_activity_created_out_of_order_does_not_regress(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    earlier = datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)
    later = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    # Insert later activity first, then an earlier one — $max must keep `later`.
    a_late = await _insert_activity(user_id, route.id, started_at=later)
    await on_activity_created(a_late, route)
    a_early = await _insert_activity(user_id, route.id, started_at=earlier)
    await on_activity_created(a_early, route)

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs.last_activity_at == later
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k "on_activity_created_sets_last or advances_last or out_of_order"`
Expected: FAIL — `urs.last_activity_at` is `None` because the hook doesn't pass it.

- [ ] **Step 3: Update `on_activity_created` to pass `last_activity_at`**

In `services/api/app/services/user_stats.py`, change line 192 from:

```python
        before, after = await _apply_user_route_stats_delta(activity.user_id, activity.route_id, deltas)
```

to:

```python
        before, after = await _apply_user_route_stats_delta(
            activity.user_id,
            activity.route_id,
            deltas,
            last_activity_at=activity.started_at,
        )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): update UserRouteStats.lastActivityAt on activity create"
```

---

### Task 3: Recompute `lastActivityAt` on `on_activity_deleted`

**Files:**
- Modify: `services/api/app/services/user_stats.py:211-251`
- Test: `services/api/tests/services/test_user_stats.py`

**Decision reference (from spec §4):**
- Hook may fire **before** `activity.delete()` (from `routers/activities.py:280` — `still_present == True`) or **after** (from `routers/my.py:440` — `still_present == False`).
- Recompute only runs when the deleted activity's `started_at` matched the current `lastActivityAt` (otherwise no-op).
- Doc-deletion short-circuit: if `$inc` drained every counter to zero the existing logic deletes the doc; in that case we skip recompute.
- When `still_present == True`, exclude `Activity.id == activity.id` from the max-scan.

- [ ] **Step 1: Write the failing tests** — append to `services/api/tests/services/test_user_stats.py`:

```python
@pytest.mark.asyncio
async def test_on_activity_deleted_recomputes_last_activity_at_when_matches(mongo_db, monkeypatch):
    # Two activities; delete the later one. lastActivityAt should drop to the earlier.
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2, 1]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    earlier = datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)
    later = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    a1 = await _insert_activity(user_id, route.id, started_at=earlier)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(user_id, route.id, started_at=later)
    await on_activity_created(a2, route)

    # Hook runs BEFORE delete (the activities.py path).
    await on_activity_deleted(a2, route)
    await a2.delete()

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is not None
    assert urs.last_activity_at == earlier


@pytest.mark.asyncio
async def test_on_activity_deleted_skips_recompute_when_deleted_not_latest(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2, 2]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    earlier = datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)
    later = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    a1 = await _insert_activity(user_id, route.id, started_at=earlier)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(user_id, route.id, started_at=later)
    await on_activity_created(a2, route)

    # Delete the earlier activity. lastActivityAt should stay at `later`.
    await on_activity_deleted(a1, route)
    await a1.delete()

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is not None
    assert urs.last_activity_at == later


@pytest.mark.asyncio
async def test_on_activity_deleted_after_delete_recomputes_correctly(mongo_db, monkeypatch):
    # The routers/my.py path deletes activities BEFORE calling the hook (still_present=False).
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2, 1]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    earlier = datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)
    later = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    a1 = await _insert_activity(user_id, route.id, started_at=earlier)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(user_id, route.id, started_at=later)
    await on_activity_created(a2, route)

    # Delete first, then hook (routers/my.py ordering).
    await a2.delete()
    await on_activity_deleted(a2, route)

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is not None
    assert urs.last_activity_at == earlier


@pytest.mark.asyncio
async def test_on_activity_deleted_sole_activity_still_deletes_urs_doc(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 1]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    activity = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(activity, route)

    await on_activity_deleted(activity, route)
    await activity.delete()

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is None  # doc fully removed; lastActivityAt recompute must not recreate it
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v -k "recomputes or skips_recompute or after_delete_recomputes or sole_activity_still"`
Expected: FAIL — recompute logic not yet implemented.

- [ ] **Step 3: Update `on_activity_deleted` body**

Replace the body of `on_activity_deleted` in `services/api/app/services/user_stats.py` (lines 211-251) with:

```python
async def on_activity_deleted(activity: Activity, route: Route) -> None:
    """Apply post-delete userStats updates. Swallows all exceptions.

    Order-agnostic with respect to ``activity.delete()``: callers may invoke
    this hook before OR after the activity doc is removed. The ``still_present``
    check adjusts ``_recount_local_day`` and ``lastActivityAt`` recompute
    accordingly.
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

        # Drop an empty UserRouteStats doc. Conditional on current zero state to
        # avoid deleting a doc concurrently upserted by on_activity_created.
        urs_doc_dropped = False
        if after["total_count"] == 0 and after["completed_count"] == 0 and after["verified_completed_count"] == 0:
            result = await UserRouteStats.get_pymongo_collection().delete_one({
                "userId": activity.user_id,
                "routeId": activity.route_id,
                "totalCount": 0,
                "completedCount": 0,
                "verifiedCompletedCount": 0,
            })
            urs_doc_dropped = result.deleted_count > 0

        local_date = _local_date_str(activity)
        remaining = await _recount_local_day(activity.user_id, local_date)
        still_present = await Activity.find_one(Activity.id == activity.id) is not None
        effective = remaining - 1 if still_present else remaining
        if effective == 0:
            inc["distinctDays"] = -1

        await _update_user_stats(activity.user_id, inc)

        # Recompute lastActivityAt only if the deleted activity matched it and
        # the UserRouteStats doc still exists.
        if not urs_doc_dropped:
            await _recompute_last_activity_at(
                activity.user_id,
                activity.route_id,
                deleted_started_at=activity.started_at,
                deleted_activity_id=activity.id if still_present else None,
            )
    except Exception:
        logger.exception("on_activity_deleted failed for activity=%s", activity.id)


async def _recompute_last_activity_at(
    user_id: PydanticObjectId,
    route_id: PydanticObjectId,
    *,
    deleted_started_at: datetime,
    deleted_activity_id: PydanticObjectId | None,
) -> None:
    """Refresh ``UserRouteStats.lastActivityAt`` after an activity deletion.

    Only recomputes when the stored ``lastActivityAt`` equals
    ``deleted_started_at`` (i.e. the deletion may have made it stale). Scans
    remaining activities for the new max; if ``deleted_activity_id`` is set
    (hook fired before the Activity doc was removed), excludes that id from
    the scan.
    """
    collection = UserRouteStats.get_pymongo_collection()
    current = await collection.find_one(
        {"userId": user_id, "routeId": route_id},
        {"lastActivityAt": 1},
    )
    if current is None:
        return

    stored = current.get("lastActivityAt")
    if stored is None or stored != deleted_started_at:
        return

    query = Activity.find(
        Activity.user_id == user_id,
        Activity.route_id == route_id,
    )
    if deleted_activity_id is not None:
        query = query.find(Activity.id != deleted_activity_id)
    latest = await query.sort([("startedAt", -1)]).limit(1).to_list()

    new_value = latest[0].started_at if latest else None
    await collection.update_one(
        {"userId": user_id, "routeId": route_id},
        {"$set": {"lastActivityAt": new_value}},
    )
```

- [ ] **Step 4: Run all user-stats tests**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v`
Expected: All existing and new tests PASS (including the four new `on_activity_deleted_*` tests).

- [ ] **Step 5: Commit**

```bash
git add services/api/app/services/user_stats.py services/api/tests/services/test_user_stats.py
git commit -m "feat(api): recompute UserRouteStats.lastActivityAt on activity delete"
```

---

### Task 4: Narrow the `UserRouteStats` defaults test

**Files:**
- Modify: `services/api/tests/models/test_activity.py:81-88`

- [ ] **Step 1: Replace the existing test**

Replace lines 81-88 of `services/api/tests/models/test_activity.py` with:

```python
def test_user_route_stats_defaults():
    """A freshly-constructed UserRouteStats has no activity yet, so
    lastActivityAt defaults to None. The hook layer sets it once an
    Activity lands."""
    from bson import ObjectId
    stats = UserRouteStats(
        user_id=ObjectId(),
        route_id=ObjectId(),
    )
    assert stats.total_count == 0
    assert stats.last_activity_at is None
```

- [ ] **Step 2: Run the test**

Run: `cd services/api && uv run pytest tests/models/test_activity.py -v`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add services/api/tests/models/test_activity.py
git commit -m "test(api): clarify UserRouteStats defaults test scope"
```

---

### Task 5: Add compound index on `(userId, lastActivityAt desc)`

**Files:**
- Modify: `services/api/app/models/activity.py:79-87`
- Test: `services/api/tests/models/test_activity.py`

- [ ] **Step 1: Write the failing test** — append to `services/api/tests/models/test_activity.py`:

```python
def test_user_route_stats_has_last_activity_at_index():
    """The (userId, lastActivityAt desc) index backs the home-screen
    "recently climbed" query; without it the endpoint falls back to a
    collection scan."""
    index_specs = UserRouteStats.Settings.indexes
    names = {idx.document["name"] for idx in index_specs if hasattr(idx, "document")}
    assert "userId_1_lastActivityAt_-1" in names
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd services/api && uv run pytest tests/models/test_activity.py::test_user_route_stats_has_last_activity_at_index -v`
Expected: FAIL — index not yet declared.

- [ ] **Step 3: Add the index**

In `services/api/app/models/activity.py`, change the top-of-file import:

```python
from pymongo import ASCENDING, DESCENDING, IndexModel
```

Then update `UserRouteStats.Settings.indexes` (lines 81-86):

```python
        indexes = [
            IndexModel(
                [("userId", ASCENDING), ("routeId", ASCENDING)],
                unique=True,
            ),
            IndexModel(
                [("userId", ASCENDING), ("lastActivityAt", DESCENDING)],
                name="userId_1_lastActivityAt_-1",
            ),
        ]
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd services/api && uv run pytest tests/models/test_activity.py -v`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/models/activity.py services/api/tests/models/test_activity.py
git commit -m "feat(api): add UserRouteStats (userId, lastActivityAt desc) index"
```

---

## Phase 2 — API: endpoint + daily-routes owner

### Task 6: Add `OwnerView` model

**Files:**
- Modify: `services/api/app/models/user.py`
- Test: `services/api/tests/models/test_user.py` (create if absent)

- [ ] **Step 1: Create / extend the model test**

Create or extend `services/api/tests/models/test_user.py` with:

```python
"""Tests for User model additions."""

from beanie.odm.fields import PydanticObjectId

from app.models.user import OwnerView


def test_owner_view_serializes_with_camel_case():
    view = OwnerView(
        user_id=PydanticObjectId("507f1f77bcf86cd799439011"),
        profile_id="climber42",
        profile_image_url="https://cdn.example/x.jpg",
        is_deleted=False,
    )
    dumped = view.model_dump(by_alias=True)
    assert dumped["userId"] == "507f1f77bcf86cd799439011"
    assert dumped["profileId"] == "climber42"
    assert dumped["profileImageUrl"] == "https://cdn.example/x.jpg"
    assert dumped["isDeleted"] is False


def test_owner_view_deleted_user_defaults():
    view = OwnerView(user_id=PydanticObjectId(), is_deleted=True)
    assert view.profile_id is None
    assert view.profile_image_url is None
    assert view.is_deleted is True
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd services/api && uv run pytest tests/models/test_user.py -v`
Expected: FAIL with `ImportError: cannot import name 'OwnerView' from 'app.models.user'`.

- [ ] **Step 3: Add `OwnerView` to `services/api/app/models/user.py`**

Append to the bottom of `services/api/app/models/user.py`:

```python
class OwnerView(BaseModel):
    """Public profile summary shown alongside a route or activity.

    ``profile_id`` and ``profile_image_url`` are null when ``is_deleted`` is
    True (user withdrew) — the mobile `OwnerBadge` falls back to a
    "탈퇴한 회원" label.
    """

    model_config = model_config

    user_id: PydanticObjectId
    profile_id: Optional[str] = None
    profile_image_url: Optional[str] = None
    is_deleted: bool = False
```

Add the missing import at the top:

```python
from beanie.odm.fields import PydanticObjectId
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd services/api && uv run pytest tests/models/test_user.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/models/user.py services/api/tests/models/test_user.py
git commit -m "feat(api): add OwnerView model for public profile projections"
```

---

### Task 7: Extend test fixture to include `Image` and `Place`

**Files:**
- Modify: `services/api/tests/services/conftest.py`

Rationale: the upcoming endpoint + daily-routes tests need to insert `Image` and `Place` documents. The current fixture only initializes five models.

- [ ] **Step 1: Update fixture**

Replace `services/api/tests/services/conftest.py` with:

```python
"""Fixtures that spin up an in-memory Mongo (mongomock-motor) and init Beanie."""

from __future__ import annotations

import pytest_asyncio
from beanie import init_beanie
from mongomock_motor import AsyncMongoMockClient

from app.models.activity import Activity, UserRouteStats
from app.models.image import Image
from app.models.place import Place
from app.models.route import Route
from app.models.user import User
from app.models.user_stats import UserStats


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient()
    db = client.get_database("besetter-test")
    await init_beanie(
        database=db,
        document_models=[User, Route, Activity, UserRouteStats, UserStats, Image, Place],
    )
    yield db
```

- [ ] **Step 2: Run the existing test suite to verify no regressions**

Run: `cd services/api && uv run pytest tests/services/test_user_stats.py -v`
Expected: All tests still PASS.

- [ ] **Step 3: Commit**

```bash
git add services/api/tests/services/conftest.py
git commit -m "test(api): include Image and Place in Beanie test init"
```

---

### Task 8: Implement `GET /my/recently-climbed-routes`

**Files:**
- Modify: `services/api/app/routers/my.py`
- Create: `services/api/tests/routers/test_my_recently_climbed_routes.py`

Design notes:
- To keep the endpoint testable without a TestClient (the existing harness doesn't have one), extract the core logic into `_build_recently_climbed_routes(user_id, limit)` that takes primitive inputs and returns the response model. The route handler is a thin wrapper.
- Use `to_public_url()` from `app.core.gcs` — **never** use `generate_signed_url` here (no signing overhead for bulk reads).
- Keep the lookup sequence in the spec (§4.1.5): `UserRouteStats` → `Route` → `Image` → `Place` → `User`.
- If a row's `Route` doc is missing (data corruption), skip that row. The stats index + join should normally be consistent.

- [ ] **Step 1: Write the failing tests**

Create `services/api/tests/routers/test_my_recently_climbed_routes.py`:

```python
"""Tests for GET /my/recently-climbed-routes (service-level)."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz

import pytest
import pytest_asyncio
from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from mongomock_motor import AsyncMongoMockClient

from app.models.activity import UserRouteStats
from app.models.image import Image, ImageMetadata
from app.models.place import Place
from app.models.route import Route, RouteType, Visibility
from app.models.user import User


pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient()
    db = client.get_database("besetter-test")
    await init_beanie(
        database=db,
        document_models=[User, Route, Image, Place, UserRouteStats],
    )
    yield db


async def _seed_user(*, profile_id: str = "owner1", is_deleted: bool = False) -> User:
    now = datetime(2026, 4, 18, tzinfo=dt_tz.utc)
    user = User(
        profile_id=profile_id,
        profile_image_url=f"https://cdn/{profile_id}.jpg" if not is_deleted else None,
        is_deleted=is_deleted,
        created_at=now,
        updated_at=now,
    )
    await user.insert()
    return user


async def _seed_route(
    *,
    owner: User,
    visibility: Visibility = Visibility.PUBLIC,
    is_deleted: bool = False,
    image_url: str = "https://storage.cloud.google.com/besetter/routes/r.jpg",
) -> tuple[Route, Image, Place]:
    now = datetime(2026, 4, 18, tzinfo=dt_tz.utc)
    place = Place(
        name="Urban Apex",
        type="gym",
        status="approved",
        created_by=owner.id,
        created_at=now,
    )
    await place.insert()
    image = Image(
        url="https://storage.cloud.google.com/besetter/walls/w.jpg",
        filename="w.jpg",
        metadata=ImageMetadata(),
        user_id=owner.id,
        place_id=place.id,
        uploaded_at=now,
    )
    await image.insert()
    route = Route(
        type=RouteType.BOULDERING,
        grade_type="v_scale",
        grade="V3",
        visibility=visibility,
        image_id=image.id,
        hold_polygon_id=PydanticObjectId(),
        user_id=owner.id,
        image_url=image_url,
        is_deleted=is_deleted,
    )
    await route.insert()
    return route, image, place


async def _seed_stats(
    *,
    viewer_id: PydanticObjectId,
    route: Route,
    last_activity_at: datetime | None,
) -> UserRouteStats:
    stats = UserRouteStats(
        user_id=viewer_id,
        route_id=route.id,
        total_count=1,
        completed_count=1,
        verified_completed_count=0,
        last_activity_at=last_activity_at,
    )
    await stats.insert()
    return stats


async def test_recent_climbed_returns_nothing_for_new_user(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.core.gcs.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert resp.data == []


async def test_recent_climbed_orders_by_last_activity_desc(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.core.gcs.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    now = datetime(2026, 4, 18, tzinfo=dt_tz.utc)
    r1, _, _ = await _seed_route(owner=owner)
    r2, _, _ = await _seed_route(owner=owner)
    r3, _, _ = await _seed_route(owner=owner)

    await _seed_stats(viewer_id=viewer.id, route=r1, last_activity_at=now.replace(hour=10))
    await _seed_stats(viewer_id=viewer.id, route=r2, last_activity_at=now.replace(hour=14))
    await _seed_stats(viewer_id=viewer.id, route=r3, last_activity_at=now.replace(hour=12))

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    ordered_ids = [str(v.id) for v in resp.data]
    assert ordered_ids == [str(r2.id), str(r3.id), str(r1.id)]


async def test_recent_climbed_excludes_null_last_activity_at(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.core.gcs.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    r_with, _, _ = await _seed_route(owner=owner)
    r_null, _, _ = await _seed_route(owner=owner)
    await _seed_stats(viewer_id=viewer.id, route=r_with, last_activity_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc))
    await _seed_stats(viewer_id=viewer.id, route=r_null, last_activity_at=None)

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert len(resp.data) == 1
    assert str(resp.data[0].id) == str(r_with.id)


async def test_recent_climbed_populates_owner_for_other_users_route(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.core.gcs.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    route, _, _ = await _seed_route(owner=owner)
    await _seed_stats(
        viewer_id=viewer.id, route=route,
        last_activity_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc),
    )

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert len(resp.data) == 1
    view = resp.data[0]
    assert view.owner.user_id == owner.id
    assert view.owner.profile_id == "owner1"
    assert view.owner.profile_image_url == "https://cdn/owner1.jpg"
    assert view.owner.is_deleted is False


async def test_recent_climbed_deleted_owner_returns_is_deleted_true(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.core.gcs.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1", is_deleted=True)

    route, _, _ = await _seed_route(owner=owner)
    await _seed_stats(
        viewer_id=viewer.id, route=route,
        last_activity_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc),
    )

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert resp.data[0].owner.is_deleted is True
    assert resp.data[0].owner.profile_id is None
    assert resp.data[0].owner.profile_image_url is None


async def test_recent_climbed_deleted_route_is_tombstone(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.core.gcs.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    route, _, _ = await _seed_route(owner=owner, is_deleted=True)
    await _seed_stats(
        viewer_id=viewer.id, route=route,
        last_activity_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc),
    )

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert len(resp.data) == 1
    assert resp.data[0].is_deleted is True


async def test_recent_climbed_private_route_returned_as_tombstone(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.core.gcs.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    route, _, _ = await _seed_route(owner=owner, visibility=Visibility.PRIVATE)
    await _seed_stats(
        viewer_id=viewer.id, route=route,
        last_activity_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc),
    )

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert len(resp.data) == 1
    assert resp.data[0].visibility == Visibility.PRIVATE


async def test_recent_climbed_respects_limit(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.core.gcs.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    now = datetime(2026, 4, 18, tzinfo=dt_tz.utc)
    for i in range(5):
        r, _, _ = await _seed_route(owner=owner)
        await _seed_stats(viewer_id=viewer.id, route=r, last_activity_at=now.replace(hour=i + 1))

    resp = await _build_recently_climbed_routes(viewer.id, limit=3)
    assert len(resp.data) == 3


async def test_recent_climbed_uses_public_gcs_host(mongo_db, monkeypatch):
    # to_public_url mock mimics rewriting to storage.googleapis.com.
    def fake_to_public_url(url):
        if not url:
            return url
        return str(url).replace("storage.cloud.google.com", "storage.googleapis.com")

    monkeypatch.setattr("app.core.gcs.to_public_url", fake_to_public_url)
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    route, _, _ = await _seed_route(owner=owner)
    await _seed_stats(
        viewer_id=viewer.id, route=route,
        last_activity_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc),
    )

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert "storage.googleapis.com" in resp.data[0].image_url
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/routers/test_my_recently_climbed_routes.py -v`
Expected: FAIL with `ImportError: cannot import name '_build_recently_climbed_routes'`.

- [ ] **Step 3: Implement the endpoint**

At the top of `services/api/app/routers/my.py`, extend the imports (merge with existing groups):

```python
from typing import List, Optional

from beanie.odm.operators.find.comparison import In, NE
from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, Path, Query, status

from app.core.gcs import to_public_url
from app.models.image import Image
from app.models.place import Place
from app.models.route import Route, RouteType, Visibility
from app.models.user import OwnerView, User
from app.routers.places import PlaceView, place_to_view
```

(Drop pre-existing duplicates. `NE` is used for `lastActivityAt != None` via Beanie's filter operators, but the clearer form below uses a raw dict filter.)

Append the following — new schemas, helper, and endpoint — to `services/api/app/routers/my.py` (place after `DailyRoutesResponse` definition, before the existing endpoints, or at the bottom of the Response-schemas section):

```python
# ---------------------------------------------------------------------------
# Recently climbed routes
# ---------------------------------------------------------------------------


class RecentRouteView(BaseModel):
    model_config = model_config

    id: PydanticObjectId
    type: RouteType
    title: Optional[str] = None
    visibility: Visibility
    is_deleted: bool = False

    grade_type: str
    grade: str
    grade_color: Optional[str] = None

    image_url: str
    overlay_image_url: Optional[str] = None

    place: Optional[PlaceView] = None
    wall_name: Optional[str] = None
    wall_expiration_date: Optional[datetime] = None

    owner: OwnerView

    my_total_count: int
    my_completed_count: int
    my_last_activity_at: datetime

    created_at: datetime
    updated_at: Optional[datetime] = None


class RecentRoutesResponse(BaseModel):
    model_config = model_config

    data: List[RecentRouteView]


async def _build_recently_climbed_routes(
    user_id: PydanticObjectId,
    limit: int,
) -> RecentRoutesResponse:
    """Return up to ``limit`` routes the user has logged activities against,
    ordered by their per-(user, route) ``lastActivityAt`` descending.

    The endpoint intentionally does NOT filter by route visibility or
    ``isDeleted`` — tombstones are part of the user's history. Mobile
    renders them with a locked / trashed badge.
    """
    # 1. UserRouteStats ordered by lastActivityAt desc, _id desc as tiebreak.
    urs_cursor = (
        UserRouteStats.find(
            UserRouteStats.user_id == user_id,
        )
        .find({"lastActivityAt": {"$ne": None}})
        .sort([("lastActivityAt", -1), ("_id", -1)])
        .limit(limit)
    )
    urs_list = await urs_cursor.to_list()
    if not urs_list:
        return RecentRoutesResponse(data=[])

    # 2. Routes — keep tombstones.
    route_ids = [urs.route_id for urs in urs_list]
    routes = await Route.find(In(Route.id, route_ids)).to_list()
    route_by_id = {r.id: r for r in routes}

    # 3. Images.
    image_ids = [r.image_id for r in routes]
    images = await Image.find(In(Image.id, image_ids)).to_list()
    image_by_id = {img.id: img for img in images}

    # 4. Places.
    place_ids = list({img.place_id for img in images if img.place_id})
    place_by_id: dict[PydanticObjectId, Place] = {}
    if place_ids:
        places = await Place.find(In(Place.id, place_ids)).to_list()
        place_by_id = {p.id: p for p in places}

    # 5. Owners — keep withdrawn users.
    owner_ids = list({r.user_id for r in routes})
    owners = await User.find(In(User.id, owner_ids)).to_list()
    owner_by_id = {u.id: u for u in owners}

    # 6. Assemble.
    data: list[RecentRouteView] = []
    for urs in urs_list:
        route = route_by_id.get(urs.route_id)
        if route is None:
            continue  # stats drift; skip.
        image = image_by_id.get(route.image_id)
        if image is None:
            continue  # image missing; skip.

        place_view: Optional[PlaceView] = None
        if image.place_id and image.place_id in place_by_id:
            place_view = place_to_view(place_by_id[image.place_id])

        owner_doc = owner_by_id.get(route.user_id)
        if owner_doc is None or owner_doc.is_deleted:
            owner_view = OwnerView(user_id=route.user_id, is_deleted=True)
        else:
            owner_view = OwnerView(
                user_id=owner_doc.id,
                profile_id=owner_doc.profile_id,
                profile_image_url=owner_doc.profile_image_url,
                is_deleted=False,
            )

        data.append(RecentRouteView(
            id=route.id,
            type=route.type,
            title=route.title,
            visibility=route.visibility,
            is_deleted=route.is_deleted,
            grade_type=route.grade_type,
            grade=route.grade,
            grade_color=route.grade_color,
            image_url=to_public_url(str(route.image_url)),
            overlay_image_url=to_public_url(str(route.overlay_image_url)) if route.overlay_image_url else None,
            place=place_view,
            wall_name=image.wall_name,
            wall_expiration_date=image.wall_expiration_date,
            owner=owner_view,
            my_total_count=urs.total_count,
            my_completed_count=urs.completed_count,
            my_last_activity_at=urs.last_activity_at,
            created_at=route.created_at,
            updated_at=route.updated_at,
        ))

    return RecentRoutesResponse(data=data)


@router.get("/recently-climbed-routes", response_model=RecentRoutesResponse)
async def get_recently_climbed_routes(
    limit: int = Query(default=9, ge=1, le=20),
    current_user: User = Depends(get_current_user),
):
    return await _build_recently_climbed_routes(current_user.id, limit)
```

Note: `PlaceView.cover_image_url` is already rewritten via `to_public_url()` inside `place_to_view` (see `routers/places.py:87`), so no additional treatment is needed here.

Double-check the spec field coverage: `id`, `type`, `title`, `visibility`, `is_deleted`, `grade_type`, `grade`, `grade_color`, `image_url`, `overlay_image_url`, `place`, `wall_name`, `wall_expiration_date`, `owner`, `my_total_count`, `my_completed_count`, `my_last_activity_at`, `created_at`, `updated_at` — all present. ✓

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/routers/test_my_recently_climbed_routes.py -v`
Expected: All 9 tests PASS.

- [ ] **Step 5: Run the whole API suite to check nothing else broke**

Run: `cd services/api && uv run pytest -v`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add services/api/app/routers/my.py services/api/tests/routers/test_my_recently_climbed_routes.py
git commit -m "feat(api): add GET /my/recently-climbed-routes"
```

---

### Task 9: Extend `GET /my/daily-routes` with `owner`

**Files:**
- Modify: `services/api/app/routers/my.py` (DailyRouteItem + get_daily_routes)
- Test: `services/api/tests/routers/test_my.py`

- [ ] **Step 1: Write the failing schema test**

Append to `services/api/tests/routers/test_my.py`:

```python
def test_daily_route_item_serializes_owner():
    """DailyRouteItem.owner should round-trip with camelCase aliases."""
    from beanie.odm.fields import PydanticObjectId
    from app.models.user import OwnerView
    from app.routers.my import DailyRouteItem

    snapshot = RouteSnapshot(grade_type="v_scale", grade="V4")
    owner = OwnerView(
        user_id=PydanticObjectId("507f1f77bcf86cd799439011"),
        profile_id="climber42",
        profile_image_url="https://cdn/x.jpg",
        is_deleted=False,
    )
    item = DailyRouteItem(
        route_id="507f1f77bcf86cd799439012",
        route_snapshot=snapshot,
        route_visibility="public",
        is_deleted=False,
        total_count=1,
        completed_count=1,
        attempted_count=0,
        total_duration=60.0,
        owner=owner,
    )
    dumped = item.model_dump(by_alias=True)
    assert dumped["owner"]["userId"] == "507f1f77bcf86cd799439011"
    assert dumped["owner"]["profileId"] == "climber42"
    assert dumped["owner"]["isDeleted"] is False


def test_daily_route_item_supports_deleted_owner():
    from beanie.odm.fields import PydanticObjectId
    from app.models.user import OwnerView
    from app.routers.my import DailyRouteItem

    snapshot = RouteSnapshot(grade_type="v_scale", grade="V4")
    item = DailyRouteItem(
        route_id="507f1f77bcf86cd799439012",
        route_snapshot=snapshot,
        route_visibility="public",
        is_deleted=False,
        total_count=1,
        completed_count=0,
        attempted_count=1,
        total_duration=30.0,
        owner=OwnerView(user_id=PydanticObjectId(), is_deleted=True),
    )
    dumped = item.model_dump(by_alias=True)
    assert dumped["owner"]["isDeleted"] is True
    assert dumped["owner"]["profileId"] is None
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/routers/test_my.py::test_daily_route_item_serializes_owner -v`
Expected: FAIL — `owner` field doesn't exist on `DailyRouteItem`.

- [ ] **Step 3: Add `owner` field to `DailyRouteItem`**

In `services/api/app/routers/my.py`, update the `DailyRouteItem` model (lines 143-154) to:

```python
class DailyRouteItem(BaseModel):
    model_config = model_config

    route_id: str
    route_snapshot: RouteSnapshot
    route_visibility: Visibility = Visibility.PUBLIC
    is_deleted: bool = False
    total_count: int
    completed_count: int
    attempted_count: int
    total_duration: float
    owner: OwnerView
```

Ensure `OwnerView` is imported at the top (Task 6 adds it; if not yet imported in this file, import it from `app.models.user`).

- [ ] **Step 4: Update the `$lookup` + `$set` stages to carry `userId`**

Inside `get_daily_routes` (around `services/api/app/routers/my.py:290-307`), change the `$lookup` stage and following `$set` to:

```python
        {"$lookup": {
            "from": "routes",
            "localField": "_id",
            "foreignField": "_id",
            "as": "route",
            "pipeline": [
                {"$project": {"visibility": 1, "isDeleted": 1, "userId": 1}},
            ],
        }},
        {"$set": {
            "routeVisibility": {
                "$ifNull": [{"$first": "$route.visibility"}, "public"],
            },
            "isDeleted": {
                "$ifNull": [{"$first": "$route.isDeleted"}, False],
            },
            "ownerUserId": {"$first": "$route.userId"},
        }},
        {"$unset": "route"},
```

- [ ] **Step 5: Batch-fetch owners and populate `owner`**

Replace the `routes = [DailyRouteItem(...) for r in doc["routes"]]` construction (lines 334-346) with:

```python
    raw_routes = doc["routes"]
    owner_ids = list({r["ownerUserId"] for r in raw_routes if r.get("ownerUserId") is not None})
    owner_by_id: dict[PydanticObjectId, User] = {}
    if owner_ids:
        owner_docs = await User.find(In(User.id, owner_ids)).to_list()
        owner_by_id = {u.id: u for u in owner_docs}

    def _owner_view(raw_owner_id) -> OwnerView:
        if raw_owner_id is None:
            # Route vanished entirely — fall back to tombstone.
            return OwnerView(user_id=PydanticObjectId(), is_deleted=True)
        owner_doc = owner_by_id.get(raw_owner_id)
        if owner_doc is None or owner_doc.is_deleted:
            return OwnerView(user_id=raw_owner_id, is_deleted=True)
        return OwnerView(
            user_id=owner_doc.id,
            profile_id=owner_doc.profile_id,
            profile_image_url=owner_doc.profile_image_url,
            is_deleted=False,
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
            owner=_owner_view(r.get("ownerUserId")),
        )
        for r in raw_routes
    ]
```

Ensure `In` is imported at the top of the file:

```python
from beanie.odm.operators.find.comparison import In
```

- [ ] **Step 6: Run schema tests**

Run: `cd services/api && uv run pytest tests/routers/test_my.py -v`
Expected: All existing tests still pass AND the new two tests pass.

- [ ] **Step 7: Commit**

```bash
git add services/api/app/routers/my.py services/api/tests/routers/test_my.py
git commit -m "feat(api): add owner field to /my/daily-routes response"
```

---

## Phase 3 — Mobile: models + providers + tab

### Task 10: Extend `RouteData` with `owner` and `isDeleted`

**Files:**
- Modify: `apps/mobile/lib/models/route_data.dart`

- [ ] **Step 1: Add `OwnerInfo` class and wire into `RouteData`**

Replace the top of `apps/mobile/lib/models/route_data.dart` (above `RouteData`) with:

```dart
import 'place_data.dart';
import 'polygon_data.dart';

class OwnerInfo {
  final String userId;
  final String? profileId;
  final String? profileImageUrl;
  final bool isDeleted;

  const OwnerInfo({
    required this.userId,
    this.profileId,
    this.profileImageUrl,
    this.isDeleted = false,
  });

  factory OwnerInfo.fromJson(Map<String, dynamic> json) => OwnerInfo(
        userId: json['userId'] as String,
        profileId: json['profileId'] as String?,
        profileImageUrl: json['profileImageUrl'] as String?,
        isDeleted: json['isDeleted'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        if (profileId != null) 'profileId': profileId,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
        'isDeleted': isDeleted,
      };
}

enum RouteType {
  bouldering,
  endurance,
}
```

(Keep the rest of the enums intact — `BoulderingHoldType`, `GripHand` — as currently defined below.)

- [ ] **Step 2: Add `owner` and `isDeleted` fields to `RouteData`**

In the `RouteData` class body, add to the field list (after `myLastActivityAt`):

```dart
  final OwnerInfo? owner;
  final bool isDeleted;
```

Add matching constructor parameters (keep them at the end):

```dart
    this.owner,
    this.isDeleted = false,
```

In `RouteData.fromJson`, add (before the closing `);`):

```dart
      owner: json['owner'] != null
          ? OwnerInfo.fromJson(json['owner'] as Map<String, dynamic>)
          : null,
      isDeleted: json['isDeleted'] as bool? ?? false,
```

In `toJson`, add:

```dart
        if (owner != null) 'owner': owner!.toJson(),
        'isDeleted': isDeleted,
```

- [ ] **Step 3: Verify analyzer is clean**

Run: `cd apps/mobile && flutter analyze`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/models/route_data.dart
git commit -m "feat(mobile): add owner and isDeleted to RouteData"
```

---

### Task 11: Create `mainTabIndexProvider` and migrate `MainTabPage`

**Files:**
- Create: `apps/mobile/lib/providers/main_tab_provider.dart`
- Modify: `apps/mobile/lib/pages/main_tab.dart`

- [ ] **Step 1: Create the provider**

Create `apps/mobile/lib/providers/main_tab_provider.dart`:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'main_tab_provider.g.dart';

/// Currently-selected index of the bottom navigation bar in `MainTabPage`.
/// Exposed as a provider so non-descendant widgets (e.g. the home screen's
/// "기록 전체" link) can switch tabs via `ref.read(mainTabIndexProvider.notifier).set(2)`.
@riverpod
class MainTabIndex extends _$MainTabIndex {
  @override
  int build() => 0;

  void set(int index) {
    if (index < 0 || index > 2) return;
    state = index;
  }
}
```

- [ ] **Step 2: Generate `.g.dart`**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: builds `apps/mobile/lib/providers/main_tab_provider.g.dart`.

- [ ] **Step 3: Wire `MainTabPage` to the provider**

Replace `apps/mobile/lib/pages/main_tab.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/activity_refresh_provider.dart';
import '../providers/main_tab_provider.dart';
import '../providers/user_provider.dart';
import 'home.dart';
import 'routes_page.dart';
import 'my_page.dart';

class MainTabPage extends HookConsumerWidget {
  const MainTabPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(mainTabIndexProvider);
    final myPageRefreshSignal = useState(0);
    final unreadCount = ref.watch(userProfileProvider).whenOrNull(
              data: (u) => u.unreadNotificationCount,
            ) ??
        0;

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: [
          const HomePage(),
          const RoutesPage(),
          MyPage(refreshSignal: myPageRefreshSignal.value),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          if (index == 2 && ref.read(activityDirtyProvider)) {
            ref.read(activityDirtyProvider.notifier).state = false;
            myPageRefreshSignal.value++;
          }
          ref.read(mainTabIndexProvider.notifier).set(index);
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: AppLocalizations.of(context)!.navHome,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.terrain),
            label: AppLocalizations.of(context)!.navRoutes,
          ),
          BottomNavigationBarItem(
            icon: Badge.count(
              count: unreadCount,
              isLabelVisible: unreadCount > 0,
              child: const Icon(Icons.person),
            ),
            label: AppLocalizations.of(context)!.navMy,
          ),
        ],
      ),
    );
  }
}
```

Note: the programmatic tab switch via `mainTabIndexProvider.notifier.set()` does NOT fire the `activityDirtyProvider` side-effect. The home screen "기록 전체" link takes the user to MY without going through the `onTap` path, so MY won't auto-refresh from that action. This matches the spec (which only calls for invalidating `recentClimbedRoutesProvider` on activity writes; MY has its own refresh flow via `activityDirtyProvider`).

- [ ] **Step 4: Verify analyzer is clean**

Run: `cd apps/mobile && flutter analyze`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/providers/main_tab_provider.dart apps/mobile/lib/providers/main_tab_provider.g.dart apps/mobile/lib/pages/main_tab.dart
git commit -m "feat(mobile): promote MainTab current index to Riverpod provider"
```

---

### Task 12: Create `recentClimbedRoutesProvider`

**Files:**
- Create: `apps/mobile/lib/providers/recent_climbed_routes_provider.dart`

- [ ] **Step 1: Create the provider**

Create `apps/mobile/lib/providers/recent_climbed_routes_provider.dart`:

```dart
import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/route_data.dart';
import '../services/http_client.dart';

part 'recent_climbed_routes_provider.g.dart';

@riverpod
Future<List<RouteData>> recentClimbedRoutes(
  RecentClimbedRoutesRef ref,
) async {
  final response = await AuthorizedHttpClient.get(
    '/my/recently-climbed-routes?limit=9',
  );
  if (response.statusCode != 200) {
    throw Exception(
      'Failed to load recently climbed routes (status ${response.statusCode})',
    );
  }
  final decoded = jsonDecode(utf8.decode(response.bodyBytes));
  final data = decoded['data'] as List<dynamic>;
  return data
      .map((e) => RouteData.fromJson(e as Map<String, dynamic>))
      .toList();
}
```

- [ ] **Step 2: Generate `.g.dart`**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: builds `recent_climbed_routes_provider.g.dart`.

- [ ] **Step 3: Verify analyzer is clean**

Run: `cd apps/mobile && flutter analyze`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/providers/recent_climbed_routes_provider.dart apps/mobile/lib/providers/recent_climbed_routes_provider.g.dart
git commit -m "feat(mobile): add recentClimbedRoutesProvider"
```

---

## Phase 4 — Mobile: l10n + OwnerBadge

### Task 13: Add l10n keys to all four locale files

**Files:**
- Modify: `apps/mobile/lib/l10n/app_ko.arb`
- Modify: `apps/mobile/lib/l10n/app_en.arb`
- Modify: `apps/mobile/lib/l10n/app_ja.arb`
- Modify: `apps/mobile/lib/l10n/app_es.arb`

- [ ] **Step 1: Add keys to Korean**

In `apps/mobile/lib/l10n/app_ko.arb`, insert before the final `"homeGreetingSub": "오늘도 올라가볼까요?"` line (so the new keys stay inside the JSON object). Pattern: append them as distinct keys just before the closing `}`; keep `homeGreetingSub` as the last key or move it above. Simplest: just add seven new keys somewhere stable (e.g. after `recentWallPhotos`).

Example insertion after the existing `"viewAll": "전체 보기",` line:

```json
  "recentlyClimbedRoutesTitle": "최근 운동한 루트",
  "recentlyClimbedRoutesSubtitle": "활동 기록 기준",
  "viewAllRecords": "기록 전체",
  "deletedUser": "탈퇴한 회원",
  "noClimbedRoutesYet": "아직 운동한 루트가 없어요",
  "startFirstWorkoutHint": "루트를 골라 첫 운동을 시작해보세요",
  "viewRoutes": "루트 보러 가기",
```

- [ ] **Step 2: Add keys to English (`app_en.arb`)**

Same insertion point. Values:

```json
  "recentlyClimbedRoutesTitle": "Recently climbed",
  "recentlyClimbedRoutesSubtitle": "By activity log",
  "viewAllRecords": "All records",
  "deletedUser": "Deleted user",
  "noClimbedRoutesYet": "No climbs logged yet",
  "startFirstWorkoutHint": "Pick a route to start your first workout",
  "viewRoutes": "Browse routes",
```

- [ ] **Step 3: Add keys to Japanese (`app_ja.arb`)**

```json
  "recentlyClimbedRoutesTitle": "最近の活動",
  "recentlyClimbedRoutesSubtitle": "活動記録順",
  "viewAllRecords": "すべての記録",
  "deletedUser": "退会済みユーザー",
  "noClimbedRoutesYet": "まだ活動記録がありません",
  "startFirstWorkoutHint": "ルートを選んで運動を始めましょう",
  "viewRoutes": "ルートを見る",
```

- [ ] **Step 4: Add keys to Spanish (`app_es.arb`)**

```json
  "recentlyClimbedRoutesTitle": "Rutas recientes",
  "recentlyClimbedRoutesSubtitle": "Por registro",
  "viewAllRecords": "Todos",
  "deletedUser": "Usuario eliminado",
  "noClimbedRoutesYet": "Aún no hay actividad",
  "startFirstWorkoutHint": "Elige una ruta y empieza",
  "viewRoutes": "Ver rutas",
```

- [ ] **Step 5: Regenerate l10n bindings**

Run: `cd apps/mobile && flutter gen-l10n`
Expected: builds updated `AppLocalizations` with the seven new accessors.

- [ ] **Step 6: Verify analyzer is clean**

Run: `cd apps/mobile && flutter analyze`
Expected: 0 issues.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/l10n/app_ko.arb apps/mobile/lib/l10n/app_en.arb apps/mobile/lib/l10n/app_ja.arb apps/mobile/lib/l10n/app_es.arb
git commit -m "i18n(mobile): add keys for recently-climbed-routes section"
```

---

### Task 14: Create `OwnerBadge` widget

**Files:**
- Create: `apps/mobile/lib/widgets/common/owner_badge.dart`

- [ ] **Step 1: Create the widget**

Create `apps/mobile/lib/widgets/common/owner_badge.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../models/route_data.dart';

class OwnerBadge extends StatelessWidget {
  final OwnerInfo owner;
  final double avatarSize;

  const OwnerBadge({
    super.key,
    required this.owner,
    this.avatarSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textStyle = TextStyle(
      fontSize: 12,
      color: Colors.grey[600],
    );

    if (owner.isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_off_outlined,
              size: avatarSize * 0.6,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(width: 6),
          Text(l10n.deletedUser, style: textStyle),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipOval(
          child: SizedBox(
            width: avatarSize,
            height: avatarSize,
            child: owner.profileImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: owner.profileImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _initialAvatar(),
                    errorWidget: (_, __, ___) => _initialAvatar(),
                  )
                : _initialAvatar(),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            owner.profileId != null ? '@${owner.profileId}' : '',
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _initialAvatar() {
    final initial = (owner.profileId ?? '?').substring(0, 1).toUpperCase();
    return Container(
      color: const Color(0xFFE6ECFB),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF1E4BD8),
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify analyzer is clean**

Run: `cd apps/mobile && flutter analyze`
Expected: 0 issues.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/common/owner_badge.dart
git commit -m "feat(mobile): add OwnerBadge shared widget"
```

---

## Phase 5 — Mobile: RecentClimbedRouteCard + Section

### Task 15: Create `RecentClimbedRouteCard`

**Files:**
- Create: `apps/mobile/lib/widgets/home/recent_climbed_route_card.dart`

This card is essentially `RouteListItem` minus the 3-dot `PopupMenuButton` + plus an `OwnerBadge` line. Tombstone handling for deleted/private routes taps a snackbar instead of navigating.

- [ ] **Step 1: Create the file**

Create `apps/mobile/lib/widgets/home/recent_climbed_route_card.dart`:

```dart
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../models/route_data.dart';
import '../../pages/viewers/route_viewer.dart';
import '../../providers/user_provider.dart';
import '../../services/http_client.dart';
import '../common/owner_badge.dart';

class RecentClimbedRouteCard extends ConsumerStatefulWidget {
  final RouteData route;

  const RecentClimbedRouteCard({super.key, required this.route});

  @override
  ConsumerState<RecentClimbedRouteCard> createState() =>
      _RecentClimbedRouteCardState();
}

class _RecentClimbedRouteCardState
    extends ConsumerState<RecentClimbedRouteCard> {
  bool _isLoading = false;

  bool get _isBlocked {
    final route = widget.route;
    if (route.isDeleted) return true;
    final myId = ref.read(userProfileProvider).valueOrNull?.id;
    if (route.visibility == 'private' &&
        route.owner != null &&
        route.owner!.userId != myId) {
      return true;
    }
    return false;
  }

  Future<void> _onTap() async {
    if (_isLoading) return;
    final l10n = AppLocalizations.of(context)!;

    if (widget.route.isDeleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.routeDeletedSnack)),
      );
      return;
    }
    if (_isBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.routePrivateSnack)),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response =
          await AuthorizedHttpClient.get('/routes/${widget.route.id}');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final routeData =
            RouteData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RouteViewer(routeData: routeData)),
        );
        return;
      }
      if (response.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.routePrivateSnack)),
        );
        return;
      }
      if (response.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.routeDeletedSnack)),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.routeUnavailableSnack)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedLoadData)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleShare() {
    const baseUrl = 'https://besetter-api-371038003203.asia-northeast3.run.app';
    Share.share('$baseUrl/share/routes/${widget.route.id}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final route = widget.route;
    final imageUrl = route.overlayImageUrl ?? route.imageUrl;
    final gradeColor = route.gradeColor != null
        ? Color(int.parse(route.gradeColor!.replaceFirst('#', ''), radix: 16))
        : const Color(0xFF1E4BD8);

    final typeLabel =
        route.type == RouteType.bouldering ? l10n.bouldering : l10n.endurance;
    final completed = route.myCompletedCount ?? 0;
    final attempts = route.myTotalCount ?? 0;
    final lastAt = route.myLastActivityAt ?? route.createdAt;

    final placeText = [route.place?.name, route.wallName]
        .whereType<String>()
        .join(' · ');

    final showOwner = route.owner != null &&
        route.owner!.userId != ref.read(userProfileProvider).valueOrNull?.id;
    final isBlocked = _isBlocked;
    final blockedIcon = route.isDeleted ? '🗑' : '🔒';
    final blockedText =
        route.isDeleted ? l10n.routeDeletedLabel : l10n.routePrivateLabel;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final thumbSize = constraints.maxWidth / 2.618;
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: thumbSize,
                            height: thumbSize,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) =>
                                        Container(color: Colors.grey[200]),
                                    errorWidget: (_, __, ___) => Container(
                                      color: Colors.grey[300],
                                      child: const Icon(
                                        Icons.broken_image,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: gradeColor,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      route.grade,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                  ),
                                ),
                                if (isBlocked)
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: Colors.black.withOpacity(0.35),
                                      child: const SizedBox(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 40),
                                  child: Text(
                                    '${typeLabel.toUpperCase()} · ${route.gradeType}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: Colors.grey[500],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  route.title ?? route.grade,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                    height: 1.2,
                                    color: Color(0xFF0F1A2E),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (placeText.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.place_outlined,
                                        size: 13,
                                        color: Colors.grey[500],
                                      ),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          placeText,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (showOwner) ...[
                                  const SizedBox(height: 6),
                                  OwnerBadge(owner: route.owner!),
                                ],
                                if (isBlocked) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        blockedIcon,
                                        style: const TextStyle(fontSize: 11),
                                      ),
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
                                const Spacer(),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 16,
                                      color: completed > 0
                                          ? const Color(0xFF1EB980)
                                          : Colors.grey[400],
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      l10n.routeCardCompleted(completed),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: completed > 0
                                            ? const Color(0xFF0F1A2E)
                                            : Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      l10n.routeCardAttempts(attempts),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Spacer(),
                                    Text(
                                      timeago.format(lastAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: InkWell(
                    onTap: _handleShare,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.share_outlined,
                        size: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ),
                if (_isLoading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black26,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
```

Note: `ref.read(userProfileProvider).valueOrNull?.id` is used here. Confirm `UserState` exposes an `id` field — it does, per `apps/mobile/lib/providers/user_provider.dart:85`.

- [ ] **Step 2: Verify analyzer is clean**

Run: `cd apps/mobile && flutter analyze`
Expected: 0 issues.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/home/recent_climbed_route_card.dart
git commit -m "feat(mobile): add RecentClimbedRouteCard widget"
```

---

### Task 16: Create `RecentClimbedRoutesSection`

**Files:**
- Create: `apps/mobile/lib/widgets/home/recent_climbed_routes_section.dart`

- [ ] **Step 1: Create the file**

Create `apps/mobile/lib/widgets/home/recent_climbed_routes_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../providers/main_tab_provider.dart';
import '../../providers/recent_climbed_routes_provider.dart';
import 'recent_climbed_route_card.dart';

class RecentClimbedRoutesSection extends ConsumerWidget {
  const RecentClimbedRoutesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(recentClimbedRoutesProvider);

    return async.when(
      loading: () => const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.failedLoadData,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(recentClimbedRoutesProvider),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
      data: (routes) {
        if (routes.isEmpty) return const _EmptyStateCard();
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              for (var i = 0; i < routes.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                RecentClimbedRouteCard(route: routes[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _EmptyStateCard extends ConsumerWidget {
  const _EmptyStateCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text('🧗', style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 12),
            Text(
              l10n.noClimbedRoutesYet,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F1A2E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.startFirstWorkoutHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () =>
                  ref.read(mainTabIndexProvider.notifier).set(1),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF1E4BD8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.viewRoutes,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward, size: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

The `l10n.retry` key already exists (used elsewhere). If not, fall back to `l10n.refresh` or the raw string "Retry" — but verify it exists first.

- [ ] **Step 2: Verify `l10n.retry` exists**

Run: `grep '"retry"' apps/mobile/lib/l10n/app_ko.arb apps/mobile/lib/l10n/app_en.arb apps/mobile/lib/l10n/app_ja.arb apps/mobile/lib/l10n/app_es.arb`

If any locale is missing the key, add `"retry"` ("다시 시도" / "Retry" / "再試行" / "Reintentar") and re-run `flutter gen-l10n`.

- [ ] **Step 3: Verify analyzer is clean**

Run: `cd apps/mobile && flutter analyze`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/widgets/home/recent_climbed_routes_section.dart apps/mobile/lib/l10n/
git commit -m "feat(mobile): add RecentClimbedRoutesSection with empty state"
```

---

## Phase 6 — Mobile: integration

### Task 17: Insert section into `HomePage`

**Files:**
- Modify: `apps/mobile/lib/pages/home.dart`

- [ ] **Step 1: Convert body to scrollable**

The current `HomePage` body is a fixed-height `Column`. With 9 cards added below the carousel, content will overflow — convert to `SingleChildScrollView`.

Replace the `body: SafeArea(child: Column(...))` block with a scrollable version, and add the new section + header right after `const WallImageCarousel()`:

Replace lines 33-138 of `apps/mobile/lib/pages/home.dart` with:

```dart
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F7),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 48, 8, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.homeGreeting(greetingName),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              height: 1.1,
                              color: Color(0xFF0F1A2E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.homeGreetingSub,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.4,
                              height: 1.15,
                              color: Color(0xFF5C6779),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Badge.count(
                        count: unreadNotifCount,
                        isLabelVisible: unreadNotifCount > 0,
                        child: const Icon(
                          Icons.notifications_outlined,
                          color: Color(0xFF2C2F30),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationsPage()),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                child: HoldEditorButton(
                  buttonKey: editorButtonKey,
                  buttonLabel: l10n.takeWallPhoto,
                  buttonIcon: Icons.camera_alt,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.recentWallPhotos,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: Color(0xFF0F1A2E),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/images'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1E4BD8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        l10n.viewAll,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const WallImageCarousel(),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.recentlyClimbedRoutesTitle,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: Color(0xFF0F1A2E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.recentlyClimbedRoutesSubtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.read(mainTabIndexProvider.notifier).set(2),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1E4BD8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        l10n.viewAllRecords,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const RecentClimbedRoutesSection(),
            ],
          ),
        ),
      ),
    );
```

Add the two new imports at the top of the file:

```dart
import '../providers/main_tab_provider.dart';
import '../widgets/home/recent_climbed_routes_section.dart';
```

- [ ] **Step 2: Verify analyzer is clean**

Run: `cd apps/mobile && flutter analyze`
Expected: 0 issues.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/pages/home.dart
git commit -m "feat(mobile): add recently-climbed-routes section to home"
```

---

### Task 18: Add `OwnerBadge` to MY page `_DailyRouteCard`

**Files:**
- Modify: `apps/mobile/lib/pages/my_page.dart`

- [ ] **Step 1: Add import and parse owner in build**

In `apps/mobile/lib/pages/my_page.dart`, add at the top:

```dart
import '../models/route_data.dart';
import '../widgets/common/owner_badge.dart';
import '../providers/user_provider.dart';
```

(Only add imports that aren't already present. If `user_provider.dart` is already imported, skip it.)

- [ ] **Step 2: Convert `_DailyRouteCard` to ConsumerStatelessWidget**

Change the class signature:

```dart
class _DailyRouteCard extends ConsumerWidget {
```

And the `build` signature:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
```

In the body, after `final imageUrl = ...;`, add:

```dart
    final ownerJson = route['owner'] as Map<String, dynamic>?;
    final owner = ownerJson != null ? OwnerInfo.fromJson(ownerJson) : null;
    final myId = ref.watch(userProfileProvider).valueOrNull?.id;
    final showOwner = owner != null && owner.userId != myId;
```

- [ ] **Step 3: Insert the badge below the place line**

Find the existing block (around line 993-1014):

```dart
                                Text(placeName, style: const TextStyle(fontSize: 12, color: Color(0xFF595C5D))),
                                if (isBlocked) ...[
```

Insert an `OwnerBadge` call between them:

```dart
                                Text(placeName, style: const TextStyle(fontSize: 12, color: Color(0xFF595C5D))),
                                if (showOwner) ...[
                                  const SizedBox(height: 4),
                                  OwnerBadge(owner: owner),
                                ],
                                if (isBlocked) ...[
```

- [ ] **Step 4: Verify analyzer is clean**

Run: `cd apps/mobile && flutter analyze`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/pages/my_page.dart
git commit -m "feat(mobile): show owner badge on MY daily route cards"
```

---

### Task 19: Invalidate `recentClimbedRoutesProvider` on activity create/delete

**Files:**
- Modify: `apps/mobile/lib/pages/viewers/route_viewer.dart`
- Modify: `apps/mobile/lib/widgets/viewers/workout_log_panel.dart`

The home section lives inside an `IndexedStack` and is therefore always present even when the user is in another tab. `activityDirtyProvider` isn't enough — we must explicitly `invalidate` the provider whenever an activity is written.

- [ ] **Step 1: Update `route_viewer.dart`**

In `apps/mobile/lib/pages/viewers/route_viewer.dart`, add the import near the top:

```dart
import '../../providers/recent_climbed_routes_provider.dart';
```

Find the `onActivityCreated` callback at line 321-324:

```dart
                    onActivityCreated: (activityData) {
                      (_workoutLogKey.currentState as dynamic)?.addActivity(activityData);
                      ProviderScope.containerOf(context).read(activityDirtyProvider.notifier).state = true;
                    },
```

Change it to:

```dart
                    onActivityCreated: (activityData) {
                      (_workoutLogKey.currentState as dynamic)?.addActivity(activityData);
                      final container = ProviderScope.containerOf(context);
                      container.read(activityDirtyProvider.notifier).state = true;
                      container.invalidate(recentClimbedRoutesProvider);
                    },
```

- [ ] **Step 2: Update `workout_log_panel.dart`**

In `apps/mobile/lib/widgets/viewers/workout_log_panel.dart`, add the import:

```dart
import '../../providers/recent_climbed_routes_provider.dart';
```

Find line 199:

```dart
      ProviderScope.containerOf(context).read(activityDirtyProvider.notifier).state = true;
```

Change it to:

```dart
      final container = ProviderScope.containerOf(context);
      container.read(activityDirtyProvider.notifier).state = true;
      container.invalidate(recentClimbedRoutesProvider);
```

- [ ] **Step 3: Verify analyzer is clean**

Run: `cd apps/mobile && flutter analyze`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/pages/viewers/route_viewer.dart apps/mobile/lib/widgets/viewers/workout_log_panel.dart
git commit -m "feat(mobile): invalidate recentClimbedRoutesProvider on activity write"
```

---

## Phase 7 — Verification

### Task 20: Manual QA checklist + final analyze

**Files:** none (verification only)

- [ ] **Step 1: API — run full suite**

Run: `cd services/api && uv run pytest -v`
Expected: All tests pass.

- [ ] **Step 2: Mobile — run analyze and tests**

Run: `cd apps/mobile && flutter analyze`
Expected: 0 issues.

Run: `cd apps/mobile && flutter test`
Expected: All tests pass (no new Flutter tests added; just make sure existing ones still compile).

- [ ] **Step 3: Simulator walkthrough** (manual; document any regressions in commit message if found)

Checklist:
- Home screen renders "최근 운동한 루트" section below wall photos.
- Owner badge: hidden for my own routes, shown with "@profileId" for others, shown as "탈퇴한 회원" for withdrawn users.
- Deleted route card: thumbnail dimmed, "🗑 삭제된 루트입니다." label, tap → snackbar only.
- Private (other-user) route card: dimmed, "🔒 비공개된 루트입니다." label, tap → snackbar.
- Empty state: "아직 운동한 루트가 없어요" card renders, CTA switches to Routes tab (index 1).
- "기록 전체" link on section header: switches to MY tab (index 2).
- Log a new activity → return to home → new card appears at top (or moves to top if route was already there).
- Delete an activity from the route viewer → home reflects updated `lastActivityAt` (may drop the card if it was the sole activity).
- MY page daily cards: owner badge appears on other-user routes; stays hidden on own-user routes.

- [ ] **Step 4: No further commit needed if all checks pass.**

---

## Self-Review Notes

**Spec coverage check:**
- 범위 안 §1 (endpoint): Task 8 ✓
- 범위 안 §2 (daily-routes owner): Task 9 ✓
- 범위 안 §3 (lastActivityAt 갱신): Tasks 1–4 ✓
- 범위 안 §4 (Mongo index): Task 5 ✓
- 범위 안 §5 (mobile home section): Tasks 15–17 ✓
- 범위 안 §6 (OwnerView + OwnerBadge): Tasks 6, 14 ✓
- §4 lastActivityAt recompute with `still_present`: Task 3 ✓ (exclusion via `deleted_activity_id`)
- `/my/daily-routes` owner aggregate pipeline: Task 9 ✓ (projects `userId`, batch-fetches users)
- No backfill: honored — `$max` picks up values as activities arrive (Task 1 note)
- `mainTabIndexProvider`: Task 11 ✓
- l10n for 7 new keys × 4 locales: Task 13 ✓
- Empty state card: Task 16 ✓
- Deleted/private tombstones: Task 15 ✓
- Invalidation on activity write: Task 19 ✓

**Type consistency:**
- `OwnerView` (Python) ↔ `OwnerInfo` (Dart): both have `user_id`, `profile_id`, `profile_image_url`, `is_deleted`. Serialization uses camelCase aliases (Pydantic `model_config`) which match the Dart JSON keys.
- `RecentRouteView.my_last_activity_at` is non-Optional (we skip null rows in the query). `RouteData.myLastActivityAt` is nullable for compatibility with `/routes/{id}` responses where stats are optional.
- `mainTabIndexProvider.set(int)` clamps to `[0, 2]`.

**Placeholder scan:** None found. All steps include concrete code or shell commands.
