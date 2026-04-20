# Marketing Push Consent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collect and persist user consent for promotional push notifications at signup and in settings, and gate promotional sends by consent + 2-year TTL + device-local night-hours (21–08).

**Architecture:** Three fields on `User` store the latest consent state. `DeviceToken` grows a `timezone` field for per-device night gating. A new `send_promotional(user_id, title_by_locale, body_by_locale, link, data)` entry point in `push_sender.py` runs the consent/TTL gate once per user and the night gate per device, and does **not** create `Notification` documents. Operational notifications keep going through `send_to_user` unchanged. Mobile adds an optional signup checkbox (under existing ToS/Privacy checkboxes) and a new settings toggle.

**Tech Stack:** FastAPI + Beanie (MongoDB ODM), Firebase Cloud Messaging v1, Flutter + hooks_riverpod, `flutter_timezone` package (new).

**Reference spec:** `docs/superpowers/specs/2026-04-20-marketing-push-consent-design.md`.

---

## File Structure

### Backend (Python / FastAPI)

- **Modify** `services/api/app/models/user.py` — add 3 consent fields to `User`.
- **Modify** `services/api/app/models/device_token.py` — add `timezone` field.
- **Modify** `services/api/app/services/push_sender.py` — extract `_is_consent_active` and `_is_night_hour_for_device` helpers; add `send_promotional`; extract a small `_send_one_raw(title, body, link, data)` helper used by both paths.
- **Modify** `services/api/app/routers/authentications.py` — accept `marketingPushConsent` in all four `/sign-up/{line|kakao|apple|google}` bodies and persist the 3 fields.
- **Modify** `services/api/app/routers/my.py` — add `PATCH /my/marketing-consent`; extend `RegisterDeviceRequest` with `timezone`.
- **Modify** `services/api/app/routers/users.py` — expose the 3 consent fields on `UserProfileResponse` (`GET /users/me`).
- **Add** `services/api/tests/services/test_push_sender.py` cases — consent gate, TTL gate, night gate helpers, send_promotional never persists Notification.
- **Add** `services/api/tests/routers/test_my_marketing_consent.py` — PATCH endpoint behaviour.
- **Add** `services/api/tests/routers/test_my_devices.py` (or extend if exists) — timezone persisted.
- **Add** `services/api/tests/routers/test_users_me.py` (or extend if exists) — three fields surfaced.

### Mobile (Flutter)

- **Modify** `apps/mobile/pubspec.yaml` — add `flutter_timezone`.
- **Modify** `apps/mobile/lib/services/push_service.dart` — send `locale` + `timezone` on register; route push taps to home.
- **Modify** `apps/mobile/lib/pages/terms_page.dart` — third optional checkbox + include `marketingPushConsent` in all four signup POST bodies.
- **Modify** `apps/mobile/lib/pages/setting.dart` — add "알림" ListTile.
- **Add** `apps/mobile/lib/pages/notification_settings_page.dart` — marketing toggle calling `PATCH /my/marketing-consent`.
- **Modify** `apps/mobile/lib/l10n/app_{ko,en,ja,es}.arb` — new strings.

---

## Tasks

### Task 1: `User` — add three marketing consent fields

**Files:**
- Modify: `services/api/app/models/user.py` (class `User`)

- [ ] **Step 1: Add fields to `User`**

In `services/api/app/models/user.py`, add to class `User` (after `unread_notification_count`):

```python
    marketing_push_consent: bool = False
    marketing_push_consent_at: Optional[datetime] = None
    marketing_push_consent_source: Optional[str] = None  # 'signup' | 'settings' | 'reconfirm'
```

`datetime` and `Optional` are already imported at the top of the file.

- [ ] **Step 2: Run static check**

```bash
cd services/api && python -c "from app.models.user import User; print(sorted(User.model_fields.keys()))"
```

Expected: output lists `marketing_push_consent`, `marketing_push_consent_at`, `marketing_push_consent_source` among others.

- [ ] **Step 3: Commit**

```bash
git add services/api/app/models/user.py
git commit -m "feat(api): add marketing_push_consent fields to User"
```

---

### Task 2: `DeviceToken` — add `timezone` field

**Files:**
- Modify: `services/api/app/models/device_token.py`

- [ ] **Step 1: Add field**

In `services/api/app/models/device_token.py`, add to class `DeviceToken` below `locale`:

```python
    timezone: Optional[str] = Field(None, description="기기 IANA 타임존 (예: 'Asia/Seoul')")
```

- [ ] **Step 2: Sanity check**

```bash
cd services/api && python -c "from app.models.device_token import DeviceToken; print('timezone' in DeviceToken.model_fields)"
```

Expected: `True`.

- [ ] **Step 3: Commit**

```bash
git add services/api/app/models/device_token.py
git commit -m "feat(api): add timezone field to DeviceToken"
```

---

### Task 3: Extract `_is_consent_active` helper + test

**Files:**
- Modify: `services/api/app/services/push_sender.py`
- Test: `services/api/tests/services/test_push_sender.py`

- [ ] **Step 1: Write the failing tests**

Append to `services/api/tests/services/test_push_sender.py`:

