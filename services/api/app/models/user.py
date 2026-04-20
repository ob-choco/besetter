from datetime import datetime
from typing import Optional
from beanie import Document
from beanie.odm.fields import PydanticObjectId
from pydantic import BaseModel
from pymongo import ASCENDING, IndexModel

from . import model_config


class LineUser(BaseModel):
    model_config = model_config

    unique_id: str

    signed_up_at: datetime
    last_login_at: datetime
    last_logout_at: Optional[datetime] = None

    email: Optional[str] = None
    name: Optional[str] = None
    profile_image_url: Optional[str] = None


class KakaoUser(BaseModel):
    model_config = model_config

    unique_id: str

    signed_up_at: datetime
    last_login_at: datetime
    last_logout_at: Optional[datetime] = None

    email: Optional[str] = None
    name: Optional[str] = None
    profile_image_url: Optional[str] = None


class AppleUser(BaseModel):
    model_config = model_config

    unique_id: str

    signed_up_at: datetime
    last_login_at: datetime
    last_logout_at: Optional[datetime] = None

    email: Optional[str] = None


class GoogleUser(BaseModel):
    model_config = model_config

    unique_id: str

    signed_up_at: datetime
    last_login_at: datetime
    last_logout_at: Optional[datetime] = None

    email: Optional[str] = None
    name: Optional[str] = None
    profile_image_url: Optional[str] = None


class User(Document):
    model_config = model_config

    profile_id: str
    name: Optional[str] = None
    email: Optional[str] = None
    profile_image_url: Optional[str] = None
    bio: Optional[str] = None
    unread_notification_count: int = 0

    marketing_push_consent: bool = False
    marketing_push_consent_at: Optional[datetime] = None
    marketing_push_consent_source: Optional[str] = None  # 'signup' | 'settings' | 'reconfirm'

    refresh_token: Optional[str] = None

    line: Optional[LineUser] = None
    kakao: Optional[KakaoUser] = None
    apple: Optional[AppleUser] = None
    google: Optional[GoogleUser] = None

    is_deleted: bool = False
    deleted_at: Optional[datetime] = None

    created_at: datetime
    updated_at: datetime

    class Settings:
        name = "users"
        keep_nulls = True
        indexes = [
            IndexModel([("profileId", ASCENDING)], unique=True),
        ]


class OwnerView(BaseModel):
    """Public profile summary shown alongside a route or activity.

    ``profile_id`` and ``profile_image_url`` are null when ``is_deleted`` is
    True (user withdrew) — the mobile `OwnerBadge` falls back to a
    "탈퇴한 회원" label.
    """

    model_config = model_config

    user_id: PydanticObjectId
    profile_id: Optional[str] = None
    profile_image_url: Optional[str] = None
    is_deleted: bool = False
