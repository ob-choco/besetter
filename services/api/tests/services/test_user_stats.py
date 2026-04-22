"""Tests for the UserStats model and user_stats service."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz
from unittest.mock import AsyncMock, patch

import pytest
from beanie.odm.fields import PydanticObjectId

from app.models.activity import Activity, ActivityStatus, RouteSnapshot, UserRouteStats
from app.models.route import Route, RouteType, Visibility
from app.models.user_stats import UserStats
from app.services.user_stats import (
    _apply_user_route_stats_delta,
    _bucket_deltas,
    _day_utc_superset,
    _local_date_str,
    _recount_local_day,
    on_activity_created,
    on_activity_deleted,
    on_route_created,
    on_route_soft_deleted,
)


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


def test_day_utc_superset_pads_plus_minus_14_hours():
    lo, hi = _day_utc_superset("2026-04-19")
    assert lo == datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)
    assert hi == datetime(2026, 4, 20, 14, 0, tzinfo=dt_tz.utc)


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
async def test_apply_urs_delta_sets_last_activity_at_on_insert(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    t = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)

    await _apply_user_route_stats_delta(
        user_id,
        route_id,
        {"total_count": 1, "completed_count": 0, "verified_completed_count": 0},
        last_activity_at=t,
    )

    doc = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    )
    assert doc is not None
    assert doc.last_activity_at == t


@pytest.mark.asyncio
async def test_apply_urs_delta_max_does_not_regress(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    newer = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    older = datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)

    await _apply_user_route_stats_delta(
        user_id, route_id,
        {"total_count": 1, "completed_count": 0, "verified_completed_count": 0},
        last_activity_at=newer,
    )
    await _apply_user_route_stats_delta(
        user_id, route_id,
        {"total_count": 1, "completed_count": 0, "verified_completed_count": 0},
        last_activity_at=older,
    )

    doc = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    )
    assert doc.last_activity_at == newer


@pytest.mark.asyncio
async def test_apply_urs_delta_no_last_activity_at_leaves_field_untouched(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    t = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)

    await _apply_user_route_stats_delta(
        user_id, route_id,
        {"total_count": 1, "completed_count": 0, "verified_completed_count": 0},
        last_activity_at=t,
    )
    await _apply_user_route_stats_delta(
        user_id, route_id,
        {"total_count": 1, "completed_count": 0, "verified_completed_count": 0},
        last_activity_at=None,
    )

    doc = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route_id,
    )
    assert doc.last_activity_at == t
    assert doc.total_count == 2


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


@pytest.mark.skip(reason="mongomock does not implement $dateToString timezone — covered by real-Mongo integration")
@pytest.mark.asyncio
async def test_recount_local_day_counts_same_user_same_date(mongo_db):
    user_id = PydanticObjectId()
    route_id = PydanticObjectId()
    snap = RouteSnapshot(grade_type="v_scale", grade="V1")

    # Two activities on 2026-04-19 KST
    await Activity(
        route_id=route_id,
        user_id=user_id,
        status=ActivityStatus.COMPLETED,
        location_verified=True,
        started_at=datetime(2026, 4, 18, 15, 30, tzinfo=dt_tz.utc),
        ended_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
        duration=1800.0,
        timezone="Asia/Seoul",
        route_snapshot=snap,
        created_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
    ).insert()
    await Activity(
        route_id=route_id,
        user_id=user_id,
        status=ActivityStatus.ATTEMPTED,
        location_verified=False,
        started_at=datetime(2026, 4, 18, 20, 0, tzinfo=dt_tz.utc),  # 2026-04-19 05:00 KST
        ended_at=datetime(2026, 4, 18, 20, 30, tzinfo=dt_tz.utc),
        duration=1800.0,
        timezone="Asia/Seoul",
        route_snapshot=snap,
        created_at=datetime(2026, 4, 18, 20, 30, tzinfo=dt_tz.utc),
    ).insert()

    assert await _recount_local_day(user_id, "2026-04-19") == 2
    assert await _recount_local_day(user_id, "2026-04-18") == 0


@pytest.mark.asyncio
async def test_recount_local_day_ignores_other_users(mongo_db):
    user_id = PydanticObjectId()
    other_id = PydanticObjectId()
    snap = RouteSnapshot(grade_type="v_scale", grade="V1")
    started = datetime(2026, 4, 19, 1, 0, tzinfo=dt_tz.utc)
    await Activity(
        route_id=PydanticObjectId(),
        user_id=other_id,
        status=ActivityStatus.COMPLETED,
        location_verified=True,
        started_at=started,
        ended_at=started,
        duration=0.0,
        timezone="UTC",
        route_snapshot=snap,
        created_at=started,
    ).insert()

    assert await _recount_local_day(user_id, "2026-04-19") == 0


@pytest.mark.skip(reason="mongomock does not implement $dateToString timezone — covered by real-Mongo integration")
@pytest.mark.asyncio
async def test_recount_local_day_falls_back_to_utc_when_timezone_null(mongo_db):
    user_id = PydanticObjectId()
    snap = RouteSnapshot(grade_type="v_scale", grade="V1")
    started = datetime(2026, 4, 19, 23, 0, tzinfo=dt_tz.utc)  # still 2026-04-19 in UTC
    await Activity(
        route_id=PydanticObjectId(),
        user_id=user_id,
        status=ActivityStatus.COMPLETED,
        location_verified=True,
        started_at=started,
        ended_at=started,
        duration=0.0,
        timezone=None,
        route_snapshot=snap,
        created_at=started,
    ).insert()

    assert await _recount_local_day(user_id, "2026-04-19") == 1


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


async def _insert_activity(
    user_id: PydanticObjectId,
    route_id: PydanticObjectId,
    *,
    status: ActivityStatus = ActivityStatus.COMPLETED,
    location_verified: bool = True,
    started_at: datetime | None = None,
    tz: str = "Asia/Seoul",
) -> Activity:
    started = started_at or datetime(2026, 4, 18, 15, 30, tzinfo=dt_tz.utc)
    activity = Activity(
        route_id=route_id,
        user_id=user_id,
        status=status,
        location_verified=location_verified,
        started_at=started,
        ended_at=started,
        duration=0.0,
        timezone=tz,
        route_snapshot=RouteSnapshot(grade_type="v_scale", grade="V1"),
        created_at=started,
    )
    await activity.insert()
    return activity


@pytest.mark.asyncio
async def test_on_activity_created_first_activity(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(return_value=1))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())  # someone else's route
    await route.insert()

    activity = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(activity, route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats is not None
    assert stats.activity.total_count == 1
    assert stats.activity.completed_count == 1
    assert stats.activity.verified_completed_count == 1
    assert stats.distinct_routes.total_count == 1
    assert stats.distinct_routes.completed_count == 1
    assert stats.distinct_routes.verified_completed_count == 1
    assert stats.distinct_days == 1
    assert stats.own_routes_activity.total_count == 0  # not user's own route


@pytest.mark.asyncio
async def test_on_activity_created_second_activity_same_route_same_day(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    a1 = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(
        user_id, route.id, status=ActivityStatus.ATTEMPTED, location_verified=False,
        started_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
    )
    await on_activity_created(a2, route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.activity.total_count == 2
    assert stats.activity.completed_count == 1
    assert stats.activity.verified_completed_count == 1
    assert stats.distinct_routes.total_count == 1  # still same route
    assert stats.distinct_days == 1  # still same day


@pytest.mark.asyncio
async def test_on_activity_created_on_own_alive_route_increments_own_routes_activity(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(return_value=1))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id)
    await route.insert()

    activity = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(activity, route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.own_routes_activity.total_count == 1
    assert stats.own_routes_activity.completed_count == 1
    assert stats.own_routes_activity.verified_completed_count == 1


@pytest.mark.asyncio
async def test_on_activity_created_on_own_soft_deleted_route_skips_own_routes_activity(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(return_value=1))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, is_deleted=True)
    await route.insert()

    activity = await _insert_activity(user_id, route.id)
    await on_activity_created(activity, route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.own_routes_activity.total_count == 0
    assert stats.activity.total_count == 1
    assert stats.distinct_routes.total_count == 1


@pytest.mark.asyncio
async def test_on_activity_deleted_sole_activity_clears_stats(mongo_db, monkeypatch):
    # on_activity_created calls _recount (returns 1 → distinctDays += 1)
    # on_activity_deleted calls _recount (returns 1 because activity still in DB; effective=0 → distinctDays -= 1)
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 1]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    activity = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(activity, route)

    await on_activity_deleted(activity, route)
    await activity.delete()

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.activity.total_count == 0
    assert stats.distinct_routes.total_count == 0
    assert stats.distinct_days == 0

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is None


@pytest.mark.asyncio
async def test_on_activity_deleted_leaves_distinct_days_when_sibling_remains(mongo_db, monkeypatch):
    # Call sequence:
    # 1. on_activity_created(a1) → _recount → 1 (distinctDays += 1)
    # 2. on_activity_created(a2) → _recount → 2 (no change)
    # 3. on_activity_deleted(a2) → _recount → 2 (a2 still in DB); effective=1 → NO change
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2, 2]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    a1 = await _insert_activity(user_id, route.id)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(
        user_id, route.id, started_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
    )
    await on_activity_created(a2, route)

    await on_activity_deleted(a2, route)
    await a2.delete()

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.distinct_days == 1
    assert stats.distinct_routes.total_count == 1


@pytest.mark.asyncio
async def test_on_activity_deleted_skips_own_routes_activity_when_route_soft_deleted(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 1]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id)
    await route.insert()

    activity = await _insert_activity(user_id, route.id)
    await on_activity_created(activity, route)

    # Simulate a soft-delete that already decremented own_routes_activity.
    await UserStats.find_one(UserStats.user_id == user_id).update(
        {"$inc": {"ownRoutesActivity.totalCount": -1, "ownRoutesActivity.completedCount": -1, "ownRoutesActivity.verifiedCompletedCount": -1}}
    )
    route.is_deleted = True

    await on_activity_deleted(activity, route)
    await activity.delete()

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.own_routes_activity.total_count == 0
    assert stats.own_routes_activity.completed_count == 0
    assert stats.own_routes_activity.verified_completed_count == 0


@pytest.mark.asyncio
async def test_on_route_created_bouldering(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, type_=RouteType.BOULDERING)
    await route.insert()

    await on_route_created(route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.routes_created.total_count == 1
    assert stats.routes_created.bouldering_count == 1
    assert stats.routes_created.endurance_count == 0


@pytest.mark.asyncio
async def test_on_route_created_endurance(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, type_=RouteType.ENDURANCE)
    await route.insert()

    await on_route_created(route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.routes_created.total_count == 1
    assert stats.routes_created.bouldering_count == 0
    assert stats.routes_created.endurance_count == 1


@pytest.mark.asyncio
async def test_on_route_soft_deleted_decrements_routes_created(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, type_=RouteType.BOULDERING)
    await route.insert()
    await on_route_created(route)

    route.is_deleted = True
    await on_route_soft_deleted(route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.routes_created.total_count == 0
    assert stats.routes_created.bouldering_count == 0


@pytest.mark.asyncio
async def test_on_activity_deleted_decrements_route_completer_stats(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 1]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    activity = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(activity, route)

    await on_activity_deleted(activity, route)
    await activity.delete()

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 0
    assert refreshed.completer_stats.completer_count == 0
    assert refreshed.completer_stats.verified_completer_count == 0


@pytest.mark.asyncio
async def test_on_activity_deleted_leaves_route_counters_when_user_still_has_other_activity(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2, 2]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    a1 = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(
        user_id, route.id,
        status=ActivityStatus.COMPLETED, location_verified=True,
        started_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
    )
    await on_activity_created(a2, route)

    await on_activity_deleted(a2, route)
    await a2.delete()

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 1
    assert refreshed.completer_stats.completer_count == 1
    assert refreshed.completer_stats.verified_completer_count == 1


@pytest.mark.asyncio
async def test_on_route_soft_deleted_decrements_own_routes_activity_per_bucket(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(return_value=1))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, type_=RouteType.BOULDERING)
    await route.insert()
    await on_route_created(route)

    a = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(a, route)

    route.is_deleted = True
    await on_route_soft_deleted(route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.own_routes_activity.total_count == 0
    assert stats.own_routes_activity.completed_count == 0
    assert stats.own_routes_activity.verified_completed_count == 0
    assert stats.routes_created.total_count == 0
    assert stats.distinct_routes.total_count == 1
    assert stats.activity.total_count == 1


@pytest.mark.asyncio
async def test_on_route_soft_deleted_no_own_activity_leaves_own_routes_activity_untouched(mongo_db):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, type_=RouteType.ENDURANCE)
    await route.insert()
    await on_route_created(route)

    route.is_deleted = True
    await on_route_soft_deleted(route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.own_routes_activity.total_count == 0
    assert stats.routes_created.total_count == 0
    assert stats.routes_created.endurance_count == 0


@pytest.mark.asyncio
async def test_on_route_soft_deleted_only_decrements_buckets_ge_one(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(return_value=1))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id, type_=RouteType.BOULDERING)
    await route.insert()
    await on_route_created(route)

    a = await _insert_activity(user_id, route.id, status=ActivityStatus.ATTEMPTED, location_verified=False)
    await on_activity_created(a, route)

    route.is_deleted = True
    await on_route_soft_deleted(route)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    assert stats.own_routes_activity.total_count == 0
    assert stats.own_routes_activity.completed_count == 0
    assert stats.own_routes_activity.verified_completed_count == 0


@pytest.mark.asyncio
async def test_on_activity_created_swallows_inner_errors(mongo_db, caplog):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id)
    await route.insert()
    activity = await _insert_activity(user_id, route.id)

    with patch(
        "app.services.user_stats._apply_user_route_stats_delta",
        side_effect=RuntimeError("boom"),
    ):
        caplog.clear()
        result = await on_activity_created(activity, route)

    assert result is None
    assert any("on_activity_created failed" in rec.message for rec in caplog.records)

    stats = await UserStats.find_one(UserStats.user_id == user_id)
    # No partial write: we bailed before any userStats write.
    assert stats is None


@pytest.mark.asyncio
async def test_on_route_created_swallows_inner_errors(mongo_db, caplog):
    user_id = PydanticObjectId()
    route = _make_route(owner_id=user_id)

    with patch(
        "app.services.user_stats._update_user_stats",
        side_effect=RuntimeError("boom"),
    ):
        caplog.clear()
        result = await on_route_created(route)

    assert result is None
    assert any("on_route_created failed" in rec.message for rec in caplog.records)


@pytest.mark.asyncio
async def test_on_activity_created_sets_last_activity_at(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(return_value=1))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    started = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    activity = await _insert_activity(user_id, route.id, started_at=started)
    await on_activity_created(activity, route)

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is not None
    assert urs.last_activity_at == started


@pytest.mark.asyncio
async def test_on_activity_created_later_activity_advances_last_activity_at(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    earlier = datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)
    later = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    a1 = await _insert_activity(user_id, route.id, started_at=earlier)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(user_id, route.id, started_at=later)
    await on_activity_created(a2, route)

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs.last_activity_at == later


@pytest.mark.asyncio
async def test_on_activity_created_out_of_order_does_not_regress(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    earlier = datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)
    later = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    a_late = await _insert_activity(user_id, route.id, started_at=later)
    await on_activity_created(a_late, route)
    a_early = await _insert_activity(user_id, route.id, started_at=earlier)
    await on_activity_created(a_early, route)

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs.last_activity_at == later


@pytest.mark.asyncio
async def test_on_activity_deleted_recomputes_last_activity_at_when_matches(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2, 1]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    earlier = datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)
    later = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    a1 = await _insert_activity(user_id, route.id, started_at=earlier)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(user_id, route.id, started_at=later)
    await on_activity_created(a2, route)

    # Hook runs BEFORE delete (the activities.py path).
    await on_activity_deleted(a2, route)
    await a2.delete()

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is not None
    assert urs.last_activity_at == earlier


@pytest.mark.asyncio
async def test_on_activity_deleted_skips_recompute_when_deleted_not_latest(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2, 2]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    earlier = datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)
    later = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    a1 = await _insert_activity(user_id, route.id, started_at=earlier)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(user_id, route.id, started_at=later)
    await on_activity_created(a2, route)

    # Delete the earlier activity; lastActivityAt should stay at `later`.
    await on_activity_deleted(a1, route)
    await a1.delete()

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is not None
    assert urs.last_activity_at == later


@pytest.mark.asyncio
async def test_on_activity_deleted_after_delete_recomputes_correctly(mongo_db, monkeypatch):
    # The routers/my.py path deletes activities BEFORE calling the hook (still_present=False).
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2, 1]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    earlier = datetime(2026, 4, 18, 10, 0, tzinfo=dt_tz.utc)
    later = datetime(2026, 4, 18, 12, 0, tzinfo=dt_tz.utc)
    a1 = await _insert_activity(user_id, route.id, started_at=earlier)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(user_id, route.id, started_at=later)
    await on_activity_created(a2, route)

    # Delete first, then hook.
    await a2.delete()
    await on_activity_deleted(a2, route)

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is not None
    assert urs.last_activity_at == earlier


@pytest.mark.asyncio
async def test_on_activity_deleted_sole_activity_still_deletes_urs_doc(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 1]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    activity = await _insert_activity(
        user_id, route.id,
        status=ActivityStatus.COMPLETED, location_verified=True,
    )
    await on_activity_created(activity, route)

    await on_activity_deleted(activity, route)
    await activity.delete()

    urs = await UserRouteStats.find_one(
        UserRouteStats.user_id == user_id,
        UserRouteStats.route_id == route.id,
    )
    assert urs is None


@pytest.mark.asyncio
async def test_route_completer_stats_roundtrip(mongo_db):
    from app.models.route import CompleterStats

    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    assert route.completer_stats.participant_count == 0
    assert route.completer_stats.completer_count == 0
    assert route.completer_stats.verified_completer_count == 0

    await Route.get_pymongo_collection().update_one(
        {"_id": route.id},
        {"$inc": {
            "completerStats.participantCount": 3,
            "completerStats.completerCount": 2,
            "completerStats.verifiedCompleterCount": 1,
        }},
    )

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 3
    assert refreshed.completer_stats.completer_count == 2
    assert refreshed.completer_stats.verified_completer_count == 1


@pytest.mark.asyncio
async def test_on_activity_created_increments_route_completer_stats_on_first_verified(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(return_value=1))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    activity = await _insert_activity(
        user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True
    )
    await on_activity_created(activity, route)

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 1
    assert refreshed.completer_stats.completer_count == 1
    assert refreshed.completer_stats.verified_completer_count == 1


@pytest.mark.asyncio
async def test_on_activity_created_second_activity_same_user_does_not_reincrement_route_counters(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(side_effect=[1, 2]))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    a1 = await _insert_activity(user_id, route.id, status=ActivityStatus.COMPLETED, location_verified=True)
    await on_activity_created(a1, route)
    a2 = await _insert_activity(
        user_id, route.id,
        status=ActivityStatus.COMPLETED, location_verified=True,
        started_at=datetime(2026, 4, 18, 16, 0, tzinfo=dt_tz.utc),
    )
    await on_activity_created(a2, route)

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 1
    assert refreshed.completer_stats.completer_count == 1
    assert refreshed.completer_stats.verified_completer_count == 1


@pytest.mark.asyncio
async def test_on_activity_created_attempted_only_increments_participant(mongo_db, monkeypatch):
    monkeypatch.setattr("app.services.user_stats._recount_local_day", AsyncMock(return_value=1))
    user_id = PydanticObjectId()
    route = _make_route(owner_id=PydanticObjectId())
    await route.insert()

    activity = await _insert_activity(
        user_id, route.id, status=ActivityStatus.ATTEMPTED, location_verified=False
    )
    await on_activity_created(activity, route)

    refreshed = await Route.find_one(Route.id == route.id)
    assert refreshed.completer_stats.participant_count == 1
    assert refreshed.completer_stats.completer_count == 0
    assert refreshed.completer_stats.verified_completer_count == 0
