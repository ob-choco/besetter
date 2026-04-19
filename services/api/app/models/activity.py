from datetime import datetime
from enum import Enum
from typing import Optional

from beanie import Document
from beanie.odm.fields import PydanticObjectId
from pydantic import BaseModel, Field
from pymongo import ASCENDING, DESCENDING, IndexModel

from . import model_config


class ActivityStatus(str, Enum):
    COMPLETED = "completed"
    ATTEMPTED = "attempted"


class RouteSnapshot(BaseModel):
    model_config = model_config

    title: Optional[str] = None
    grade_type: str
    grade: str
    grade_color: Optional[str] = None
    place_id: Optional[PydanticObjectId] = None
    place_name: Optional[str] = None
    image_url: Optional[str] = None
    overlay_image_url: Optional[str] = None


class ActivityStats(BaseModel):
    model_config = model_config

    total_count: int = 0
    total_duration: float = 0
    completed_count: int = 0
    completed_duration: float = 0
    verified_completed_count: int = 0
    verified_completed_duration: float = 0


class Activity(Document):
    model_config = model_config

    route_id: PydanticObjectId
    user_id: PydanticObjectId
    status: ActivityStatus
    location_verified: bool = False
    started_at: datetime
    ended_at: datetime
    duration: float
    timezone: Optional[str] = None  # IANA timezone, e.g. "Asia/Seoul"
    route_snapshot: RouteSnapshot
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Settings:
        name = "activities"
        indexes = [
            IndexModel([("userId", ASCENDING), ("startedAt", ASCENDING)]),
            IndexModel([("routeId", ASCENDING), ("userId", ASCENDING), ("startedAt", ASCENDING)]),
        ]
        keep_nulls = True


class UserRouteStats(Document):
    model_config = model_config

    user_id: PydanticObjectId
    route_id: PydanticObjectId
    total_count: int = 0
    total_duration: float = 0
    completed_count: int = 0
    completed_duration: float = 0
    verified_completed_count: int = 0
    verified_completed_duration: float = 0
    last_activity_at: Optional[datetime] = None

    class Settings:
        name = "userRouteStats"
        indexes = [
            IndexModel(
                [("userId", ASCENDING), ("routeId", ASCENDING)],
                unique=True,
            ),
            IndexModel(
                [("userId", ASCENDING), ("lastActivityAt", DESCENDING)],
                name="userId_1_lastActivityAt_-1",
            ),
        ]
        keep_nulls = True
