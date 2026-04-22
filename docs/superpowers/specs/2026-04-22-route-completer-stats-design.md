# Route Completer Stats & Verified Completers List

## Goal

Expose, per route, the distinct count of users who have recorded at least one
activity on the route (in each of the three existing status buckets), and
surface a scrollable, ranked list of verified completers on the route detail
screen. Counters are maintained via the existing post-mutation `$inc` hooks in
`app/services/user_stats.py` at the exact same 0↔1 transition points already
computed for `userStats.distinct_routes`.

## Scope

**Covered:**

- New embedded counter `Route.completer_stats` with three fields:
  `participantCount`, `completerCount`, `verifiedCompleterCount`.
- Maintenance of all three counters via `$inc` at activity create/delete.
- New paginated endpoint listing verified completers for a route.
- Mobile UI: a new section on the route detail screen showing the verified
  completer count, a horizontal row of avatars sized to the device width, and
  a `+N 더 보기` chip that opens a full-list bottom sheet.
- i18n strings for ko / en / ja / es.
- Backfill script for existing routes.

**Non-goals:**

- Exposing `participantCount` / `completerCount` in the UI (stored only;
  serves any future surface).
- Ordering surfaces other than the route detail screen.
- Undo/undelete of routes (not present in the codebase).
- Admin dashboards for route-level stats.
- Real-time updates to the list while the sheet is open.

## Data Model

### Route document addition

`app/models/route.py`:

```python
class CompleterStats(BaseModel):
    model_config = model_config

    participant_count: int = 0
    completer_count: int = 0
    verified_completer_count: int = 0


class Route(Document):
    ...
    completer_stats: CompleterStats = Field(default_factory=CompleterStats)
```

DB field names are camelCase per the existing serializer:
`completerStats.participantCount`, `completerStats.completerCount`,
`completerStats.verifiedCompleterCount`.

### Semantics

- `participantCount`: distinct users with `UserRouteStats.totalCount >= 1`.
- `completerCount`: distinct users with `UserRouteStats.completedCount >= 1`.
- `verifiedCompleterCount`: distinct users with
  `UserRouteStats.verifiedCompletedCount >= 1`.

Route owners are included when they verify-complete their own route — the
counters are simple "distinct users with bucket ≥ 1" and do not exclude the
owner.

Visibility (public / unlisted / private) does not affect counter maintenance.
Private routes are owner-only in practice, so the counter converges trivially
without extra guards; a future visibility change therefore needs no backfill.

## Service Integration

Maintenance hooks live in `app/services/user_stats.py`, inside the already-
atomic 0↔1 transition block.

### `on_activity_created` (extend existing)

After the existing per-bucket transition check at
`app/services/user_stats.py:208-215`, build a Route `$inc` update that mirrors
the buckets that transitioned 0→1 and apply it against the `routes` collection.

```python
_ROUTE_COMPLETER_DB_FIELDS = {
    "total_count": "completerStats.participantCount",
    "completed_count": "completerStats.completerCount",
    "verified_completed_count": "completerStats.verifiedCompleterCount",
}

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

This runs inside the existing `try/except Exception` wrapper so a failure is
logged and swallowed; the main activity insert is unaffected.

### `on_activity_deleted` (extend existing)

Mirror: after the existing decrement block (user_stats.py:237-244), build a
`route_inc` where `before[bucket] >= 1 and after[bucket] == 0` contributes
`-1` and apply the same `update_one`. Same swallow-on-error behavior.

### Ownership / soft-delete edges

- **Route owner activity**: no special case. The counter simply reflects
  "distinct users with bucket ≥ 1," regardless of whether the user is the
  owner.
- **Route soft-delete**: no counter adjustment. The Route document remains;
  the counter stays frozen. Since soft-deleted routes are hidden from all
  screens, the stale value has no effect. Restoring a route (not currently
  possible) would likewise keep the counter consistent.

## Backend API

### `GET /routes/{route_id}` (extend)

No code change required. `RouteDetailView` inherits from `Route`, so
`completer_stats` flows through to the response automatically. All three
counts ship; the mobile client renders only `verifiedCompleterCount`.

### `GET /routes/{route_id}/verified-completers` (new)

**Query params**
- `limit: int` — 1 ≤ n ≤ 50, default 20.
- `cursor: str | None` — base64 keyset cursor.

**Access control**
Reuses `_can_access_route(route, current_user)` (`app/routers/routes.py`) —
identical to the route detail endpoint.

**Query**

```
UserRouteStats
  where routeId == R AND verifiedCompletedCount >= 1
  sort   verifiedCompletedCount DESC, lastActivityAt DESC, _id DESC
  limit  N + 1   # over-fetch to detect next page
