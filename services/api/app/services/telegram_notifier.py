"""Best-effort Telegram DM notifier for operator-facing server events.

All public functions swallow exceptions internally: callers do not need
try/except. Transient failures log at warning level; misconfiguration
(missing config keys) logs at error level. The originating HTTP request
is never affected.
"""
from __future__ import annotations

import logging

from aiohttp import ClientSession, ClientTimeout

from app.core import config

logger = logging.getLogger(__name__)

_TELEGRAM_API = "https://api.telegram.org"
_HTTP_TIMEOUT_S = 5


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
