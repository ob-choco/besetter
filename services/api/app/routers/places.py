import logging
import os
import re
import uuid
from datetime import datetime, timezone
from typing import List, Literal, Optional

from beanie.odm.fields import PydanticObjectId
from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Query, Response, UploadFile
from fastapi import status
from pydantic import BaseModel, Field

from app.core.geo import haversine_distance
from app.core.gcs import bucket, extract_blob_path_from_url, get_base_url, to_public_url
from app.dependencies import get_current_user
from app.models import model_config
from app.models.image import Image
from app.models.notification import Notification
from app.models.place import Place, PlaceSuggestion, PlaceSuggestionChanges, normalize_name
from app.models.route import Route
from app.models.user import User
from app.services import push_sender, telegram_notifier
from beanie.odm.operators.find.comparison import In

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/places", tags=["places"])


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------


PLACE_NAME_MAX_LENGTH = 64


class CreatePlaceRequest(BaseModel):
    model_config = model_config

    name: str = Field(..., description="장소 이름", min_length=1, max_length=PLACE_NAME_MAX_LENGTH)
    latitude: Optional[float] = Field(None, description="위도", ge=-90, le=90)
    longitude: Optional[float] = Field(None, description="경도", ge=-180, le=180)
    type: str = Field("gym", description="장소 유형 (gym | private-gym)")


class PlaceSuggestionView(BaseModel):
    model_config = model_config

    id: PydanticObjectId
    place_id: PydanticObjectId
    requested_by: PydanticObjectId
    status: str
    changes: PlaceSuggestionChanges
    created_at: datetime


class PlaceView(BaseModel):
    model_config = model_config

    id: PydanticObjectId
    name: str
    type: str
    status: Literal["pending", "approved", "rejected", "merged"]
    latitude: Optional[float]
    longitude: Optional[float]
    cover_image_url: Optional[str]
    created_by: PydanticObjectId
    distance: Optional[float] = None


class PlaceImageUploadResponse(BaseModel):
    model_config = model_config

    cover_image_url: str


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def place_to_view(place: Place, distance: Optional[float] = None) -> PlaceView:
    return PlaceView(
        id=place.id,
        name=place.name,
        type=place.type,
        status=place.status,
        latitude=place.latitude,
        longitude=place.longitude,
        cover_image_url=to_public_url(place.cover_image_url),
        created_by=place.created_by,
        distance=round(distance, 2) if distance is not None else None,
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


def _validate_place_name_or_raise(name: str) -> None:
    length = len(name)
    if length < 1 or length > PLACE_NAME_MAX_LENGTH:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"name must be 1..{PLACE_NAME_MAX_LENGTH} characters",
        )


def _validate_coord_or_raise(latitude: Optional[float], longitude: Optional[float]) -> None:
    if latitude is not None and not -90 <= latitude <= 90:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="latitude must be within [-90, 90]",
        )
    if longitude is not None and not -180 <= longitude <= 180:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="longitude must be within [-180, 180]",
        )


def _upload_place_image(content: bytes, file_ext: str) -> str:
    """Upload the place cover image to GCS and return its public URL."""
    unique_name = str(uuid.uuid4())
    blob = bucket.blob(f"place_images/{unique_name}{file_ext}")
    content_type = "image/png" if file_ext == ".png" else "image/jpeg"
    blob.upload_from_string(data=content, content_type=content_type)
    return f"{get_base_url()}/place_images/{unique_name}{file_ext}"


@router.post("", status_code=status.HTTP_201_CREATED, response_model=PlaceView)
async def create_place(
    background_tasks: BackgroundTasks,
    name: str = Form(...),
    type: str = Form("gym"),
    latitude: Optional[float] = Form(None),
    longitude: Optional[float] = Form(None),
    image: Optional[UploadFile] = File(None),
    current_user: User = Depends(get_current_user),
):
    if type not in ("gym", "private-gym"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="type must be 'gym' or 'private-gym'",
        )

    if type == "gym" and (latitude is None or longitude is None):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="latitude and longitude are required for type 'gym'",
        )

    _validate_place_name_or_raise(name)
    _validate_coord_or_raise(latitude, longitude)

    # 이미지 처리
    cover_image_url = None
    if image is not None and image.filename:
        file_ext = os.path.splitext(image.filename)[1].lower()
        if file_ext not in (".jpg", ".jpeg", ".png"):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Only jpg/jpeg/png files are supported",
            )
        content = await image.read()
        cover_image_url = _upload_place_image(content, file_ext)

    place = Place(
        name=name,
        normalized_name=normalize_name(name),
        type=type,
        status="pending" if type == "gym" else "approved",
        cover_image_url=cover_image_url,
        created_by=current_user.id,
        created_at=datetime.now(tz=timezone.utc),
    )
    place.set_location_from(latitude, longitude)

    created = await place.save()

    # Best-effort: notify the requester with a thank-you message for gym registration.
    if place.type == "gym":
        try:
            notif = Notification(
                user_id=current_user.id,
                type="place_registration_ack",
                title="",
                body="",
                params={"place_name": place.name},
                link=f"/places/{place.id}",
                created_at=datetime.now(tz=timezone.utc),
            )
            await notif.save()
            await User.get_pymongo_collection().update_one(
                {"_id": current_user.id},
                {"$inc": {"unreadNotificationCount": 1}},
            )
            background_tasks.add_task(
                push_sender.send_to_user, current_user.id, notif
            )
        except Exception as exc:
            logger.warning(
                "registration_ack notification failed for place %s: %s",
                place.id,
                exc,
                exc_info=True,
            )
        background_tasks.add_task(
            telegram_notifier.notify_place_registration_request,
            place,
            current_user,
        )

    return place_to_view(created)


