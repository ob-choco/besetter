"""Tests for DELETE /images/{image_id} and its _soft_delete_image helper."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz

import pytest
import pytest_asyncio
from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from bson import ObjectId
from mongomock_motor import AsyncMongoMockClient

from app.models.image import Image, ImageMetadata
from app.routers.images import ImageDeleteOutcome, _soft_delete_image


pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient()
    db = client.get_database("besetter-test")
    await init_beanie(database=db, document_models=[Image])
    yield db


def _make_image(
    *,
    user_id: PydanticObjectId,
    route_count: int = 0,
    is_deleted: bool = False,
) -> Image:
    return Image(
        url="https://example.com/x.jpg",
        filename="x.jpg",
        metadata=ImageMetadata(),
        user_id=user_id,
        uploaded_at=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
        route_count=route_count,
        is_deleted=is_deleted,
    )


async def test_soft_delete_flips_flag_and_returns_deleted(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id)
    await image.insert()

    now = datetime(2026, 4, 20, 12, 0, tzinfo=dt_tz.utc)
    outcome = await _soft_delete_image(
        image.id, user_id, confirm=False, now=now
    )

    assert outcome == ImageDeleteOutcome(status="deleted", route_count=0)

    refreshed = await Image.get(image.id)
    assert refreshed.is_deleted is True
    assert refreshed.deleted_at.replace(tzinfo=dt_tz.utc) == now
