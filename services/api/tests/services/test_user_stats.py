"""Tests for the UserStats model and user_stats service."""

from __future__ import annotations

import pytest
from beanie.odm.fields import PydanticObjectId

from app.models.user_stats import UserStats


@pytest.mark.asyncio
async def test_user_stats_roundtrip(mongo_db):
    user_id = PydanticObjectId()
    doc = UserStats(user_id=user_id)
    await doc.insert()

    fetched = await UserStats.find_one(UserStats.user_id == user_id)
    assert fetched is not None
    assert fetched.user_id == user_id
    assert fetched.activity.total_count == 0
    assert fetched.distinct_routes.completed_count == 0
    assert fetched.distinct_days == 0
    assert fetched.own_routes_activity.verified_completed_count == 0
    assert fetched.routes_created.total_count == 0
    assert fetched.routes_created.bouldering_count == 0
    assert fetched.routes_created.endurance_count == 0
