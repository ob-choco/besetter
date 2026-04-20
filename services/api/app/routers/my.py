import logging
from datetime import datetime, timezone
from typing import List, Optional
from zoneinfo import ZoneInfo

from beanie.odm.operators.find.comparison import In
from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
from pydantic import BaseModel, Field

from app.core.gcs import to_public_url
from app.dependencies import get_current_user
from app.models import model_config
from app.models.activity import Activity, ActivityStatus, RouteSnapshot, UserRouteStats
from app.models.device_token import DeviceToken
from app.models.image import Image
from app.models.place import Place
from app.models.route import Route, RouteType, Visibility
from app.models.user_stats import (
    ActivityCounters,
    RoutesCreatedCounters,
    UserStats,
)
from app.routers.activities import (
    _build_stats_inc,
    _update_route_stats,
)
from app.routers.places import PlaceView, place_to_view
from app.services import user_stats as user_stats_service
from app.models.user import OwnerView, User
from beanie.odm.fields import PydanticObjectId

router = APIRouter(prefix="/my", tags=["my"])

logger = logging.getLogger(__name__)

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


def _day_utc_superset(date_str: str) -> tuple[datetime, datetime]:
    """UTC window guaranteed to contain every activity whose local date
    (in its own stored timezone) equals date_str. Padded ±14h to cover
    every possible IANA offset."""
    from datetime import timedelta

    year, month, day = map(int, date_str.split("-"))
    naive_day_start = datetime(year, month, day, tzinfo=timezone.utc)
    naive_day_end = naive_day_start + timedelta(days=1)
    return (
        naive_day_start - timedelta(hours=14),
        naive_day_end + timedelta(hours=14),
    )


def _month_utc_superset(year: int, month: int) -> tuple[datetime, datetime]:
    """UTC window guaranteed to contain every activity whose local year/month
    (in its own stored timezone) equals year/month. Padded ±14h."""
    from datetime import timedelta

    naive_month_start = datetime(year, month, 1, tzinfo=timezone.utc)
    if month == 12:
        naive_month_end = datetime(year + 1, 1, 1, tzinfo=timezone.utc)
    else:
        naive_month_end = datetime(year, month + 1, 1, tzinfo=timezone.utc)
    return (
        naive_month_start - timedelta(hours=14),
        naive_month_end + timedelta(hours=14),
    )


def _merge_incs(incs: list[dict]) -> dict:
    """Merge multiple $inc dicts by summing values of common keys."""
    merged: dict = {}
    for inc in incs:
        for key, value in inc.items():
            merged[key] = merged.get(key, 0) + value
    return merged


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
    verified_completed_count: int = 0
    attempted_count: int = 0
    total_duration: float = 0
    route_count: int = 0


class DailyRouteItem(BaseModel):
    model_config = model_config

    route_id: str
    route_snapshot: RouteSnapshot
    route_visibility: Visibility = Visibility.PUBLIC
    is_deleted: bool = False
    total_count: int
    completed_count: int
    verified_completed_count: int
    attempted_count: int
    total_duration: float
    owner: OwnerView


class DailyRoutesResponse(BaseModel):
    model_config = model_config

    summary: DailySummary
    routes: list[DailyRouteItem]


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

    image_id: PydanticObjectId
    hold_polygon_id: PydanticObjectId
    image_url: str
    overlay_image_url: Optional[str] = None

    place: Optional[PlaceView] = None
    wall_name: Optional[str] = None
    wall_expiration_date: Optional[datetime] = None

    owner: OwnerView

    total_count: int
    completed_count: int
    verified_completed_count: int
    attempted_count: int
    last_activity_at: datetime

    created_at: datetime
    updated_at: Optional[datetime] = None


class RecentRoutesResponse(BaseModel):
    model_config = model_config

    data: List[RecentRouteView]


class UserStatsResponse(BaseModel):
    model_config = model_config

    activity: ActivityCounters = Field(default_factory=ActivityCounters)
    distinct_routes: ActivityCounters = Field(default_factory=ActivityCounters)
    distinct_days: int = 0
    own_routes_activity: ActivityCounters = Field(default_factory=ActivityCounters)
    routes_created: RoutesCreatedCounters = Field(default_factory=RoutesCreatedCounters)


