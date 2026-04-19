"""Tests for the Image.routeCount backfill script."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz

import pytest
from beanie.odm.fields import PydanticObjectId

from app.models.image import Image, ImageMetadata
from app.models.route import Route, RouteType, Visibility
from scripts.backfill_image_route_count import backfill_all, backfill_image


pytestmark = pytest.mark.asyncio


def _make_image(user_id: PydanticObjectId, *, route_count: int = 0) -> Image:
    return Image(
        url="https://example.com/x.jpg",
        filename="x.jpg",
        metadata=ImageMetadata(),
        user_id=user_id,
        uploaded_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc),
        route_count=route_count,
    )


def _make_route(user_id: PydanticObjectId, image_id: PydanticObjectId, *, is_deleted: bool = False) -> Route:
    return Route(
        type=RouteType.BOULDERING,
        grade_type="v_scale",
        grade="V1",
        visibility=Visibility.PUBLIC,
        image_id=image_id,
        hold_polygon_id=PydanticObjectId(),
        user_id=user_id,
        image_url="https://example.com/x.jpg",
        is_deleted=is_deleted,
    )


async def test_backfill_image_counts_only_active_routes(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id)
    await image.insert()

    # 2 alive + 1 soft-deleted on this image
    for _ in range(2):
        await _make_route(user_id, image.id).insert()
    await _make_route(user_id, image.id, is_deleted=True).insert()

    count = await backfill_image(image.id)
    assert count == 2

    refreshed = await Image.get(image.id)
    assert refreshed.route_count == 2


async def test_backfill_all_zeroes_orphan_and_aggregates(mongo_db):
    user_id = PydanticObjectId()
    # Image A has 3 alive routes; start with a stale routeCount of 999
    image_a = _make_image(user_id, route_count=999)
    # Image B has 0 alive (one soft-deleted) routes; stale routeCount 5
    image_b = _make_image(user_id, route_count=5)
    await image_a.insert()
    await image_b.insert()
    for _ in range(3):
        await _make_route(user_id, image_a.id).insert()
    await _make_route(user_id, image_b.id, is_deleted=True).insert()

    await backfill_all()

    assert (await Image.get(image_a.id)).route_count == 3
    assert (await Image.get(image_b.id)).route_count == 0


async def test_backfill_all_is_idempotent(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id)
    await image.insert()
    for _ in range(4):
        await _make_route(user_id, image.id).insert()

    await backfill_all()
    first = (await Image.get(image.id)).route_count
    await backfill_all()
    second = (await Image.get(image.id)).route_count

    assert first == second == 4
