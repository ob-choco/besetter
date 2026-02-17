from typing import List, Optional
from pydantic import BaseModel, Field, HttpUrl

from datetime import datetime
from beanie import Document
from beanie.odm.fields import PydanticObjectId

from pymongo import IndexModel, ASCENDING
from . import model_config


class HoldPolygonData(BaseModel):
    model_config = model_config

    polygon_id: int = Field(..., description="폴리곤 고유 ID")
    points: List[tuple[int, int]] = Field(..., description="폴리곤을 구성하는 좌표점들 [(x, y), ...]")
    # approximated_points: List[tuple[int, int]] = Field(..., description="폴리곤을 근사하는 좌표점들 [(x, y), ...]")
    type: str = Field(..., description="hold 또는 volume")  # hold, volume, hold_feedback, volume_feedback
    score: Optional[float] = Field(default=None, description="검출 신뢰도 점수")

    feedback_status: Optional[str] = Field(default=None, description="피드백 상태 (pending, approved, rejected)")
    feedback_at: Optional[datetime] = Field(default=None, description="피드백이 처리된 시간")
    is_deleted: Optional[bool] = Field(default=None, description="삭제 여부")


class HoldPolygon(Document):
    model_config = model_config

    image_id: PydanticObjectId = Field(..., description="이미지 ID")
    user_id: PydanticObjectId = Field(..., description="이미지를 업로드한 사용자의 ID")
    image_url: HttpUrl = Field(..., description="이미지 URL (비정규화)")
    polygons: List[HoldPolygonData] = Field(default_factory=list, description="이미지 내의 모든 폴리곤 데이터")
    is_deleted: bool = Field(False, description="삭제 여부")
    deleted_at: Optional[datetime] = Field(None, description="삭제 일시")
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: Optional[datetime] = Field(None)

    # image에 있는 데이터를 동일하게 쓴다.
    gym_name: Optional[str] = Field(None, description="암장 이름")
    wall_name: Optional[str] = Field(None, description="벽 이름")
    wall_expiration_date: Optional[datetime] = Field(None, description="벽 만료 일자")

    class Settings:
        name = "holdPolygons"
        indexes = [IndexModel([("imageId", ASCENDING)])]
        keep_nulls = True