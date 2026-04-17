import pytest
from unittest.mock import AsyncMock, MagicMock

from bson import ObjectId
from fastapi import HTTPException


@pytest.mark.asyncio
async def test_approved_place_returns_itself():
    from app.services.place_status import resolve_place_for_use

    place = MagicMock(id=ObjectId(), name="X", status="approved",
                     created_by=ObjectId(), merged_into_place_id=None)
    user = MagicMock(id=ObjectId())
    result = await resolve_place_for_use(place, user)
    assert result is place


@pytest.mark.asyncio
async def test_own_pending_place_returns_itself():
    from app.services.place_status import resolve_place_for_use

    uid = ObjectId()
    place = MagicMock(id=ObjectId(), name="X", status="pending",
                     created_by=uid, merged_into_place_id=None)
    user = MagicMock(id=uid)
    result = await resolve_place_for_use(place, user)
    assert result is place


@pytest.mark.asyncio
async def test_foreign_pending_raises_409():
    from app.services.place_status import resolve_place_for_use

    place = MagicMock(id=ObjectId(), name="X", status="pending",
                     created_by=ObjectId(), merged_into_place_id=None)
    user = MagicMock(id=ObjectId())
    with pytest.raises(HTTPException) as exc:
        await resolve_place_for_use(place, user)
    assert exc.value.status_code == 409
    assert exc.value.detail["code"] == "PLACE_NOT_USABLE"
    assert exc.value.detail["place_status"] == "pending"


@pytest.mark.asyncio
async def test_rejected_raises_409():
    from app.services.place_status import resolve_place_for_use

    place = MagicMock(id=ObjectId(), name="X", status="rejected",
                     created_by=ObjectId(), merged_into_place_id=None)
    user = MagicMock(id=ObjectId())
    with pytest.raises(HTTPException) as exc:
        await resolve_place_for_use(place, user)
    assert exc.value.status_code == 409
    assert exc.value.detail["place_status"] == "rejected"


@pytest.mark.asyncio
async def test_merged_redirects_to_target(monkeypatch):
    from app.services import place_status as mod

    target_id = ObjectId()
    target = MagicMock(id=target_id, name="Target", status="approved",
                       created_by=ObjectId(), merged_into_place_id=None)
    get_mock = AsyncMock(return_value=target)
    monkeypatch.setattr(mod.Place, "get", get_mock)

    place = MagicMock(id=ObjectId(), name="Old", status="merged",
                     created_by=ObjectId(), merged_into_place_id=target_id)
    user = MagicMock(id=ObjectId())
    result = await mod.resolve_place_for_use(place, user)
    assert result is target
    get_mock.assert_awaited_once_with(target_id)


@pytest.mark.asyncio
async def test_merged_without_target_id_raises_409():
    from app.services.place_status import resolve_place_for_use

    place = MagicMock(id=ObjectId(), name="X", status="merged",
                     created_by=ObjectId(), merged_into_place_id=None)
    user = MagicMock(id=ObjectId())
    with pytest.raises(HTTPException) as exc:
        await resolve_place_for_use(place, user)
    assert exc.value.status_code == 409


@pytest.mark.asyncio
async def test_merged_chain_stops_at_one_hop(monkeypatch):
    """A→B where B is also merged: single-hop follow, then 409 (chain not followed)."""
    from app.services import place_status as mod

    b_id = ObjectId()
    b = MagicMock(id=b_id, name="B", status="merged",
                  created_by=ObjectId(), merged_into_place_id=ObjectId())
    monkeypatch.setattr(mod.Place, "get", AsyncMock(return_value=b))

    a = MagicMock(id=ObjectId(), name="A", status="merged",
                  created_by=ObjectId(), merged_into_place_id=b_id)
    user = MagicMock(id=ObjectId())
    with pytest.raises(HTTPException) as exc:
        await mod.resolve_place_for_use(a, user)
    assert exc.value.status_code == 409
