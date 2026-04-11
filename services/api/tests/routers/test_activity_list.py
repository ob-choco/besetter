from app.routers.activities import MyStatsResponse


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
