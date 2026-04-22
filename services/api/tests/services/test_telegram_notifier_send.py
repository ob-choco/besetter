"""Unit tests for telegram_notifier._send — no real network calls."""
from __future__ import annotations

import logging
from unittest.mock import AsyncMock, MagicMock, patch

import aiohttp
import pytest


@pytest.mark.asyncio
async def test_send_success_calls_sendmessage_with_expected_body():
    from app.services import telegram_notifier

    mock_resp = MagicMock()
    mock_resp.status = 200
    mock_resp.json = AsyncMock(return_value={"ok": True, "result": {}})
    mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
    mock_resp.__aexit__ = AsyncMock(return_value=False)

    mock_session = MagicMock()
    mock_session.post = MagicMock(return_value=mock_resp)
    mock_session.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session.__aexit__ = AsyncMock(return_value=False)

    def fake_config_get(key: str):
        return {"telegram.bot_token": "TOKEN", "telegram.chat_id": "CHAT"}[key]

    with patch.object(telegram_notifier, "ClientSession", return_value=mock_session), \
         patch.object(telegram_notifier.config, "get", side_effect=fake_config_get):
        await telegram_notifier._send("hello")

    mock_session.post.assert_called_once()
    args, kwargs = mock_session.post.call_args
    assert args[0] == "https://api.telegram.org/botTOKEN/sendMessage"
    assert kwargs["json"] == {
        "chat_id": "CHAT",
        "text": "hello",
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }


@pytest.mark.asyncio
async def test_send_non_2xx_logs_warning_and_swallows(caplog):
    from app.services import telegram_notifier

    mock_resp = MagicMock()
    mock_resp.status = 500
    mock_resp.text = AsyncMock(return_value="oops")
    mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
    mock_resp.__aexit__ = AsyncMock(return_value=False)

    mock_session = MagicMock()
    mock_session.post = MagicMock(return_value=mock_resp)
    mock_session.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session.__aexit__ = AsyncMock(return_value=False)

    def fake_config_get(key: str):
        return {"telegram.bot_token": "T", "telegram.chat_id": "C"}[key]

    with caplog.at_level(logging.WARNING, logger="app.services.telegram_notifier"), \
         patch.object(telegram_notifier, "ClientSession", return_value=mock_session), \
         patch.object(telegram_notifier.config, "get", side_effect=fake_config_get):
        await telegram_notifier._send("x")

    assert any("telegram send failed" in rec.message for rec in caplog.records)


@pytest.mark.asyncio
async def test_send_ok_false_response_logs_warning(caplog):
    from app.services import telegram_notifier

    mock_resp = MagicMock()
    mock_resp.status = 200
    mock_resp.json = AsyncMock(return_value={"ok": False, "description": "bad"})
    mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
    mock_resp.__aexit__ = AsyncMock(return_value=False)

    mock_session = MagicMock()
    mock_session.post = MagicMock(return_value=mock_resp)
    mock_session.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session.__aexit__ = AsyncMock(return_value=False)

    def fake_config_get(key: str):
        return {"telegram.bot_token": "T", "telegram.chat_id": "C"}[key]

    with caplog.at_level(logging.WARNING, logger="app.services.telegram_notifier"), \
         patch.object(telegram_notifier, "ClientSession", return_value=mock_session), \
         patch.object(telegram_notifier.config, "get", side_effect=fake_config_get):
        await telegram_notifier._send("x")

    assert any("telegram send failed" in rec.message for rec in caplog.records)


@pytest.mark.asyncio
async def test_send_client_error_is_swallowed(caplog):
    from app.services import telegram_notifier

    def raise_client_error(*a, **kw):
        raise aiohttp.ClientError("boom")

    mock_session = MagicMock()
    mock_session.post = MagicMock(side_effect=raise_client_error)
    mock_session.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session.__aexit__ = AsyncMock(return_value=False)

    def fake_config_get(key: str):
        return {"telegram.bot_token": "T", "telegram.chat_id": "C"}[key]

    with caplog.at_level(logging.WARNING, logger="app.services.telegram_notifier"), \
         patch.object(telegram_notifier, "ClientSession", return_value=mock_session), \
         patch.object(telegram_notifier.config, "get", side_effect=fake_config_get):
        await telegram_notifier._send("x")  # must not raise

    assert any("telegram notify error" in rec.message for rec in caplog.records)


@pytest.mark.asyncio
async def test_send_missing_config_logs_error_and_does_not_call_http(caplog):
    from app.services import telegram_notifier

    def raise_missing(key: str):
        raise ValueError(f"Could not find key '{key}' in settings.")

    mock_session_ctor = MagicMock()

    with caplog.at_level(logging.ERROR, logger="app.services.telegram_notifier"), \
         patch.object(telegram_notifier, "ClientSession", mock_session_ctor), \
         patch.object(telegram_notifier.config, "get", side_effect=raise_missing):
        await telegram_notifier._send("x")

    mock_session_ctor.assert_not_called()
    assert any("telegram config missing" in rec.message for rec in caplog.records)
