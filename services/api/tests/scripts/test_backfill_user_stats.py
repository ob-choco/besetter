"""Tests for the user_stats backfill script."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz
from unittest.mock import AsyncMock

import pytest
from beanie.odm.fields import PydanticObjectId

from app.models.activity import Activity, ActivityStatus, RouteSnapshot, UserRouteStats
from app.models.route import Route, RouteType, Visibility
from app.models.user import User
from app.models.user_stats import UserStats
from scripts.backfill_user_stats import backfill_user


pytestmark = pytest.mark.asyncio


def _make_user() -> User:
    now = datetime(2026, 4, 18, tzinfo=dt_tz.utc)
    return User(
        profile_id=f"user_{PydanticObjectId()}",
        name="X",
        email="x@example.com",
        created_at=now,
        updated_at=now,
    )


def _make_route(owner_id: PydanticObjectId, type_: RouteType = RouteType.BOULDERING, is_deleted: bool = False) -> Route:
    return Route(
        type=type_,
        grade_type="v_scale",
        grade="V1",
        visibility=Visibility.PUBLIC,
        image_id=PydanticObjectId(),
        hold_polygon_id=PydanticObjectId(),
        user_id=owner_id,
        image_url="https://example.com/a.jpg",
        is_deleted=is_deleted,
    )


async def _seed_activity(
    user_id: PydanticObjectId,
    route_id: PydanticObjectId,
    *,
    status: ActivityStatus,
    location_verified: bool,
    started_at: datetime,
    tz: str = "Asia/Seoul",
) -> None:
    await Activity(
        route_id=route_id,
        user_id=user_id,
        status=status,
        location_verified=location_verified,
        started_at=started_at,
        ended_at=started_at,
        duration=0.0,
        timezone=tz,
        route_snapshot=RouteSnapshot(grade_type="v_scale", grade="V1"),
        created_at=started_at,
    ).insert()
    # Match the live path: keep UserRouteStats consistent for backfill counting.
    inc_total = 1
    inc_completed = 1 if status == ActivityStatus.COMPLETED else 0
    inc_verified = 1 if inc_completed and location_verified else 0
    await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    ).upsert(
        {"$inc": {"totalCount": inc_total, "completedCount": inc_completed, "verifiedCompletedCount": inc_verified}},
        on_insert=UserRouteStats(
            user_id=user_id,
            route_id=route_id,
            total_count=inc_total,
            completed_count=inc_completed,
            verified_completed_count=inc_verified,
        ),
    )


async def test_backfill_user_computes_all_counters(mongo_db, monkeypatch):
    user = _make_user()
    await user.insert()

    # Two routes: one alive boulder, one soft-deleted endurance. Both owned by user.
    own_boulder = _make_route(owner_id=user.id, type_=RouteType.BOULDERING)
    own_endurance_deleted = _make_route(owner_id=user.id, type_=RouteType.ENDURANCE, is_deleted=True)
    other_route = _make_route(owner_id=PydanticObjectId(), type_=RouteType.BOULDERING)
    await own_boulder.insert()
    await own_endurance_deleted.insert()
    await other_route.insert()

    # Activities:
    # - 1 completed+verified on own_boulder (day 2026-04-19 KST)
    # - 1 attempted on own_boulder (same day)
    # - 1 completed (no verify) on other_route (day 2026-04-20 KST)
    await _seed_activity(
        user.id, own_boulder.id, status=ActivityStatus.COMPLETED, location_verified=True,
        started_at=datetime(2026, 4, 18, 15, 0, tzinfo=dt_tz.utc),
    )
    await _seed_activity(
        user.id, own_boulder.id, status=ActivityStatus.ATTEMPTED, location_verified=False,
        started_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
    )
    await _seed_activity(
        user.id, other_route.id, status=ActivityStatus.COMPLETED, location_verified=False,
        started_at=datetime(2026, 4, 19, 15, 0, tzinfo=dt_tz.utc),
    )

    monkeypatch.setattr(
        "scripts.backfill_user_stats._distinct_days",
        AsyncMock(return_value=2),
    )
    await backfill_user(user.id)

    stats = await UserStats.find_one(UserStats.user_id == user.id)
    assert stats is not None
    assert stats.activity.total_count == 3
    assert stats.activity.completed_count == 2
    assert stats.activity.verified_completed_count == 1

    assert stats.distinct_routes.total_count == 2  # own_boulder + other_route
    assert stats.distinct_routes.completed_count == 2
    assert stats.distinct_routes.verified_completed_count == 1

    assert stats.distinct_days == 2

    # own_routes_activity scoped to currently-alive own routes.
    # own_boulder (alive) has completed+verified → all three buckets = 1.
    # own_endurance_deleted has no activity. other_route is not own.
    assert stats.own_routes_activity.total_count == 1
    assert stats.own_routes_activity.completed_count == 1
    assert stats.own_routes_activity.verified_completed_count == 1

    # routes_created: only alive routes counted.
    assert stats.routes_created.total_count == 1
    assert stats.routes_created.bouldering_count == 1
    assert stats.routes_created.endurance_count == 0


async def test_backfill_user_is_idempotent(mongo_db, monkeypatch):
    user = _make_user()
    await user.insert()
    route = _make_route(owner_id=user.id)
    await route.insert()
    await _seed_activity(
        user.id, route.id, status=ActivityStatus.COMPLETED, location_verified=True,
        started_at=datetime(2026, 4, 18, 15, 0, tzinfo=dt_tz.utc),
    )

    monkeypatch.setattr(
        "scripts.backfill_user_stats._distinct_days",
        AsyncMock(return_value=1),
    )
    await backfill_user(user.id)
    first = await UserStats.find_one(UserStats.user_id == user.id)
    await backfill_user(user.id)
    second = await UserStats.find_one(UserStats.user_id == user.id)

    assert first.model_dump(exclude={"updated_at", "id"}) == second.model_dump(exclude={"updated_at", "id"})