@router.get("/nearby", response_model=List[PlaceView])
async def get_nearby_places(
    latitude: float = Query(..., description="기준 위도"),
    longitude: float = Query(..., description="기준 경도"),
    radius: float = Query(100, description="반경 (미터)"),
    current_user: User = Depends(get_current_user),
):
    # $nearSphere with 2dsphere index — returns sorted by distance
    query_filter = {
        "type": "gym",
        "$or": [
            {"status": "approved"},
            {"status": "pending", "createdBy": current_user.id},
        ],
        "location": {
            "$nearSphere": {
                "$geometry": {
                    "type": "Point",
                    "coordinates": [longitude, latitude],
                },
                "$maxDistance": radius,
            }
        },
    }

    candidates = await Place.find(query_filter).to_list()

    results: List[PlaceView] = []
    for place in candidates:
        distance = (
            haversine_distance(latitude, longitude, place.latitude, place.longitude)
            if place.latitude and place.longitude
            else None
        )
        results.append(
            place_to_view(place, distance=distance)
        )

    return results


@router.get("/instant-search", response_model=List[PlaceView])
async def instant_search_places(
    query: str = Query(..., description="검색어"),
    current_user: User = Depends(get_current_user),
):
    normalized_query = normalize_name(query)
    if len(normalized_query) < 2:
        return []

    candidates = await Place.find(
        {
            "type": "gym",
            "$or": [
                {"status": "approved"},
                {"status": "pending", "createdBy": current_user.id},
            ],
            "normalizedName": {
                "$regex": re.escape(normalized_query),
                "$options": "i",
            },
        }
    ).limit(20).to_list()

    return [place_to_view(place) for place in candidates]


@router.get("/my-private", response_model=List[PlaceView])
async def get_my_private_places(
    current_user: User = Depends(get_current_user),
):
    """Return every private-gym place owned by the current user, newest first."""
    candidates = await Place.find(
        Place.type == "private-gym",
        Place.created_by == current_user.id,
    ).sort(-Place.created_at).to_list()

    return [place_to_view(place) for place in candidates]


@router.put("/{place_id}", response_model=PlaceView)
async def update_place(
    place_id: str,
    name: Optional[str] = Form(None),
    latitude: Optional[float] = Form(None),
    longitude: Optional[float] = Form(None),
    image: Optional[UploadFile] = File(None),
    current_user: User = Depends(get_current_user),
):
    place = await Place.get(place_id)
    if place is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Place not found")

    is_owner = str(place.created_by) == str(current_user.id)
    if not is_owner:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not allowed to update this place",
        )

    if place.type == "gym" and place.status != "pending":
        # Direct-edit only applies to own pending gyms. Reviewed gyms
        # (approved / rejected / merged) must go through the suggestion flow
        # or be treated as stale from the client's perspective.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "PLACE_NOT_USABLE",
                "place_id": str(place.id),
                "place_name": place.name,
                "place_status": place.status,
            },
        )

    if name is not None:
        _validate_place_name_or_raise(name)
        place.name = name
        place.normalized_name = normalize_name(name)

    _validate_coord_or_raise(latitude, longitude)
    new_lat = latitude if latitude is not None else place.latitude
    new_lng = longitude if longitude is not None else place.longitude
    place.set_location_from(new_lat, new_lng)

    if image is not None and image.filename:
        file_ext = os.path.splitext(image.filename)[1].lower()
        if file_ext not in (".jpg", ".jpeg", ".png"):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Only jpg/jpeg/png files are supported",
            )
        content = await image.read()
        place.cover_image_url = _upload_place_image(content, file_ext)

    await place.save()
    return place_to_view(place)