```

The sort key `verifiedCompletedCount, lastActivityAt, _id` gives a stable
tie-break. An index should be added:

```python
# UserRouteStats.Settings.indexes
IndexModel(
    [
        ("routeId", ASCENDING),
        ("verifiedCompletedCount", DESCENDING),
        ("lastActivityAt", DESCENDING),
        ("_id", DESCENDING),
    ],
    name="routeId_1_verifiedCompletedCount_-1_lastActivityAt_-1__id_-1",
    partialFilterExpression={"verifiedCompletedCount": {"$gte": 1}},
)
```

Implementation enriches each `UserRouteStats` row with the user document via
a single `$lookup` aggregation against `users`, producing `OwnerView`
(existing model, `app/models/user.py:100-114`). Missing user documents
(rare) are surfaced as `is_deleted=True` with null `profile_id` /
`profile_image_url`.

**Cursor format**

```
base64("{verifiedCount}|{lastActivityAtIso}|{stats_doc_id}")
```

Decoded into a `$match`/`$sort`-compatible keyset clause:

```
$match: { $or: [
  { verifiedCompletedCount: { $lt: C } },
  { verifiedCompletedCount: C, lastActivityAt: { $lt: T } },
  { verifiedCompletedCount: C, lastActivityAt: T, _id: { $lt: I } },
] }
```

**Response schema**

```python
class VerifiedCompleterItem(BaseModel):
    model_config = model_config
    user: OwnerView
    verified_completed_count: int
    last_activity_at: datetime

class VerifiedCompletersResponse(BaseModel):
    model_config = model_config
    data: List[VerifiedCompleterItem]
    meta: RouteListMeta  # { next_token: str | None }
```

`next_token` is null when the server returned ≤ `limit` rows.

### Why the user list is not inlined

Computing "how many avatars fit in the row" is a client-side measurement
problem. The client issues a single small-page fetch on route detail entry
(e.g., `limit=10`), renders as many avatars as fit using a `LayoutBuilder`,
and uses `completerStats.verifiedCompleterCount − visible` to label the
`+N 더 보기` chip. The bottom sheet issues its own paginated fetches (the
first page may reuse the cached route-detail response).

## Mobile UI

### Placement

In `apps/mobile/lib/pages/viewers/route_viewer.dart`, the new section sits
**directly below the user's own workout log panel** (`WorkoutLogPanel`).
Rationale (per user): putting peers' records below the user's own records
creates a natural motivational comparison.

### Route detail row

- Section header: `인증된 완등자 🏅 · {count}명`. The emoji is kept in code
  (not in ARB) so changing it later doesn't require re-translating.
- The section is hidden entirely when `verifiedCompleterCount == 0`.
- Row layout (fit-only, no horizontal scroll):
  - Measure available width with `LayoutBuilder`.
  - Compute `visible = floor((width − chip_width) / (avatar_width + gap))`.
    Avatar: 40×40 circle, gap 8, chip reserves ~ 100px.
  - Render up to `visible` avatars. Append `+{verifiedCompleterCount −
    visible} 더 보기` chip when the count exceeds the visible slot.
  - Tapping any avatar or the chip opens `VerifiedCompletersSheet`.

### Bottom sheet

New widget: `apps/mobile/lib/widgets/sheets/verified_completers_sheet.dart`.

- `ConsumerStatefulWidget`. Launched via
  `showModalBottomSheet(isScrollControlled: true, ...)` (same pattern as
  `place_selection_sheet.dart`).
- Header: `인증된 완등자` title + `{count}명` trailing.
- Row: circular avatar (44×44) + `@{profile_id}` + count badge
  (`verifiedCompletedCount`, orange accent). Avatar rendering is extracted
  from the existing `OwnerBadge` (`apps/mobile/lib/widgets/common/owner_badge.dart`)
  — either by lifting the avatar into a small shared widget or by
  duplicating its fallback logic (initial letter, deleted-user placeholder).
- Deleted users: `탈퇴한 회원` in place of the handle, placeholder icon
  avatar (same rules as `OwnerBadge`).
- Pagination: `ScrollController` with near-end threshold fetches next page
  via `_cursor`/`_hasMore`, mirroring `notifications_page.dart` (lines
  16-96).

### Mobile data layer

- `apps/mobile/lib/models/route_data.dart`: add `CompleterStats` class with
  three `int` fields and `RouteData.completerStats: CompleterStats` (default
  all-zero).
- New model `VerifiedCompleterItem`: `OwnerInfo owner`, `int
  verifiedCompletedCount`, `DateTime lastActivityAt`.
- New service call wrapping `GET /routes/{id}/verified-completers` using
  the existing `AuthorizedHttpClient`.

## i18n

Add to all four ARB files (`app_ko.arb`, `app_en.arb`, `app_ja.arb`,
`app_es.arb`):

| Key | ko | en | ja | es |
| --- | --- | --- | --- | --- |
| `verifiedCompletersTitle` | 인증된 완등자 | Verified Completers | 認定完登者 | Escaladores verificados |
| `verifiedCompletersCount` | `{count}명` | `{count}` | `{count}人` | `{count}` |
| `verifiedCompletersMore` | `+{count} 더 보기` | `+{count} more` | `+{count} もっと見る` | `+{count} más` |

Existing `탈퇴한 회원` / deleted-user fallback keys are reused.

After ARB edits, regenerate: `dart run build_runner build --delete-conflicting-outputs`.

## Backfill

New script: `services/api/scripts/backfill_route_completer_stats.py`.

**Modes**
- Default: iterate all routes.
- `--route-id <id>`: recompute a single route.

**Per-route algorithm**

```
agg on userRouteStats where routeId == R:
  participantCount        = sum($cond[totalCount >= 1, 1, 0])
  completerCount          = sum($cond[completedCount >= 1, 1, 0])
  verifiedCompleterCount  = sum($cond[verifiedCompletedCount >= 1, 1, 0])

