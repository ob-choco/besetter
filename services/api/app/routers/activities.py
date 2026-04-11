import base64
from datetime import datetime, timezone
from typing import List, Optional

from beanie.odm.fields import PydanticObjectId
from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi import status as http_status
from pydantic import BaseModel, Field

from app.core.geo import haversine_distance
from app.dependencies import get_current_user
from app.models import model_config
from app.models.activity import (
    Activity,
    ActivityStatus,
    RouteSnapshot,
    UserRouteStats,
)
from app.models.image import Image
from app.models.place import Place
from app.models.route import Route
from app.models.user import User

router = APIRouter(prefix="/routes", tags=["activities"])

LOCATION_VERIFICATION_RADIUS_M = 300


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------


class CreateActivityRequest(BaseModel):
    model_config = model_config

    latitude: float
    longitude: float
    status: ActivityStatus
    started_at: datetime
    ended_at: datetime
    timezone: str


class ActivityResponse(BaseModel):
    model_config = model_config

    id: PydanticObjectId
    route_id: PydanticObjectId
    status: ActivityStatus
    location_verified: bool
    started_at: datetime
    ended_at: datetime
    duration: float
    route_snapshot: RouteSnapshot
    created_at: datetime
    updated_at: Optional[datetime] = None


class MyStatsResponse(BaseModel):
    model_config = model_config

    total_count: int = 0
    total_duration: float = 0
    completed_count: int = 0
    completed_duration: float = 0
    verified_completed_count: int = 0
    verified_completed_duration: float = 0


class ActivityListItem(BaseModel):
    model_config = model_config

    id: str = Field(serialization_alias="id")
    status: ActivityStatus
    location_verified: bool
    started_at: datetime
    ended_at: datetime
    duration: float
    created_at: datetime


class MyActivitiesResponse(BaseModel):
    model_config = model_config

    activities: List[ActivityListItem]
    next_cursor: Optional[str] = None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _compute_duration(started_at: datetime, ended_at: datetime) -> float:
    """Return duration in seconds between started_at and ended_at (2 decimal places)."""
    return round((ended_at - started_at).total_seconds(), 2)


def _build_stats_inc(
    status: ActivityStatus,
    location_verified: bool,
    duration: float,
    sign: int = 1,
) -> dict:
    """Build a MongoDB $inc dict for activity_stats / UserRouteStats fields.

    sign=1 for increment, sign=-1 for decrement.
    """
    inc = {}
    inc["totalCount"] = sign
    inc["totalDuration"] = sign * duration

    if status == ActivityStatus.COMPLETED:
        inc["completedCount"] = sign
        inc["completedDuration"] = sign * duration
        if location_verified:
            inc["verifiedCompletedCount"] = sign
            inc["verifiedCompletedDuration"] = sign * duration

    return inc


async def _update_route_stats(route_id: PydanticObjectId, inc: dict) -> None:
    """Increment Route.activity_stats fields."""
    prefixed = {f"activityStats.{k}": v for k, v in inc.items()}
    await Route.find_one(Route.id == route_id).update({"$inc": prefixed})


async def _update_user_route_stats(
    user_id: PydanticObjectId,
    route_id: PydanticObjectId,
    inc: dict,
    activity_at: Optional[datetime] = None,
) -> None:
    """Upsert and increment UserRouteStats fields."""
    update_ops: dict = {"$inc": inc}
    if activity_at:
        update_ops["$set"] = {"lastActivityAt": activity_at}

    await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    ).upsert(
        update_ops,
        on_insert=UserRouteStats(
            user_id=user_id,
            route_id=route_id,
            total_count=inc.get("totalCount", 0),
            total_duration=inc.get("totalDuration", 0),
            completed_count=inc.get("completedCount", 0),
            completed_duration=inc.get("completedDuration", 0),
            verified_completed_count=inc.get("verifiedCompletedCount", 0),
            verified_completed_duration=inc.get("verifiedCompletedDuration", 0),
            last_activity_at=activity_at,
        ),
    )


def _activity_to_response(activity: Activity) -> ActivityResponse:
    """Convert Activity document to response model."""
    return ActivityResponse(
        id=activity.id,
        route_id=activity.route_id,
        status=activity.status,
        location_verified=activity.location_verified,
        started_at=activity.started_at,
        ended_at=activity.ended_at,
        duration=activity.duration,
        route_snapshot=activity.route_snapshot,
        created_at=activity.created_at,
        updated_at=activity.updated_at,
    )


async def _build_route_snapshot(route: Route) -> RouteSnapshot:
    """Build RouteSnapshot from Route, Image, and Place."""
    image = await Image.get(route.image_id)

    place_id = None
    place_name = None
    if image and image.place_id:
        place = await Place.get(image.place_id)
        if place:
            place_id = place.id
            place_name = place.name

    return RouteSnapshot(
        title=route.title,
        grade_type=route.grade_type,
        grade=route.grade,
        grade_color=route.grade_color,
        place_id=place_id,
        place_name=place_name,
        image_url=str(route.image_url) if route.image_url else None,
        overlay_image_url=str(route.overlay_image_url) if route.overlay_image_url else None,
    )


async def _verify_location(route: Route, latitude: float, longitude: float) -> bool:
    """Check if user's location is within 300m of the route's place."""
    image = await Image.get(route.image_id)
    if not image or not image.place_id:
        return False

    place = await Place.get(image.place_id)
    if not place or place.latitude is None or place.longitude is None:
        return False

    distance = haversine_distance(latitude, longitude, place.latitude, place.longitude)
    return distance <= LOCATION_VERIFICATION_RADIUS_M


