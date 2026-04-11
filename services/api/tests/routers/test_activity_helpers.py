from datetime import datetime, timezone
from app.routers.activities import _build_stats_inc, _compute_duration
from app.models.activity import ActivityStatus


# ---------------------------------------------------------------------------
# _compute_duration
# ---------------------------------------------------------------------------


def test_compute_duration_basic():
    start = datetime(2026, 4, 11, 14, 0, 0, tzinfo=timezone.utc)
    end = datetime(2026, 4, 11, 14, 5, 30, tzinfo=timezone.utc)
    assert _compute_duration(start, end) == 330


def test_compute_duration_zero():
    t = datetime(2026, 4, 11, 14, 0, 0, tzinfo=timezone.utc)
    assert _compute_duration(t, t) == 0


# ---------------------------------------------------------------------------
# _build_stats_inc — increment (sign=1)
# ---------------------------------------------------------------------------


def test_stats_inc_completed_unverified():
    inc = _build_stats_inc(ActivityStatus.COMPLETED, False, 300, sign=1)
    assert inc == {
        "totalCount": 1,
        "totalDuration": 300,
        "completedCount": 1,
        "completedDuration": 300,
    }


def test_stats_inc_completed_verified():
    inc = _build_stats_inc(ActivityStatus.COMPLETED, True, 300, sign=1)
    assert inc == {
        "totalCount": 1,
        "totalDuration": 300,
        "completedCount": 1,
        "completedDuration": 300,
        "verifiedCompletedCount": 1,
        "verifiedCompletedDuration": 300,
    }


def test_stats_inc_attempted():
    inc = _build_stats_inc(ActivityStatus.ATTEMPTED, False, 120, sign=1)
    assert inc == {
        "totalCount": 1,
        "totalDuration": 120,
    }


# ---------------------------------------------------------------------------
# _build_stats_inc — decrement (sign=-1)
# ---------------------------------------------------------------------------


def test_stats_dec_completed_verified():
    inc = _build_stats_inc(ActivityStatus.COMPLETED, True, 300, sign=-1)
    assert inc == {
        "totalCount": -1,
        "totalDuration": -300,
        "completedCount": -1,
        "completedDuration": -300,
        "verifiedCompletedCount": -1,
        "verifiedCompletedDuration": -300,
    }


def test_stats_dec_attempted():
    inc = _build_stats_inc(ActivityStatus.ATTEMPTED, True, 120, sign=-1)
    assert inc == {
        "totalCount": -1,
        "totalDuration": -120,
    }
