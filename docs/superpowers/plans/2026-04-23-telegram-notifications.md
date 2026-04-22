# Telegram Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Send Telegram DM alerts to the operator on three key server events — new user signup, new gym registration request, and place improvement request — using a best-effort, fire-and-forget background task.

**Architecture:** Add a thin `telegram_notifier` service module in `services/api/app/services/`. The module exposes three domain-typed public functions (`notify_new_user`, `notify_place_registration_request`, `notify_place_improvement_request`). Each router that handles one of the target events schedules the notification via `BackgroundTasks` after the primary write succeeds. All failures are swallowed inside the notifier and logged with `logger.warning` — they never propagate to HTTP responses.

**Tech Stack:** Python 3.10+, FastAPI, aiohttp, pytest / pytest-asyncio, Beanie (MongoDB ODM), pytz. Config loaded via existing `app.core.config.get`.

**Spec reference:** `docs/superpowers/specs/2026-04-23-telegram-notifications-design.md`

---

## Task 1: Create notifier module skeleton with `_send`

**Files:**
- Create: `services/api/app/services/telegram_notifier.py`
- Test: `services/api/tests/services/test_telegram_notifier_send.py`

- [ ] **Step 1: Write the failing test file**

Create `services/api/tests/services/test_telegram_notifier_send.py`:

```python
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
```

- [ ] **Step 2: Run tests — expect ImportError / module-not-found**

Run: `cd services/api && uv run pytest tests/services/test_telegram_notifier_send.py -v`
Expected: all tests fail because `app.services.telegram_notifier` does not yet exist.

- [ ] **Step 3: Create the module with minimal `_send`**

Create `services/api/app/services/telegram_notifier.py`:

```python
"""Best-effort Telegram DM notifier for operator-facing server events.

All public functions swallow exceptions internally: callers do not need
try/except. Failures are logged with logger.warning and the originating
HTTP request is never affected.
"""
from __future__ import annotations

import asyncio
import logging

import aiohttp
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
                if resp.status != 200:
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
    except (aiohttp.ClientError, asyncio.TimeoutError, Exception) as exc:
        logger.warning("telegram notify error: %s", exc, exc_info=True)
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd services/api && uv run pytest tests/services/test_telegram_notifier_send.py -v`
Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/services/telegram_notifier.py \
        services/api/tests/services/test_telegram_notifier_send.py
git commit -m "feat(api): add telegram_notifier module with best-effort _send"
```

---

## Task 2: Message builder for signup

**Files:**
- Modify: `services/api/app/services/telegram_notifier.py`
- Create: `services/api/tests/services/test_telegram_notifier_messages.py`

- [ ] **Step 1: Write failing tests for `_build_signup_text`**

Create `services/api/tests/services/test_telegram_notifier_messages.py`:

```python
"""Pure-function tests for telegram_notifier message builders."""
from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace

from app.services.telegram_notifier import _build_signup_text


def _make_user(**overrides):
    defaults = dict(
        name="Alice",
        email="alice@example.com",
        profile_id="alice123",
        created_at=datetime(2026, 4, 23, 5, 30, tzinfo=timezone.utc),  # 14:30 KST
    )
    defaults.update(overrides)
    return SimpleNamespace(**defaults)


def test_build_signup_text_line_provider():
    user = _make_user()
    text = _build_signup_text(user, provider="line")
    assert "🆕 <b>새 유저 가입</b>" in text
    assert "이름: Alice" in text
    assert "이메일: alice@example.com" in text
    assert "Provider: line" in text
    assert "Profile ID: alice123" in text
    assert "2026-04-23 14:30" in text


def test_build_signup_text_missing_name_renders_dash():
    user = _make_user(name=None)
    text = _build_signup_text(user, provider="apple")
    assert "이름: —" in text


def test_build_signup_text_missing_email_renders_dash():
    user = _make_user(email=None)
    text = _build_signup_text(user, provider="apple")
    assert "이메일: —" in text


def test_build_signup_text_html_escapes_user_fields():
    user = _make_user(name="<Alice & Co>")
    text = _build_signup_text(user, provider="line")
    assert "&lt;Alice &amp; Co&gt;" in text
    assert "<Alice & Co>" not in text


def test_build_signup_text_includes_each_of_four_providers():
    for provider in ("line", "kakao", "apple", "google"):
        text = _build_signup_text(_make_user(), provider=provider)
        assert f"Provider: {provider}" in text
