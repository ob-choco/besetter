from datetime import datetime, timezone
from app.models.activity import (
    ActivityStatus,
    RouteSnapshot,
    ActivityStats,
    Activity,
    UserRouteStats,
)


def test_activity_status_values():
    assert ActivityStatus.STARTED == "started"
    assert ActivityStatus.COMPLETED == "completed"
    assert ActivityStatus.ATTEMPTED == "attempted"


def test_route_snapshot_minimal():
    snap = RouteSnapshot(
        grade_type="v_scale",
        grade="V7",
    )
    assert snap.title is None
    assert snap.grade_type == "v_scale"
    assert snap.grade == "V7"
    assert snap.place_id is None
    assert snap.image_url is None


def test_route_snapshot_full():
    snap = RouteSnapshot(
        title="Electric Drift",
        grade_type="v_scale",
        grade="V7",
        grade_color="#FF5722",
        place_name="Urban Apex Gym",
        image_url="https://example.com/img.jpg",
        overlay_image_url="https://example.com/overlay.jpg",
    )
    assert snap.title == "Electric Drift"
    assert snap.place_name == "Urban Apex Gym"


def test_activity_stats_defaults():
    stats = ActivityStats()
    assert stats.total_count == 0
    assert stats.total_duration == 0
    assert stats.completed_count == 0
    assert stats.completed_duration == 0
    assert stats.verified_completed_count == 0
    assert stats.verified_completed_duration == 0


def test_activity_stats_camel_case_alias():
    stats = ActivityStats()
    dumped = stats.model_dump(by_alias=True)
    assert "totalCount" in dumped
    assert "totalDuration" in dumped
    assert "completedCount" in dumped
    assert "verifiedCompletedCount" in dumped


def test_activity_default_status():
    from bson import ObjectId
    snap = RouteSnapshot(grade_type="v_scale", grade="V7")
    now = datetime.now(tz=timezone.utc)
    activity = Activity(
        route_id=ObjectId(),
        user_id=ObjectId(),
        location_verified=True,
        started_at=now,
        route_snapshot=snap,
        created_at=now,
    )
    assert activity.status == ActivityStatus.STARTED
    assert activity.ended_at is None
    assert activity.duration is None


def test_user_route_stats_defaults():
    from bson import ObjectId
    stats = UserRouteStats(
        user_id=ObjectId(),
        route_id=ObjectId(),
    )
    assert stats.total_count == 0
    assert stats.last_activity_at is None
