from datetime import datetime, timezone
from typing import Optional
from zoneinfo import ZoneInfo

from bson import ObjectId
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from app.dependencies import get_current_user
from app.models import model_config
from app.models.activity import Activity
from app.models.user import User

router = APIRouter(prefix="/my", tags=["my"])

DEFAULT_TIMEZONE = "Asia/Seoul"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _to_local_date_str(utc_dt: datetime, tz_name: str) -> str:
    """Convert a UTC datetime to a YYYY-MM-DD string in the given timezone."""
    local_dt = utc_dt.astimezone(ZoneInfo(tz_name))
    return local_dt.strftime("%Y-%m-%d")


def _month_utc_range(year: int, month: int, tz_name: str) -> tuple[datetime, datetime]:
    """Return (start, end) in UTC for a given year/month in the given timezone."""
    tz_info = ZoneInfo(tz_name)
    local_start = datetime(year, month, 1, tzinfo=tz_info)

    if month == 12:
        local_end = datetime(year + 1, 1, 1, tzinfo=tz_info)
    else:
        local_end = datetime(year, month + 1, 1, tzinfo=tz_info)

    return (
        local_start.astimezone(timezone.utc),
        local_end.astimezone(timezone.utc),
    )


def _day_utc_range(date_str: str, tz_name: str) -> tuple[datetime, datetime]:
    """Return (start, end) in UTC for a given date string (YYYY-MM-DD) in the given timezone."""
    from datetime import timedelta

    tz_info = ZoneInfo(tz_name)
    year, month, day = map(int, date_str.split("-"))
    local_start = datetime(year, month, day, tzinfo=tz_info)
    local_end = local_start + timedelta(days=1)

    return (
        local_start.astimezone(timezone.utc),
        local_end.astimezone(timezone.utc),
    )


# ---------------------------------------------------------------------------
# Response schemas
# ---------------------------------------------------------------------------


class LastActivityDateResponse(BaseModel):
    model_config = model_config

    last_activity_date: Optional[str] = None


class MonthlySummaryResponse(BaseModel):
    model_config = model_config

    active_dates: list[int] = []


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("/last-activity-date", response_model=LastActivityDateResponse)
async def get_last_activity_date(
    timezone_param: str = Query(alias="timezone", default=DEFAULT_TIMEZONE),
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

    date_str = _to_local_date_str(activity[0].started_at, timezone_param)
    return LastActivityDateResponse(last_activity_date=date_str)


@router.get("/monthly-summary", response_model=MonthlySummaryResponse)
async def get_monthly_summary(
    year: int = Query(ge=2026),
    month: int = Query(ge=1, le=12),
    timezone_param: str = Query(alias="timezone", default=DEFAULT_TIMEZONE),
    current_user: User = Depends(get_current_user),
):
    start_utc, end_utc = _month_utc_range(year, month, timezone_param)

    pipeline = [
        {"$match": {
            "userId": current_user.id,
            "startedAt": {"$gte": start_utc, "$lt": end_utc},
        }},
        {"$group": {
            "_id": {"$dayOfMonth": {"date": "$startedAt", "timezone": timezone_param}},
        }},
        {"$sort": {"_id": 1}},
    ]

    results = await Activity.aggregate(pipeline).to_list()
    active_dates = [doc["_id"] for doc in results]

    return MonthlySummaryResponse(active_dates=active_dates)
