from types import SimpleNamespace

from bson import ObjectId

from app.routers.users import UserProfileResponse, _build_profile_response


def _make_user(
    *,
    id: ObjectId,
    name: str | None = None,
    email: str | None = None,
    bio: str | None = None,
    profile_image_url: str | None = None,
) -> SimpleNamespace:
    return SimpleNamespace(
        id=id,
        name=name,
        email=email,
        bio=bio,
        profile_image_url=profile_image_url,
    )


def test_user_profile_response_serializes_id():
    """UserProfileResponse should carry a string id field."""
    resp = UserProfileResponse(
        id="507f1f77bcf86cd799439011",
        name="alice",
        email=None,
        bio=None,
        profile_image_url=None,
    )
    dumped = resp.model_dump(by_alias=True)
    assert dumped["id"] == "507f1f77bcf86cd799439011"


def test_build_profile_response_populates_id_as_string():
    """_build_profile_response should stringify the user's ObjectId into `id`."""
    oid = ObjectId()
    user = _make_user(id=oid, name="alice", email="a@example.com")

    resp = _build_profile_response(user)

    assert resp.id == str(oid)
    assert resp.name == "alice"
    assert resp.email == "a@example.com"
    assert resp.profile_image_url is None


def test_build_profile_response_passes_through_nulls():
    """Missing optional fields should round-trip as None."""
    oid = ObjectId()
    user = _make_user(id=oid)

    resp = _build_profile_response(user)

    assert resp.id == str(oid)
    assert resp.name is None
    assert resp.email is None
    assert resp.bio is None
    assert resp.profile_image_url is None
