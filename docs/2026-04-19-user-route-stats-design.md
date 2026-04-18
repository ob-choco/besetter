# User-Level Route Statistics (userStats)

## Goal

Maintain per-user aggregate statistics around route activities and route creation in a dedicated `userStats` collection. Counters are maintained via `$inc` post-processing at mutation time, with a backfill script for bootstrap and reconciliation.

## Scope

**Covered counters (all per-user):**

- **Activity counts** (all routes): total, completed, verified+completed
- **Distinct routes with activity** (all routes, per status bucket): count of distinct routes where the user has ≥1 activity of that kind
- **Distinct days with activity**: count of distinct local dates where the user has ≥1 activity
- **Distinct own routes with own activity** (per status bucket): count of distinct user-owned routes where the user has ≥1 of their own activity of that kind
- **Routes created** (currently alive, i.e. not soft-deleted): total, bouldering, endurance

**Non-goals:**

- Duration aggregates (can be added later by extending `ActivityCounters`).
- Strict ACID across collections (no transactions).
- Real-time exposure to clients (the API surface is out of scope of this spec; this spec only lands the data layer and mutation hooks).

## Data Model

New collection `userStats` (MongoDB), one document per user, unique index on `user_id`.

```python
# app/models/user_stats.py

class ActivityCounters(BaseModel):
    total_count: int = 0
    completed_count: int = 0
    verified_completed_count: int = 0

class RoutesCreatedCounters(BaseModel):
    total_count: int = 0
    bouldering_count: int = 0
    endurance_count: int = 0

class UserStats(Document):
    user_id: PydanticObjectId
    activity: ActivityCounters                # activity counts across all routes
    distinct_routes: ActivityCounters         # distinct routes the user has ≥1 activity on (per bucket)
    distinct_days: int = 0                    # distinct local dates with ≥1 activity
    own_routes_activity: ActivityCounters     # distinct own routes with ≥1 of user's own activity (per bucket)
    routes_created: RoutesCreatedCounters     # currently-alive routes the user created
    updated_at: Optional[datetime] = None

    class Settings:
        name = "userStats"
        indexes = [IndexModel([("userId", ASCENDING)], unique=True)]
        keep_nulls = True
```

**Notes:**

- `ActivityCounters` mirrors the existing `ActivityStats` / `UserRouteStats` naming (`total_count`, `completed_count`, `verified_completed_count`) without duration fields.
- `distinct_days` is a single integer — not bucketed by status (per requirements).
- All counters default to 0. First mutation creates the doc via `upsert=True` + `$setOnInsert`.

## Status/Bucket Semantics

Existing activity semantics apply (unchanged):

- `total_count`: every activity
- `completed_count`: `activity.status == COMPLETED`
- `verified_completed_count`: `activity.status == COMPLETED AND activity.location_verified`

`_build_stats_inc()` in `routers/activities.py:101-123` already returns this delta dict and will be reused.

## Local Date (Timezone)

Activity local date is computed as:

```python
tz_name = activity.timezone or "UTC"
local_date_str = activity.started_at.astimezone(ZoneInfo(tz_name)).date().isoformat()  # "YYYY-MM-DD"
```

This mirrors the existing helper `_to_local_date_str` in `routers/my.py:30-32` and the aggregation pattern `{"$ifNull": ["$timezone", "UTC"]}`.

## Service Module: `app/services/user_stats.py`

### Public API

```python
async def on_activity_created(activity: Activity, route: Route) -> None
async def on_activity_deleted(activity: Activity, route: Route) -> None
async def on_route_created(route: Route) -> None
async def on_route_soft_deleted(route: Route) -> None
```

Each function is wrapped in `try/except Exception`. Failures are logged via `logger.exception(...)` and swallowed — main mutation is unaffected. Drift is resolved by running `scripts/backfill_user_stats.py`.

### Internal Helpers

```python
def _bucket_deltas(status: ActivityStatus, location_verified: bool) -> dict[str, int]
    # {"total_count": ±1, "completed_count": ±1 if completed else 0, "verified_completed_count": ±1 if completed and verified else 0}

async def _apply_user_route_stats_delta(user_id, route_id, deltas) -> tuple[Counters, Counters]
    # find_one_and_update with $inc and upsert=True, return_document=AFTER.
    # Returns (before_counts, after_counts) where before = after − delta. Atomic per document.

def _local_date_str(activity: Activity) -> str
    # activity.started_at.astimezone(ZoneInfo(activity.timezone or "UTC")).date().isoformat()

async def _recount_local_day(user_id, local_date_str) -> int
    # Aggregates activities where user_id == user_id AND project(localDate via $ifNull timezone) == local_date_str.
    # Returns the count.
```