routes.update_one({_id: R}, {$set: {completerStats: {...}}})
```

Idempotent (re-run safe). Progress logging every N routes. Reuses
`MONGO_URL`.

Run once on deploy to bootstrap existing routes; subsequent maintenance is
handled by the `$inc` hooks.

## Concurrency

- **Single-user 0↔1 atomicity**: preserved by the existing
  `find_one_and_update(..., return_document=AFTER, upsert=True)` on
  `UserRouteStats`. `before = after − delta`, so a transition fires exactly
  once per user-route-bucket, even under concurrent +1 callers.
- **Multi-user concurrent first activity**: each user's own UserRouteStats
  upsert transitions independently; two independent `Route $inc(+1)` calls
  sum correctly.
- **Route `$inc` is not co-transactional with the UserRouteStats upsert**.
  If the process dies between them, counters may drift. Drift is recovered
  by re-running `backfill_route_completer_stats.py --route-id <affected>`.
- **Route doc missing** (shouldn't happen): `update_one` is a no-op;
  nothing else breaks.

## Testing

### Service-level (`tests/services/test_user_stats.py`, extend existing)

1. First completed+verified activity for `(user, route)`:
   - `Route.completerStats.participantCount`,
     `completerStats.completerCount`,
     `completerStats.verifiedCompleterCount` each +1.
2. Second verified activity from the same user: all three counters
   unchanged.
3. Only-attempt activity (status=ATTEMPTED): `participantCount` +1;
   `completerCount` / `verifiedCompleterCount` unchanged.
4. Activity deletion that drives bucket → 0: corresponding Route counter
   decrements by 1; other buckets unchanged.
5. Owner verifying own route: counted (no special case).
6. Stats service exception: asserted via mock — the main activity
   create/delete still persists and the response is 2xx.

### Endpoint (`tests/routers/test_verified_completers.py`, new)

1. Sorts results by `verifiedCompletedCount DESC, lastActivityAt DESC`.
2. Cursor round-trip (page 1 → page 2 → exhausted `next_token = null`).
3. `_can_access_route` denies private routes to non-owners (403).
4. Deleted user is serialized with `is_deleted=True`, `profile_id=None`,
   `profile_image_url=None`.
5. `verifiedCompletedCount == 0` users are excluded.

### Backfill (`tests/scripts/test_backfill_route_completer_stats.py`, new)

1. Seed routes and `UserRouteStats`. Run script. Verify
   `Route.completerStats` matches expected per-bucket distinct counts.
2. Rerun — result identical (idempotency).

## Open Questions

None at spec time.
