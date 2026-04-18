# Notification i18n Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render `/notifications` responses in the caller's language (ko/en/ja/es) via the `Accept-Language` header using code-defined templates, keyed by notification type, with snapshot params.

**Architecture:** Server reads `Accept-Language` on `GET /notifications`, picks a supported locale (fallback `ko`), and renders `title`/`body` from a typed template table using snapshot `params` (e.g. `place_name`). Existing records without `params` keep using their stored `title`/`body` (backwards compat fallback).

**Tech Stack:** FastAPI, Beanie/Pydantic, pytest; Flutter `http` package on mobile.

Reference design spec: `docs/superpowers/specs/2026-04-18-notification-i18n-design.md`.

---

## File Structure

**Create:**
- `services/api/app/services/notification_templates.py` — template dict, supported locales, default locale.
- `services/api/app/services/notification_renderer.py` — locale parser + `render(notif, locale)`.
- `services/api/tests/services/test_notification_renderer.py` — unit tests for the renderer.

**Modify:**
- `services/api/app/models/notification.py` — add `params: dict` field.
- `services/api/app/routers/notifications.py` — read `Accept-Language`, render in `list_notifications`.
- `services/api/app/routers/places.py` — two notification creation sites (lines ~156, ~458): drop hardcoded `title`/`body`, use `params={"place_name": ...}` with `title=""`, `body=""`.
- `services/api/tests/routers/test_notifications.py` — add i18n assertions (adapt or add alongside the existing `notification_to_view` test).
- `apps/mobile/lib/services/notification_service.dart` — send `Accept-Language` header on GET.

---

## Task 1: Add notification templates module

**Files:**
- Create: `services/api/app/services/notification_templates.py`

- [ ] **Step 1: Create the templates module**

```python
# services/api/app/services/notification_templates.py
"""Notification message templates keyed by type, field, and locale.

Templates are rendered at response time from Notification.params.
Placeholders use Python str.format syntax, e.g. "{place_name}".
"""

SUPPORTED_LOCALES: tuple[str, ...] = ("ko", "en", "ja", "es")
DEFAULT_LOCALE: str = "ko"

TEMPLATES: dict[str, dict[str, dict[str, str]]] = {
    "place_registration_ack": {
        "title": {
            "ko": "암장 등록 요청이 접수되었습니다",
            "en": "Your gym registration request has been received",
            "ja": "クライミングジム登録リクエストを受け付けました",
            "es": "Tu solicitud de registro de gimnasio ha sido recibida",
        },
        "body": {
            "ko": "{place_name} 등록 요청 감사합니다 🙌 빠르게 확인 후 반영하겠습니다.",
            "en": "Thanks for requesting to register {place_name} 🙌 We'll review and apply it shortly.",
            "ja": "{place_name} の登録リクエストありがとうございます 🙌 早急に確認して反映します。",
            "es": "Gracias por solicitar el registro de {place_name} 🙌 Lo revisaremos y aplicaremos pronto.",
        },
    },
    "place_suggestion_ack": {
        "title": {
            "ko": "장소 정보 수정 제안이 접수되었습니다",
            "en": "Your place info update suggestion has been received",
            "ja": "スポット情報の修正提案を受け付けました",
            "es": "Tu sugerencia de actualización del lugar ha sido recibida",
        },
        "body": {
            "ko": "{place_name}에 대한 소중한 제보 감사합니다 🙌 빠르게 확인 후 반영하겠습니다.",
            "en": "Thanks for your input on {place_name} 🙌 We'll review and apply it shortly.",
            "ja": "{place_name} に関するご提案ありがとうございます 🙌 早急に確認して反映します。",
            "es": "Gracias por tu aporte sobre {place_name} 🙌 Lo revisaremos y aplicaremos pronto.",
        },
    },
}
```

- [ ] **Step 2: Verify it imports cleanly**

Run: `cd services/api && uv run python -c "from app.services.notification_templates import TEMPLATES, SUPPORTED_LOCALES, DEFAULT_LOCALE; print(len(TEMPLATES), SUPPORTED_LOCALES, DEFAULT_LOCALE)"`
Expected: `2 ('ko', 'en', 'ja', 'es') ko`

- [ ] **Step 3: Commit**

```bash
git add services/api/app/services/notification_templates.py
git commit -m "feat(api): add notification message templates for ko/en/ja/es"
```

---

## Task 2: Add locale parser + renderer (TDD)

**Files:**
- Create: `services/api/app/services/notification_renderer.py`
- Test: `services/api/tests/services/test_notification_renderer.py`

- [ ] **Step 1: Write failing tests**

