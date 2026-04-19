"""Tests for the Image.routeCount inline `$inc` helper in routes.py."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz
from unittest.mock import AsyncMock, patch

import pytest
import pytest_asyncio
from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from mongomock_motor import AsyncMongoMockClient

from app.models.image import Image, ImageMetadata
from app.routers.routes import _inc_image_route_count


pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient()
    db = client.get_database("besetter-test")
    await init_beanie(database=db, document_models=[Image])
    yield db


def _make_image(route_count: int = 0) -> Image:
    return Image(
        url="https://example.com/x.jpg",
        filename="x.jpg",
        metadata=ImageMetadata(),
        user_id=PydanticObjectId(),
        uploaded_at=datetime(2026, 4, 18, tzinfo=dt_tz.utc),
        route_count=route_count,
    )


async def test_inc_image_route_count_increments(mongo_db):
    image = _make_image()
    await image.insert()

    await _inc_image_route_count(image.id, 1)

    refreshed = await Image.get(image.id)
    assert refreshed.route_count == 1


async def test_inc_image_route_count_decrements(mongo_db):
    image = _make_image(route_count=3)
    await image.insert()

    await _inc_image_route_count(image.id, -1)

    refreshed = await Image.get(image.id)
    assert refreshed.route_count == 2


async def test_inc_image_route_count_on_missing_image_is_noop(mongo_db):
    # update_one on a non-existent _id is a silent no-op; must not raise.
    await _inc_image_route_count(PydanticObjectId(), 1)


async def test_inc_image_route_count_swallows_inner_errors(mongo_db, caplog):
    image = _make_image()
    await image.insert()

    failing = AsyncMock(side_effect=RuntimeError("boom"))
    with patch.object(Image.get_pymongo_collection(), "update_one", failing):
        result = await _inc_image_route_count(image.id, 1)

    assert result is None
    assert any("inc image.routeCount failed" in rec.message for rec in caplog.records)
