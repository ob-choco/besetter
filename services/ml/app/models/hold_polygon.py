from typing import List, Optional, Tuple
from pydantic import BaseModel, Field


from . import model_config


class HoldPolygonData(BaseModel):
    model_config = model_config

    polygon_id: int = Field(..., description="폴리곤 고유 ID")
    points: List[Tuple[int, int]] = Field(
        ..., description="폴리곤을 구성하는 좌표점들 [(x, y), ...]"
    )
    type: str = Field(..., description="hold 또는 volume")  # hold, volume
    score: Optional[float] = Field(default=None, description="검출 신뢰도 점수")


class HoldPolygon(BaseModel):
    model_config = model_config

    polygons: List[HoldPolygonData] = Field(
        default_factory=list, description="이미지 내의 모든 폴리곤 데이터"
    )
