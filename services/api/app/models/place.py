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
    latitude: Optional[float] = Field(None, description="위도")
    longitude: Optional[float] = Field(None, description="경도")
    location: Optional[GeoJsonPoint] = Field(None, description="GeoJSON Point for 2dsphere index")
    image_url: Optional[str] = Field(None, description="장소 이미지 URL")
    thumbnail_url: Optional[str] = Field(None, description="장소 썸네일 URL")
    created_by: PydanticObjectId = Field(..., description="생성한 사용자의 ID")
    created_at: datetime = Field(..., description="생성 시간")

    def set_location(self):
        """latitude/longitude로부터 GeoJSON location 필드를 설정"""
        if self.latitude is not None and self.longitude is not None:
            self.location = GeoJsonPoint(coordinates=[self.longitude, self.latitude])
        else:
            self.location = None

    class Settings:
        name = "places"
        indexes = [
            IndexModel([("location", GEOSPHERE)], sparse=True),
            IndexModel([("created_by", ASCENDING)]),
            IndexModel([("normalized_name", ASCENDING)]),
        ]
        keep_nulls = True


class PlaceSuggestionChanges(BaseModel):
    model_config = model_config

    name: Optional[str] = Field(None, description="변경 제안된 이름")
    latitude: Optional[float] = Field(None, description="변경 제안된 위도")
    longitude: Optional[float] = Field(None, description="변경 제안된 경도")
    image_url: Optional[str] = Field(None, description="변경 제안된 이미지 URL")


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
        name = "place_suggestions"
        indexes = [
            IndexModel([("place_id", ASCENDING)]),
            IndexModel([("status", ASCENDING)]),
        ]
        keep_nulls = True
