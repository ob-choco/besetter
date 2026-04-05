import math
from datetime import datetime, timezone
from typing import List, Optional

from beanie.odm.fields import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi import status
from pydantic import BaseModel, Field

from app.dependencies import get_current_user
from app.models import model_config
from app.models.place import Place, normalize_name
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
