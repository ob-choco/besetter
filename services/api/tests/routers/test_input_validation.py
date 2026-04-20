"""Tests for request-schema length/range validation across routers."""

from datetime import datetime, timedelta, timezone

import pytest
from bson import ObjectId
from pydantic import ValidationError


# ---------------------------------------------------------------------------
# Routes: title 1~50, description ≤500, grade_score 0~10000
# ---------------------------------------------------------------------------


def test_create_route_rejects_title_over_50_chars():
    from app.routers.routes import CreateRouteRequest
    from app.models.route import RouteType

    with pytest.raises(ValidationError):
        CreateRouteRequest(
            type=RouteType.BOULDERING,
            title="x" * 51,
            image_id=ObjectId(),
            grade_type="V",
            grade="V1",
        )


def test_create_route_rejects_empty_title():
    from app.routers.routes import CreateRouteRequest
    from app.models.route import RouteType

    with pytest.raises(ValidationError):
        CreateRouteRequest(
            type=RouteType.BOULDERING,
            title="",
            image_id=ObjectId(),
            grade_type="V",
            grade="V1",
        )


def test_create_route_accepts_title_50_chars():
    from app.routers.routes import CreateRouteRequest
    from app.models.route import RouteType

    req = CreateRouteRequest(
        type=RouteType.BOULDERING,
        title="x" * 50,
        image_id=ObjectId(),
        grade_type="V",
        grade="V1",
    )
    assert len(req.title) == 50


def test_create_route_rejects_description_over_500_chars():
    from app.routers.routes import CreateRouteRequest
    from app.models.route import RouteType

    with pytest.raises(ValidationError):
        CreateRouteRequest(
            type=RouteType.BOULDERING,
            description="x" * 501,
            image_id=ObjectId(),
            grade_type="V",
            grade="V1",
        )


def test_create_route_rejects_grade_score_below_zero():
    from app.routers.routes import CreateRouteRequest
    from app.models.route import RouteType

    with pytest.raises(ValidationError):
        CreateRouteRequest(
            type=RouteType.BOULDERING,
            image_id=ObjectId(),
            grade_type="V",
            grade="V1",
            grade_score=-1,
        )


def test_create_route_rejects_grade_score_above_10000():
    from app.routers.routes import CreateRouteRequest
    from app.models.route import RouteType

    with pytest.raises(ValidationError):
        CreateRouteRequest(
            type=RouteType.BOULDERING,
            image_id=ObjectId(),
            grade_type="V",
            grade="V1",
            grade_score=10001,
        )


def test_create_route_accepts_grade_score_boundaries():
    from app.routers.routes import CreateRouteRequest
    from app.models.route import RouteType

    for score in (0, 10000):
        req = CreateRouteRequest(
            type=RouteType.BOULDERING,
            image_id=ObjectId(),
            grade_type="V",
            grade="V1",
            grade_score=score,
        )
        assert req.grade_score == score


def test_update_route_rejects_title_over_50_chars():
    from app.routers.routes import UpdateRouteRequest

    with pytest.raises(ValidationError):
        UpdateRouteRequest(title="x" * 51)


def test_update_route_rejects_empty_title():
    from app.routers.routes import UpdateRouteRequest

    with pytest.raises(ValidationError):
        UpdateRouteRequest(title="")


def test_update_route_rejects_description_over_500_chars():
    from app.routers.routes import UpdateRouteRequest

    with pytest.raises(ValidationError):
        UpdateRouteRequest(description="x" * 501)


def test_update_route_rejects_grade_score_out_of_range():
    from app.routers.routes import UpdateRouteRequest

    with pytest.raises(ValidationError):
        UpdateRouteRequest(grade_score=-1)
    with pytest.raises(ValidationError):
        UpdateRouteRequest(grade_score=10001)


# ---------------------------------------------------------------------------
# Places: name 1~64
# ---------------------------------------------------------------------------


def test_create_place_rejects_name_over_64_chars():
    from app.routers.places import CreatePlaceRequest

    with pytest.raises(ValidationError):
        CreatePlaceRequest(name="x" * 65)


def test_create_place_rejects_empty_name():
    from app.routers.places import CreatePlaceRequest

    with pytest.raises(ValidationError):
        CreatePlaceRequest(name="")


def test_create_place_accepts_name_64_chars():
    from app.routers.places import CreatePlaceRequest

    req = CreatePlaceRequest(name="x" * 64)
    assert len(req.name) == 64