```python
from datetime import datetime, timedelta, timezone

from app.services.push_sender import _is_consent_active


class _FakeUser:
    def __init__(self, consent: bool, consent_at):
        self.marketing_push_consent = consent
        self.marketing_push_consent_at = consent_at


def _now():
    return datetime(2026, 4, 21, 12, 0, 0, tzinfo=timezone.utc)


def test_is_consent_active_none_user_false():
    assert _is_consent_active(None, now=_now()) is False


def test_is_consent_active_not_consented_false():
    user = _FakeUser(consent=False, consent_at=None)
    assert _is_consent_active(user, now=_now()) is False


def test_is_consent_active_consent_at_missing_false():
    user = _FakeUser(consent=True, consent_at=None)
    assert _is_consent_active(user, now=_now()) is False


def test_is_consent_active_recent_true():
    user = _FakeUser(consent=True, consent_at=_now() - timedelta(days=30))
    assert _is_consent_active(user, now=_now()) is True


def test_is_consent_active_ttl_boundary_inside_true():
    # 729 days 23h old → still active
    user = _FakeUser(consent=True, consent_at=_now() - timedelta(days=729, hours=23))
    assert _is_consent_active(user, now=_now()) is True


def test_is_consent_active_ttl_expired_false():
    # 731 days old → expired
    user = _FakeUser(consent=True, consent_at=_now() - timedelta(days=731))
    assert _is_consent_active(user, now=_now()) is False
```

- [ ] **Step 2: Run test, verify failure**

```bash
cd services/api && pytest tests/services/test_push_sender.py -v -k is_consent_active
```

Expected: ImportError or 6 failures ("cannot import name `_is_consent_active`").

- [ ] **Step 3: Implement the helper**

Append to `services/api/app/services/push_sender.py` (after existing helpers, before `_send_one`):

```python
from datetime import timedelta, timezone as _tz

CONSENT_TTL = timedelta(days=730)


def _is_consent_active(user, now: Optional[datetime] = None) -> bool:
    """True if the user currently has a valid marketing push consent.

    A consent is valid when `marketing_push_consent` is True AND
    `marketing_push_consent_at` is present AND within CONSENT_TTL of `now`.
    `now` defaults to the current UTC time; tests inject a fixed value.
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
```

Also add `from datetime import datetime` if not already imported at the module top.

- [ ] **Step 4: Run test, verify pass**

```bash
cd services/api && pytest tests/services/test_push_sender.py -v -k is_consent_active
```

Expected: 6 passing.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/services/push_sender.py services/api/tests/services/test_push_sender.py
git commit -m "feat(api): add _is_consent_active helper for marketing push"
```

---

### Task 4: Extract `_is_night_hour_for_device` helper + test

**Files:**
- Modify: `services/api/app/services/push_sender.py`
- Test: `services/api/tests/services/test_push_sender.py`

- [ ] **Step 1: Write the failing tests**

Append to `services/api/tests/services/test_push_sender.py`:

```python
from app.services.push_sender import _is_night_hour_for_device


class _FakeDevice:
    def __init__(self, timezone_name):
        self.timezone = timezone_name


# Pick a fixed UTC instant and reason about the local hour for each zone.
# 2026-04-21 13:00 UTC → Asia/Seoul 22:00 (night), Europe/Paris 15:00 (day),
# America/Los_Angeles 06:00 (still night — 21≤h or h<8 → night)
_FIXED_UTC = datetime(2026, 4, 21, 13, 0, 0, tzinfo=timezone.utc)


def test_is_night_hour_kst_22h_true():
    d = _FakeDevice("Asia/Seoul")
    assert _is_night_hour_for_device(d, now=_FIXED_UTC) is True


def test_is_night_hour_paris_15h_false():
    d = _FakeDevice("Europe/Paris")
    assert _is_night_hour_for_device(d, now=_FIXED_UTC) is False


def test_is_night_hour_la_6h_true():
    d = _FakeDevice("America/Los_Angeles")
    assert _is_night_hour_for_device(d, now=_FIXED_UTC) is True


def test_is_night_hour_fallback_when_missing():
    # Empty timezone → treat as Asia/Seoul → 22:00 → night
    d = _FakeDevice(None)
    assert _is_night_hour_for_device(d, now=_FIXED_UTC) is True


def test_is_night_hour_invalid_timezone_falls_back():
    d = _FakeDevice("Not/AZone")
    # Invalid zone → fallback → Asia/Seoul → 22:00 → night
    assert _is_night_hour_for_device(d, now=_FIXED_UTC) is True


def test_is_night_hour_boundary_21h_true():
    # 12:00 UTC → Seoul 21:00 sharp → night (>=21)
    now = datetime(2026, 4, 21, 12, 0, 0, tzinfo=timezone.utc)
    d = _FakeDevice("Asia/Seoul")
    assert _is_night_hour_for_device(d, now=now) is True


def test_is_night_hour_boundary_8h_false():
    # 23:00 UTC → Seoul 08:00 → NOT night (h==8)
    now = datetime(2026, 4, 20, 23, 0, 0, tzinfo=timezone.utc)
    d = _FakeDevice("Asia/Seoul")
    assert _is_night_hour_for_device(d, now=now) is False
```

- [ ] **Step 2: Run, verify failure**

```bash
cd services/api && pytest tests/services/test_push_sender.py -v -k is_night_hour
```

Expected: ImportError ("cannot import name `_is_night_hour_for_device`").

- [ ] **Step 3: Implement the helper**

In `services/api/app/services/push_sender.py`, add near `_is_consent_active`:

```python
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

_NIGHT_FALLBACK_TZ = "Asia/Seoul"