### Behavior

**`on_activity_created(activity, route)`**

1. `deltas = _bucket_deltas(activity.status, activity.location_verified)` (positive).
2. `(before, after) = _apply_user_route_stats_delta(activity.user_id, activity.route_id, deltas)`.
3. For each bucket in `{total_count, completed_count, verified_completed_count}`:
   - If `before[b] == 0 and after[b] >= 1`: `userStats[user].distinct_routes.<b> += 1`.
   - If (1) `before[b] == 0 and after[b] >= 1` AND (2) `route.user_id == activity.user_id` AND (3) `not route.is_deleted`: `userStats[user].own_routes_activity.<b> += 1`.
4. `userStats[user].activity.<b> += deltas[b]` for each bucket (direct `$inc`).
5. `count = await _recount_local_day(activity.user_id, _local_date_str(activity))`. If `count == 1`: `userStats[user].distinct_days += 1`.

**`on_activity_deleted(activity, route)`**

1. `deltas = _bucket_deltas(...)` (negative).
2. `(before, after) = _apply_user_route_stats_delta(...)`.
3. For each bucket:
   - If `before[b] >= 1 and after[b] == 0`: `userStats[user].distinct_routes.<b> -= 1`.
   - If (1) `before[b] >= 1 and after[b] == 0` AND (2) `route.user_id == activity.user_id` AND (3) `not route.is_deleted`: `userStats[user].own_routes_activity.<b> -= 1`.
     - **`route.is_deleted` check**: if the route was already soft-deleted, `own_routes_activity` was already decremented at soft-delete time (see `on_route_soft_deleted` below). Skipping here prevents double-decrement.
4. `userStats[user].activity.<b> -= |deltas[b]|` for each bucket.
5. If `after == {total:0, completed:0, verified_completed:0}`: delete the `UserRouteStats` document (mirrors existing cleanup).
6. `count = await _recount_local_day(...)`. If `count == 0`: `userStats[user].distinct_days -= 1`.

**`on_route_created(route)`**

1. `userStats[route.user_id].routes_created.total_count += 1`.
2. `userStats[route.user_id].routes_created.<type>_count += 1` where `<type>` ∈ `{bouldering, endurance}`.

**`on_route_soft_deleted(route)`**

1. `userStats[route.user_id].routes_created.total_count -= 1`.
2. `userStats[route.user_id].routes_created.<type>_count -= 1`.
3. Fetch `UserRouteStats(user_id=route.user_id, route_id=route.id)`. If it exists, for each bucket where its value ≥ 1: `userStats[route.user_id].own_routes_activity.<bucket> -= 1`.

`Route.type` is immutable on the edit endpoint (`routers/routes.py` edit body does not include `type`), so no type-change handling is needed.

### Upserts

Every `userStats` update uses `upsert=True`. First touch creates the document; `$setOnInsert` sets `updated_at = datetime.utcnow()`. Subsequent updates `$set` `updated_at`.

## Router Integration

### `routers/activities.py`

- `create_activity` (around L231-275): after saving the activity document, call `await user_stats.on_activity_created(activity, route)`. The existing `_update_user_route_stats` logic (L131-...) moves **into** `on_activity_created` as its internal implementation — the router no longer calls it directly. `_update_route_stats` (which maintains the embedded `Route.activity_stats`) stays in place as-is; it serves a different purpose.
- `delete_activity` (around L278-307): after deleting the activity, call `await user_stats.on_activity_deleted(activity, route)`. Same ownership handoff — `UserRouteStats` decrement moves into the service.

### `routers/routes.py`

- `create_route` (around L95-166): after the route is saved, call `await user_stats.on_route_created(route)`.
- `delete_route` (around L561-580): after setting `is_deleted = True` and saving, call `await user_stats.on_route_soft_deleted(route)`.

### Refactor Boundaries

- **Move into service**: `_update_user_route_stats` (UserRouteStats upsert with $inc + last_activity_at set) and its symmetric decrement.
- **Stay in router**: `_build_stats_inc` (shared utility; moved later if needed), `_update_route_stats` (embedded `Route.activity_stats` maintenance — unrelated to user-level stats).

## Backfill Script: `scripts/backfill_user_stats.py`

Idempotent full recomputation.

**Modes:**

- Default: iterate all users in `users` collection.
- `--user-id <id>`: recompute a single user (manual recovery).

**Per-user algorithm:**

