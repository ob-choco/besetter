import logging
import os
import re
import uuid
from datetime import datetime, timezone
from typing import List, Optional

from beanie.odm.fields import PydanticObjectId
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi import status
from pydantic import BaseModel, Field

from app.core.geo import haversine_distance
from app.core.gcs import bucket, get_base_url
from app.dependencies import get_current_user
from app.models import model_config
from app.models.notification import Notification
from app.models.place import Place, PlaceSuggestion, PlaceSuggestionChanges, normalize_name
from app.models.user import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/places", tags=["places"])


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------


class CreatePlaceRequest(BaseModel):
    model_config = model_config

    name: str = Field(..., description="장소 이름")
    latitude: Optional[float] = Field(None, description="위도")
    longitude: Optional[float] = Field(None, description="경도")
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
        latitude=place.latitude,
        longitude=place.longitude,
        cover_image_url=place.cover_image_url,
        created_by=place.created_by,
        distance=distance,
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


def _upload_place_image(content: bytes, file_ext: str) -> str:
    """Upload the place cover image to GCS and return its public URL."""
    unique_name = str(uuid.uuid4())
    blob = bucket.blob(f"place_images/{unique_name}{file_ext}")
    content_type = "image/png" if file_ext == ".png" else "image/jpeg"
    blob.upload_from_string(data=content, content_type=content_type)
    return f"{get_base_url()}/place_images/{unique_name}{file_ext}"


@router.post("", status_code=status.HTTP_201_CREATED, response_model=PlaceView)
async def create_place(
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
        cover_image_url=cover_image_url,
        created_by=current_user.id,
        created_at=datetime.now(tz=timezone.utc),
    )
    place.set_location_from(latitude, longitude)

    created = await place.save()
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
            place_to_view(place, distance=round(distance, 2) if distance else None)
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

    if place.type != "private-gym" or str(place.created_by) != str(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not allowed to update this place",
        )

    if name is not None:
        place.name = name
        place.normalized_name = normalize_name(name)

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


@router.post("/suggestions", status_code=status.HTTP_201_CREATED, response_model=PlaceSuggestionView)
async def create_place_suggestion(
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
        place_name_snapshot = place.name
        notif = Notification(
            user_id=current_user.id,
            type="place_suggestion_ack",
            title="정보 수정 제안이 접수되었습니다",
            body=(
                f"{place_name_snapshot}에 대한 소중한 제보 감사합니다 🙌 "
                "운영진이 확인하고 반영할게요."
            ),
            link=f"/places/{place.id}",
            created_at=datetime.now(tz=timezone.utc),
        )
        await notif.save()
        await User.get_motor_collection().update_one(
            {"_id": current_user.id},
            {"$inc": {"unreadNotificationCount": 1}},
        )
    except Exception as exc:  # best-effort; do not block suggestion creation
        logger.warning(
            "notification creation failed for place %s: %s",
            place.id,
            exc,
            exc_info=True,
        )

    return PlaceSuggestionView(
        id=created.id,
        place_id=created.place_id,
        requested_by=created.requested_by,
        status=created.status,
        changes=created.changes,
        created_at=created.created_at,
    )