@router.delete("/{place_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_place(
    place_id: str,
    current_user: User = Depends(get_current_user),
):
    place = await Place.get(place_id)
    if place is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Place not found",
        )

    is_owner = str(place.created_by) == str(current_user.id)
    is_own_pending_gym = (
        place.type == "gym" and place.status == "pending" and is_owner
    )
    is_own_private_gym = place.type == "private-gym" and is_owner
    if not (is_own_pending_gym or is_own_private_gym):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only your own pending gym or private-gym place can be deleted",
        )

    # Pending gym 데이터는 서비스에 노출된 적이 없으므로 audit 이력을
    # 남기지 않고 하드 삭제한다. Image/Route의 is_deleted soft-delete
    # 패턴은 의도적으로 건너뛴다.

    # 이 장소에 속한 이미지 수집
    images = await Image.find(Image.place_id == place.id).to_list()
    image_ids = [img.id for img in images]

    # 1) 루트 overlay 블롭 정리 후 루트 하드 삭제
    if image_ids:
        try:
            routes = await Route.find(In(Route.image_id, image_ids)).to_list()
            for route in routes:
                try:
                    overlay_blob = extract_blob_path_from_url(route.overlay_image_url)
                    if overlay_blob:
                        bucket.blob(overlay_blob).delete()
                except Exception as exc:
                    logger.warning(
                        "delete_place: route %s overlay GCS delete failed: %s",
                        route.id, exc, exc_info=True,
                    )
            await Route.find(In(Route.image_id, image_ids)).delete()
        except Exception as exc:
            logger.warning("delete_place: route cleanup failed for place %s: %s", place.id, exc, exc_info=True)

    # 2) 이미지 하드 삭제 + GCS 블롭 삭제 (best-effort per image)
    for img in images:
        try:
            await img.delete()
        except Exception as exc:
            logger.warning("delete_place: image %s delete failed: %s", img.id, exc, exc_info=True)
        try:
            blob_name = extract_blob_path_from_url(str(img.url)) if img.url else None
            if blob_name:
                bucket.blob(blob_name).delete()
        except Exception as exc:
            logger.warning("delete_place: image %s GCS delete failed: %s", img.id, exc, exc_info=True)

    # 3) 커버 이미지 GCS 블롭 삭제 (best-effort)
    try:
        cover_blob = extract_blob_path_from_url(place.cover_image_url or "")
        if cover_blob:
            bucket.blob(cover_blob).delete()
    except Exception as exc:
        logger.warning("delete_place: cover GCS delete failed for place %s: %s", place.id, exc, exc_info=True)

    # 4) Place 하드 삭제
    await place.delete()

    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/suggestions", status_code=status.HTTP_201_CREATED, response_model=PlaceSuggestionView)
async def create_place_suggestion(
    background_tasks: BackgroundTasks,
    place_id: str = Form(...),
    name: Optional[str] = Form(None),
    latitude: Optional[float] = Form(None),
    longitude: Optional[float] = Form(None),
    image: Optional[UploadFile] = File(None),
    current_user: User = Depends(get_current_user),
):
    place = await Place.get(place_id)
    if place is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Place not found")

    if place.type == "private-gym":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Suggestions are not allowed for private-gym places",
        )

    if place.status != "approved":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Suggestions are only allowed for approved places",
        )

    if name is not None:
        _validate_place_name_or_raise(name)
    _validate_coord_or_raise(latitude, longitude)

    # Upload image if provided
    cover_image_url: Optional[str] = None
    if image is not None and image.filename:
        file_ext = os.path.splitext(image.filename)[1].lower()
        if file_ext not in (".jpg", ".jpeg", ".png"):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Only jpg/jpeg/png files are supported",
            )
        content = await image.read()
        cover_image_url = _upload_place_image(content, file_ext)

    # Reject no-op suggestions
    if name is None and latitude is None and longitude is None and cover_image_url is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="At least one of name, latitude/longitude, or image must be provided",
        )

    changes = PlaceSuggestionChanges(
        name=name,
        latitude=latitude,
        longitude=longitude,
        cover_image_url=cover_image_url,
    )

    suggestion = PlaceSuggestion(
        place_id=place.id,
        requested_by=current_user.id,
        status="pending",
        changes=changes,
        created_at=datetime.now(tz=timezone.utc),
    )
    created = await suggestion.save()

    # Best-effort: notify the requester with a thank-you message.
    try:
        notif = Notification(
            user_id=current_user.id,
            type="place_suggestion_ack",
            title="",
            body="",
            params={"place_name": place.name},
            link=f"/places/{place.id}",
            created_at=datetime.now(tz=timezone.utc),
        )
        await notif.save()
        await User.get_pymongo_collection().update_one(
            {"_id": current_user.id},
            {"$inc": {"unreadNotificationCount": 1}},
        )
        background_tasks.add_task(
            push_sender.send_to_user, current_user.id, notif
        )
    except Exception as exc:  # best-effort; do not block suggestion creation
        logger.warning(
            "notification creation failed for place %s: %s",
            place.id,
            exc,
            exc_info=True,
        )
    background_tasks.add_task(
        telegram_notifier.notify_place_improvement_request,
        created,
        place,
        current_user,
    )

    return PlaceSuggestionView(
        id=created.id,
        place_id=created.place_id,
        requested_by=created.requested_by,
        status=created.status,
        changes=created.changes,
        created_at=created.created_at,
    )


