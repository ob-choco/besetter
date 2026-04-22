"""Verify public notify_* functions build the correct text and delegate to _send."""
from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest

from app.services import telegram_notifier


def _user():
    return SimpleNamespace(
        name="Alice",
        email="a@example.com",
        profile_id="alice",
        created_at=datetime(2026, 4, 23, 5, 30, tzinfo=timezone.utc),
    )


def _place():
    return SimpleNamespace(
        id="p1",
        name="Gym",
        latitude=1.0,
        longitude=2.0,
        cover_image_url=None,
    )


def _requester():
    return SimpleNamespace(name="R", profile_id="r1")


@pytest.mark.asyncio
async def test_notify_new_user_calls_send_with_signup_text():
    send_mock = AsyncMock()
    with patch.object(telegram_notifier, "_send", send_mock):
        await telegram_notifier.notify_new_user(_user(), provider="line")

    send_mock.assert_awaited_once()
    sent_text = send_mock.await_args.args[0]
    assert "새 유저 가입" in sent_text
    assert "Provider: line" in sent_text


@pytest.mark.asyncio
async def test_notify_place_registration_request_calls_send():
    send_mock = AsyncMock()
    with patch.object(telegram_notifier, "_send", send_mock):
        await telegram_notifier.notify_place_registration_request(_place(), _requester())

    send_mock.assert_awaited_once()
    sent_text = send_mock.await_args.args[0]
    assert "장소 등록 요청" in sent_text
    assert "Place ID: p1" in sent_text


@pytest.mark.asyncio
async def test_notify_place_improvement_request_calls_send():
    send_mock = AsyncMock()
    changes = SimpleNamespace(name="N", latitude=None, longitude=None, cover_image_url=None)
    sugg = SimpleNamespace(id="s1", changes=changes)

    with patch.object(telegram_notifier, "_send", send_mock):
        await telegram_notifier.notify_place_improvement_request(sugg, _place(), _requester())

    send_mock.assert_awaited_once()
    sent_text = send_mock.await_args.args[0]
    assert "장소 개선 요청" in sent_text
    assert "Suggestion ID: s1" in sent_text


@pytest.mark.asyncio
async def test_notify_new_user_swallows_builder_exception(caplog):
    """If the builder itself raises (bad input), still don't propagate."""
    import logging

    with caplog.at_level(logging.WARNING, logger="app.services.telegram_notifier"), \
         patch.object(telegram_notifier, "_build_signup_text", side_effect=RuntimeError("bad")):
        await telegram_notifier.notify_new_user(_user(), provider="line")

    assert any("telegram notify error" in rec.message for rec in caplog.records)
