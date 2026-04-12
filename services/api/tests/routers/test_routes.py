from types import SimpleNamespace

from bson import ObjectId

from app.models.route import Visibility
from app.routers.routes import _can_access_route, RouteDetailView


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


def test_route_detail_view_has_optional_activity_flag():
    """RouteDetailView must expose `hasOtherUserActivities` as optional camelCase field."""
    fields = RouteDetailView.model_fields
    assert "has_other_user_activities" in fields
    # Optional → default None, not required
    assert fields["has_other_user_activities"].is_required() is False


def test_route_detail_view_serializes_activity_flag_camel_case():
    """When set, the flag must serialize as `hasOtherUserActivities`."""
    view = RouteDetailView.model_construct(
        has_other_user_activities=True,
    )
    dumped = view.model_dump(by_alias=True, exclude_none=True)
    assert dumped.get("hasOtherUserActivities") is True