```python
# services/api/tests/services/test_notification_renderer.py
from datetime import datetime, timezone
from types import SimpleNamespace

from beanie.odm.fields import PydanticObjectId

from app.services.notification_renderer import pick_locale, render


def _make_notif(
    *,
    type: str = "place_suggestion_ack",
    params: dict | None = None,
    title: str = "",
    body: str = "",
):
    return SimpleNamespace(
        id=PydanticObjectId("64b000000000000000000001"),
        user_id=PydanticObjectId("64b000000000000000000002"),
        type=type,
        title=title,
        body=body,
        link=None,
        read_at=None,
        created_at=datetime(2026, 4, 18, tzinfo=timezone.utc),
        params=params if params is not None else {},
    )


# --- pick_locale ---

def test_pick_locale_returns_primary_subtag():
    assert pick_locale("ko-KR,ko;q=0.9,en;q=0.8") == "ko"
    assert pick_locale("en-US") == "en"
    assert pick_locale("ja") == "ja"
    assert pick_locale("es-ES") == "es"


def test_pick_locale_none_returns_default():
    assert pick_locale(None) == "ko"
    assert pick_locale("") == "ko"


def test_pick_locale_unsupported_falls_back_to_default():
    assert pick_locale("fr-FR") == "ko"
    assert pick_locale("zh,fr") == "ko"


def test_pick_locale_is_case_insensitive():
    assert pick_locale("EN-US") == "en"
    assert pick_locale("Ja-JP") == "ja"


# --- render ---

def test_render_new_record_uses_template_for_locale():
    notif = _make_notif(
        type="place_suggestion_ack",
        params={"place_name": "클라이밍파크"},
    )
    title, body = render(notif, "ko")
    assert title == "장소 정보 수정 제안이 접수되었습니다"
    assert "클라이밍파크" in body
    assert "소중한 제보 감사합니다" in body


def test_render_new_record_english():
    notif = _make_notif(
        type="place_registration_ack",
        params={"place_name": "ClimbPark"},
    )
    title, body = render(notif, "en")
    assert title == "Your gym registration request has been received"
    assert "ClimbPark" in body


def test_render_new_record_japanese():
    notif = _make_notif(
        type="place_suggestion_ack",
        params={"place_name": "クライミングパーク"},
    )
    title, body = render(notif, "ja")
    assert "スポット情報" in title
    assert "クライミングパーク" in body


def test_render_new_record_spanish():
    notif = _make_notif(
        type="place_registration_ack",
        params={"place_name": "ClimbPark"},
    )
    title, body = render(notif, "es")
    assert "solicitud de registro" in title
    assert "ClimbPark" in body


def test_render_unsupported_locale_uses_default_template():
    notif = _make_notif(
        type="place_suggestion_ack",
        params={"place_name": "클라이밍파크"},
    )
    title, body = render(notif, "fr")
    assert title == "장소 정보 수정 제안이 접수되었습니다"
    assert "클라이밍파크" in body


def test_render_old_record_without_params_returns_stored_values():
    """Records created before this feature have empty params; we must return
    whatever was pre-rendered into title/body at creation time."""
    notif = _make_notif(
        type="place_suggestion_ack",
        params={},
        title="정보 수정 제안이 접수되었습니다",
        body="클라이밍파크에 대한 소중한 제보 감사합니다 🙌 운영진이 확인하고 반영할게요.",
    )
    title, body = render(notif, "en")
    assert title == "정보 수정 제안이 접수되었습니다"
    assert body.startswith("클라이밍파크")


def test_render_unknown_type_falls_back_to_stored():
    notif = _make_notif(
        type="totally_unknown_type",
        params={"place_name": "X"},
        title="saved title",
        body="saved body",
    )
    title, body = render(notif, "ko")
    assert title == "saved title"
    assert body == "saved body"


def test_render_missing_placeholder_falls_back_to_stored():
    """If the template references {place_name} but params don't include it,
    fall back to the stored value rather than crashing."""
    notif = _make_notif(
        type="place_suggestion_ack",
        params={"other_var": "X"},
        title="saved title",
        body="saved body",
    )
    title, body = render(notif, "ko")
    # Title template has no placeholder so it still renders.
    assert title == "장소 정보 수정 제안이 접수되었습니다"
    # Body needs place_name — should fall back to stored body.
    assert body == "saved body"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_notification_renderer.py -v`
Expected: all fail with `ModuleNotFoundError: No module named 'app.services.notification_renderer'`.

- [ ] **Step 3: Implement renderer**