```

- [ ] **Step 2: Run tests — expect fail (function not defined)**

Run: `cd services/api && uv run pytest tests/services/test_telegram_notifier_messages.py -v`
Expected: ImportError on `_build_signup_text`.

- [ ] **Step 3: Add `_build_signup_text` and helpers**

Append to `services/api/app/services/telegram_notifier.py`:

```python
from datetime import datetime
from html import escape as _html_escape
from typing import Any

import pytz

_KST = pytz.timezone("Asia/Seoul")


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


def _build_signup_text(user: Any, provider: str) -> str:
    return (
        "🆕 <b>새 유저 가입</b>\n"
        f"이름: {_val(getattr(user, 'name', None))}\n"
        f"이메일: {_val(getattr(user, 'email', None))}\n"
        f"Provider: {_val(provider)}\n"
        f"Profile ID: {_val(getattr(user, 'profile_id', None))}\n"
        f"가입 시각: {_fmt_kst(getattr(user, 'created_at', None))}"
    )
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd services/api && uv run pytest tests/services/test_telegram_notifier_messages.py -v`
Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/services/telegram_notifier.py \
        services/api/tests/services/test_telegram_notifier_messages.py
git commit -m "feat(api): add signup message builder for telegram_notifier"
```

---

## Task 3: Message builder for new gym registration request

**Files:**
- Modify: `services/api/app/services/telegram_notifier.py`
- Modify: `services/api/tests/services/test_telegram_notifier_messages.py`

- [ ] **Step 1: Write failing tests for `_build_place_request_text`**

Append to `services/api/tests/services/test_telegram_notifier_messages.py`:

```python
from app.services.telegram_notifier import _build_place_request_text


def _make_place(**overrides):
    defaults = dict(
        id="place-abc",
        name="Climbing Park",
        latitude=37.1234,
        longitude=127.5678,
        cover_image_url="https://example.com/cover.jpg",
    )
    defaults.update(overrides)
    return SimpleNamespace(**defaults)


def _make_requester(name="Requester", profile_id="req123"):
    return SimpleNamespace(name=name, profile_id=profile_id)


def test_build_place_request_text_full():
    text = _build_place_request_text(_make_place(), _make_requester())
    assert "📍 <b>장소 등록 요청</b>" in text
    assert "장소: Climbing Park" in text
    assert "좌표: 37.1234, 127.5678" in text
    assert "Place ID: place-abc" in text
    assert "요청자: Requester (req123)" in text
    assert "커버: https://example.com/cover.jpg" in text


def test_build_place_request_text_without_cover():
    place = _make_place(cover_image_url=None)
    text = _build_place_request_text(place, _make_requester())
    assert "커버: —" in text


def test_build_place_request_text_escapes_place_name():
    place = _make_place(name="<Evil> & Gym")
    text = _build_place_request_text(place, _make_requester())
    assert "&lt;Evil&gt; &amp; Gym" in text
```

- [ ] **Step 2: Run new tests — expect fail**

Run: `cd services/api && uv run pytest tests/services/test_telegram_notifier_messages.py -v -k place_request`
Expected: ImportError for `_build_place_request_text`.

- [ ] **Step 3: Add `_build_place_request_text`**

Append to `services/api/app/services/telegram_notifier.py`:

```python
def _coord_line(lat: Any, lng: Any) -> str:
    if lat is None and lng is None:
        return "—"
    return f"{_val(lat)}, {_val(lng)}"


def _build_place_request_text(place: Any, requester: Any) -> str:
    return (
        "📍 <b>장소 등록 요청</b>\n"
        f"장소: {_val(getattr(place, 'name', None))}\n"
        f"좌표: {_coord_line(getattr(place, 'latitude', None), getattr(place, 'longitude', None))}\n"
        f"Place ID: {_val(getattr(place, 'id', None))}\n"
        f"요청자: {_val(getattr(requester, 'name', None))} ({_val(getattr(requester, 'profile_id', None))})\n"
        f"커버: {_val(getattr(place, 'cover_image_url', None))}"
    )
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd services/api && uv run pytest tests/services/test_telegram_notifier_messages.py -v`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/services/telegram_notifier.py \
        services/api/tests/services/test_telegram_notifier_messages.py
