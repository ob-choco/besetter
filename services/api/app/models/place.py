import re
from beanie import Document
from typing import Optional, Literal
from beanie.odm.fields import PydanticObjectId
from pydantic import BaseModel, Field
from datetime import datetime
from pymongo import IndexModel, ASCENDING, GEOSPHERE

from . import model_config


class GeoJsonPoint(BaseModel):
    model_config = model_config

    type: str = Field(default="Point")
    coordinates: list[float] = Field(default_factory=list, description="[longitude, latitude]")


def normalize_name(name: str) -> str:
    """Remove spaces, symbols, special characters and lowercase the name.
    Handles Korean, Japanese, and Latin characters."""
    # Keep only Unicode letters and digits (covers Korean, Japanese, Latin, etc.)
    normalized = re.sub(r"[^\w]", "", name, flags=re.UNICODE)
    # Remove underscores (included in \w but considered a symbol here)
    normalized = normalized.replace("_", "")
    return normalized.lower()


class Place(Document):
    model_config = model_config

    name: str = Field(..., description="장소 이름")
    normalized_name: str = Field(..., description="정규화된 장소 이름 (공백/기호 제거, 소문자)")
    type: Literal["gym", "private-gym"] = Field(..., description="장소 유형")
    location: Optional[GeoJsonPoint] = Field(None, description="GeoJSON Point [lng, lat]")
    cover_image_url: Optional[str] = Field(None, description="대표 이미지 URL")
    created_by: PydanticObjectId = Field(..., description="생성한 사용자의 ID")
    created_at: datetime = Field(..., description="생성 시간")
    status: Literal["pending", "approved", "rejected", "merged"] = Field(
        default="approved",
        description="장소 상태. gym 최초 생성은 pending, private-gym은 approved.",
    )
    merged_into_place_id: Optional[PydanticObjectId] = Field(
        default=None,
        description="merged 상태일 때 병합 대상 place의 ID. 검수 툴이 설정.",
    )
    rejected_reason: Optional[str] = Field(
        default=None,
        description="FAIL 시 운영자가 남긴 반려 사유 (선택).",
    )

    def set_location_from(self, latitude: Optional[float], longitude: Optional[float]):
        """lat/lng으로 GeoJSON location 설정"""
        if latitude is not None and longitude is not None:
            self.location = GeoJsonPoint(coordinates=[longitude, latitude])
        else:
            self.location = None

    @property
    def latitude(self) -> Optional[float]:
        if self.location and len(self.location.coordinates) == 2:
            return self.location.coordinates[1]
        return None

    @property
    def longitude(self) -> Optional[float]:
        if self.location and len(self.location.coordinates) == 2:
            return self.location.coordinates[0]
        return None

    class Settings:
        name = "places"
        indexes = [
            IndexModel([("location", GEOSPHERE)], sparse=True),
            IndexModel([("createdBy", ASCENDING)]),
            IndexModel([("normalizedName", ASCENDING)]),
            IndexModel([("type", ASCENDING), ("status", ASCENDING)]),
        ]
        keep_nulls = True


class PlaceSuggestionChanges(BaseModel):
    model_config = model_config

    name: Optional[str] = Field(None, description="변경 제안된 이름")
    latitude: Optional[float] = Field(None, description="변경 제안된 위도")
    longitude: Optional[float] = Field(None, description="변경 제안된 경도")
    cover_image_url: Optional[str] = Field(None, description="변경 제안된 대표 이미지 URL")


class PlaceSuggestion(Document):
    model_config = model_config

    place_id: PydanticObjectId = Field(..., description="제안 대상 장소의 ID")
    requested_by: PydanticObjectId = Field(..., description="제안한 사용자의 ID")
    status: Literal["pending", "approved", "rejected"] = Field(..., description="제안 상태")
    changes: PlaceSuggestionChanges = Field(..., description="제안된 변경 사항")
    created_at: datetime = Field(..., description="생성 시간")
    read_at: Optional[datetime] = Field(None, description="읽은 시간")
    reviewed_at: Optional[datetime] = Field(None, description="검토 시간")

    class Settings:
        name = "placeSuggestions"
        indexes = [
            IndexModel([("placeId", ASCENDING)]),
            IndexModel([("status", ASCENDING)]),
        ]
        keep_nulls = True
