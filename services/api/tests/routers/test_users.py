from types import SimpleNamespace

from bson import ObjectId

from app.routers.users import UserProfileResponse, _build_profile_response


def _make_user(
    *,
    id: ObjectId,
    profile_id: str = "testuser01",
    name: str | None = None,
    email: str | None = None,
    bio: str | None = None,
    profile_image_url: str | None = None,
    unread_notification_count: int = 0,
) -> SimpleNamespace:
    return SimpleNamespace(
        id=id,
        profile_id=profile_id,
        name=name,
        email=email,
        bio=bio,
        profile_image_url=profile_image_url,
        unread_notification_count=unread_notification_count,
    )


def test_user_profile_response_serializes_id():
    resp = UserProfileResponse(
        id="507f1f77bcf86cd799439011",
        profile_id="climber99",
        name="alice",
        email=None,
        bio=None,
        profile_image_url=None,
    )
    dumped = resp.model_dump(by_alias=True)
    assert dumped["id"] == "507f1f77bcf86cd799439011"


def test_user_profile_response_serializes_profile_id_camelcase():
    """profile_id field should emit as profileId in JSON."""
    resp = UserProfileResponse(
        id="507f1f77bcf86cd799439011",
        profile_id="climber99",
    )
    dumped = resp.model_dump(by_alias=True)
    assert dumped["profileId"] == "climber99"


def test_build_profile_response_populates_profile_id():
    oid = ObjectId()
    user = _make_user(id=oid, profile_id="kx9m2pq7vn3a", name="alice")
    resp = _build_profile_response(user)
    assert resp.profile_id == "kx9m2pq7vn3a"


def test_build_profile_response_populates_id_as_string():
    oid = ObjectId()
    user = _make_user(id=oid, name="alice", email="a@example.com")

    resp = _build_profile_response(user)

    assert resp.id == str(oid)
    assert resp.name == "alice"
    assert resp.email == "a@example.com"
    assert resp.profile_image_url is None


def test_build_profile_response_passes_through_nulls():
    oid = ObjectId()
    user = _make_user(id=oid)

    resp = _build_profile_response(user)

    assert resp.id == str(oid)
    assert resp.name is None
    assert resp.email is None
    assert resp.bio is None
    assert resp.profile_image_url is None


import pytest
from fastapi import HTTPException, status as http_status

from app.routers.users import _validate_profile_id_or_raise


@pytest.mark.parametrize(
    "value,expected_code",
    [
        ("abc", "PROFILE_ID_TOO_SHORT"),
        ("a" * 17, "PROFILE_ID_TOO_LONG"),
        ("Climber99", "PROFILE_ID_INVALID_CHARS"),
        ("_climber9", "PROFILE_ID_INVALID_START_END"),
        ("clim__ber", "PROFILE_ID_CONSECUTIVE_SPECIAL"),
        ("fuckmaster", "PROFILE_ID_RESERVED"),  # profanity substring
    ],
)
def test_validate_profile_id_or_raise_maps_errors(value, expected_code):
    with pytest.raises(HTTPException) as exc_info:
        _validate_profile_id_or_raise(value)
    assert exc_info.value.status_code == http_status.HTTP_422_UNPROCESSABLE_ENTITY
    assert exc_info.value.detail["code"] == expected_code


def test_validate_profile_id_or_raise_reserved_exact():
    with pytest.raises(HTTPException) as exc_info:
        _validate_profile_id_or_raise("besetterofficial")
    assert exc_info.value.detail["code"] == "PROFILE_ID_RESERVED"


def test_validate_profile_id_or_raise_accepts_valid():
    # Should not raise.
    _validate_profile_id_or_raise("climber99")


from app.routers.users import (
    ProfileIdAvailabilityResponse,
    _compute_profile_id_availability,
)


def test_availability_response_schema_camelcase():
    resp = ProfileIdAvailabilityResponse(
        value="climber99",
        available=True,
        reason=None,
    )
    dumped = resp.model_dump(by_alias=True)
    assert dumped == {"value": "climber99", "available": True, "reason": None}


def test_compute_availability_reserved_short_circuits_db():
    """Validation failure returns immediately without touching DB."""
    current = _make_user(id=ObjectId(), profile_id="owner001x")
    result = _compute_profile_id_availability(
        value="_bad_start",
        current_user=current,
        exists=None,
    )
    assert result.available is False
    assert result.reason == "PROFILE_ID_INVALID_START_END"


def test_compute_availability_self_is_available():
    """The caller's current profile_id is always available to them."""
    current = _make_user(id=ObjectId(), profile_id="climber99")
    result = _compute_profile_id_availability(
        value="climber99",
        current_user=current,
        exists=True,  # not consulted because of self-match
    )
    assert result.available is True
    assert result.reason is None


def test_compute_availability_taken_by_another():
    current = _make_user(id=ObjectId(), profile_id="ownerabc")
    result = _compute_profile_id_availability(
        value="someone1",
        current_user=current,
        exists=True,
    )
    assert result.available is False
    assert result.reason == "PROFILE_ID_TAKEN"


def test_compute_availability_free():
    current = _make_user(id=ObjectId(), profile_id="ownerabc")
    result = _compute_profile_id_availability(
        value="newname01",
        current_user=current,
        exists=False,
    )
    assert result.available is True
    assert result.reason is None
