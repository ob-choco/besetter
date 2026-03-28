from typing import List, Optional
from pydantic import BaseModel, Field, HttpUrl
from enum import Enum
from datetime import datetime
from beanie import Document
from beanie.odm.fields import PydanticObjectId

from pymongo import IndexModel, ASCENDING
from . import model_config


class RouteType(str, Enum):
    BOULDERING = "bouldering"
    ENDURANCE = "endurance"


class Visibility(str, Enum):
    PUBLIC = "public"
    PRIVATE = "private"
    UNLISTED = "unlisted"


class BoulderingHold(BaseModel):
    model_config = model_config

    polygon_id: int = Field(..., description="폴리곤 ID")
    type: str = Field(..., description="홀드 타입")
    marking_count: Optional[int] = Field(None, description="마킹 개수")
    checkpoint_score: Optional[int] = Field(None, description="체크포인트 점수")


class EnduranceHold(BaseModel):
    model_config = model_config

    polygon_id: int = Field(..., description="폴리곤 ID")
    grip_hand: Optional[str] = Field(None, description="손")


class Route(Document):
    model_config = model_config

    type: RouteType = Field(..., description="루트 타입")

    title: Optional[str] = Field(None, description="루트 제목")
    description: Optional[str] = Field(None, description="루트 설명")
    visibility: Visibility = Field(Visibility.PUBLIC, description="루트 공개 여부")
    grade_type: str = Field(..., description="등급 타입")
    grade: str = Field(..., description="등급")
    grade_color: Optional[str] = Field(None, description="등급 색상")
    grade_score: Optional[int] = Field(None, description="등급 점수")

    image_id: PydanticObjectId = Field(..., description="이미지 ID")
    hold_polygon_id: PydanticObjectId = Field(..., description="홀드 폴리곤 ID")
    user_id: PydanticObjectId = Field(..., description="이미지를 업로드한 사용자의 ID")
    image_url: HttpUrl = Field(..., description="이미지 URL (비정규화)")

    bouldering_holds: Optional[List[BoulderingHold]] = Field(None, description="볼더링 홀드 목록")
    endurance_holds: Optional[List[EnduranceHold]] = Field(None, description="지구력 홀드 목록")

    is_deleted: bool = Field(False, description="루트가 삭제되었는지 여부")

    overlay_image_url: Optional[HttpUrl] = Field(None, description="오버레이 이미지 URL")
    overlay_processing: bool = Field(False, description="오버레이 이미지 생성 작업 중 여부")
    overlay_started_at: Optional[datetime] = Field(None, description="오버레이 작업 시작 시간")
    overlay_completed_at: Optional[datetime] = Field(None, description="오버레이 작업 완료 시간")

    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: Optional[datetime] = Field(None)
    deleted_at: Optional[datetime] = Field(None)

    class Settings:
        name = "routes"
        keep_nulls = True
