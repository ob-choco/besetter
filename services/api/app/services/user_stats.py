"""User-level route statistics service.

Maintains the ``userStats`` collection via post-write ``$inc`` hooks at
activity and route mutation points. See
``docs/2026-04-19-user-route-stats-design.md`` for semantics.
"""

from __future__ import annotations

from datetime import timezone
from zoneinfo import ZoneInfo

from app.models.activity import Activity, ActivityStatus


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