git commit -m "feat(api): add place-registration message builder for telegram_notifier"
```

---

## Task 4: Message builder for place improvement request

**Files:**
- Modify: `services/api/app/services/telegram_notifier.py`
- Modify: `services/api/tests/services/test_telegram_notifier_messages.py`

- [ ] **Step 1: Write failing tests for `_build_suggestion_text`**

Append to `services/api/tests/services/test_telegram_notifier_messages.py`:

```python
from app.services.telegram_notifier import _build_suggestion_text


def _make_changes(**overrides):
    defaults = dict(
        name=None,
        latitude=None,
        longitude=None,
        cover_image_url=None,
    )
    defaults.update(overrides)
    return SimpleNamespace(**defaults)


def _make_suggestion(changes):
    return SimpleNamespace(id="sugg-xyz", changes=changes)


def test_build_suggestion_text_name_only():
    sugg = _make_suggestion(_make_changes(name="New Name"))
    text = _build_suggestion_text(sugg, _make_place(), _make_requester())
    assert "✏️ <b>장소 개선 요청</b>" in text
    assert "장소: Climbing Park (place-abc)" in text
    assert "이름: New Name" in text
    assert "좌표: —" in text
    assert "이미지: —" in text
    assert "요청자: Requester (req123)" in text
    assert "Suggestion ID: sugg-xyz" in text


def test_build_suggestion_text_coords_both_set():
    sugg = _make_suggestion(_make_changes(latitude=10.0, longitude=20.0))
    text = _build_suggestion_text(sugg, _make_place(), _make_requester())
    assert "좌표: 10.0, 20.0" in text


def test_build_suggestion_text_coords_one_missing_still_renders():
    sugg = _make_suggestion(_make_changes(latitude=10.0))
    text = _build_suggestion_text(sugg, _make_place(), _make_requester())
    assert "좌표: 10.0, —" in text


def test_build_suggestion_text_image_only():
    sugg = _make_suggestion(_make_changes(cover_image_url="https://example.com/x.jpg"))
    text = _build_suggestion_text(sugg, _make_place(), _make_requester())
    assert "이미지: https://example.com/x.jpg" in text
```

- [ ] **Step 2: Run new tests — expect fail**

Run: `cd services/api && uv run pytest tests/services/test_telegram_notifier_messages.py -v -k suggestion`
Expected: ImportError for `_build_suggestion_text`.

- [ ] **Step 3: Add `_build_suggestion_text`**

Append to `services/api/app/services/telegram_notifier.py`:

```python
def _build_suggestion_text(suggestion: Any, place: Any, requester: Any) -> str:
    changes = getattr(suggestion, "changes", None)
    c_name = getattr(changes, "name", None)
    c_lat = getattr(changes, "latitude", None)
    c_lng = getattr(changes, "longitude", None)
    c_img = getattr(changes, "cover_image_url", None)

    return (
        "✏️ <b>장소 개선 요청</b>\n"
        f"장소: {_val(getattr(place, 'name', None))} ({_val(getattr(place, 'id', None))})\n"
        "변경 제안:\n"
        f"  • 이름: {_val(c_name)}\n"
        f"  • 좌표: {_coord_line(c_lat, c_lng)}\n"
        f"  • 이미지: {_val(c_img)}\n"
        f"요청자: {_val(getattr(requester, 'name', None))} ({_val(getattr(requester, 'profile_id', None))})\n"
        f"Suggestion ID: {_val(getattr(suggestion, 'id', None))}"
    )
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd services/api && uv run pytest tests/services/test_telegram_notifier_messages.py -v`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/services/telegram_notifier.py \
        services/api/tests/services/test_telegram_notifier_messages.py
git commit -m "feat(api): add suggestion message builder for telegram_notifier"
```

---

## Task 5: Public notify wrappers

**Files:**
- Modify: `services/api/app/services/telegram_notifier.py`
- Create: `services/api/tests/services/test_telegram_notifier_notify.py`

- [ ] **Step 1: Write failing tests for the three public wrappers**

Create `services/api/tests/services/test_telegram_notifier_notify.py`:

```python
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
```

- [ ] **Step 2: Run tests — expect fail**

Run: `cd services/api && uv run pytest tests/services/test_telegram_notifier_notify.py -v`
Expected: AttributeError / not-defined for `notify_new_user`, etc.

- [ ] **Step 3: Add the three public wrappers**

Append to `services/api/app/services/telegram_notifier.py`:

