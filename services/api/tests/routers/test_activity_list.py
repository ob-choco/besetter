from datetime import datetime, timezone

from app.routers.activities import (
    MyStatsResponse,
    MyActivitiesResponse,
    ActivityListItem,
    _encode_activity_cursor,
    _decode_activity_cursor,
)


def test_my_stats_response_schema():
    """MyStatsResponse should serialize with camelCase aliases."""
    stats = MyStatsResponse(
        total_count=5,
        total_duration=1234.56,
        completed_count=3,
        completed_duration=987.65,
        verified_completed_count=2,
        verified_completed_duration=600.12,
    )
    dumped = stats.model_dump(by_alias=True)
    assert dumped["totalCount"] == 5
    assert dumped["completedDuration"] == 987.65
    assert dumped["verifiedCompletedCount"] == 2


def test_activity_list_item_schema():
    """ActivityListItem should serialize with camelCase aliases."""
    item = ActivityListItem(
        id="507f1f77bcf86cd799439011",
        status="completed",
        location_verified=True,
        started_at=datetime(2023, 10, 25, 14, 20, 0, tzinfo=timezone.utc),
        ended_at=datetime(2023, 10, 25, 15, 5, 12, tzinfo=timezone.utc),
        duration=2712.0,
        created_at=datetime(2023, 10, 25, 14, 20, 0, tzinfo=timezone.utc),
    )
    dumped = item.model_dump(by_alias=True)
    assert "id" in dumped
    assert "_id" not in dumped
    assert dumped["locationVerified"] is True
    assert dumped["startedAt"] == datetime(2023, 10, 25, 14, 20, 0, tzinfo=timezone.utc)
    assert "started_at" not in dumped


def test_my_activities_response_schema():
    """MyActivitiesResponse should have activities list and nextCursor."""
    resp = MyActivitiesResponse(activities=[], next_cursor=None)
    dumped = resp.model_dump(by_alias=True)
    assert dumped["activities"] == []
    assert dumped["nextCursor"] is None


def test_encode_decode_activity_cursor():
    """Cursor encode/decode should round-trip correctly."""
    cursor = _encode_activity_cursor("2023-10-25T14:20:00+00:00", "507f1f77bcf86cd799439011")
    started_at_str, last_id = _decode_activity_cursor(cursor)
    assert started_at_str == "2023-10-25T14:20:00+00:00"
    assert last_id == "507f1f77bcf86cd799439011"
