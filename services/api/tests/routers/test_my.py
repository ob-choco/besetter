from datetime import datetime, timezone as tz, timedelta

from app.routers.my import (
    LastActivityDateResponse,
    MonthlySummaryResponse,
    DailyRoutesResponse,
    DailySummary,
    DailyRouteItem,
    _to_local_date_str,
    _month_utc_range,
    _day_utc_range,
    _day_utc_superset,
    _month_utc_superset,
    _merge_incs,
)
from app.models.activity import RouteSnapshot


def test_last_activity_date_response_schema():
    """LastActivityDateResponse should serialize with camelCase alias."""
    resp = LastActivityDateResponse(last_activity_date="2026-04-10")
    dumped = resp.model_dump(by_alias=True)
    assert dumped["lastActivityDate"] == "2026-04-10"


def test_last_activity_date_response_null():
    """LastActivityDateResponse should allow null."""
    resp = LastActivityDateResponse(last_activity_date=None)
    dumped = resp.model_dump(by_alias=True)
    assert dumped["lastActivityDate"] is None


def test_to_local_date_str_kst():
    """UTC datetime should convert to KST date string."""
    # 2026-04-10 15:30 UTC = 2026-04-11 00:30 KST
    utc_dt = datetime(2026, 4, 10, 15, 30, 0, tzinfo=tz.utc)
    result = _to_local_date_str(utc_dt, "Asia/Seoul")
    assert result == "2026-04-11"


def test_to_local_date_str_same_day():
    """UTC datetime in the middle of day should stay same day in KST."""
    # 2026-04-10 05:00 UTC = 2026-04-10 14:00 KST
    utc_dt = datetime(2026, 4, 10, 5, 0, 0, tzinfo=tz.utc)
    result = _to_local_date_str(utc_dt, "Asia/Seoul")
    assert result == "2026-04-10"


def test_month_utc_range_kst():
    """Month range for April 2026 in KST should start at Mar 31 15:00 UTC."""
    start, end = _month_utc_range(2026, 4, "Asia/Seoul")
    # April 1 00:00 KST = March 31 15:00 UTC
    assert start == datetime(2026, 3, 31, 15, 0, 0, tzinfo=tz.utc)
    # May 1 00:00 KST = April 30 15:00 UTC
    assert end == datetime(2026, 4, 30, 15, 0, 0, tzinfo=tz.utc)


def test_day_utc_range_kst():
    """Day range for 2026-04-10 in KST."""
    start, end = _day_utc_range("2026-04-10", "Asia/Seoul")
    # April 10 00:00 KST = April 9 15:00 UTC
    assert start == datetime(2026, 4, 9, 15, 0, 0, tzinfo=tz.utc)
    # April 11 00:00 KST = April 10 15:00 UTC
    assert end == datetime(2026, 4, 10, 15, 0, 0, tzinfo=tz.utc)


def test_day_utc_range_end_of_month():
    """Day range for last day of month should work correctly."""
    start, end = _day_utc_range("2026-04-30", "Asia/Seoul")
    # April 30 00:00 KST = April 29 15:00 UTC
    assert start == datetime(2026, 4, 29, 15, 0, 0, tzinfo=tz.utc)
    # May 1 00:00 KST = April 30 15:00 UTC
    assert end == datetime(2026, 4, 30, 15, 0, 0, tzinfo=tz.utc)


def test_day_utc_range_feb_28():
    """Day range for Feb 28 in non-leap year."""
    start, end = _day_utc_range("2027-02-28", "Asia/Seoul")
    assert start == datetime(2027, 2, 27, 15, 0, 0, tzinfo=tz.utc)
    # March 1 00:00 KST = Feb 28 15:00 UTC
    assert end == datetime(2027, 2, 28, 15, 0, 0, tzinfo=tz.utc)


def test_monthly_summary_response_schema():
    """MonthlySummaryResponse should serialize with camelCase alias."""
    resp = MonthlySummaryResponse(active_dates=[1, 5, 9, 12])
    dumped = resp.model_dump(by_alias=True)
    assert dumped["activeDates"] == [1, 5, 9, 12]


def test_monthly_summary_response_empty():
    """MonthlySummaryResponse should handle empty list."""
    resp = MonthlySummaryResponse(active_dates=[])
    dumped = resp.model_dump(by_alias=True)
    assert dumped["activeDates"] == []


def test_daily_routes_response_schema():
    """DailyRoutesResponse should serialize with camelCase aliases."""
    snapshot = RouteSnapshot(
        title="Morning Light",
        grade_type="v_grade",
        grade="V4",
        grade_color="#4CAF50",
        place_name="Urban Apex Gym",
    )
    from beanie.odm.fields import PydanticObjectId
    from app.models.user import OwnerView

    route_item = DailyRouteItem(
        route_id="507f1f77bcf86cd799439011",
        route_snapshot=snapshot,
        route_visibility="public",
        is_deleted=False,
        total_count=3,
        completed_count=2,
        attempted_count=1,
        total_duration=845.50,
        owner=OwnerView(user_id=PydanticObjectId(), is_deleted=True),
    )
    summary = DailySummary(
        total_count=3,
        completed_count=2,
        attempted_count=1,
        total_duration=845.50,
        route_count=1,
    )
    resp = DailyRoutesResponse(summary=summary, routes=[route_item])
    dumped = resp.model_dump(by_alias=True)

    assert dumped["summary"]["totalCount"] == 3
    assert dumped["summary"]["routeCount"] == 1
    assert len(dumped["routes"]) == 1
    assert dumped["routes"][0]["routeId"] == "507f1f77bcf86cd799439011"
    assert dumped["routes"][0]["routeSnapshot"]["gradeType"] == "v_grade"
    assert dumped["routes"][0]["routeVisibility"] == "public"
    assert dumped["routes"][0]["isDeleted"] is False
    assert dumped["routes"][0]["completedCount"] == 2
    assert dumped["routes"][0]["totalDuration"] == 845.50