```python
async def notify_new_user(user: Any, provider: str) -> None:
    """Send a Telegram alert for a new signup. Best-effort."""
    try:
        text = _build_signup_text(user, provider)
    except Exception as exc:
        logger.warning("telegram notify error: %s", exc, exc_info=True)
        return
    await _send(text)


async def notify_place_registration_request(place: Any, requester: Any) -> None:
    """Send a Telegram alert for a new gym registration request. Best-effort."""
    try:
        text = _build_place_request_text(place, requester)
    except Exception as exc:
        logger.warning("telegram notify error: %s", exc, exc_info=True)
        return
    await _send(text)


async def notify_place_improvement_request(suggestion: Any, place: Any, requester: Any) -> None:
    """Send a Telegram alert for a place improvement suggestion. Best-effort."""
    try:
        text = _build_suggestion_text(suggestion, place, requester)
    except Exception as exc:
        logger.warning("telegram notify error: %s", exc, exc_info=True)
        return
    await _send(text)
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd services/api && uv run pytest tests/services/test_telegram_notifier_notify.py -v`
Expected: all 4 tests pass.

- [ ] **Step 5: Run full notifier test suite**

Run: `cd services/api && uv run pytest tests/services/test_telegram_notifier_messages.py tests/services/test_telegram_notifier_send.py tests/services/test_telegram_notifier_notify.py -v`
Expected: every test passes.

- [ ] **Step 6: Commit**

```bash
git add services/api/app/services/telegram_notifier.py \
        services/api/tests/services/test_telegram_notifier_notify.py
git commit -m "feat(api): add public notify_* wrappers on telegram_notifier"
```

---

## Task 6: Wire into `POST /places` (gym registration)

**Files:**
- Modify: `services/api/app/routers/places.py` (around the existing `if place.type == "gym":` block at approx. lines 183–209)

- [ ] **Step 1: Add the import**

Open `services/api/app/routers/places.py`. Near the other `app.services` imports (search for `from app.services import push_sender` or similar), add:

```python
from app.services import telegram_notifier
```

Keep it on its own line next to the other service imports. If imports are grouped, put it in the `app.services` group.

- [ ] **Step 2: Schedule the telegram notification for gym registration**

Inside the existing `if place.type == "gym":` block in `POST /`, **after** the existing `background_tasks.add_task(push_sender.send_to_user, ...)` call and its surrounding `try/except`, append:

```python
        background_tasks.add_task(
            telegram_notifier.notify_place_registration_request,
            place,
            current_user,
        )
```

The block should end with both the existing push-sender task and the new telegram task scheduled.

- [ ] **Step 3: Schedule the telegram notification for suggestions**

In `POST /suggestions`, **after** the existing best-effort `try/except` that enqueues the `place_suggestion_ack` notification (`background_tasks.add_task(push_sender.send_to_user, ...)`), append:

```python
    background_tasks.add_task(
        telegram_notifier.notify_place_improvement_request,
        created,
        place,
        current_user,
    )
```

- [ ] **Step 4: Run existing place tests — verify no regression**

Run: `cd services/api && uv run pytest tests/routers/test_places.py -v`
Expected: all pre-existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): telegram alerts on gym registration and suggestion requests"
```

---

## Task 7: Wire into all 4 signup endpoints

**Files:**
- Modify: `services/api/app/routers/authentications.py`

- [ ] **Step 1: Add imports**

Near the top of `services/api/app/routers/authentications.py`, with the other imports, add:

```python
from fastapi import BackgroundTasks
from app.services import telegram_notifier
```

`BackgroundTasks` goes next to the existing `fastapi` imports. `telegram_notifier` goes with other `app.services` imports if any, otherwise after the `app.core.config` import.

- [ ] **Step 2: Wire `POST /sign-up/line`**

In the `signup` function decorated with `@router.post("/sign-up/line", ...)`:

1. Add `background_tasks: BackgroundTasks,` as a parameter (insert it right after `credentials`).
2. After the existing `await user.save()`, before the `return SignInResponse(...)`, add:

```python
    background_tasks.add_task(telegram_notifier.notify_new_user, user, "line")
```

- [ ] **Step 3: Wire `POST /sign-up/kakao`**

Same change to the `signup` function decorated with `@router.post("/sign-up/kakao", ...)`:
- Add `background_tasks: BackgroundTasks,` parameter.
- After `await user.save()`:

```python
    background_tasks.add_task(telegram_notifier.notify_new_user, user, "kakao")
