"""Send FCM push notifications via HTTP v1 API using ADC.

The sender iterates all device tokens for a user, renders title/body in each
device's preferred locale, and POSTs to
`https://fcm.googleapis.com/v1/projects/{project_id}/messages:send`.

Error codes that indicate an invalidated token (UNREGISTERED,
INVALID_ARGUMENT, SENDER_ID_MISMATCH) cause the stale DeviceToken row to be
deleted so stale rows do not accumulate.
"""
import asyncio
import logging
from datetime import datetime, timedelta, timezone as _tz
from typing import Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import aiohttp
import google.auth
import google.auth.transport.requests
from beanie.odm.fields import PydanticObjectId

from app.core.config import get
from app.models.device_token import DeviceToken
from app.models.notification import Notification
from app.services.notification_renderer import render
from app.services.notification_templates import DEFAULT_LOCALE, SUPPORTED_LOCALES

logger = logging.getLogger(__name__)

_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_FCM_TIMEOUT = aiohttp.ClientTimeout(total=10)

CONSENT_TTL = timedelta(days=730)
_NIGHT_FALLBACK_TZ = "Asia/Seoul"

_credentials = None
_project_id: Optional[str] = None


def _is_night_hour_for_device(device, now: Optional[datetime] = None) -> bool:
    """True when the device's local hour falls in 21:00–07:59 (inclusive).

    Uses DeviceToken.timezone; falls back to Asia/Seoul when missing or
    unknown.
    """
    tz_name = getattr(device, "timezone", None) or _NIGHT_FALLBACK_TZ
    try:
        tz = ZoneInfo(tz_name)
    except ZoneInfoNotFoundError:
        tz = ZoneInfo(_NIGHT_FALLBACK_TZ)
    now = now or datetime.now(_tz.utc)
    local_hour = now.astimezone(tz).hour
    return local_hour >= 21 or local_hour < 8


def _is_consent_active(user, now: Optional[datetime] = None) -> bool:
    """True if the user currently has a valid marketing push consent.

    Valid when `marketing_push_consent` is True AND
    `marketing_push_consent_at` is present AND within CONSENT_TTL of `now`.
    """
    if user is None:
        return False
    if not getattr(user, "marketing_push_consent", False):
        return False
    consent_at = getattr(user, "marketing_push_consent_at", None)
    if consent_at is None:
        return False
    now = now or datetime.now(_tz.utc)
    return (now - consent_at) <= CONSENT_TTL


def _ensure_credentials() -> None:
    global _credentials, _project_id
    if _credentials is not None and _project_id is not None:
        return
    credentials, detected_project = google.auth.default(scopes=[_FCM_SCOPE])
    _credentials = credentials
    try:
        _project_id = get("firebase.project_id")
    except Exception:
        _project_id = detected_project


def _refresh_access_token() -> str:
    _ensure_credentials()
    assert _credentials is not None
    if not _credentials.valid:
        _credentials.refresh(google.auth.transport.requests.Request())
    return _credentials.token


def _primary_locale(raw: Optional[str]) -> str:
    if not raw:
        return DEFAULT_LOCALE
    primary = raw.split("-", 1)[0].split("_", 1)[0].lower()
    return primary if primary in SUPPORTED_LOCALES else DEFAULT_LOCALE


def _is_invalid_token_error(status: int, body_text: str) -> bool:
    if status == 404:
        return True
    if status == 400 and "INVALID_ARGUMENT" in body_text:
        return True
    if status == 403 and "SENDER_ID_MISMATCH" in body_text:
        return True
    return False


async def _send_one(
    session: aiohttp.ClientSession,
    project_id: str,
    access_token: str,
    device: DeviceToken,
    notif: Notification,
) -> None:
    title, body = render(notif, _primary_locale(device.locale))
    url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
    data_payload: dict[str, str] = {
        "type": notif.type,
        "notificationId": str(notif.id),
    }
    if notif.link:
        data_payload["link"] = notif.link
    payload = {
        "message": {
            "token": device.token,
            "notification": {"title": title, "body": body},
            "data": data_payload,
        }
    }
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json; charset=UTF-8",
    }
    try:
        async with session.post(url, json=payload, headers=headers) as resp:
            if resp.status == 200:
                return
            body_text = await resp.text()
            logger.warning(
                "FCM send failed status=%s token=%s body=%s",
                resp.status, device.token[:16], body_text,
            )
            if _is_invalid_token_error(resp.status, body_text):
                await DeviceToken.find_one(
                    DeviceToken.token == device.token
                ).delete()
    except Exception:
        logger.exception("FCM send exception token=%s", device.token[:16])


async def send_to_user(user_id: PydanticObjectId, notif: Notification) -> None:
    """Fan out a push notification to every device token of the given user."""
    try:
        devices = await DeviceToken.find(DeviceToken.user_id == user_id).to_list()
        if not devices:
            return
        _ensure_credentials()
        if not _project_id:
            logger.error("push_sender: FCM project_id unavailable")
            return
        loop = asyncio.get_running_loop()
        access_token = await loop.run_in_executor(None, _refresh_access_token)
        async with aiohttp.ClientSession(timeout=_FCM_TIMEOUT) as session:
            await asyncio.gather(
                *(
                    _send_one(session, _project_id, access_token, d, notif)
                    for d in devices
                ),
                return_exceptions=True,
            )
    except Exception:
        logger.exception(
            "push_sender.send_to_user failed user=%s notif=%s",
            user_id, getattr(notif, "id", None),
        )