# ---------------------------------------------------------------------------
# Users: name ≤32, bio ≤300 (via UpdateMyProfileRequest schema)
# ---------------------------------------------------------------------------


def test_update_my_profile_rejects_name_over_32_chars():
    from app.routers.users import UpdateMyProfileRequest

    with pytest.raises(ValidationError):
        UpdateMyProfileRequest(name="x" * 33)


def test_update_my_profile_accepts_name_32_chars():
    from app.routers.users import UpdateMyProfileRequest

    req = UpdateMyProfileRequest(name="x" * 32)
    assert len(req.name) == 32


def test_update_my_profile_rejects_bio_over_300_chars():
    from app.routers.users import UpdateMyProfileRequest

    with pytest.raises(ValidationError):
        UpdateMyProfileRequest(bio="x" * 301)


def test_update_my_profile_accepts_bio_300_chars():
    from app.routers.users import UpdateMyProfileRequest

    req = UpdateMyProfileRequest(bio="x" * 300)
    assert len(req.bio) == 300


# ---------------------------------------------------------------------------
# Activities: times coherent, coord ranges, timezone IANA
# ---------------------------------------------------------------------------


def _valid_activity_kwargs(**overrides):
    now = datetime.now(tz=timezone.utc)
    base = dict(
        latitude=37.5,
        longitude=127.0,
        status="completed",
        started_at=now - timedelta(minutes=30),
        ended_at=now - timedelta(minutes=1),
        timezone="Asia/Seoul",
    )
    base.update(overrides)
    return base


def test_create_activity_rejects_latitude_out_of_range():
    from app.routers.activities import CreateActivityRequest

    with pytest.raises(ValidationError):
        CreateActivityRequest(**_valid_activity_kwargs(latitude=91))
    with pytest.raises(ValidationError):
        CreateActivityRequest(**_valid_activity_kwargs(latitude=-91))


def test_create_activity_rejects_longitude_out_of_range():
    from app.routers.activities import CreateActivityRequest

    with pytest.raises(ValidationError):
        CreateActivityRequest(**_valid_activity_kwargs(longitude=181))
    with pytest.raises(ValidationError):
        CreateActivityRequest(**_valid_activity_kwargs(longitude=-181))


def test_create_activity_rejects_ended_before_started():
    from app.routers.activities import CreateActivityRequest

    now = datetime.now(tz=timezone.utc)
    with pytest.raises(ValidationError):
        CreateActivityRequest(
            **_valid_activity_kwargs(
                started_at=now,
                ended_at=now - timedelta(minutes=1),
            )
        )


def test_create_activity_rejects_future_started_at():
    from app.routers.activities import CreateActivityRequest

    future = datetime.now(tz=timezone.utc) + timedelta(hours=2)
    with pytest.raises(ValidationError):
        CreateActivityRequest(
            **_valid_activity_kwargs(
                started_at=future,
                ended_at=future + timedelta(minutes=30),
            )
        )


def test_create_activity_rejects_duration_over_12_hours():
    from app.routers.activities import CreateActivityRequest

    now = datetime.now(tz=timezone.utc)
    with pytest.raises(ValidationError):
        CreateActivityRequest(
            **_valid_activity_kwargs(
                started_at=now - timedelta(hours=13),
                ended_at=now - timedelta(minutes=1),
            )
        )


def test_create_activity_rejects_invalid_timezone():
    from app.routers.activities import CreateActivityRequest

    with pytest.raises(ValidationError):
        CreateActivityRequest(**_valid_activity_kwargs(timezone="Not/A_Zone"))


def test_create_activity_accepts_valid_request():
    from app.routers.activities import CreateActivityRequest

    req = CreateActivityRequest(**_valid_activity_kwargs())
    assert req.timezone == "Asia/Seoul"


# ---------------------------------------------------------------------------
# Wall name: ≤32 (validated by hold_polygons patch path via helper)
# ---------------------------------------------------------------------------


def test_validate_wall_name_rejects_over_32_chars():
    from app.routers.hold_polygons import _validate_wall_name

    with pytest.raises(ValueError):
        _validate_wall_name("x" * 33)


def test_validate_wall_name_accepts_32_chars():
    from app.routers.hold_polygons import _validate_wall_name

    # returns None on success
    assert _validate_wall_name("x" * 32) is None


def test_validate_wall_name_accepts_none():
    from app.routers.hold_polygons import _validate_wall_name

    assert _validate_wall_name(None) is None