```

- [ ] **Step 4: Wire `POST /sign-up/apple`**

Same change to `signup_apple`:
- Add `background_tasks: BackgroundTasks,` parameter.
- After `await user.save()`:

```python
    background_tasks.add_task(telegram_notifier.notify_new_user, user, "apple")
```

- [ ] **Step 5: Wire `POST /sign-up/google`**

Same change to `signup_google`:
- Add `background_tasks: BackgroundTasks,` parameter.
- After `await user.save()`:

```python
    background_tasks.add_task(telegram_notifier.notify_new_user, user, "google")
```

- [ ] **Step 6: Verify existing authentications tests still pass**

Run: `cd services/api && uv run pytest tests/routers/test_authentications_signup_consent.py -v`
Expected: the signature-check tests still pass (they assert on body params, which we have not changed).

- [ ] **Step 7: Commit**

```bash
git add services/api/app/routers/authentications.py
git commit -m "feat(api): telegram alert on signup for all 4 providers"
```

---

## Task 8: Add `telegram` block to local `settings.yaml`

**Files:**
- Modify: `services/api/settings.yaml`

- [ ] **Step 1: Append the telegram block**

Add this section to the end of `services/api/settings.yaml` (keep it structurally consistent with the other top-level keys):

```yaml
telegram:
  bot_token: "<bot token — ask operator, or leave placeholder for local dev>"
  chat_id: "8502249947"
```

> If the bot token has been revoked per the design's operational note, replace the placeholder with the new token (or leave the old one for now if the operator hasn't rotated yet — the value is only used for local dev and will be overridden by Secret Manager in deployed environments).

- [ ] **Step 2: Sanity check — config can read the new keys**

Run a small smoke test from the services/api directory:

```bash
cd services/api && uv run python -c "
from yaml import safe_load
with open('settings.yaml') as f:
    data = safe_load(f)
assert 'telegram' in data, 'telegram block missing'
assert 'bot_token' in data['telegram'], 'bot_token missing'
assert 'chat_id' in data['telegram'], 'chat_id missing'
print('ok:', data['telegram']['chat_id'])
"
```

Expected: `ok: 8502249947`.

- [ ] **Step 3: Commit**

```bash
git add services/api/settings.yaml
git commit -m "chore(api): add telegram block to local settings.yaml"
```

---

## Task 9: Manual end-to-end verification

No code changes. This is the post-deploy verification checklist from the spec. Run these against the local API (or staging) and confirm the operator DM receives each message.

**Pre-conditions:**
- API running with the new `telegram` config loaded.
- `BesetterNotiBot` has been started by the operator (DM established — already confirmed during design).

- [ ] **Step 1: Signup alert — 4 providers**

Trigger one signup per provider (line / kakao / apple / google) via the mobile client or test scripts. Confirm 4 DMs received with:
- Correct provider label
- Name, email, profile_id, KST signup timestamp

- [ ] **Step 2: Gym registration alert**

Submit `POST /places` with `type="gym"` via the mobile client. Confirm DM received with the place name, coordinates, and requester info.

- [ ] **Step 3: Negative — private-gym does not alert**

Submit `POST /places` with `type="private-gym"`. Confirm **no** DM is sent (private-gym is auto-approved and not part of the review queue).

- [ ] **Step 4: Suggestion alert**

Submit `POST /places/suggestions` on an approved gym. Confirm DM received with the original place info, the proposed changes, and requester info.

- [ ] **Step 5: Final commit (optional)**

If the manual test raised any tweaks to message copy, apply them as a small follow-up commit. Otherwise nothing to commit here.

---

## Files Summary

Created:
- `services/api/app/services/telegram_notifier.py`
- `services/api/tests/services/test_telegram_notifier_send.py`
- `services/api/tests/services/test_telegram_notifier_messages.py`
- `services/api/tests/services/test_telegram_notifier_notify.py`

Modified:
- `services/api/app/routers/authentications.py` — 4 signup endpoints gain `BackgroundTasks` and a `notify_new_user` task.
- `services/api/app/routers/places.py` — `POST /` (gym branch) and `POST /suggestions` schedule telegram tasks.
- `services/api/settings.yaml` — new `telegram` block for local dev.

Config (external, already done):
- Secret Manager `api-secret` YAML has the `telegram` block.
