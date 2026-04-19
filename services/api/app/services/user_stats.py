"""User-level route statistics service.

Maintains the ``userStats`` collection via post-write ``$inc`` hooks at
activity and route mutation points. See
``docs/2026-04-19-user-route-stats-design.md`` for semantics.
"""

from __future__ import annotations

from datetime import timezone
from zoneinfo import ZoneInfo

from beanie.odm.fields import PydanticObjectId
from pymongo import ReturnDocument

from app.models.activity import Activity, ActivityStatus, UserRouteStats


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
    activity's stored ``timezone`` (UTC fallback), and counts matches.
    """
    collection = Activity.get_pymongo_collection()
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