1. `activity`: aggregate `activities` where `user_id == U`:
   - `total_count = count`
   - `completed_count = sum($cond[status=="completed", 1, 0])`
   - `verified_completed_count = sum($cond[status=="completed" AND location_verified, 1, 0])`
2. `distinct_routes`: aggregate `userRouteStats` where `user_id == U`:
   - `total_count = sum($cond[totalCount>=1, 1, 0])`
   - `completed_count = sum($cond[completedCount>=1, 1, 0])`
   - `verified_completed_count = sum($cond[verifiedCompletedCount>=1, 1, 0])`
3. `distinct_days`: aggregate `activities` where `user_id == U`, project local date using `$dateToString` + `$ifNull[$timezone, "UTC"]`, group by that date → count of distinct groups.
4. `own_routes_activity`: `$lookup` `userRouteStats` → `routes` on `routeId`. Filter `userRouteStats.user_id == U AND routes.user_id == U AND routes.is_deleted != true`. Per-bucket `sum($cond[>=1, 1, 0])`.
5. `routes_created`: `routes` where `user_id == U AND is_deleted != True`:
   - `total_count = count`
   - `bouldering_count = count where type=="bouldering"`
   - `endurance_count = count where type=="endurance"`
6. `userStats.replace_one({user_id: U}, computed_doc, upsert=True)`.

Progress logging per N users. Reuses `MONGO_URL` env var.

## Error Handling

- Service functions catch all exceptions internally and log via `logger.exception`. They do not raise.
- Main mutation (activity/route CRUD) is never blocked by stats failures.
- If stats drift, operators run `backfill_user_stats.py --user-id <affected>` or full rerun.

## Concurrency

- **UserRouteStats bucket transitions (0↔1)**: handled atomically via `find_one_and_update(..., return_document=AFTER, upsert=True)`. `before = after − delta`; concurrent +1 callers see `before >= 1` after the second call and correctly skip the transition increment.
- **`distinct_days` re-count**: small race window when two activities for the same `(user, localDate)` are created near-simultaneously. Both may observe `count >= 2` after their own insert and both skip the `+1`, under-counting by one. Mitigation: re-run backfill for affected users. Mitigation is considered acceptable at current traffic; a stricter alternative (a per-`(user, localDate)` marker doc with unique index) is intentionally out of scope.
- **Route soft-delete** is guarded by the existing `if route.is_deleted: return` check (`routers/routes.py` L577), so `on_route_soft_deleted` is not double-invoked.

## Testing

New test module `tests/services/test_user_stats.py`. Requires a real MongoDB connection (existing tests mock heavily but don't run Mongo-backed service tests); add a minimal pytest fixture that connects to a test DB via `MONGO_URL` and drops it on teardown. Add to `tests/conftest.py`.

**Test cases:**

1. **`on_activity_created`**
   - First activity: `activity`, `distinct_routes.total_count`, `distinct_days` each +1.
   - Second activity (same user/route/day): `activity.total_count` +1; `distinct_routes` and `distinct_days` unchanged.
   - Completed+verified activity: `completed_count` and `verified_completed_count` both +1 in both `activity` and `distinct_routes`.
   - Own route: `own_routes_activity` also +1.
   - Own route with `is_deleted=True`: `own_routes_activity` unchanged.

2. **`on_activity_deleted`**
   - Sole activity deletion: all touched counters back to 0, `UserRouteStats` doc removed.
   - Same-day sibling exists: `distinct_days` unchanged on delete.
   - Own route + `is_deleted=True`: `own_routes_activity` unchanged (already decremented at soft-delete).

3. **`on_route_created` / `on_route_soft_deleted`**
   - `routes_created` bucket correctness for each type.
   - Soft-delete with existing `UserRouteStats` ≥1: `own_routes_activity` buckets each −1; without it, unchanged.

4. **Error swallowing**
   - Mock the service's internal Mongo call to raise. Verify the main create/delete endpoints still return 2xx and the primary document is persisted.

5. **Backfill**
   - Seed users, routes, activities. Run script. Verify `userStats` matches expected.
   - Rerun script. Result identical (idempotent).

## Open Questions

None at spec time. All earlier ambiguities have been resolved through brainstorming:

- Day count mechanism — re-count post-mutation, ±1 on 0/1 boundary (confirmed).
- `routes_created` semantics — currently-alive routes; soft-delete decrements.
- `ownRoutesActivity` semantics — distinct route bucket; soft-delete decrements via `UserRouteStats` lookup.
- `route.is_deleted` short-circuit on `on_activity_deleted` to prevent double-decrement.
- Stats errors are best-effort; reconciliation via backfill script.