```python
# services/api/app/services/notification_renderer.py
"""Render notifications for a given locale.

- `pick_locale` picks the first supported primary subtag in an Accept-Language
  header, else the default locale.
- `render` returns `(title, body)`. For records with non-empty `params`, it
  formats the type/locale template; otherwise it returns the stored
  `title`/`body` (backwards compatibility for records created before this
  feature).
"""
from typing import Any

from app.services.notification_templates import (
    DEFAULT_LOCALE,
    SUPPORTED_LOCALES,
    TEMPLATES,
)


def pick_locale(accept_language: str | None) -> str:
    """Return the first supported primary subtag in the header, else default.

    Very small parser: splits on commas and semicolons, lowercases, takes the
    primary subtag before any hyphen, ignores quality values. Good enough for
    our four-locale set.
    """
    if not accept_language:
        return DEFAULT_LOCALE
    for raw in accept_language.split(","):
        tag = raw.split(";", 1)[0].strip().lower()
        if not tag:
            continue
        primary = tag.split("-", 1)[0]
        if primary in SUPPORTED_LOCALES:
            return primary
    return DEFAULT_LOCALE


def _render_field(
    type_: str,
    field: str,
    locale: str,
    params: dict[str, Any],
    stored: str,
) -> str:
    by_field = TEMPLATES.get(type_)
    if not by_field:
        return stored
    by_locale = by_field.get(field, {})
    template = by_locale.get(locale) or by_locale.get(DEFAULT_LOCALE)
    if not template:
        return stored
    try:
        return template.format(**params)
    except (KeyError, IndexError):
        return stored


def render(notif, locale: str) -> tuple[str, str]:
    """Render (title, body) for a notification in the given locale.

    Returns stored title/body unchanged if the record has no params (old
    records created before this feature were pre-rendered in Korean).
    """
    params = getattr(notif, "params", None) or {}
    if not params:
        return notif.title, notif.body
    title = _render_field(notif.type, "title", locale, params, notif.title)
    body = _render_field(notif.type, "body", locale, params, notif.body)
    return title, body
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_notification_renderer.py -v`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/services/notification_renderer.py services/api/tests/services/test_notification_renderer.py
git commit -m "feat(api): add Accept-Language-aware notification renderer"
```

---

## Task 3: Add `params` field to Notification model

**Files:**
- Modify: `services/api/app/models/notification.py`

- [ ] **Step 1: Add the field**

In `services/api/app/models/notification.py`, after the `created_at` field and before `class Settings`, add:

```python
    params: dict = Field(
        default_factory=dict,
        description="템플릿 렌더용 변수 스냅샷 (예: {'place_name': '...'})",
    )
```

Final class should look like:

```python
class Notification(Document):
    model_config = model_config

    user_id: PydanticObjectId = Field(..., description="알림 수신자")
    type: str = Field(..., description="알림 타입 (place_suggestion_ack 등)")
    title: str = Field(..., description="알림 제목")
    body: str = Field(..., description="알림 본문 (렌더 완료된 스냅샷)")
    link: Optional[str] = Field(None, description="연결 경로. 저장만 하고 동작은 없음")
    read_at: Optional[datetime] = Field(None, description="읽은 시간")
    created_at: datetime = Field(..., description="생성 시간")
    params: dict = Field(
        default_factory=dict,
        description="템플릿 렌더용 변수 스냅샷 (예: {'place_name': '...'})",
    )

    class Settings:
        name = "notifications"
        indexes = [
            IndexModel([("userId", ASCENDING), ("createdAt", DESCENDING)]),
        ]
        keep_nulls = True
```

- [ ] **Step 2: Verify the model still imports and validates**

Run: `cd services/api && uv run python -c "from app.models.notification import Notification; n = Notification(user_id='64b000000000000000000001', type='x', title='', body='', created_at=__import__('datetime').datetime.now()); print(n.params)"`
Expected: `{}`

- [ ] **Step 3: Run existing notification tests — they must still pass**

Run: `cd services/api && uv run pytest tests/routers/test_notifications.py -v`
Expected: existing `test_notification_to_view_maps_all_fields` still PASSES (it uses SimpleNamespace so the model change is orthogonal).

- [ ] **Step 4: Commit**

```bash
git add services/api/app/models/notification.py
git commit -m "feat(api): add params field to Notification for template rendering"
```

---

## Task 4: Wire `Accept-Language` into GET /notifications

**Files:**
- Modify: `services/api/app/routers/notifications.py`
- Modify: `services/api/tests/routers/test_notifications.py`

- [ ] **Step 1: Write failing tests**

Replace the contents of `services/api/tests/routers/test_notifications.py` with:

```python
from datetime import datetime, timezone
from types import SimpleNamespace

