from datetime import datetime, timezone
from typing import Optional
from zoneinfo import ZoneInfo

from bson import ObjectId
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from app.core.gcs import extract_blob_path_from_url, generate_signed_url
from app.dependencies import get_current_user
from app.models import model_config
from app.models.activity import Activity, RouteSnapshot
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


def _sign_snapshot_urls(snapshot: dict) -> dict:
    """Replace raw GCS URLs in a routeSnapshot dict with signed URLs."""
    for key in ("imageUrl", "overlayImageUrl"):
        url = snapshot.get(key)
        if url:
            blob_path = extract_blob_path_from_url(url)
            if blob_path:
                snapshot[key] = generate_signed_url(blob_path)
    return snapshot


# ---------------------------------------------------------------------------
# Response schemas
# ---------------------------------------------------------------------------


class LastActivityDateResponse(BaseModel):
    model_config = model_config

    last_activity_date: Optional[str] = None


class MonthlySummaryResponse(BaseModel):
    model_config = model_config

    active_dates: list[int] = []


class DailySummary(BaseModel):
    model_config = model_config

    total_count: int = 0
    completed_count: int = 0
    attempted_count: int = 0
    total_duration: float = 0
    route_count: int = 0


class DailyRouteItem(BaseModel):
    model_config = model_config

    route_id: str
    route_snapshot: RouteSnapshot
    total_count: int
    completed_count: int
    attempted_count: int
    total_duration: float


class DailyRoutesResponse(BaseModel):
    model_config = model_config

    summary: DailySummary
    routes: list[DailyRouteItem]


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

    collection = Activity.get_pymongo_collection()
    cursor = collection.aggregate(pipeline)
    results = await cursor.to_list(length=None)
    active_dates = [doc["_id"] for doc in results]

    return MonthlySummaryResponse(active_dates=active_dates)


@router.get("/daily-routes", response_model=DailyRoutesResponse)
async def get_daily_routes(
    date: str = Query(pattern=r"^\d{4}-\d{2}-\d{2}$"),
    timezone_param: str = Query(alias="timezone", default=DEFAULT_TIMEZONE),
    current_user: User = Depends(get_current_user),
):
    start_utc, end_utc = _day_utc_range(date, timezone_param)

    pipeline = [
        {"$match": {
            "userId": current_user.id,
            "startedAt": {"$gte": start_utc, "$lt": end_utc},
        }},
        {"$group": {
            "_id": "$routeId",
            "routeSnapshot": {"$first": "$routeSnapshot"},
            "totalCount": {"$sum": 1},
            "completedCount": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
            "attemptedCount": {"$sum": {"$cond": [{"$eq": ["$status", "attempted"]}, 1, 0]}},
            "totalDuration": {"$sum": "$duration"},
        }},
        {"$group": {
            "_id": None,
            "routes": {"$push": "$$ROOT"},
            "totalCount": {"$sum": "$totalCount"},
            "completedCount": {"$sum": "$completedCount"},
            "attemptedCount": {"$sum": "$attemptedCount"},
            "totalDuration": {"$sum": "$totalDuration"},
            "routeCount": {"$sum": 1},
        }},
    ]

    collection = Activity.get_pymongo_collection()
    cursor = collection.aggregate(pipeline)
    results = await cursor.to_list(length=None)

    if not results:
        return DailyRoutesResponse(summary=DailySummary(), routes=[])

    doc = results[0]
    summary = DailySummary(
        total_count=doc["totalCount"],
        completed_count=doc["completedCount"],
        attempted_count=doc["attemptedCount"],
        total_duration=doc["totalDuration"],
        route_count=doc["routeCount"],
    )
    routes = [
        DailyRouteItem(
            route_id=str(r["_id"]),
            route_snapshot=RouteSnapshot(**_sign_snapshot_urls(r["routeSnapshot"])),
            total_count=r["totalCount"],
            completed_count=r["completedCount"],
            attempted_count=r["attemptedCount"],
            total_duration=r["totalDuration"],
        )
        for r in doc["routes"]
    ]

    return DailyRoutesResponse(summary=summary, routes=routes)
