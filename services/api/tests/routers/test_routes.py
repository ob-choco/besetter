from types import SimpleNamespace

from bson import ObjectId

from app.models.route import Visibility
from app.routers.routes import _can_access_route


def _make_route(owner_id: ObjectId, visibility: Visibility) -> SimpleNamespace:
    return SimpleNamespace(user_id=owner_id, visibility=visibility)


def _make_user(user_id: ObjectId) -> SimpleNamespace:
    return SimpleNamespace(id=user_id)


def test_owner_can_access_public_route():
    uid = ObjectId()
    assert _can_access_route(_make_route(uid, Visibility.PUBLIC), _make_user(uid)) is True


def test_owner_can_access_private_route():
    uid = ObjectId()
    assert _can_access_route(_make_route(uid, Visibility.PRIVATE), _make_user(uid)) is True


def test_non_owner_can_access_public_route():
    owner = ObjectId()
    viewer = ObjectId()
    assert _can_access_route(_make_route(owner, Visibility.PUBLIC), _make_user(viewer)) is True


def test_non_owner_cannot_access_private_route():
    owner = ObjectId()
    viewer = ObjectId()
    assert _can_access_route(_make_route(owner, Visibility.PRIVATE), _make_user(viewer)) is False


def test_non_owner_can_access_unlisted_route():
    """UNLISTED is only blocked from discovery, not from direct access (matches share.py)."""
    owner = ObjectId()
    viewer = ObjectId()
    assert _can_access_route(_make_route(owner, Visibility.UNLISTED), _make_user(viewer)) is True
