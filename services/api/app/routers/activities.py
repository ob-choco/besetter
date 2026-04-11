from datetime import datetime, timezone
from typing import Optional

from beanie.odm.fields import PydanticObjectId
from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException
from fastapi import status as http_status
from pydantic import BaseModel, Field

from app.core.geo import haversine_distance
from app.dependencies import get_current_user
from app.models import model_config
from app.models.activity import (
    Activity,
    ActivityStats,
    ActivityStatus,
    RouteSnapshot,
    UserRouteStats,
)
from app.models.image import Image
from app.models.place import Place
from app.models.route import Route
from app.models.user import User
from app.core.gcs import generate_signed_url, extract_blob_path_from_url

router = APIRouter(prefix="/routes", tags=["activities"])

LOCATION_VERIFICATION_RADIUS_M = 300
AUTO_CANCEL_MAX_DURATION_S = 3600


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------


class CreateActivityRequest(BaseModel):
    model_config = model_config

    latitude: float
    longitude: float
    status: Optional[ActivityStatus] = None
    ended_at: Optional[datetime] = None


class UpdateActivityRequest(BaseModel):
    model_config = model_config

    status: ActivityStatus
    ended_at: datetime


class ActivityResponse(BaseModel):
    model_config = model_config

    id: PydanticObjectId
    route_id: PydanticObjectId
    status: ActivityStatus
    location_verified: bool
    started_at: datetime
    ended_at: Optional[datetime] = None
    duration: Optional[int] = None
    route_snapshot: RouteSnapshot
    created_at: datetime
    updated_at: Optional[datetime] = None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _compute_duration(started_at: datetime, ended_at: datetime) -> int:
    """Return duration in seconds between started_at and ended_at."""
    return int((ended_at - started_at).total_seconds())


def _build_stats_inc(
    status: ActivityStatus,
    location_verified: bool,
    duration: Optional[int],
    sign: int = 1,
) -> dict:
    """Build a MongoDB $inc dict for activity_stats / UserRouteStats fields.

    sign=1 for increment, sign=-1 for decrement.
    """
    inc = {}
    inc["totalCount"] = sign

    if duration is not None:
        inc["totalDuration"] = sign * duration

    if status == ActivityStatus.COMPLETED:
        inc["completedCount"] = sign
        if duration is not None:
            inc["completedDuration"] = sign * duration
        if location_verified:
            inc["verifiedCompletedCount"] = sign
            if duration is not None:
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
    if not place or not place.latitude or not place.longitude:
        return False

    distance = haversine_distance(latitude, longitude, place.latitude, place.longitude)
    return distance <= LOCATION_VERIFICATION_RADIUS_M


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

    # 2. 상태 및 endedAt 유효성
    req_status = request.status or ActivityStatus.STARTED
    if req_status in (ActivityStatus.COMPLETED, ActivityStatus.ATTEMPTED) and request.ended_at is None:
        raise HTTPException(
            status_code=http_status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="endedAt is required when status is completed or attempted",
        )

    # 3. 위치 인증
    location_verified = await _verify_location(route, request.latitude, request.longitude)

    # 4. 자동취소: 같은 route + user의 기존 "started" Activity
    now = datetime.now(tz=timezone.utc)
    existing_started = await Activity.find(
        Activity.route_id == route.id,
        Activity.user_id == current_user.id,
        Activity.status == ActivityStatus.STARTED,
    ).to_list()

    for old in existing_started:
        raw_duration = int((now - old.started_at).total_seconds())
        capped_duration = min(raw_duration, AUTO_CANCEL_MAX_DURATION_S)
        old.status = ActivityStatus.ATTEMPTED
        old.ended_at = now
        old.duration = capped_duration
        old.updated_at = now
        await old.save()

        # 자동취소 stats: total_count는 이미 +1 되어 있으므로 duration만 추가
        auto_inc = {}
        if capped_duration > 0:
            auto_inc["totalDuration"] = capped_duration
        if auto_inc:
            await _update_route_stats(route.id, auto_inc)
            await _update_user_route_stats(current_user.id, route.id, auto_inc)

    # 5. 스냅샷 생성
    snapshot = await _build_route_snapshot(route)

    # 6. duration 계산
    duration = None
    if req_status in (ActivityStatus.COMPLETED, ActivityStatus.ATTEMPTED):
        duration = _compute_duration(now, request.ended_at)

    # 7. Activity 생성
    activity = Activity(
        route_id=route.id,
        user_id=current_user.id,
        status=req_status,
        location_verified=location_verified,
        started_at=now,
        ended_at=request.ended_at if req_status != ActivityStatus.STARTED else None,
        duration=duration,
        route_snapshot=snapshot,
        created_at=now,
    )
    await activity.save()

    # 8. Stats 갱신
    inc = _build_stats_inc(req_status, location_verified, duration, sign=1)
    await _update_route_stats(route.id, inc)
    await _update_user_route_stats(current_user.id, route.id, inc, activity_at=now)

    return _activity_to_response(activity)


@router.patch("/{route_id}/activity/{activity_id}", response_model=ActivityResponse)
async def update_activity(
    route_id: str,
    activity_id: str,
    request: UpdateActivityRequest,
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

    # 2. 이미 종료된 건 수정 불가
    if activity.status != ActivityStatus.STARTED:
        raise HTTPException(
            status_code=http_status.HTTP_400_BAD_REQUEST,
            detail="Only activities with status 'started' can be updated",
        )

    # 3. status 유효성
    if request.status not in (ActivityStatus.COMPLETED, ActivityStatus.ATTEMPTED):
        raise HTTPException(
            status_code=http_status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Status must be 'completed' or 'attempted'",
        )

    # 4. duration 계산 + 업데이트
    now = datetime.now(tz=timezone.utc)
    duration = _compute_duration(activity.started_at, request.ended_at)
    activity.status = request.status
    activity.ended_at = request.ended_at
    activity.duration = duration
    activity.updated_at = now
    await activity.save()

    # 5. Stats 갱신 — PATCH는 이미 total_count +1 되어 있으므로 count 증가 없이 duration + completed 관련만
    inc: dict = {}
    inc["totalDuration"] = duration
    if request.status == ActivityStatus.COMPLETED:
        inc["completedCount"] = 1
        inc["completedDuration"] = duration
        if activity.location_verified:
            inc["verifiedCompletedCount"] = 1
            inc["verifiedCompletedDuration"] = duration

    await _update_route_stats(activity.route_id, inc)
    await _update_user_route_stats(current_user.id, activity.route_id, inc, activity_at=now)

    return _activity_to_response(activity)
