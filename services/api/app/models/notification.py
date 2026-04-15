from datetime import datetime
from typing import Optional

from beanie import Document
from beanie.odm.fields import PydanticObjectId
from pydantic import Field
from pymongo import ASCENDING, DESCENDING, IndexModel

from . import model_config


class Notification(Document):
    model_config = model_config

    user_id: PydanticObjectId = Field(..., description="알림 수신자")
    type: str = Field(..., description="알림 타입 (place_suggestion_ack 등)")
    title: str = Field(..., description="알림 제목")
    body: str = Field(..., description="알림 본문 (렌더 완료된 스냅샷)")
    link: Optional[str] = Field(None, description="연결 경로. 저장만 하고 동작은 없음")
    read_at: Optional[datetime] = Field(None, description="읽은 시간")
    created_at: datetime = Field(..., description="생성 시간")

    class Settings:
        name = "notifications"
        indexes = [
            IndexModel([("userId", ASCENDING), ("createdAt", DESCENDING)]),
        ]
        keep_nulls = True
