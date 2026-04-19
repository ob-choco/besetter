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