def _is_night_hour_for_device(device, now: Optional[datetime] = None) -> bool:
    """True when the device's local hour falls in 21:00–07:59 (inclusive).

    Uses DeviceToken.timezone; falls back to Asia/Seoul when missing or
    unknown. `now` defaults to current UTC; tests inject a fixed instant.
    """
    tz_name = getattr(device, "timezone", None) or _NIGHT_FALLBACK_TZ
    try:
        tz = ZoneInfo(tz_name)
    except ZoneInfoNotFoundError:
        tz = ZoneInfo(_NIGHT_FALLBACK_TZ)
    now = now or datetime.now(_tz.utc)
    local_hour = now.astimezone(tz).hour
    return local_hour >= 21 or local_hour < 8
```

- [ ] **Step 4: Run, verify pass**

```bash
cd services/api && pytest tests/services/test_push_sender.py -v -k is_night_hour
```

Expected: 7 passing.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/services/push_sender.py services/api/tests/services/test_push_sender.py
git commit -m "feat(api): add _is_night_hour_for_device helper for promo gating"
```

---

### Task 5: Extract `_send_one_raw` so promo path can reuse FCM logic

**Files:**
- Modify: `services/api/app/services/push_sender.py`

- [ ] **Step 1: Introduce `_send_one_raw`**

In `services/api/app/services/push_sender.py`, replace the existing `_send_one` with a thin adapter that delegates to a new `_send_one_raw`:

```python
async def _send_one_raw(
    session: aiohttp.ClientSession,
    project_id: str,
    access_token: str,
    device: DeviceToken,
    title: str,
    body: str,
    link: Optional[str],
    extra_data: Optional[dict[str, str]],
) -> None:
    url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
    data_payload: dict[str, str] = dict(extra_data or {})
    if link:
        data_payload["link"] = link
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


async def _send_one(
    session: aiohttp.ClientSession,
    project_id: str,
    access_token: str,
    device: DeviceToken,
    notif: Notification,
) -> None:
    title, body = render(notif, _primary_locale(device.locale))
    extra = {"type": notif.type, "notificationId": str(notif.id)}
    await _send_one_raw(session, project_id, access_token, device, title, body, notif.link, extra)
```

- [ ] **Step 2: Run existing tests**

```bash
cd services/api && pytest tests/services/test_push_sender.py -v
```

Expected: all prior tests still pass (helpers unchanged, `_send_one` re-uses new helper).

- [ ] **Step 3: Commit**

```bash
git add services/api/app/services/push_sender.py
git commit -m "refactor(api): extract _send_one_raw to share FCM send across paths"
```

---

### Task 6: Add `send_promotional` + "does not persist Notification" test

**Files:**
- Modify: `services/api/app/services/push_sender.py`
- Test: `services/api/tests/services/test_push_sender.py`

- [ ] **Step 1: Write the failing test**

Append to `services/api/tests/services/test_push_sender.py`:

```python
from unittest.mock import AsyncMock, MagicMock, patch


@patch("app.services.push_sender.DeviceToken")
@patch("app.services.push_sender.User")
@patch("app.services.push_sender.Notification")
@patch("app.services.push_sender._send_one_raw", new_callable=AsyncMock)
@patch("app.services.push_sender._ensure_credentials")
@patch("app.services.push_sender._refresh_access_token", return_value="access-token")
@patch("app.services.push_sender.aiohttp.ClientSession")
def test_send_promotional_does_not_create_notification(
    client_session,
    refresh_tok,
    ensure_creds,
    send_raw,
    notification_cls,
    user_cls,
    device_cls,
):
    """send_promotional must not call Notification.insert/save/create."""
    import asyncio

    # Fake user with active consent
    fake_user = _FakeUser(
        consent=True,
        consent_at=datetime(2026, 4, 1, tzinfo=timezone.utc),
    )
    user_cls.find_one = MagicMock(return_value=AsyncMock(
        __call__=None)())
    # Simpler: bypass the chain and stub the awaitable directly
    async def _find_user(*_a, **_kw): return fake_user
    user_cls.find_one = MagicMock(side_effect=lambda *_a, **_kw: _async_result(fake_user))

    # Devices with timezone in "day" hours
    fake_device = MagicMock()
    fake_device.timezone = "Europe/Paris"
    fake_device.locale = "en-US"
    fake_device.token = "tok"

    async def _dev_list(*_a, **_kw):
        class _Cursor:
            async def to_list(self):
                return [fake_device]
        return _Cursor()
    device_cls.find = MagicMock(side_effect=lambda *_a, **_kw: _async_result(_Cursor_list([fake_device])))

    # Force project_id and session
    import app.services.push_sender as ps
    ps._project_id = "test-project"

    session_instance = MagicMock()
    session_instance.__aenter__ = AsyncMock(return_value=session_instance)
    session_instance.__aexit__ = AsyncMock(return_value=None)
    client_session.return_value = session_instance

    from app.services.push_sender import send_promotional

    asyncio.run(send_promotional(
        PydanticObjectId_fake(),
        title_by_locale={"ko": "ko-title", "en": "en-title"},
        body_by_locale={"ko": "ko-body", "en": "en-body"},
        link="/home",
        data={"campaign": "spring"},
    ))

    # KEY assertion: Notification ODM never touched
    assert not notification_cls.method_calls, (
        f"send_promotional must not touch Notification, got: {notification_cls.method_calls}"
    )
```

**NOTE TO IMPLEMENTER:** The mocking above is brittle; the goal is a _minimal_ test that fails today. If your local patching of `Beanie`'s `find` chain proves messy, simplify by asserting the rule **without** running the full flow — test the intent via a lighter-weight contract test:

Replace Step 1 entirely with this simpler version if the integration mock is painful:

```python
def test_send_promotional_never_imports_Notification_in_body():
    """Contract: send_promotional's source code does not reference Notification.

    Keeps the promise that promo pushes are ephemeral. This is a
    read-your-source test — deliberately simple.
    """
    import inspect
    from app.services import push_sender
    src = inspect.getsource(push_sender.send_promotional)
    assert "Notification" not in src, (
        "send_promotional body must not reference Notification; "
        "promo pushes are not persisted."
    )
```

Use the simpler contract test. Delete the integration attempt above before committing.

- [ ] **Step 2: Run, verify failure**

```bash
cd services/api && pytest tests/services/test_push_sender.py -v -k send_promotional
```

Expected: AttributeError ("module has no attribute `send_promotional`").

- [ ] **Step 3: Implement `send_promotional`**

Append to `services/api/app/services/push_sender.py`:

```python
async def send_promotional(
    user_id: PydanticObjectId,
    title_by_locale: dict[str, str],
    body_by_locale: dict[str, str],
    link: Optional[str] = None,
    data: Optional[dict[str, str]] = None,
) -> None:
    """Send a promotional push to every eligible device of `user_id`.

    Gate order:
      1. User exists AND has active consent within CONSENT_TTL.
      2. Per device: local hour is NOT in 21:00-07:59.
    Does not create any Notification document.
    """
    from app.models.user import User  # local import to keep top clean

    try:
        user = await User.find_one(User.id == user_id)
        if not _is_consent_active(user):
            return
        devices = await DeviceToken.find(DeviceToken.user_id == user_id).to_list()
        if not devices:
            return
        _ensure_credentials()
        if not _project_id:
            logger.error("send_promotional: FCM project_id unavailable")
            return
        loop = asyncio.get_running_loop()
        access_token = await loop.run_in_executor(None, _refresh_access_token)
        async with aiohttp.ClientSession(timeout=_FCM_TIMEOUT) as session:
            async def _maybe_send(d: DeviceToken):
                if _is_night_hour_for_device(d):
                    return
                locale = _primary_locale(d.locale)
                title = title_by_locale.get(locale) or title_by_locale.get(DEFAULT_LOCALE)
                body = body_by_locale.get(locale) or body_by_locale.get(DEFAULT_LOCALE)
                if not title or not body:
                    return
                await _send_one_raw(
                    session, _project_id, access_token, d, title, body, link, data,
                )

            await asyncio.gather(
                *(_maybe_send(d) for d in devices),
                return_exceptions=True,
            )
    except Exception:
        logger.exception("send_promotional failed user=%s", user_id)
```

- [ ] **Step 4: Run, verify pass**

```bash
cd services/api && pytest tests/services/test_push_sender.py -v -k send_promotional
```

Expected: the contract test passes (source does not mention `Notification`).

- [ ] **Step 5: Full test run**

```bash
cd services/api && pytest tests/services/test_push_sender.py -v
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add services/api/app/services/push_sender.py services/api/tests/services/test_push_sender.py
git commit -m "feat(api): add send_promotional with consent + TTL + night gate"
```

---

### Task 7: `POST /my/devices` accepts `timezone`

**Files:**
- Modify: `services/api/app/routers/my.py` — class `RegisterDeviceRequest` + `register_device`
- Add: `services/api/tests/routers/test_my_devices.py`

- [ ] **Step 1: Write the failing test**

Create `services/api/tests/routers/test_my_devices.py`:

```python
from app.routers.my import RegisterDeviceRequest


def test_register_device_request_accepts_timezone():
    body = RegisterDeviceRequest.model_validate({
        "token": "abc",
        "platform": "ios",
        "timezone": "Asia/Seoul",
    })
    assert body.timezone == "Asia/Seoul"


def test_register_device_request_timezone_optional():
    body = RegisterDeviceRequest.model_validate({
        "token": "abc",
        "platform": "ios",
    })
    assert body.timezone is None
```

- [ ] **Step 2: Run, verify failure**

```bash
cd services/api && pytest tests/routers/test_my_devices.py -v
```

Expected: AttributeError / ValidationError — `timezone` field unknown.

- [ ] **Step 3: Extend `RegisterDeviceRequest` and `register_device`**

In `services/api/app/routers/my.py`, update `RegisterDeviceRequest`:

```python
class RegisterDeviceRequest(BaseModel):
    model_config = model_config

    token: str = Field(..., min_length=1)
    platform: str = Field(..., description="'ios' | 'android'")
    app_version: Optional[str] = None
    locale: Optional[str] = None
    timezone: Optional[str] = None
```

Update `register_device` to persist `timezone` in both the existing-doc path and the new-doc path:

```python
    existing = await DeviceToken.find_one(DeviceToken.token == payload.token)
    if existing is not None:
        existing.user_id = current_user.id
        existing.platform = payload.platform
        existing.app_version = payload.app_version
        existing.locale = payload.locale
        existing.timezone = payload.timezone
        existing.last_seen_at = now
        await existing.save()
        return

    await DeviceToken(
        user_id=current_user.id,
        token=payload.token,
        platform=payload.platform,
        app_version=payload.app_version,
        locale=payload.locale,
        timezone=payload.timezone,
        created_at=now,
        last_seen_at=now,
    ).insert()
```

- [ ] **Step 4: Run, verify pass**

```bash
cd services/api && pytest tests/routers/test_my_devices.py -v
```