from beanie.odm.fields import PydanticObjectId

from app.routers.notifications import notification_to_view


def _notif(**overrides):
    base = dict(
        id=PydanticObjectId("64b000000000000000000001"),
        user_id=PydanticObjectId("64b000000000000000000002"),
        type="place_suggestion_ack",
        title="saved title",
        body="saved body",
        link="/places/64b000000000000000000003",
        read_at=None,
        created_at=datetime(2026, 4, 15, 12, 0, 0, tzinfo=timezone.utc),
        params={},
    )
    base.update(overrides)
    return SimpleNamespace(**base)


def test_notification_to_view_maps_all_fields_old_record():
    """Records without params return stored title/body regardless of locale."""
    notif = _notif(
        title="정보 수정 제안이 접수되었습니다",
        body="클라이밍파크 강남점에 대한 소중한 제보 감사합니다 🙌 운영진이 확인하고 반영할게요.",
    )
    view = notification_to_view(notif, locale="en")
    assert view.id == notif.id
    assert view.type == "place_suggestion_ack"
    assert view.title == "정보 수정 제안이 접수되었습니다"
    assert view.body.startswith("클라이밍파크 강남점")
    assert view.link == "/places/64b000000000000000000003"
    assert view.read_at is None
    assert view.created_at == notif.created_at


def test_notification_to_view_renders_from_params_ko():
    notif = _notif(
        type="place_suggestion_ack",
        params={"place_name": "클라이밍파크"},
    )
    view = notification_to_view(notif, locale="ko")
    assert view.title == "장소 정보 수정 제안이 접수되었습니다"
    assert "클라이밍파크" in view.body


def test_notification_to_view_renders_from_params_en():
    notif = _notif(
        type="place_registration_ack",
        params={"place_name": "ClimbPark"},
    )
    view = notification_to_view(notif, locale="en")
    assert view.title == "Your gym registration request has been received"
    assert "ClimbPark" in view.body
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/routers/test_notifications.py -v`
Expected: all three fail because `notification_to_view` currently takes only one argument.

- [ ] **Step 3: Update the router**

In `services/api/app/routers/notifications.py`:

**(a)** Update imports at the top:

```python
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from beanie.odm.fields import PydanticObjectId
from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.dependencies import get_current_user
from app.models import model_config
from app.models.notification import Notification
from app.models.user import User
from app.services.notification_renderer import pick_locale, render
```

**(b)** Replace `notification_to_view`:

```python
def notification_to_view(notif: Notification, locale: str) -> NotificationView:
    title, body = render(notif, locale)
    return NotificationView(
        id=notif.id,
        type=notif.type,
        title=title,
        body=body,
        link=notif.link,
        read_at=notif.read_at,
        created_at=notif.created_at,
    )
```

**(c)** Update `list_notifications` to accept and use `Accept-Language`:

```python
@router.get("", response_model=NotificationListResponse)
async def list_notifications(
    before: Optional[datetime] = Query(None, description="이 시각 이전 알림만"),
    limit: int = Query(20, ge=1, le=50),
    accept_language: Optional[str] = Header(None, alias="Accept-Language"),
    current_user: User = Depends(get_current_user),
):
    query_filter: dict = {"userId": current_user.id}
    if before is not None:
        query_filter["createdAt"] = {"$lt": before}

    items = (
        await Notification.find(query_filter)
        .sort(-Notification.created_at)
        .limit(limit)
        .to_list()
    )

    locale = pick_locale(accept_language)
    next_cursor = items[-1].created_at if len(items) == limit else None
    return NotificationListResponse(
        items=[notification_to_view(n, locale) for n in items],
        next_cursor=next_cursor,
    )
```

Leave `mark_notifications_read` unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/routers/test_notifications.py tests/services/test_notification_renderer.py -v`
Expected: all PASS.

- [ ] **Step 5: Run full test suite for regressions**

Run: `cd services/api && uv run pytest -q`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add services/api/app/routers/notifications.py services/api/tests/routers/test_notifications.py
git commit -m "feat(api): render GET /notifications by Accept-Language"
```

---

## Task 5: Update notification creation sites to use `params`

**Files:**
- Modify: `services/api/app/routers/places.py` (two sites near lines 156 and 458)

- [ ] **Step 1: Update the `place_registration_ack` creation (~line 156)**

Find this block in `services/api/app/routers/places.py`:

```python
            notif = Notification(
                user_id=current_user.id,
                type="place_registration_ack",
                title="암장 등록 요청이 접수되었습니다",
                body=(
                    f"{place.name} 등록을 요청해주신 소중한 제보 감사합니다 🙌 "
                    "서비스에 반영될 수 있도록 빠르게 처리해서 알려드리겠습니다."
                ),
                link=f"/places/{place.id}",
                created_at=datetime.now(tz=timezone.utc),
            )