def test_daily_route_item_private_and_deleted_flags():
    from beanie.odm.fields import PydanticObjectId
    from app.models.user import OwnerView

    snapshot = RouteSnapshot(grade_type="v_grade", grade="V2")
    item = DailyRouteItem(
        route_id="507f1f77bcf86cd799439012",
        route_snapshot=snapshot,
        route_visibility="private",
        is_deleted=True,
        total_count=1,
        completed_count=0,
        attempted_count=1,
        total_duration=12.0,
        owner=OwnerView(user_id=PydanticObjectId(), is_deleted=True),
    )
    dumped = item.model_dump(by_alias=True)
    assert dumped["routeVisibility"] == "private"
    assert dumped["isDeleted"] is True


def test_daily_routes_response_empty():
    """DailyRoutesResponse with no data should have zero summary and empty routes."""
    summary = DailySummary()
    resp = DailyRoutesResponse(summary=summary, routes=[])
    dumped = resp.model_dump(by_alias=True)
    assert dumped["summary"]["totalCount"] == 0
    assert dumped["routes"] == []


def test_day_utc_superset_basic():
    """±14h padded window around a calendar day in UTC."""
    start, end = _day_utc_superset("2026-04-12")
    assert start == datetime(2026, 4, 11, 10, 0, 0, tzinfo=tz.utc)
    assert end == datetime(2026, 4, 13, 14, 0, 0, tzinfo=tz.utc)


def test_day_utc_superset_year_boundary():
    """Year rollover should not break the window."""
    start, end = _day_utc_superset("2026-01-01")
    assert start == datetime(2025, 12, 31, 10, 0, 0, tzinfo=tz.utc)
    assert end == datetime(2026, 1, 2, 14, 0, 0, tzinfo=tz.utc)


def test_month_utc_superset_basic():
    """±14h padded window around a calendar month in UTC."""
    start, end = _month_utc_superset(2026, 4)
    assert start == datetime(2026, 3, 31, 10, 0, 0, tzinfo=tz.utc)
    assert end == datetime(2026, 5, 1, 14, 0, 0, tzinfo=tz.utc)


def test_month_utc_superset_year_boundary():
    """December should roll over to next January correctly."""
    start, end = _month_utc_superset(2026, 12)
    assert start == datetime(2026, 11, 30, 10, 0, 0, tzinfo=tz.utc)
    assert end == datetime(2027, 1, 1, 14, 0, 0, tzinfo=tz.utc)


def test_merge_incs_empty_list():
    assert _merge_incs([]) == {}


def test_merge_incs_single_dict():
    assert _merge_incs([{"totalCount": 1, "totalDuration": 30.5}]) == {
        "totalCount": 1,
        "totalDuration": 30.5,
    }


def test_merge_incs_overlapping_keys():
    merged = _merge_incs([
        {"totalCount": 1, "totalDuration": 10.0, "completedCount": 1},
        {"totalCount": 1, "totalDuration": 20.0},
        {"totalCount": 1, "totalDuration": 5.5, "completedCount": 1, "completedDuration": 5.5},
    ])
    assert merged == {
        "totalCount": 3,
        "totalDuration": 35.5,
        "completedCount": 2,
        "completedDuration": 5.5,
    }


def test_merge_incs_negative_signs():
    """Decrement dicts sum correctly."""
    assert _merge_incs([
        {"totalCount": -1, "totalDuration": -10.0},
        {"totalCount": -1, "totalDuration": -20.0},
    ]) == {"totalCount": -2, "totalDuration": -30.0}


def test_daily_route_item_serializes_owner():
    """DailyRouteItem.owner should round-trip with camelCase aliases."""
    from beanie.odm.fields import PydanticObjectId
    from app.models.user import OwnerView
    from app.routers.my import DailyRouteItem

    snapshot = RouteSnapshot(grade_type="v_scale", grade="V4")
    owner = OwnerView(
        user_id=PydanticObjectId("507f1f77bcf86cd799439011"),
        profile_id="climber42",
        profile_image_url="https://cdn/x.jpg",
        is_deleted=False,
    )
    item = DailyRouteItem(
        route_id="507f1f77bcf86cd799439012",
        route_snapshot=snapshot,
        route_visibility="public",
        is_deleted=False,
        total_count=1,
        completed_count=1,
        attempted_count=0,
        total_duration=60.0,
        owner=owner,
    )
    dumped = item.model_dump(by_alias=True, mode="json")
    assert dumped["owner"]["userId"] == "507f1f77bcf86cd799439011"
    assert dumped["owner"]["profileId"] == "climber42"
    assert dumped["owner"]["isDeleted"] is False


def test_daily_route_item_supports_deleted_owner():
    from beanie.odm.fields import PydanticObjectId
    from app.models.user import OwnerView
    from app.routers.my import DailyRouteItem

    snapshot = RouteSnapshot(grade_type="v_scale", grade="V4")
    item = DailyRouteItem(
        route_id="507f1f77bcf86cd799439012",
        route_snapshot=snapshot,
        route_visibility="public",
        is_deleted=False,
        total_count=1,
        completed_count=0,
        attempted_count=1,
        total_duration=30.0,
        owner=OwnerView(user_id=PydanticObjectId(), is_deleted=True),
    )
    dumped = item.model_dump(by_alias=True, mode="json")
    assert dumped["owner"]["isDeleted"] is True
    assert dumped["owner"]["profileId"] is None
