"""Tests for GET /my/recently-climbed-routes (service-level)."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz

import pytest
import pytest_asyncio
from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from mongomock_motor import AsyncMongoMockClient

from app.models.activity import UserRouteStats
from app.models.image import Image, ImageMetadata
from app.models.place import Place, normalize_name
from app.models.route import Route, RouteType, Visibility
from app.models.user import User


pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient(tz_aware=True)
    db = client.get_database("besetter-test")
    await init_beanie(
        database=db,
        document_models=[User, Route, Image, Place, UserRouteStats],
    )
    yield db


@pytest.fixture(autouse=True)
def _stub_to_public_url(monkeypatch):
    """Root conftest mocks app.core.gcs as a MagicMock, leaving to_public_url
    returning MagicMock instances (which break PlaceView validation). Replace
    the symbol in every module that imported it from the mocked source."""
    stub = lambda url: str(url) if url else None
    monkeypatch.setattr("app.routers.my.to_public_url", stub)
    monkeypatch.setattr("app.routers.places.to_public_url", stub)
    return stub


async def _seed_user(*, profile_id: str = "owner1", is_deleted: bool = False) -> User:
    now = datetime(2026, 4, 18, tzinfo=dt_tz.utc)
    user = User(
        profile_id=profile_id,
        profile_image_url=f"https://cdn/{profile_id}.jpg" if not is_deleted else None,
        is_deleted=is_deleted,
        created_at=now,
        updated_at=now,
    )
    await user.insert()
    return user


async def _seed_route(
    *,
    owner: User,
    visibility: Visibility = Visibility.PUBLIC,
    is_deleted: bool = False,
    image_url: str = "https://storage.cloud.google.com/besetter/routes/r.jpg",
) -> tuple[Route, Image, Place]:
    now = datetime(2026, 4, 18, tzinfo=dt_tz.utc)
    place = Place(
        name="Urban Apex",
        normalized_name=normalize_name("Urban Apex"),
        type="gym",
        status="approved",
        created_by=owner.id,
        created_at=now,
    )
    await place.insert()
    image = Image(
        url="https://storage.cloud.google.com/besetter/walls/w.jpg",
        filename="w.jpg",
        metadata=ImageMetadata(),
        user_id=owner.id,
        place_id=place.id,
        uploaded_at=now,
    )
    await image.insert()
    route = Route(
        type=RouteType.BOULDERING,
        grade_type="v_scale",
        grade="V3",
        visibility=visibility,
        image_id=image.id,
        hold_polygon_id=PydanticObjectId(),
        user_id=owner.id,
        image_url=image_url,
        is_deleted=is_deleted,
    )
    await route.insert()
    return route, image, place


async def _seed_stats(
    *,
    viewer_id: PydanticObjectId,
    route: Route,
    last_activity_at: datetime | None,
) -> UserRouteStats:
    stats = UserRouteStats(
        user_id=viewer_id,
        route_id=route.id,
        total_count=1,
        completed_count=1,
        verified_completed_count=0,
        last_activity_at=last_activity_at,
    )
    await stats.insert()
    return stats


async def test_recent_climbed_returns_nothing_for_new_user(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.routers.my.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert resp.data == []


async def test_recent_climbed_orders_by_last_activity_desc(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.routers.my.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    now = datetime(2026, 4, 18, tzinfo=dt_tz.utc)
    r1, _, _ = await _seed_route(owner=owner)
    r2, _, _ = await _seed_route(owner=owner)
    r3, _, _ = await _seed_route(owner=owner)

    await _seed_stats(viewer_id=viewer.id, route=r1, last_activity_at=now.replace(hour=10))
    await _seed_stats(viewer_id=viewer.id, route=r2, last_activity_at=now.replace(hour=14))
    await _seed_stats(viewer_id=viewer.id, route=r3, last_activity_at=now.replace(hour=12))

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    ordered_ids = [str(v.id) for v in resp.data]
    assert ordered_ids == [str(r2.id), str(r3.id), str(r1.id)]


async def test_recent_climbed_excludes_null_last_activity_at(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.routers.my.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    r_with, _, _ = await _seed_route(owner=owner)
    r_null, _, _ = await _seed_route(owner=owner)
    await _seed_stats(viewer_id=viewer.id, route=r_with, last_activity_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc))
    await _seed_stats(viewer_id=viewer.id, route=r_null, last_activity_at=None)

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert len(resp.data) == 1
    assert str(resp.data[0].id) == str(r_with.id)


async def test_recent_climbed_populates_owner_for_other_users_route(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.routers.my.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    route, _, _ = await _seed_route(owner=owner)
    await _seed_stats(
        viewer_id=viewer.id, route=route,
        last_activity_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc),
    )

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert len(resp.data) == 1
    view = resp.data[0]
    assert view.owner.user_id == owner.id
    assert view.owner.profile_id == "owner1"
    assert view.owner.profile_image_url == "https://cdn/owner1.jpg"
    assert view.owner.is_deleted is False


async def test_recent_climbed_deleted_owner_returns_is_deleted_true(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.routers.my.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1", is_deleted=True)

    route, _, _ = await _seed_route(owner=owner)
    await _seed_stats(
        viewer_id=viewer.id, route=route,
        last_activity_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc),
    )

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert resp.data[0].owner.is_deleted is True
    assert resp.data[0].owner.profile_id is None
    assert resp.data[0].owner.profile_image_url is None


async def test_recent_climbed_deleted_route_is_tombstone(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.routers.my.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    route, _, _ = await _seed_route(owner=owner, is_deleted=True)
    await _seed_stats(
        viewer_id=viewer.id, route=route,
        last_activity_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc),
    )

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert len(resp.data) == 1
    assert resp.data[0].is_deleted is True


async def test_recent_climbed_private_route_returned_as_tombstone(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.routers.my.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    route, _, _ = await _seed_route(owner=owner, visibility=Visibility.PRIVATE)
    await _seed_stats(
        viewer_id=viewer.id, route=route,
        last_activity_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc),
    )

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert len(resp.data) == 1
    assert resp.data[0].visibility == Visibility.PRIVATE


async def test_recent_climbed_respects_limit(mongo_db, monkeypatch):
    monkeypatch.setattr(
        "app.routers.my.to_public_url",
        lambda url: str(url) if url else url,
    )
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    now = datetime(2026, 4, 18, tzinfo=dt_tz.utc)
    for i in range(5):
        r, _, _ = await _seed_route(owner=owner)
        await _seed_stats(viewer_id=viewer.id, route=r, last_activity_at=now.replace(hour=i + 1))

    resp = await _build_recently_climbed_routes(viewer.id, limit=3)
    assert len(resp.data) == 3


async def test_recent_climbed_uses_public_gcs_host(mongo_db, monkeypatch):
    def fake_to_public_url(url):
        if not url:
            return url
        return str(url).replace("storage.cloud.google.com", "storage.googleapis.com")

    monkeypatch.setattr("app.routers.my.to_public_url", fake_to_public_url)
    from app.routers.my import _build_recently_climbed_routes
    viewer = await _seed_user(profile_id="viewer")
    owner = await _seed_user(profile_id="owner1")

    route, _, _ = await _seed_route(owner=owner)
    await _seed_stats(
        viewer_id=viewer.id, route=route,
        last_activity_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc),
    )

    resp = await _build_recently_climbed_routes(viewer.id, limit=9)
    assert "storage.googleapis.com" in resp.data[0].image_url
