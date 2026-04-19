"""Tests for GET /my/user-stats (surface-level userStats for the mobile client)."""

from __future__ import annotations

import pytest
import pytest_asyncio
from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from mongomock_motor import AsyncMongoMockClient

from app.models.user_stats import (
    ActivityCounters,
    RoutesCreatedCounters,
    UserStats,
)
from app.routers.my import UserStatsResponse, _build_user_stats_response


pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient()
    db = client.get_database("besetter-test")
    await init_beanie(database=db, document_models=[UserStats])
    yield db


def test_user_stats_response_schema_camelcase():
    resp = UserStatsResponse(
        activity=ActivityCounters(total_count=5, completed_count=3, verified_completed_count=1),
        distinct_routes=ActivityCounters(total_count=4, completed_count=2, verified_completed_count=1),
        distinct_days=7,
        own_routes_activity=ActivityCounters(total_count=2, completed_count=1, verified_completed_count=1),
        routes_created=RoutesCreatedCounters(total_count=3, bouldering_count=2, endurance_count=1),
    )
    dumped = resp.model_dump(by_alias=True)

    assert dumped["activity"]["totalCount"] == 5
    assert dumped["activity"]["completedCount"] == 3
    assert dumped["activity"]["verifiedCompletedCount"] == 1
    assert dumped["distinctRoutes"]["totalCount"] == 4
    assert dumped["distinctDays"] == 7
    assert dumped["ownRoutesActivity"]["completedCount"] == 1
    assert dumped["routesCreated"]["boulderingCount"] == 2
    assert dumped["routesCreated"]["enduranceCount"] == 1


def test_user_stats_response_default_is_zero():
    resp = UserStatsResponse()
    dumped = resp.model_dump(by_alias=True)
    assert dumped["activity"]["totalCount"] == 0
    assert dumped["distinctDays"] == 0
    assert dumped["routesCreated"]["totalCount"] == 0


async def test_build_user_stats_response_returns_zeros_when_missing(mongo_db):
    resp = await _build_user_stats_response(PydanticObjectId())
    assert isinstance(resp, UserStatsResponse)
    assert resp.distinct_days == 0
    assert resp.activity.total_count == 0
    assert resp.routes_created.total_count == 0


async def test_build_user_stats_response_reads_persisted_doc(mongo_db):
    user_id = PydanticObjectId()
    await UserStats(
        user_id=user_id,
        activity=ActivityCounters(total_count=10, completed_count=7, verified_completed_count=3),
        distinct_routes=ActivityCounters(total_count=6, completed_count=4, verified_completed_count=2),
        distinct_days=12,
        own_routes_activity=ActivityCounters(total_count=3, completed_count=2, verified_completed_count=1),
        routes_created=RoutesCreatedCounters(total_count=5, bouldering_count=4, endurance_count=1),
    ).insert()

    resp = await _build_user_stats_response(user_id)

    assert resp.activity.total_count == 10
    assert resp.distinct_routes.completed_count == 4
    assert resp.distinct_days == 12
    assert resp.own_routes_activity.completed_count == 2
    assert resp.routes_created.bouldering_count == 4
    assert resp.routes_created.endurance_count == 1
