"""User-level route statistics service.

Maintains the ``userStats`` collection via post-write ``$inc`` hooks at
activity and route mutation points. See
``docs/2026-04-19-user-route-stats-design.md`` for semantics.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from beanie.odm.fields import PydanticObjectId
from pymongo import ReturnDocument

from app.models.activity import Activity, ActivityStatus, UserRouteStats
from app.models.route import Route, RouteType
from app.models.user_stats import UserStats


logger = logging.getLogger(__name__)


BUCKET_FIELDS = ("total_count", "completed_count", "verified_completed_count")


def _day_utc_superset(date_str: str) -> tuple[datetime, datetime]:
    """UTC window guaranteed to contain every activity whose local date
    (in its own stored timezone) equals ``date_str``. Padded ±14h to cover
    every IANA offset."""
    year, month, day = map(int, date_str.split("-"))
    day_start = datetime(year, month, day, tzinfo=timezone.utc)
    day_end = day_start + timedelta(days=1)
    return (day_start - timedelta(hours=14), day_end + timedelta(hours=14))


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


def _local_date_str(activity: Activity) -> str:
    """Return the activity's started_at local date in ISO ``YYYY-MM-DD`` form.

    Uses the activity's stored ``timezone`` field (IANA). Falls back to UTC
    when unset, matching the aggregation pattern used in ``routers/my.py``.
    Naive ``started_at`` values are treated as UTC.
    """
    started = activity.started_at
    if started.tzinfo is None:
        started = started.replace(tzinfo=timezone.utc)
    tz_name = activity.timezone or "UTC"
    return started.astimezone(ZoneInfo(tz_name)).date().isoformat()


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

    collection = UserRouteStats.get_pymongo_collection()
    updated = await collection.find_one_and_update(
        {"userId": user_id, "routeId": route_id},
        {
            "$inc": inc,
            "$setOnInsert": {
                "userId": user_id,
                "routeId": route_id,
                "totalDuration": 0,
                "completedDuration": 0,
                "verifiedCompletedDuration": 0,
                "lastActivityAt": None,
            },
        },
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )

    after = {k: updated.get(_URS_BUCKET_DB_FIELDS[k], 0) for k in BUCKET_FIELDS}
    before = {k: after[k] - deltas[k] for k in BUCKET_FIELDS}
    return before, after


async def _recount_local_day(user_id: PydanticObjectId, local_date_str: str) -> int:
    """Return how many of ``user_id``'s activities have ``_local_date_str`` equal to ``local_date_str``.

    Computes the local date server-side via Mongo's ``$dateToString`` using the
    activity's stored ``timezone`` (UTC fallback), and counts matches. Narrows
    the initial ``$match`` with a ±14h UTC superset around ``local_date_str``
    so we don't scan a user's entire activity history on every call.
    """
    utc_lo, utc_hi = _day_utc_superset(local_date_str)
    collection = Activity.get_pymongo_collection()
    pipeline = [
        {"$match": {"userId": user_id, "startedAt": {"$gte": utc_lo, "$lt": utc_hi}}},
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


async def _update_user_stats(user_id: PydanticObjectId, inc: dict[str, int]) -> None:
    """Run ``$inc`` against ``userStats`` for ``user_id``, upserting if missing.

    ``inc`` keys are dotted DB paths like ``activity.totalCount``.
    """
    if not inc:
        return
    collection = UserStats.get_pymongo_collection()
    await collection.update_one(
        {"userId": user_id},
        {
            "$inc": inc,
            "$set": {"updatedAt": datetime.now(tz=timezone.utc)},
            "$setOnInsert": {"userId": user_id},
        },
        upsert=True,
    )


async def on_activity_created(activity: Activity, route: Route) -> None:
    """Apply post-create userStats updates. Swallows all exceptions.

    Call AFTER the activity has been persisted (``await activity.insert()``):
    ``_recount_local_day`` relies on the newly-inserted row being queryable
    to detect the 0→1 distinct-days transition.
    """
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


async def on_activity_deleted(activity: Activity, route: Route) -> None:
    """Apply post-delete userStats updates. Swallows all exceptions.

    Order-agnostic with respect to ``activity.delete()``: callers may invoke
    this hook before OR after the activity doc is removed. The ``still_present``
    check adjusts ``_recount_local_day`` accordingly.
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
        if after["total_count"] == 0 and after["completed_count"] == 0 and after["verified_completed_count"] == 0:
            await UserRouteStats.get_pymongo_collection().delete_one({
                "userId": activity.user_id,
                "routeId": activity.route_id,
                "totalCount": 0,
                "completedCount": 0,
                "verifiedCompletedCount": 0,
            })

        local_date = _local_date_str(activity)
        remaining = await _recount_local_day(activity.user_id, local_date)
        still_present = await Activity.find_one(Activity.id == activity.id) is not None
        effective = remaining - 1 if still_present else remaining
        if effective == 0:
            inc["distinctDays"] = -1

        await _update_user_stats(activity.user_id, inc)
    except Exception:
        logger.exception("on_activity_deleted failed for activity=%s", activity.id)


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