Expected: 2 passing.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/my.py services/api/tests/routers/test_my_devices.py
git commit -m "feat(api): accept timezone on POST /my/devices"
```

---

### Task 8: Sign-up endpoints accept `marketingPushConsent`

**Files:**
- Modify: `services/api/app/routers/authentications.py` (all four `/sign-up/*` endpoints)

The four endpoints are on lines 132, 241, 335, 447 (approximate — re-grep before editing).

- [ ] **Step 1: Re-locate the endpoints**

```bash
cd services/api && grep -n "@router.post(\"/sign-up/" app/routers/authentications.py
```

Expected: four lines — line, kakao, apple, google.

- [ ] **Step 2: Edit `/sign-up/line`**

Change the signature and User construction:

```python
@router.post("/sign-up/line", status_code=status.HTTP_201_CREATED)
async def signup(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    nonce_id: str = Body(embed=True, alias="nonceId"),
    marketing_push_consent: bool = Body(False, embed=True, alias="marketingPushConsent"),
    http_client: ClientSession = Depends(get_http_client),
):
```

And in the `User(...)` construction block inside that function, add:

```python
        marketing_push_consent=marketing_push_consent,
        marketing_push_consent_at=(now if marketing_push_consent else None),
        marketing_push_consent_source=("signup" if marketing_push_consent else None),
```

- [ ] **Step 3: Edit `/sign-up/kakao`**

Add `marketing_push_consent: bool = Body(False, embed=True, alias="marketingPushConsent")` to the signature; add the same three constructor kwargs in its `User(...)` block.

- [ ] **Step 4: Edit `/sign-up/apple`**

Same change. Open the file and read lines 335–445 to locate the `User(...)` construction; add the signature param + three kwargs there too.

- [ ] **Step 5: Edit `/sign-up/google`**

Same change. Same pattern at the `User(...)` construction in that function.

- [ ] **Step 6: Write a thin validation test**

Create `services/api/tests/routers/test_authentications_signup_consent.py`:

```python
"""Signature-level check: /sign-up/* routes declare marketingPushConsent.

Touches only the router declarations, not the full OAuth flows.
"""
from fastapi.routing import APIRoute

from app.routers.authentications import router


_PATHS = {
    "/authentications/sign-up/line",
    "/authentications/sign-up/kakao",
    "/authentications/sign-up/apple",
    "/authentications/sign-up/google",
}


def test_all_signup_routes_declare_marketing_consent_body():
    routes = {r.path: r for r in router.routes if isinstance(r, APIRoute)}
    for path in _PATHS:
        full = path.replace("/authentications", "", 1)  # router has prefix
        assert full in routes, f"missing route {full}"
        r = routes[full]
        param_names = {p.name for p in r.dependant.body_params}
        assert "marketing_push_consent" in param_names, (
            f"{path} is missing marketingPushConsent body param; got {param_names}"
        )
```

- [ ] **Step 7: Run**

```bash
cd services/api && pytest tests/routers/test_authentications_signup_consent.py -v
```

Expected: 1 passing.

- [ ] **Step 8: Commit**

```bash
git add services/api/app/routers/authentications.py services/api/tests/routers/test_authentications_signup_consent.py
git commit -m "feat(api): accept marketingPushConsent on sign-up endpoints"
```

---

### Task 9: `PATCH /my/marketing-consent` router

**Files:**
- Modify: `services/api/app/routers/my.py`
- Add: `services/api/tests/routers/test_my_marketing_consent.py`

- [ ] **Step 1: Write the failing test**

Create `services/api/tests/routers/test_my_marketing_consent.py`:

```python
from app.routers.my import MarketingConsentRequest


def test_marketing_consent_request_true():
    body = MarketingConsentRequest.model_validate({"consent": True})
    assert body.consent is True


def test_marketing_consent_request_false():
    body = MarketingConsentRequest.model_validate({"consent": False})
    assert body.consent is False


def test_marketing_consent_request_missing_rejected():
    import pytest as _pytest
    from pydantic import ValidationError
    with _pytest.raises(ValidationError):
        MarketingConsentRequest.model_validate({})
```

- [ ] **Step 2: Run, verify failure**

```bash
cd services/api && pytest tests/routers/test_my_marketing_consent.py -v
```

Expected: ImportError — `MarketingConsentRequest` does not exist.

- [ ] **Step 3: Add the request model and endpoint**

Append to `services/api/app/routers/my.py` (end of file, after `unregister_device`):

```python
# ---------------------------------------------------------------------------
# Marketing push consent
# ---------------------------------------------------------------------------


class MarketingConsentRequest(BaseModel):
    model_config = model_config

    consent: bool = Field(...)


@router.patch("/marketing-consent", status_code=status.HTTP_204_NO_CONTENT)
async def update_marketing_consent(
    payload: MarketingConsentRequest,
    current_user: User = Depends(get_current_user),
):
    now = datetime.now(timezone.utc)
    current_user.marketing_push_consent = payload.consent
    current_user.marketing_push_consent_at = now
    current_user.marketing_push_consent_source = "settings"
    await current_user.save()
```

- [ ] **Step 4: Run, verify pass**

```bash
cd services/api && pytest tests/routers/test_my_marketing_consent.py -v
```

Expected: 3 passing.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/my.py services/api/tests/routers/test_my_marketing_consent.py
git commit -m "feat(api): add PATCH /my/marketing-consent endpoint"
```

---

### Task 10: Expose consent fields on `GET /users/me`

**Files:**
- Modify: `services/api/app/routers/users.py`
- Add: `services/api/tests/routers/test_users_me_consent.py`

- [ ] **Step 1: Write the failing test**

Create `services/api/tests/routers/test_users_me_consent.py`:

```python
from app.routers.users import UserProfileResponse


def test_user_profile_response_has_consent_fields():
    fields = set(UserProfileResponse.model_fields.keys())
    assert "marketing_push_consent" in fields
    assert "marketing_push_consent_at" in fields
    assert "marketing_push_consent_source" in fields


def test_user_profile_response_camelcases_consent_fields():
    resp = UserProfileResponse(
        id="x",
        profile_id="p",
        marketing_push_consent=True,
        marketing_push_consent_at=None,
        marketing_push_consent_source="signup",
    )
    dumped = resp.model_dump(by_alias=True)
    assert dumped["marketingPushConsent"] is True
    assert dumped["marketingPushConsentSource"] == "signup"
```

- [ ] **Step 2: Run, verify failure**

```bash
cd services/api && pytest tests/routers/test_users_me_consent.py -v
```

Expected: 2 failures — fields missing.

- [ ] **Step 3: Extend `UserProfileResponse` and `_build_profile_response`**

In `services/api/app/routers/users.py`, add to class `UserProfileResponse`:

```python
    marketing_push_consent: bool = False
    marketing_push_consent_at: Optional[datetime] = None
    marketing_push_consent_source: Optional[str] = None
```

Add `from datetime import datetime` to imports if not already present.

In `_build_profile_response`, construct the response with the extra kwargs:

```python
    return UserProfileResponse(
        id=str(user.id),
        profile_id=user.profile_id,
        name=user.name,
        email=user.email,
        bio=user.bio,
        profile_image_url=signed_url,
        unread_notification_count=user.unread_notification_count,
        marketing_push_consent=user.marketing_push_consent,
        marketing_push_consent_at=user.marketing_push_consent_at,
        marketing_push_consent_source=user.marketing_push_consent_source,
    )
```

- [ ] **Step 4: Run, verify pass**

```bash
cd services/api && pytest tests/routers/test_users_me_consent.py -v
```

Expected: 2 passing.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/users.py services/api/tests/routers/test_users_me_consent.py
git commit -m "feat(api): surface marketing consent on GET /users/me"
```

---

### Task 11: Mobile — add `flutter_timezone` dependency

**Files:**
- Modify: `apps/mobile/pubspec.yaml`

- [ ] **Step 1: Add dependency**

In `apps/mobile/pubspec.yaml`, under `dependencies:`, add:

```yaml
  flutter_timezone: ^3.0.1
```

- [ ] **Step 2: Fetch packages**

```bash
cd apps/mobile && flutter pub get
```

Expected: resolves without error; `pubspec.lock` is updated.

- [ ] **Step 3: Analyze**

```bash
cd apps/mobile && flutter analyze
```

Expected: no new issues.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock
git commit -m "build(mobile): add flutter_timezone"
```

---

### Task 12: Mobile — `PushService.registerWithServer` sends `locale` + `timezone`

**Files:**
- Modify: `apps/mobile/lib/services/push_service.dart`

- [ ] **Step 1: Update imports and register body**

Open `apps/mobile/lib/services/push_service.dart`. Add near the top:

```dart
import 'package:flutter/services.dart' show PlatformDispatcher;
import 'package:flutter_timezone/flutter_timezone.dart';
```

Replace `registerWithServer` with:

```dart
  static Future<void> registerWithServer() async {
    final token = _fcmToken;
    if (token == null) return;

    final locale = PlatformDispatcher.instance.locale.toLanguageTag();
    String? timezone;
    try {
      timezone = await FlutterTimezone.getLocalTimezone();
    } catch (e) {
      timezone = null; // server falls back to Asia/Seoul
    }

    try {
      final response = await AuthorizedHttpClient.post(
        '/my/devices',
        body: {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'locale': locale,
          if (timezone != null) 'timezone': timezone,
        },
      );
      debugPrint('[Push] POST /my/devices: ${response.statusCode}');
    } catch (e) {
      debugPrint('[Push] POST /my/devices failed: $e');
    }
  }
```

- [ ] **Step 2: Analyze**

```bash
cd apps/mobile && flutter analyze
```

Expected: no issues. (`PlatformDispatcher` may come from `dart:ui` instead of `flutter/services.dart` — if analyzer complains, switch the import to `import 'dart:ui' show PlatformDispatcher;`.)

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/services/push_service.dart
git commit -m "feat(mobile): send locale + timezone on /my/devices register"
```

---

### Task 13: Mobile — route push taps to the home tab

**Files:**
- Modify: `apps/mobile/lib/services/push_service.dart`

- [ ] **Step 1: Add a navigator key pattern**

In `apps/mobile/lib/main.dart`, locate the `MaterialApp` and add a global key (read the file first if needed):

```dart
// near top of file:
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
```

Pass it into `MaterialApp(navigatorKey: rootNavigatorKey, ...)`.

If `main.dart` already has a navigator key, reuse it and skip this step.

- [ ] **Step 2: Use the key in `PushService`**

In `apps/mobile/lib/services/push_service.dart`, import the key and update both tap handlers:

```dart
import '../main.dart' show rootNavigatorKey;
```

Replace `onMessageOpenedApp` and the initial-message block in `init()`:

```dart
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('[Push] opened from background: data=${message.data}');
      _routeToHome();
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('[Push] opened from terminated: data=${initial.data}');
      _routeToHome();
    }
```

Add a helper at the bottom of the class:

```dart
  static void _routeToHome() {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamedAndRemoveUntil('/home', (route) => false);
  }
```

- [ ] **Step 3: Analyze**

```bash
cd apps/mobile && flutter analyze
```

Expected: no issues. If the app uses a route other than `/home` for the main tab, adjust the constant — `apps/mobile/lib/main.dart` is authoritative.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/services/push_service.dart apps/mobile/lib/main.dart
git commit -m "feat(mobile): route push taps to the home tab"
```

---

### Task 14: Mobile l10n — new strings

**Files:**
- Modify: `apps/mobile/lib/l10n/app_ko.arb`, `app_en.arb`, `app_ja.arb`, `app_es.arb`

- [ ] **Step 1: Add keys to each locale**

Add these key/value pairs to the respective ARB files (preserving each file's existing JSON formatting).

`app_ko.arb`:

```json
  "marketingPushConsentOptional": "광고성 알림 수신 (선택)",
  "marketingPushConsentHint": "광고성 알림은 야간(21–08시)에 발송되지 않으며, 설정에서 언제든지 변경할 수 있습니다.",
  "notifications": "알림",
  "marketingPushSettingTitle": "광고성 알림 수신",
  "marketingPushSettingSubtitleOn": "동의함 ({date})",
  "@marketingPushSettingSubtitleOn": {"placeholders": {"date": {"type": "String"}}},
  "marketingPushSettingSubtitleOff": "동의하지 않음",
  "marketingPushSettingsNoticeOperational": "운영 관련 알림(예: 내가 제보한 장소의 처리 결과)은 이 설정과 무관하게 발송될 수 있습니다.",
  "marketingPushSettingsNoticeNight": "광고성 알림은 야간(21–08시)에 발송되지 않습니다.",
```

`app_en.arb`:

```json
  "marketingPushConsentOptional": "Marketing notifications (optional)",
  "marketingPushConsentHint": "Marketing pushes are never sent at night (9pm–8am) and you can change this anytime in settings.",
  "notifications": "Notifications",
  "marketingPushSettingTitle": "Marketing notifications",
  "marketingPushSettingSubtitleOn": "Opted in ({date})",
  "@marketingPushSettingSubtitleOn": {"placeholders": {"date": {"type": "String"}}},
  "marketingPushSettingSubtitleOff": "Opted out",
  "marketingPushSettingsNoticeOperational": "Operational notifications (e.g. responses to places you submit) are sent regardless of this setting.",
  "marketingPushSettingsNoticeNight": "Marketing notifications are not sent between 9pm and 8am.",
```

`app_ja.arb`:

```json
  "marketingPushConsentOptional": "広告通知を受け取る（任意）",
  "marketingPushConsentHint": "広告通知は夜間（21時～翌8時）には送信されず、設定でいつでも変更できます。",
  "notifications": "通知",
  "marketingPushSettingTitle": "広告通知を受け取る",
  "marketingPushSettingSubtitleOn": "同意済み（{date}）",
  "@marketingPushSettingSubtitleOn": {"placeholders": {"date": {"type": "String"}}},
  "marketingPushSettingSubtitleOff": "未同意",
  "marketingPushSettingsNoticeOperational": "運営関連の通知（例：スポット提案の処理結果）は本設定に関わらず送信されます。",
  "marketingPushSettingsNoticeNight": "広告通知は21時〜翌8時には送信されません。",
```

`app_es.arb`:

```json
  "marketingPushConsentOptional": "Recibir notificaciones promocionales (opcional)",
  "marketingPushConsentHint": "Las notificaciones promocionales no se envían por la noche (21:00–08:00) y puedes cambiarlo en cualquier momento en ajustes.",
  "notifications": "Notificaciones",
  "marketingPushSettingTitle": "Notificaciones promocionales",
  "marketingPushSettingSubtitleOn": "Aceptado ({date})",
  "@marketingPushSettingSubtitleOn": {"placeholders": {"date": {"type": "String"}}},
  "marketingPushSettingSubtitleOff": "No aceptado",
  "marketingPushSettingsNoticeOperational": "Las notificaciones operativas (p. ej. respuestas a lugares que sugieres) se envían independientemente de este ajuste.",
  "marketingPushSettingsNoticeNight": "Las notificaciones promocionales no se envían entre las 21:00 y las 08:00.",
```

- [ ] **Step 2: Regenerate localizations and analyze**

```bash
cd apps/mobile && flutter pub get && flutter analyze
```

Expected: new getters available on `AppLocalizations`, analyzer clean.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/l10n/app_ko.arb apps/mobile/lib/l10n/app_en.arb apps/mobile/lib/l10n/app_ja.arb apps/mobile/lib/l10n/app_es.arb
git commit -m "i18n(mobile): add marketing consent strings (ko/en/ja/es)"
```

---

### Task 15: Mobile — `TermsPage` adds optional consent checkbox

**Files:**
- Modify: `apps/mobile/lib/pages/terms_page.dart`

- [ ] **Step 1: Add state field**

At the top of `_TermsPageState` (beside `_isServiceTermsAgreed`, `_isPrivacyPolicyAgreed`) add:

```dart
  bool _isMarketingConsentAgreed = false;
```

`_canProceed` stays unchanged (marketing is optional).

- [ ] **Step 2: Include consent in all four signup requests**

In `_handleSignUp`, each of the four `jsonEncode({...})` bodies must include `marketingPushConsent`. The LINE branch already encodes `nonceId`; add a sibling key. The other three currently have empty-body POSTs — give them a body.

LINE:

```dart
          body: jsonEncode({
            'nonceId': widget.nonceId,
            'marketingPushConsent': _isMarketingConsentAgreed,
          }),
```

KAKAO:

```dart
          body: jsonEncode({
            'marketingPushConsent': _isMarketingConsentAgreed,
          }),
```

APPLE:

```dart
          body: jsonEncode({
            'marketingPushConsent': _isMarketingConsentAgreed,
          }),
```

GOOGLE:

```dart
          body: jsonEncode({
            'marketingPushConsent': _isMarketingConsentAgreed,
          }),
```

- [ ] **Step 3: Render the third checkbox**

In `build`, add a third `CheckboxListTile` directly after the Privacy Policy one (just before `const Spacer()`):

```dart
            CheckboxListTile(
              title: Text(AppLocalizations.of(context)!.marketingPushConsentOptional),
              subtitle: Text(
                AppLocalizations.of(context)!.marketingPushConsentHint,
                style: const TextStyle(fontSize: 12),
              ),
              value: _isMarketingConsentAgreed,
              onChanged: (value) {
                setState(() {
                  _isMarketingConsentAgreed = value ?? false;
                });
              },
            ),
```

- [ ] **Step 4: Analyze**

```bash
cd apps/mobile && flutter analyze
```

Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/pages/terms_page.dart
git commit -m "feat(mobile): add optional marketing consent checkbox to TermsPage"
```

---

### Task 16: Mobile — add "알림" entry to `SettingsPage`

**Files:**
- Modify: `apps/mobile/lib/pages/setting.dart`

- [ ] **Step 1: Add the import and ListTile**

Add to imports at the top:

```dart
import 'notification_settings_page.dart';
```

In the `ListView` children, directly below the language `ListTile` (before the Logout tile), add:

```dart
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(AppLocalizations.of(context)!.notifications),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsPage(),
                ),
              );
            },
          ),
```

- [ ] **Step 2: Analyze**

```bash
cd apps/mobile && flutter analyze
```

Expected: will fail — `notification_settings_page.dart` missing. Proceed to next task.

- [ ] **Step 3: (Deferred commit)**

Do not commit yet; Task 17 completes the pair.

---

### Task 17: Mobile — new `NotificationSettingsPage`

**Files:**
- Add: `apps/mobile/lib/pages/notification_settings_page.dart`

- [ ] **Step 1: Create the page**

Write `apps/mobile/lib/pages/notification_settings_page.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/http_client.dart';

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  bool _consent = false;
  DateTime? _consentAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await AuthorizedHttpClient.get('/users/me');
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _consent = (data['marketingPushConsent'] as bool?) ?? false;
          final at = data['marketingPushConsentAt'] as String?;
          _consentAt = at == null ? null : DateTime.tryParse(at);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool next) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _consent = next; // optimistic
    });
    try {
      final resp = await AuthorizedHttpClient.patch(
        '/my/marketing-consent',
        body: {'consent': next},
      );
      if (resp.statusCode != 204) {
        throw Exception('status ${resp.statusCode}');
      }
      setState(() {
        _consentAt = DateTime.now().toUtc();
        _saving = false;
      });
    } catch (_) {
      // revert
      setState(() {
        _consent = !next;
        _saving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.errorOccurred),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifications)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: Text(l10n.marketingPushSettingTitle),
                  subtitle: Text(_buildSubtitle(l10n)),
                  value: _consent,
                  onChanged: _saving ? null : _toggle,
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.marketingPushSettingsNoticeOperational,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.marketingPushSettingsNoticeNight,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  String _buildSubtitle(AppLocalizations l10n) {
    if (!_consent) {
      return l10n.marketingPushSettingSubtitleOff;
    }
    final when = _consentAt;
    if (when == null) {
      // consent true but no timestamp (shouldn't happen post-migration);
      // fall through gracefully.
      return l10n.marketingPushSettingSubtitleOn(
        DateFormat.yMMMd(l10n.localeName).format(DateTime.now()),
      );
    }
    return l10n.marketingPushSettingSubtitleOn(
      DateFormat.yMMMd(l10n.localeName).format(when.toLocal()),
    );
  }
}
```

- [ ] **Step 2: Verify `AuthorizedHttpClient.get/patch` exist**

```bash
cd apps/mobile && grep -n "static.*get\|static.*patch" lib/services/http_client.dart
```

Expected: both `get` and `patch` are present. If `patch` is missing, add:

```dart
  static Future<http.Response> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final headers = await _buildHeaders();
    return http.patch(
      Uri.parse('$_host$path'),
      headers: headers,
      body: jsonEncode(body ?? {}),
    );
  }
```

Mirror the existing `post` implementation for headers and host.

- [ ] **Step 3: Analyze**

```bash
cd apps/mobile && flutter analyze
```

Expected: clean.

- [ ] **Step 4: Commit (bundles Task 16 + 17)**

```bash
git add apps/mobile/lib/pages/notification_settings_page.dart apps/mobile/lib/pages/setting.dart apps/mobile/lib/services/http_client.dart
git commit -m "feat(mobile): add notification settings page with marketing toggle"
```

---

## Smoke Test After All Tasks

- [ ] Backend unit tests:

```bash
cd services/api && pytest tests/services/test_push_sender.py tests/routers/test_my_marketing_consent.py tests/routers/test_my_devices.py tests/routers/test_users_me_consent.py tests/routers/test_authentications_signup_consent.py -v
```

Expected: all green.

- [ ] Flutter analyze:

```bash
cd apps/mobile && flutter analyze
```

Expected: no issues.

- [ ] Manual spot check (device or simulator, optional):
  - Fresh signup through each provider → confirm API receives `marketingPushConsent` in body.
  - Settings → 알림 → toggle on/off twice; refresh page; state persists.
  - Background kill + FCM payload tap → app opens at home tab.
