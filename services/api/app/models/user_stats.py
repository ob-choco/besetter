from datetime import datetime
from typing import Optional

from beanie import Document
from beanie.odm.fields import PydanticObjectId
from pydantic import BaseModel, Field
from pymongo import ASCENDING, IndexModel

from . import model_config


class ActivityCounters(BaseModel):
    model_config = model_config

    total_count: int = 0
    completed_count: int = 0
    verified_completed_count: int = 0


class RoutesCreatedCounters(BaseModel):
    model_config = model_config

    total_count: int = 0
    bouldering_count: int = 0
    endurance_count: int = 0


class UserStats(Document):
    model_config = model_config

    user_id: PydanticObjectId
    activity: ActivityCounters = Field(default_factory=ActivityCounters)
    distinct_routes: ActivityCounters = Field(default_factory=ActivityCounters)
    distinct_days: int = 0
    own_routes_activity: ActivityCounters = Field(default_factory=ActivityCounters)
    routes_created: RoutesCreatedCounters = Field(default_factory=RoutesCreatedCounters)
    updated_at: Optional[datetime] = None

    class Settings:
        name = "userStats"
        indexes = [
            IndexModel([("userId", ASCENDING)], unique=True),
        ]
        keep_nulls = True
