"""Tests for DELETE /images/{image_id} and its _soft_delete_image helper."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz
from unittest.mock import MagicMock

import pytest
import pytest_asyncio
from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from bson import ObjectId
from fastapi import HTTPException
from mongomock_motor import AsyncMongoMockClient

from app.models.image import Image, ImageMetadata
from app.routers.images import ImageDeleteOutcome, _soft_delete_image, delete_image


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


async def test_soft_delete_returns_not_found_when_image_missing(mongo_db):
    user_id = PydanticObjectId()
    nonexistent = ObjectId()

    outcome = await _soft_delete_image(
        nonexistent,
        user_id,
        confirm=False,
        now=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    )

    assert outcome == ImageDeleteOutcome(status="not_found")


async def test_soft_delete_returns_not_found_for_other_users_image(mongo_db):
    owner_id = PydanticObjectId()
    other_id = PydanticObjectId()
    image = _make_image(user_id=owner_id)
    await image.insert()

    outcome = await _soft_delete_image(
        image.id,
        other_id,
        confirm=False,
        now=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    )

    assert outcome == ImageDeleteOutcome(status="not_found")
    refreshed = await Image.get(image.id)
    assert refreshed.is_deleted is False


async def test_soft_delete_returns_not_found_when_already_deleted(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id, is_deleted=True)
    await image.insert()

    outcome = await _soft_delete_image(
        image.id,
        user_id,
        confirm=False,
        now=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    )

    assert outcome == ImageDeleteOutcome(status="not_found")


async def test_soft_delete_requires_confirmation_when_routes_exist(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id, route_count=3)
    await image.insert()

    outcome = await _soft_delete_image(
        image.id,
        user_id,
        confirm=False,
        now=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    )

    assert outcome == ImageDeleteOutcome(
        status="needs_confirmation", route_count=3
    )

    refreshed = await Image.get(image.id)
    assert refreshed.is_deleted is False
    assert refreshed.deleted_at is None


async def test_soft_delete_proceeds_with_confirm_true_when_routes_exist(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id, route_count=3)
    await image.insert()

    now = datetime(2026, 4, 20, 9, 0, tzinfo=dt_tz.utc)
    outcome = await _soft_delete_image(
        image.id,
        user_id,
        confirm=True,
        now=now,
    )

    assert outcome == ImageDeleteOutcome(status="deleted", route_count=0)

    refreshed = await Image.get(image.id)
    assert refreshed.is_deleted is True
    assert refreshed.deleted_at.replace(tzinfo=dt_tz.utc) == now
    assert refreshed.route_count == 3  # confirm does not touch route_count


def _mock_user(user_id: PydanticObjectId) -> MagicMock:
    user = MagicMock()
    user.id = user_id
    return user


async def test_delete_image_endpoint_returns_none_on_success(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id)
    await image.insert()

    result = await delete_image(
        image_id=str(image.id),
        confirm=False,
        current_user=_mock_user(user_id),
    )

    assert result is None
    refreshed = await Image.get(image.id)
    assert refreshed.is_deleted is True


async def test_delete_image_endpoint_raises_400_on_bad_object_id(mongo_db):
    user_id = PydanticObjectId()

    with pytest.raises(HTTPException) as exc_info:
        await delete_image(
            image_id="not-a-valid-object-id",
            confirm=False,
            current_user=_mock_user(user_id),
        )

    assert exc_info.value.status_code == 400


async def test_delete_image_endpoint_raises_404_when_missing(mongo_db):
    user_id = PydanticObjectId()

    with pytest.raises(HTTPException) as exc_info:
        await delete_image(
            image_id=str(ObjectId()),
            confirm=False,
            current_user=_mock_user(user_id),
        )

    assert exc_info.value.status_code == 404


async def test_delete_image_endpoint_raises_409_with_route_count(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id, route_count=5)
    await image.insert()

    with pytest.raises(HTTPException) as exc_info:
        await delete_image(
            image_id=str(image.id),
            confirm=False,
            current_user=_mock_user(user_id),
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == {
        "code": "IMAGE_HAS_ROUTES",
        "route_count": 5,
    }