def _encode_activity_cursor(started_at_iso: str, last_id: str) -> str:
    cursor_str = f"{started_at_iso}|{last_id}"
    return base64.b64encode(cursor_str.encode()).decode()


def _decode_activity_cursor(cursor: str) -> tuple[str, str]:
    decoded = base64.b64decode(cursor.encode()).decode()
    started_at_str, last_id = decoded.split("|", 1)
    return started_at_str, last_id


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.post("/{route_id}/activity", status_code=http_status.HTTP_201_CREATED, response_model=ActivityResponse)
async def create_activity(
    route_id: str,
    request: CreateActivityRequest,
    current_user: User = Depends(get_current_user),
):
    # 1. Route 존재 확인
    route = await Route.find_one(
        Route.id == ObjectId(route_id),
        Route.is_deleted != True,
    )
    if not route:
        raise HTTPException(status_code=http_status.HTTP_404_NOT_FOUND, detail="Route not found")

    # 2. 위치 인증
    location_verified = await _verify_location(route, request.latitude, request.longitude)

    # 3. 스냅샷 생성
    snapshot = await _build_route_snapshot(route)

    # 4. duration 계산
    duration = _compute_duration(request.started_at, request.ended_at)

    # 5. Activity 생성
    now = datetime.now(tz=timezone.utc)
    activity = Activity(
        route_id=route.id,
        user_id=current_user.id,
        status=request.status,
        location_verified=location_verified,
        started_at=request.started_at,
        ended_at=request.ended_at,
        duration=duration,
        timezone=request.timezone,
        route_snapshot=snapshot,
        created_at=now,
    )
    await activity.save()

    # 6. Stats 갱신
    inc = _build_stats_inc(request.status, location_verified, duration, sign=1)
    await _update_route_stats(route.id, inc)
    await _update_user_route_stats(current_user.id, route.id, inc, activity_at=now)

    return _activity_to_response(activity)


@router.delete("/{route_id}/activity/{activity_id}", status_code=http_status.HTTP_204_NO_CONTENT)
async def delete_activity(
    route_id: str,
    activity_id: str,
    current_user: User = Depends(get_current_user),
):
    # 1. Activity 존재 + 소유 확인
    activity = await Activity.find_one(
        Activity.id == ObjectId(activity_id),
        Activity.route_id == ObjectId(route_id),
        Activity.user_id == current_user.id,
    )
    if not activity:
        raise HTTPException(status_code=http_status.HTTP_404_NOT_FOUND, detail="Activity not found")

    # 2. Stats 감소
    inc = _build_stats_inc(activity.status, activity.location_verified, activity.duration, sign=-1)
    await _update_route_stats(activity.route_id, inc)
    await _update_user_route_stats(current_user.id, activity.route_id, inc)

    # 3. Hard delete
    await activity.delete()


@router.get("/{route_id}/my-stats", response_model=MyStatsResponse)
async def get_my_stats(
    route_id: str,
    current_user: User = Depends(get_current_user),
):
    stats = await UserRouteStats.find_one(
        UserRouteStats.user_id == current_user.id,
        UserRouteStats.route_id == ObjectId(route_id),
    )
    if not stats:
        return MyStatsResponse()

    return MyStatsResponse(
        total_count=stats.total_count,
        total_duration=stats.total_duration,
        completed_count=stats.completed_count,
        completed_duration=stats.completed_duration,
        verified_completed_count=stats.verified_completed_count,
        verified_completed_duration=stats.verified_completed_duration,
    )


@router.get("/{route_id}/my-activities", response_model=MyActivitiesResponse)
async def get_my_activities(
    route_id: str,
    current_user: User = Depends(get_current_user),
    status: Optional[ActivityStatus] = None,
    limit: int = Query(default=10, ge=1, le=50),
    cursor: Optional[str] = None,
):
    query_filters = [
        Activity.route_id == ObjectId(route_id),
        Activity.user_id == current_user.id,
    ]

    if status:
        query_filters.append(Activity.status == status)

    if cursor:
        try:
            started_at_str, last_id = _decode_activity_cursor(cursor)
            cursor_started_at = datetime.fromisoformat(started_at_str)
            cursor_id = ObjectId(last_id)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid cursor")
        # startedAt DESC, _id DESC: get items before cursor
        from beanie.odm.operators.find.comparison import LT
        from beanie.odm.operators.find.logical import Or, And
        from beanie.odm.operators.find.comparison import Eq

        query_filters.append(
            Or(
                LT(Activity.started_at, cursor_started_at),
                And(
                    Eq(Activity.started_at, cursor_started_at),
                    LT(Activity.id, cursor_id),
                ),
            )
        )

    activities = (
        await Activity.find(*query_filters)
        .sort([("started_at", -1), ("_id", -1)])
        .limit(limit + 1)
        .to_list()
    )

    has_next = len(activities) > limit
    next_cursor = None

    if has_next:
        activities = activities[:limit]
        last = activities[-1]
        next_cursor = _encode_activity_cursor(
            last.started_at.isoformat(), str(last.id)
        )

    return MyActivitiesResponse(
        activities=[
            ActivityListItem(
                id=str(a.id),
                status=a.status,
                location_verified=a.location_verified,
                started_at=a.started_at,
                ended_at=a.ended_at,
                duration=a.duration,
                created_at=a.created_at,
            )
            for a in activities
        ],
        next_cursor=next_cursor,
    )
