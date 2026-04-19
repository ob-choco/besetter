"""Tests for the UserStats model and user_stats service."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz

import pytest
from beanie.odm.fields import PydanticObjectId

from app.models.activity import Activity, ActivityStatus, RouteSnapshot, UserRouteStats
from app.models.user_stats import UserStats
from app.services.user_stats import _apply_user_route_stats_delta, _bucket_deltas, _local_date_str


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


def test_bucket_deltas_attempted():
    assert _bucket_deltas(ActivityStatus.ATTEMPTED, location_verified=True, sign=1) == {
        "total_count": 1,
        "completed_count": 0,
        "verified_completed_count": 0,
    }


def test_bucket_deltas_completed_unverified():
    assert _bucket_deltas(ActivityStatus.COMPLETED, location_verified=False, sign=1) == {
        "total_count": 1,
        "completed_count": 1,
        "verified_completed_count": 0,
    }


def test_bucket_deltas_completed_verified():
    assert _bucket_deltas(ActivityStatus.COMPLETED, location_verified=True, sign=1) == {
        "total_count": 1,
        "completed_count": 1,
        "verified_completed_count": 1,
    }


def test_bucket_deltas_negative_sign():
    assert _bucket_deltas(ActivityStatus.COMPLETED, location_verified=True, sign=-1) == {
        "total_count": -1,
        "completed_count": -1,
        "verified_completed_count": -1,
    }


def _make_activity(started_at: datetime, tz: str | None) -> Activity:
    return Activity.model_construct(
        route_id=PydanticObjectId(),
        user_id=PydanticObjectId(),
        status=ActivityStatus.COMPLETED,
        location_verified=False,
        started_at=started_at,
        ended_at=started_at,
        duration=0.0,
        timezone=tz,
        route_snapshot=RouteSnapshot(grade_type="v_scale", grade="V1"),
        created_at=started_at,
    )


def test_local_date_str_with_seoul_timezone_crosses_utc_midnight():
    # 2026-04-18T15:30Z == 2026-04-19 00:30 KST → "2026-04-19"
    started = datetime(2026, 4, 18, 15, 30, tzinfo=dt_tz.utc)
    activity = _make_activity(started, "Asia/Seoul")
    assert _local_date_str(activity) == "2026-04-19"


def test_local_date_str_with_utc_explicit():
    started = datetime(2026, 4, 19, 10, 0, tzinfo=dt_tz.utc)
    activity = _make_activity(started, "UTC")
    assert _local_date_str(activity) == "2026-04-19"


def test_local_date_str_with_none_falls_back_to_utc():
    started = datetime(2026, 4, 19, 10, 0, tzinfo=dt_tz.utc)
    activity = _make_activity(started, None)
    assert _local_date_str(activity) == "2026-04-19"


def test_local_date_str_naive_started_at_treated_as_utc():
    # Naive datetime should be treated as UTC, not system-local time.
    started = datetime(2026, 4, 19, 10, 0)  # no tzinfo
    activity = _make_activity(started, "Asia/Seoul")
    # 10:00 UTC → 19:00 KST → "2026-04-19"
    assert _local_date_str(activity) == "2026-04-19"


@pytest.mark.asyncio
async def test_apply_urs_delta_inserts_first_time(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    deltas = {"total_count": 1, "completed_count": 1, "verified_completed_count": 0}

    before, after = await _apply_user_route_stats_delta(user_id, route_id, deltas)

    assert before == {"total_count": 0, "completed_count": 0, "verified_completed_count": 0}
    assert after == {"total_count": 1, "completed_count": 1, "verified_completed_count": 0}

    doc = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    )
    assert doc is not None
    assert doc.total_count == 1
    assert doc.completed_count == 1


@pytest.mark.asyncio
async def test_apply_urs_delta_increments_existing(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    deltas = {"total_count": 1, "completed_count": 0, "verified_completed_count": 0}

    await _apply_user_route_stats_delta(user_id, route_id, deltas)
    before, after = await _apply_user_route_stats_delta(user_id, route_id, deltas)

    assert before == {"total_count": 1, "completed_count": 0, "verified_completed_count": 0}
    assert after == {"total_count": 2, "completed_count": 0, "verified_completed_count": 0}


@pytest.mark.asyncio
async def test_apply_urs_delta_decrements_to_zero(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    await _apply_user_route_stats_delta(
        user_id, route_id, {"total_count": 1, "completed_count": 1, "verified_completed_count": 1}
    )

    before, after = await _apply_user_route_stats_delta(
        user_id, route_id, {"total_count": -1, "completed_count": -1, "verified_completed_count": -1}
    )

    assert before == {"total_count": 1, "completed_count": 1, "verified_completed_count": 1}
    assert after == {"total_count": 0, "completed_count": 0, "verified_completed_count": 0}


@pytest.mark.asyncio
async def test_apply_urs_delta_mixed_signs(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    await _apply_user_route_stats_delta(
        user_id, route_id, {"total_count": 1, "completed_count": 1, "verified_completed_count": 1}
    )

    before, after = await _apply_user_route_stats_delta(
        user_id, route_id, {"total_count": 0, "completed_count": -1, "verified_completed_count": -1}
    )

    assert before == {"total_count": 1, "completed_count": 1, "verified_completed_count": 1}
    assert after == {"total_count": 1, "completed_count": 0, "verified_completed_count": 0}


@pytest.mark.asyncio
async def test_apply_urs_delta_upsert_initializes_duration_fields(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    await _apply_user_route_stats_delta(
        user_id, route_id, {"total_count": 1, "completed_count": 0, "verified_completed_count": 0}
    )

    doc = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    )
    assert doc is not None
    assert doc.total_duration == 0
    assert doc.completed_duration == 0
    assert doc.verified_completed_duration == 0
    assert doc.last_activity_at is None