```

Replace with:

```python
            notif = Notification(
                user_id=current_user.id,
                type="place_registration_ack",
                title="",
                body="",
                params={"place_name": place.name},
                link=f"/places/{place.id}",
                created_at=datetime.now(tz=timezone.utc),
            )
```

- [ ] **Step 2: Update the `place_suggestion_ack` creation (~line 458)**

Find this block:

```python
        place_name_snapshot = place.name
        notif = Notification(
            user_id=current_user.id,
            type="place_suggestion_ack",
            title="정보 수정 제안이 접수되었습니다",
            body=(
                f"{place_name_snapshot}에 대한 소중한 제보 감사합니다 🙌 "
                "서비스에 반영될 수 있도록 빠르게 처리해서 알려드리겠습니다."
            ),
            link=f"/places/{place.id}",
            created_at=datetime.now(tz=timezone.utc),
        )
```

Replace with:

```python
        notif = Notification(
            user_id=current_user.id,
            type="place_suggestion_ack",
            title="",
            body="",
            params={"place_name": place.name},
            link=f"/places/{place.id}",
            created_at=datetime.now(tz=timezone.utc),
        )
```

(The `place_name_snapshot = place.name` line is no longer needed — remove it.)

- [ ] **Step 3: Run full test suite**

Run: `cd services/api && uv run pytest -q`
Expected: all PASS.

- [ ] **Step 4: Smoke-check the router imports**

Run: `cd services/api && uv run python -c "from app.routers import places; print('ok')"`
Expected: `ok`.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): store notification params instead of pre-rendered text"
```

---

## Task 6: Send `Accept-Language` from the mobile NotificationService

**Files:**
- Modify: `apps/mobile/lib/services/notification_service.dart`

- [ ] **Step 1: Update `NotificationService.list` to send the header**

In `apps/mobile/lib/services/notification_service.dart`:

**(a)** Add the import at the top alongside existing imports:

```dart
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import '../models/notification_data.dart';
import 'http_client.dart';
```

**(b)** Replace the `list` method body — specifically the `AuthorizedHttpClient.get` call — to pass the header:

```dart
  static Future<NotificationListResult> list({
    DateTime? before,
    int limit = 20,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (before != null) {
      query['before'] = before.toUtc().toIso8601String();
    }
    final qs = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final path = qs.isEmpty ? '/notifications' : '/notifications?$qs';

    final response = await AuthorizedHttpClient.get(
      path,
      extraHeaders: {
        'Accept-Language': PlatformDispatcher.instance.locale.languageCode,
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load notifications: ${response.statusCode}',
      );
    }
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final items = (decoded['items'] as List<dynamic>)
        .map((e) => NotificationData.fromJson(e as Map<String, dynamic>))
        .toList();
    final nextCursorStr = decoded['nextCursor'] as String?;
    final nextCursor =
        nextCursorStr == null ? null : DateTime.parse(nextCursorStr);
    return NotificationListResult(items: items, nextCursor: nextCursor);
  }
```

(Leave `markRead` unchanged — it doesn't return message text.)

- [ ] **Step 2: Run static analysis**

Run: `cd apps/mobile && flutter analyze lib/services/notification_service.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run full analyze for regressions**

Run: `cd apps/mobile && flutter analyze`
Expected: no new errors introduced by this change.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/services/notification_service.dart
git commit -m "feat(mobile): send Accept-Language on GET /notifications"
```

---

## Final verification

- [ ] **Run the API test suite one more time**

Run: `cd services/api && uv run pytest -q`
Expected: all PASS.

- [ ] **Run the Flutter analyzer one more time**

Run: `cd apps/mobile && flutter analyze`
Expected: no new issues.

- [ ] **Manual sanity check via curl (optional, if staging/dev API is reachable)**

```bash
# Requires a valid access token; locale should flip the rendered body language.
curl -s -H "Authorization: Bearer $TOKEN" -H "Accept-Language: en" \
  "$API_URL/notifications?limit=5" | jq '.items[0] | {type, title, body}'
```

Expected: when the latest notification is a newly-created one (post-Task 5), `title`/`body` are in English; with `Accept-Language: ko` they are in Korean. Older records still show their stored Korean text regardless of header.
