from datetime import datetime
from typing import Optional
from beanie import Document
from pydantic import BaseModel

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

    name: Optional[str] = None
    email: Optional[str] = None
    profile_image_url: Optional[str] = None

    refresh_token: Optional[str] = None

    line: Optional[LineUser] = None
    kakao: Optional[KakaoUser] = None
    apple: Optional[AppleUser] = None
    google: Optional[GoogleUser] = None

    created_at: datetime
    updated_at: datetime

    class Settings:
        name = "users"
        keep_nulls = True
