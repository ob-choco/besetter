"""Best-effort Telegram DM notifier for operator-facing server events.

All public functions swallow exceptions internally: callers do not need
try/except. Transient failures log at warning level; misconfiguration
(missing config keys) logs at error level. The originating HTTP request
is never affected.
"""
from __future__ import annotations

import logging
from datetime import datetime
from html import escape as _html_escape
from typing import Any

from aiohttp import ClientSession, ClientTimeout
import pytz

from app.core import config

logger = logging.getLogger(__name__)

_TELEGRAM_API = "https://api.telegram.org"
_HTTP_TIMEOUT_S = 5
_KST = pytz.timezone("Asia/Seoul")


async def _send(text: str) -> None:
    """POST sendMessage to Telegram. Swallow every failure."""
    try:
        token = config.get("telegram.bot_token")
        chat_id = config.get("telegram.chat_id")
    except ValueError as exc:
        logger.error("telegram config missing: %s", exc)
        return

    url = f"{_TELEGRAM_API}/bot{token}/sendMessage"
    body = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }

    try:
        async with ClientSession(timeout=ClientTimeout(total=_HTTP_TIMEOUT_S)) as session:
            async with session.post(url, json=body) as resp:
                if not (200 <= resp.status < 300):
                    response_text = await resp.text()
                    logger.warning(
                        "telegram send failed: status=%s body=%s",
                        resp.status,
                        response_text[:500],
                    )
                    return
                data = await resp.json()
                if not data.get("ok"):
                    logger.warning(
                        "telegram send failed: ok=false description=%s",
                        data.get("description"),
                    )
    except Exception as exc:
        logger.warning("telegram notify error: %s", exc, exc_info=True)


def _fmt_kst(dt: datetime | None) -> str:
    if dt is None:
        return "—"
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=pytz.UTC)
    return dt.astimezone(_KST).strftime("%Y-%m-%d %H:%M")


def _val(x: Any) -> str:
    if x is None:
        return "—"
    if isinstance(x, str) and not x.strip():
        return "—"
    return _html_escape(str(x))


def _coord_line(lat: Any, lng: Any) -> str:
    if lat is None and lng is None:
        return "—"
    return f"{_val(lat)}, {_val(lng)}"


def _build_signup_text(user: Any, provider: str) -> str:
    return (
        "🆕 <b>새 유저 가입</b>\n"
        f"이름: {_val(getattr(user, 'name', None))}\n"
        f"이메일: {_val(getattr(user, 'email', None))}\n"
        f"Provider: {_val(provider)}\n"
        f"Profile ID: {_val(getattr(user, 'profile_id', None))}\n"
        f"가입 시각: {_fmt_kst(getattr(user, 'created_at', None))}"
    )


def _build_place_request_text(place: Any, requester: Any) -> str:
    return (
        "📍 <b>장소 등록 요청</b>\n"
        f"장소: {_val(getattr(place, 'name', None))}\n"
        f"좌표: {_coord_line(getattr(place, 'latitude', None), getattr(place, 'longitude', None))}\n"
        f"Place ID: {_val(getattr(place, 'id', None))}\n"
        f"요청자: {_val(getattr(requester, 'name', None))} ({_val(getattr(requester, 'profile_id', None))})\n"
        f"커버: {_val(getattr(place, 'cover_image_url', None))}"
    )
