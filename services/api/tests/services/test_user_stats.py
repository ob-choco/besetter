"""Tests for the UserStats model and user_stats service."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz

import pytest
from beanie.odm.fields import PydanticObjectId

from app.models.activity import Activity, ActivityStatus, RouteSnapshot
from app.models.user_stats import UserStats
from app.services.user_stats import _bucket_deltas, _local_date_str


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
    return Activity(
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


async def test_local_date_str_with_seoul_timezone_crosses_utc_midnight(mongo_db):
    # 2026-04-18T15:30Z == 2026-04-19 00:30 KST → "2026-04-19"
    started = datetime(2026, 4, 18, 15, 30, tzinfo=dt_tz.utc)
    activity = _make_activity(started, "Asia/Seoul")
    assert _local_date_str(activity) == "2026-04-19"


async def test_local_date_str_with_utc_explicit(mongo_db):
    started = datetime(2026, 4, 19, 10, 0, tzinfo=dt_tz.utc)
    activity = _make_activity(started, "UTC")
    assert _local_date_str(activity) == "2026-04-19"


async def test_local_date_str_with_none_falls_back_to_utc(mongo_db):
    started = datetime(2026, 4, 19, 10, 0, tzinfo=dt_tz.utc)
    activity = _make_activity(started, None)
    assert _local_date_str(activity) == "2026-04-19"
