"""Tests for scripts/backfill_route_completer_stats.py."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz

import pytest
import pytest_asyncio
from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from mongomock_motor import AsyncMongoMockClient

from app.models.activity import UserRouteStats
from app.models.route import Route, RouteType, Visibility
from app.models.user import User
from scripts.backfill_route_completer_stats import backfill_route


pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient(tz_aware=True)
    db = client.get_database("besetter-test")
    await init_beanie(
        database=db,
        document_models=[User, Route, UserRouteStats],
    )
    yield db


def _new_route(owner_id: PydanticObjectId) -> Route:
    return Route(
        type=RouteType.BOULDERING,
        grade_type="v_scale", grade="V3",
        visibility=Visibility.PUBLIC,
        image_id=PydanticObjectId(),
        hold_polygon_id=PydanticObjectId(),
        user_id=owner_id,
        image_url="https://example.com/x.jpg",
    )


async def test_backfill_computes_distinct_user_counts(mongo_db):
    owner_id = PydanticObjectId()
    route = _new_route(owner_id)
    await route.insert()

    for total, completed, verified in [
        (5, 5, 5),
        (3, 2, 0),
        (1, 0, 0),
    ]:
        await UserRouteStats(
            user_id=PydanticObjectId(),
            route_id=route.id,
            total_count=total,
            completed_count=completed,
            verified_completed_count=verified,
            last_activity_at=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
        ).insert()

    await backfill_route(route.id)

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 3
    assert refreshed.completer_stats.completer_count == 2
    assert refreshed.completer_stats.verified_completer_count == 1


async def test_backfill_is_idempotent(mongo_db):
    owner_id = PydanticObjectId()
    route = _new_route(owner_id)
    await route.insert()

    await UserRouteStats(
        user_id=PydanticObjectId(), route_id=route.id,
        total_count=1, completed_count=1, verified_completed_count=1,
        last_activity_at=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    ).insert()

    await backfill_route(route.id)
    await backfill_route(route.id)

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 1
    assert refreshed.completer_stats.completer_count == 1
    assert refreshed.completer_stats.verified_completer_count == 1


async def test_backfill_zeroes_when_no_user_route_stats(mongo_db):
    owner_id = PydanticObjectId()
    route = _new_route(owner_id)
    route.completer_stats.verified_completer_count = 7
    await route.insert()

    await backfill_route(route.id)

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 0
    assert refreshed.completer_stats.completer_count == 0
    assert refreshed.completer_stats.verified_completer_count == 0