async def _build_user_stats_response(user_id: PydanticObjectId) -> UserStatsResponse:
    stats = await UserStats.find_one(UserStats.user_id == user_id)
    if stats is None:
        return UserStatsResponse()
    return UserStatsResponse(
        activity=stats.activity,
        distinct_routes=stats.distinct_routes,
        distinct_days=stats.distinct_days,
        own_routes_activity=stats.own_routes_activity,
        routes_created=stats.routes_created,
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("/user-stats", response_model=UserStatsResponse)
async def get_my_user_stats(
    current_user: User = Depends(get_current_user),
):
    return await _build_user_stats_response(current_user.id)


@router.get("/last-activity-date", response_model=LastActivityDateResponse)
async def get_last_activity_date(
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

    a = activity[0]
    tz_name = a.timezone or "UTC"
    date_str = _to_local_date_str(a.started_at, tz_name)
    return LastActivityDateResponse(last_activity_date=date_str)


@router.get("/monthly-summary", response_model=MonthlySummaryResponse)
async def get_monthly_summary(
    year: int = Query(ge=2026),
    month: int = Query(ge=1, le=12),
    current_user: User = Depends(get_current_user),
):
    utc_lo, utc_hi = _month_utc_superset(year, month)
    year_month = f"{year:04d}-{month:02d}"

    pipeline = [
        {"$match": {
            "userId": current_user.id,
            "startedAt": {"$gte": utc_lo, "$lt": utc_hi},
        }},
        {"$addFields": {
            "localYearMonth": {
                "$dateToString": {
                    "format": "%Y-%m",
                    "date": "$startedAt",
                    "timezone": {"$ifNull": ["$timezone", "UTC"]},
                }
            },
            "localDay": {
                "$dayOfMonth": {
                    "date": "$startedAt",
                    "timezone": {"$ifNull": ["$timezone", "UTC"]},
                }
            },
        }},
        {"$match": {"localYearMonth": year_month}},
        {"$group": {"_id": "$localDay"}},
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
    current_user: User = Depends(get_current_user),
):
    utc_lo, utc_hi = _day_utc_superset(date)

    pipeline = [
        {"$match": {
            "userId": current_user.id,
            "startedAt": {"$gte": utc_lo, "$lt": utc_hi},
        }},
        {"$addFields": {
            "localDate": {
                "$dateToString": {
                    "format": "%Y-%m-%d",
                    "date": "$startedAt",
                    "timezone": {"$ifNull": ["$timezone", "UTC"]},
                }
            }
        }},
        {"$match": {"localDate": date}},
        {"$group": {
            "_id": "$routeId",
            "routeSnapshot": {"$first": "$routeSnapshot"},
            "totalCount": {"$sum": 1},
            "completedCount": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
            "verifiedCompletedCount": {"$sum": {"$cond": [
                {"$and": [
                    {"$eq": ["$status", "completed"]},
                    {"$eq": ["$locationVerified", True]},
                ]},
                1,
                0,
            ]}},
            "attemptedCount": {"$sum": {"$cond": [{"$eq": ["$status", "attempted"]}, 1, 0]}},
            "totalDuration": {"$sum": "$duration"},
        }},
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
        {"$group": {
            "_id": None,
            "routes": {"$push": "$$ROOT"},
            "totalCount": {"$sum": "$totalCount"},
            "completedCount": {"$sum": "$completedCount"},
            "verifiedCompletedCount": {"$sum": "$verifiedCompletedCount"},
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
        verified_completed_count=doc["verifiedCompletedCount"],
        attempted_count=doc["attemptedCount"],
        total_duration=doc["totalDuration"],
        route_count=doc["routeCount"],
    )
    raw_routes = doc["routes"]
    owner_ids = list({r["ownerUserId"] for r in raw_routes if r.get("ownerUserId") is not None})
    owner_by_id: dict[PydanticObjectId, User] = {}
    if owner_ids:
        owner_docs = await User.find(In(User.id, owner_ids)).to_list()
        owner_by_id = {u.id: u for u in owner_docs}

    def _owner_view(raw_owner_id) -> OwnerView:
        if raw_owner_id is None:
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
            verified_completed_count=r["verifiedCompletedCount"],
            attempted_count=r["attemptedCount"],
            total_duration=r["totalDuration"],
            owner=_owner_view(r.get("ownerUserId")),
        )
        for r in raw_routes
    ]

    return DailyRoutesResponse(summary=summary, routes=routes)


@router.delete("/daily-routes/{route_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_daily_route_group(
    route_id: str = Path(...),
    date: str = Query(pattern=r"^\d{4}-\d{2}-\d{2}$"),
    current_user: User = Depends(get_current_user),
):
    try:
        route_object_id = ObjectId(route_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid route_id format",
        )

    utc_lo, utc_hi = _day_utc_superset(date)

    pipeline = [
        {"$match": {
            "userId": current_user.id,
            "routeId": route_object_id,
            "startedAt": {"$gte": utc_lo, "$lt": utc_hi},
        }},
        {"$addFields": {
            "localDate": {
                "$dateToString": {
                    "format": "%Y-%m-%d",
                    "date": "$startedAt",
                    "timezone": {"$ifNull": ["$timezone", "UTC"]},
                }
            }
        }},
        {"$match": {"localDate": date}},
        {"$project": {
            "_id": 1,
            "userId": 1,
            "routeId": 1,
            "status": 1,
            "locationVerified": 1,
            "duration": 1,
            "startedAt": 1,
            "endedAt": 1,
            "timezone": 1,
            "routeSnapshot": 1,
            "createdAt": 1,
        }},
    ]

    collection = Activity.get_pymongo_collection()
    cursor = collection.aggregate(pipeline)
    matched = await cursor.to_list(length=None)

    if not matched:
        return

    route = await Route.find_one(Route.id == route_object_id)
    if route is None:
        logger.warning(
            "delete_daily_route_group: route_id=%s missing; hard-deleting %d activities but skipping stats decrement",
            route_object_id,
            len(matched),
        )
        await collection.delete_many({"_id": {"$in": [m["_id"] for m in matched]}})
        return

    # 1. Build Activity objects in memory (we need full state for the hooks, and the docs will be gone after delete_many).
    activities: list[Activity] = []
    merged_inc: dict[str, int] = {}
    for m in matched:
        a = Activity.model_construct(
            id=m["_id"],
            user_id=m["userId"],
            route_id=m["routeId"],
            status=ActivityStatus(m["status"]),
            location_verified=m.get("locationVerified", False),
            started_at=m["startedAt"],
            ended_at=m["endedAt"],
            duration=m.get("duration", 0.0),
            timezone=m["timezone"],
            route_snapshot=RouteSnapshot(**m["routeSnapshot"]),
            created_at=m["createdAt"],
        )
        activities.append(a)
        inc = _build_stats_inc(a.status, a.location_verified, a.duration, sign=-1)
        for k, v in inc.items():
            merged_inc[k] = merged_inc.get(k, 0) + v

    activity_ids = [a.id for a in activities]

    # 2. Hard delete all activities first (conservative drift direction, same as before).
    await collection.delete_many({"_id": {"$in": activity_ids}})

    # 3. Route-level stats decrement is still bulk-merged (Route.activityStats is per-route, not per-user-per-day).
    await _update_route_stats(route_object_id, merged_inc)

    # 4. Per-activity user-level hook. The hook is order-agnostic re: activity.delete() thanks to its `still_present` check.
    for a in activities:
        await user_stats_service.on_activity_deleted(a, route)


# ---------------------------------------------------------------------------
# Recently climbed routes
# ---------------------------------------------------------------------------


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

    route_ids = [urs.route_id for urs in urs_list]
    routes = await Route.find(In(Route.id, route_ids)).to_list()
    route_by_id = {r.id: r for r in routes}

    image_ids = [r.image_id for r in routes]
    images = await Image.find(In(Image.id, image_ids)).to_list()
    image_by_id = {img.id: img for img in images}

    place_ids = list({img.place_id for img in images if img.place_id})
    place_by_id: dict[PydanticObjectId, Place] = {}
    if place_ids:
        places = await Place.find(In(Place.id, place_ids)).to_list()
        place_by_id = {p.id: p for p in places}

    owner_ids = list({r.user_id for r in routes})
    owners = await User.find(In(User.id, owner_ids)).to_list()
    owner_by_id = {u.id: u for u in owners}

    data: list[RecentRouteView] = []
    for urs in urs_list:
        route = route_by_id.get(urs.route_id)
        if route is None:
            continue
        image = image_by_id.get(route.image_id)
        if image is None:
            continue

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
            image_id=route.image_id,
            hold_polygon_id=route.hold_polygon_id,
            image_url=to_public_url(str(route.image_url)),
            overlay_image_url=to_public_url(str(route.overlay_image_url)) if route.overlay_image_url else None,
            place=place_view,
            wall_name=image.wall_name,
            wall_expiration_date=image.wall_expiration_date,
            owner=owner_view,
            total_count=urs.total_count,
            completed_count=urs.completed_count,
            verified_completed_count=urs.verified_completed_count,
            attempted_count=urs.total_count - urs.completed_count,
            last_activity_at=urs.last_activity_at,
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


# ---------------------------------------------------------------------------
# Push notification device tokens
# ---------------------------------------------------------------------------


class RegisterDeviceRequest(BaseModel):
    model_config = model_config

    token: str = Field(..., min_length=1)
    platform: str = Field(..., description="'ios' | 'android'")
    app_version: Optional[str] = None
    locale: Optional[str] = None
    timezone: Optional[str] = None


@router.post("/devices", status_code=status.HTTP_204_NO_CONTENT)
async def register_device(
    payload: RegisterDeviceRequest,
    current_user: User = Depends(get_current_user),
):
    if payload.platform not in ("ios", "android"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="platform must be 'ios' or 'android'",
        )

    now = datetime.now(timezone.utc)
    existing = await DeviceToken.find_one(DeviceToken.token == payload.token)
    if existing is not None:
        existing.user_id = current_user.id
        existing.platform = payload.platform
        existing.app_version = payload.app_version
        existing.locale = payload.locale
        existing.timezone = payload.timezone
        existing.last_seen_at = now
        await existing.save()
        return

    await DeviceToken(
        user_id=current_user.id,
        token=payload.token,
        platform=payload.platform,
        app_version=payload.app_version,
        locale=payload.locale,
        timezone=payload.timezone,
        created_at=now,
        last_seen_at=now,
    ).insert()


@router.delete("/devices/{token}", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_device(
    token: str = Path(..., min_length=1),
    current_user: User = Depends(get_current_user),
):
    await DeviceToken.find_one(
        DeviceToken.token == token,
        DeviceToken.user_id == current_user.id,
    ).delete()
