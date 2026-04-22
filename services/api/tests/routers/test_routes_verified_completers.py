"""Tests for GET /routes/{id}/verified-completers.

These tests invoke the handler function directly (not via TestClient) — other
router tests in this suite follow the same pattern because `httpx` is not
installed in the dev env. The handler is a plain async function, so this
exercises the real aggregation and serialization paths.
"""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz

import pytest
import pytest_asyncio
from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from fastapi import HTTPException
from mongomock_motor import AsyncMongoMockClient

from app.models.activity import UserRouteStats
from app.models.image import Image
from app.models.place import Place
from app.models.route import Route, RouteType, Visibility
from app.models.user import User
from app.routers.routes import get_verified_completers


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


async def _seed_user(*, profile_id: str = "owner", is_deleted: bool = False) -> User:
    now = datetime(2026, 4, 22, tzinfo=dt_tz.utc)
    user = User(
        profile_id=profile_id,
        profile_image_url=None if is_deleted else f"https://cdn/{profile_id}.jpg",
        is_deleted=is_deleted,
        created_at=now,
        updated_at=now,
    )
    await user.insert()
    return user


async def _seed_route(owner: User, visibility: Visibility = Visibility.PUBLIC) -> Route:
    route = Route(
        type=RouteType.BOULDERING,
        grade_type="v_scale",
        grade="V4",
        visibility=visibility,
        image_id=PydanticObjectId(),
        hold_polygon_id=PydanticObjectId(),
        user_id=owner.id,
        image_url="https://example.com/a.jpg",
    )
    await route.insert()
    return route


async def _seed_urs(
    *,
    user: User,
    route: Route,
    verified_count: int,
    last_activity_at: datetime,
) -> UserRouteStats:
    doc = UserRouteStats(
        user_id=user.id,
        route_id=route.id,
        total_count=verified_count,
        completed_count=verified_count,
        verified_completed_count=verified_count,
        last_activity_at=last_activity_at,
    )
    await doc.insert()
    return doc


def _dump(resp) -> dict:
    """Serialize a VerifiedCompletersResponse with camelCase aliases."""
    return resp.model_dump(by_alias=True)


async def test_returns_empty_when_no_completers(mongo_db):
    owner = await _seed_user(profile_id="owner")
    route = await _seed_route(owner)

    resp = await get_verified_completers(
        route_id=str(route.id), limit=20, cursor=None, current_user=owner
    )
    body = _dump(resp)
    assert body["data"] == []
    assert body["meta"]["nextToken"] is None


async def test_sorts_by_verified_count_desc_then_last_activity_desc(mongo_db):
    owner = await _seed_user(profile_id="owner")
    route = await _seed_route(owner)

    u1 = await _seed_user(profile_id="u1")
    u2 = await _seed_user(profile_id="u2")
    u3 = await _seed_user(profile_id="u3")

    t0 = datetime(2026, 4, 20, 10, 0, tzinfo=dt_tz.utc)
    await _seed_urs(
        user=u1, route=route, verified_count=5,
        last_activity_at=datetime(2026, 4, 20, 8, 0, tzinfo=dt_tz.utc),
    )
    await _seed_urs(user=u2, route=route, verified_count=5, last_activity_at=t0)
    await _seed_urs(user=u3, route=route, verified_count=2, last_activity_at=t0)

    resp = await get_verified_completers(
        route_id=str(route.id), limit=10, cursor=None, current_user=owner
    )
    data = _dump(resp)["data"]
    assert [item["user"]["profileId"] for item in data] == ["u2", "u1", "u3"]


async def test_pagination_round_trip(mongo_db):
    owner = await _seed_user(profile_id="owner")
    route = await _seed_route(owner)

    for i in range(5):
        u = await _seed_user(profile_id=f"u{i}")
        await _seed_urs(
            user=u, route=route,
            verified_count=5 - i,
            last_activity_at=datetime(2026, 4, 20, 10, i, tzinfo=dt_tz.utc),
        )

    page1 = _dump(await get_verified_completers(
        route_id=str(route.id), limit=2, cursor=None, current_user=owner,
    ))
    assert len(page1["data"]) == 2
    assert page1["meta"]["nextToken"] is not None

    page2 = _dump(await get_verified_completers(
        route_id=str(route.id), limit=2,
        cursor=page1["meta"]["nextToken"], current_user=owner,
    ))
    assert len(page2["data"]) == 2

    page3 = _dump(await get_verified_completers(
        route_id=str(route.id), limit=2,
        cursor=page2["meta"]["nextToken"], current_user=owner,
    ))
    assert len(page3["data"]) == 1
    assert page3["meta"]["nextToken"] is None

    ordered = [
        item["user"]["profileId"]
        for page in (page1, page2, page3)
        for item in page["data"]
    ]
    assert ordered == ["u0", "u1", "u2", "u3", "u4"]


async def test_private_route_non_owner_gets_403(mongo_db):
    owner = await _seed_user(profile_id="owner")
    other = await _seed_user(profile_id="other")
    route = await _seed_route(owner, visibility=Visibility.PRIVATE)

    with pytest.raises(HTTPException) as exc:
        await get_verified_completers(
            route_id=str(route.id), limit=20, cursor=None, current_user=other,
        )
    assert exc.value.status_code == 403


async def test_deleted_user_serialized_with_null_fields(mongo_db):
    owner = await _seed_user(profile_id="owner")
    gone = await _seed_user(profile_id="gone", is_deleted=True)
    route = await _seed_route(owner)
    await _seed_urs(
        user=gone, route=route, verified_count=3,
        last_activity_at=datetime(2026, 4, 20, 10, 0, tzinfo=dt_tz.utc),
    )

    resp = await get_verified_completers(
        route_id=str(route.id), limit=20, cursor=None, current_user=owner,
    )
    entry = _dump(resp)["data"][0]
    assert entry["user"]["isDeleted"] is True
    assert entry["user"].get("profileId") is None
    assert entry["user"].get("profileImageUrl") is None


async def test_excludes_zero_verified_count_users(mongo_db):
    owner = await _seed_user(profile_id="owner")
    route = await _seed_route(owner)

    u1 = await _seed_user(profile_id="u1")
    u2 = await _seed_user(profile_id="u2")

    await UserRouteStats(
        user_id=u1.id, route_id=route.id,
        total_count=3, completed_count=0, verified_completed_count=0,
        last_activity_at=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    ).insert()
    await _seed_urs(
        user=u2, route=route, verified_count=1,
        last_activity_at=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    )

    resp = await get_verified_completers(
        route_id=str(route.id), limit=20, cursor=None, current_user=owner,
    )
    data = _dump(resp)["data"]
    assert [item["user"]["profileId"] for item in data] == ["u2"]
