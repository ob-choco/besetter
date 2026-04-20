from datetime import datetime
from typing import Optional

from beanie import Document
from beanie.odm.fields import PydanticObjectId
from pydantic import Field
from pymongo import ASCENDING, IndexModel

from . import model_config


class DeviceToken(Document):
    model_config = model_config

    user_id: PydanticObjectId = Field(..., description="토큰 소유자")
    token: str = Field(..., description="FCM 레지스트레이션 토큰")
    platform: str = Field(..., description="'ios' | 'android'")
    app_version: Optional[str] = Field(None, description="앱 버전")
    locale: Optional[str] = Field(None, description="기기 로케일 (예: 'ko-KR')")
    created_at: datetime = Field(..., description="최초 등록 시간")
    last_seen_at: datetime = Field(..., description="가장 최근에 본 시간")

    class Settings:
        name = "deviceTokens"
        indexes = [
            IndexModel([("token", ASCENDING)], unique=True),
            IndexModel([("userId", ASCENDING)]),
        ]
        keep_nulls = True
