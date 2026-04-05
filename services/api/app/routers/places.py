import io
import math
import os
import uuid
from datetime import datetime, timezone
from typing import List, Optional

from beanie.odm.fields import PydanticObjectId
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi import status
from PIL import Image as PILImage
from pydantic import BaseModel, Field

from app.core.gcs import bucket, get_base_url
from app.dependencies import get_current_user
from app.models import model_config
from app.models.place import Place, PlaceSuggestion, PlaceSuggestionChanges, normalize_name
from app.models.user import User

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


class UpdatePlaceRequest(BaseModel):
    model_config = model_config

    name: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None


class CreatePlaceSuggestionRequest(BaseModel):
    model_config = model_config

    place_id: str
    changes: PlaceSuggestionChanges


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
    image_url: Optional[str]
    thumbnail_url: Optional[str]
    created_by: PydanticObjectId
    distance: Optional[float] = None


class PlaceImageUploadResponse(BaseModel):
    model_config = model_config

    image_url: str
    thumbnail_url: str


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Return distance in metres between two (lat, lon) points."""
    R = 6_371_000  # Earth radius in metres
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _place_to_view(place: Place, distance: Optional[float] = None) -> PlaceView:
    return PlaceView(
        id=place.id,
        name=place.name,
        type=place.type,
        latitude=place.latitude,
        longitude=place.longitude,
        image_url=place.image_url,
        thumbnail_url=place.thumbnail_url,
        created_by=place.created_by,
        distance=distance,
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.post("", status_code=status.HTTP_201_CREATED, response_model=PlaceView)
async def create_place(
    request: CreatePlaceRequest,
    current_user: User = Depends(get_current_user),
):
    if request.type not in ("gym", "private-gym"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="type must be 'gym' or 'private-gym'",
        )

    if request.type == "gym" and (request.latitude is None or request.longitude is None):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="latitude and longitude are required for type 'gym'",
        )

    place = Place(
        name=request.name,
        normalized_name=normalize_name(request.name),
        type=request.type,
        latitude=request.latitude,
        longitude=request.longitude,
        image_url=None,
        thumbnail_url=None,
        created_by=current_user.id,
        created_at=datetime.now(tz=timezone.utc),
    )

    created = await place.save()
    return _place_to_view(created)


@router.get("/nearby", response_model=List[PlaceView])
async def get_nearby_places(
    latitude: float = Query(..., description="기준 위도"),
    longitude: float = Query(..., description="기준 경도"),
    radius: float = Query(100, description="반경 (미터)"),
    current_user: User = Depends(get_current_user),
):
    # Bounding box pre-filter (1 degree lat ≈ 111 320 m)
    delta_lat = radius / 111_320
    delta_lon = radius / (111_320 * math.cos(math.radians(latitude)))

    lat_min = latitude - delta_lat
    lat_max = latitude + delta_lat
    lon_min = longitude - delta_lon
    lon_max = longitude + delta_lon

    candidates = await Place.find(
        Place.latitude >= lat_min,
        Place.latitude <= lat_max,
        Place.longitude >= lon_min,
        Place.longitude <= lon_max,
    ).to_list()

    results: List[PlaceView] = []
    for place in candidates:
        # Visibility filter
        if place.type == "private-gym" and str(place.created_by) != str(current_user.id):
            continue

        # Exact haversine distance check
        if place.latitude is None or place.longitude is None:
            continue
        distance = _haversine(latitude, longitude, place.latitude, place.longitude)
        if distance <= radius:
            results.append(_place_to_view(place, distance=round(distance, 2)))

    results.sort(key=lambda p: p.distance)
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
        {"normalized_name": {"$regex": normalized_query, "$options": "i"}}
    ).limit(20).to_list()

    results: List[PlaceView] = []
    for place in candidates:
        if place.type == "private-gym" and str(place.created_by) != str(current_user.id):
            continue
        results.append(_place_to_view(place))

    return results


@router.put("/{place_id}", response_model=PlaceView)
async def update_place(
    place_id: str,
    request: UpdatePlaceRequest,
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

    if request.name is not None:
        place.name = request.name
        place.normalized_name = normalize_name(request.name)
    if request.latitude is not None:
        place.latitude = request.latitude
    if request.longitude is not None:
        place.longitude = request.longitude

    await place.save()
    return _place_to_view(place)


@router.post("/suggestions", status_code=status.HTTP_201_CREATED, response_model=PlaceSuggestionView)
async def create_place_suggestion(
    request: CreatePlaceSuggestionRequest,
    current_user: User = Depends(get_current_user),
):
    place = await Place.get(request.place_id)
    if place is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Place not found")

    if place.type == "private-gym":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Suggestions are not allowed for private-gym places",
        )

    suggestion = PlaceSuggestion(
        place_id=place.id,
        requested_by=current_user.id,
        status="pending",
        changes=request.changes,
        created_at=datetime.now(tz=timezone.utc),
    )
    created = await suggestion.save()

    return PlaceSuggestionView(
        id=created.id,
        place_id=created.place_id,
        requested_by=created.requested_by,
        status=created.status,
        changes=created.changes,
        created_at=created.created_at,
    )


@router.post("/{place_id}/image", response_model=PlaceImageUploadResponse)
async def upload_place_image(
    place_id: str,
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    place = await Place.get(place_id)
    if place is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Place not found")

    file_ext = os.path.splitext(file.filename or "")[1].lower()
    if file_ext not in (".jpg", ".jpeg", ".png"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only jpg/jpeg/png files are supported",
        )

    if place.type == "private-gym":
        if str(place.created_by) != str(current_user.id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only the creator can upload an image for a private gym",
            )
    else:
        # gym: only allowed if no image exists yet
        if place.image_url is not None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="This place already has an image. Please use the suggestion feature to propose a new one.",
            )

    content = await file.read()
    unique_name = str(uuid.uuid4())

    # Upload original image
    blob = bucket.blob(f"place_images/{unique_name}{file_ext}")
    content_type = "image/png" if file_ext == ".png" else "image/jpeg"
    blob.upload_from_string(data=content, content_type=content_type)
    image_url = f"{get_base_url()}/place_images/{unique_name}{file_ext}"

    # Generate and upload 200x200 thumbnail
    img = PILImage.open(io.BytesIO(content))
    img = img.convert("RGB")
    img.thumbnail((200, 200))
    thumb_buffer = io.BytesIO()
    img.save(thumb_buffer, format="JPEG", quality=85)
    thumb_buffer.seek(0)

    thumb_blob = bucket.blob(f"place_images/{unique_name}_thumb.jpg")
    thumb_blob.upload_from_string(data=thumb_buffer.read(), content_type="image/jpeg")
    thumbnail_url = f"{get_base_url()}/place_images/{unique_name}_thumb.jpg"

    place.image_url = image_url
    place.thumbnail_url = thumbnail_url
    await place.save()

    return PlaceImageUploadResponse(image_url=image_url, thumbnail_url=thumbnail_url)
