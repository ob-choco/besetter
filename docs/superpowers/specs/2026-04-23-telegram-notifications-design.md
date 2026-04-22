# Telegram Notifications for Key Server Events — Design

Date: 2026-04-23
Status: Approved (brainstorming)

## Purpose

Deliver operator-facing Telegram alerts on three server events so the team is notified without having to poll the DB or admin UI:

1. New user signup (any provider)
2. New gym registration request (`POST /places` with `type="gym"`, which enters `status="pending"` awaiting admin review)
3. Place improvement request (`POST /places/suggestions`)

Alerts are sent to a **single Telegram DM** (the operator's personal chat). Delivery is **best-effort, fire-and-forget** — request handling never blocks on or fails because of Telegram.

## Non-Goals

- No retries, no outbound queue, no rate-limit handling. If Telegram drops a notification, it is logged and lost.
- No admin-side actions via Telegram (approve/reject buttons, etc.).
- No separate channels per event type (single chat for all three).
- No runtime on/off flag — alerts are sent in **all environments** (local, staging, prod) as long as config is present.

## Configuration

Added to the `api-secret` Secret Manager YAML (already updated by the user):

```yaml
telegram:
  bot_token: "<bot token>"
  chat_id: "<operator chat id>"
```

Read via the existing `app.core.config.get("telegram.bot_token")` / `get("telegram.chat_id")` pattern.

For local development, the same keys are read from `services/api/settings.yaml`. Since the chat is the operator's personal DM, local runs will also deliver — this is intentional (see Q4 decision).

**Operational note:** the bot token originally shared in chat was exposed in plaintext. It should be revoked in Telegram and the replacement saved only in Secret Manager.

## Module: `services/api/app/services/telegram_notifier.py`

Single new module, no dependencies on existing services.

### Public API

```python
async def notify_new_user(user: User, provider: str) -> None
async def notify_place_registration_request(place: Place, requester: User) -> None
async def notify_place_improvement_request(
    suggestion: PlaceSuggestion, place: Place, requester: User
) -> None
```

- Each function builds the message text, then delegates to the internal `_send(text)`.
- Each function fully swallows exceptions internally — callers do **not** need `try/except`.

### Internal helpers

```python
async def _send(text: str) -> None
def _build_signup_text(user: User, provider: str) -> str
def _build_place_request_text(place: Place, requester: User) -> str
def _build_suggestion_text(
    suggestion: PlaceSuggestion, place: Place, requester: User
) -> str
```

Message builders are **pure functions** — unit-testable without mocks.

### HTTP call

`_send` uses a fresh `aiohttp.ClientSession` per call with `ClientTimeout(total=5)`. It does **not** reuse the request-scoped `get_http_client` dependency, because background tasks may outlive the originating request.

Request:
```
POST https://api.telegram.org/bot<TOKEN>/sendMessage
{
  "chat_id": <chat_id>,
  "text": <text>,
  "parse_mode": "HTML",
  "disable_web_page_preview": true
}
```

### Error handling

- `config.get` raises `ValueError` when keys are missing → `logger.error("telegram config missing: %s", exc)`, return. This is treated as a misconfigured deploy, not a per-request failure.
- HTTP 2xx with `{"ok": true}` → success, return.
- Any other HTTP status / response body → `logger.warning("telegram send failed: status=%s body=%s", status, body)`.
- `asyncio.TimeoutError`, `aiohttp.ClientError`, any other exception → `logger.warning("telegram notify error: %s", exc, exc_info=True)`.
- **Never** log the message body at warning level (the body contains PII: user email, name, profile id).

## Message Formats

HTML parse mode. The builders HTML-escape `&`, `<`, `>` in user-supplied fields. `None` / empty values render as `—`. Timestamps render in KST (`Asia/Seoul`) as `YYYY-MM-DD HH:mm`.

### 1. New user signup

```
🆕 <b>새 유저 가입</b>
이름: {user.name}
이메일: {user.email or "—"}
Provider: {provider}   # one of line/kakao/apple/google
Profile ID: {user.profile_id}
가입 시각: {signed_up_at_kst}
```

Provider is passed explicitly by the caller (each signup endpoint knows which provider it is) rather than inferred from `user.line / user.kakao / ...`.

### 2. New gym registration request

```
📍 <b>장소 등록 요청</b>
장소: {place.name}
좌표: {place.latitude}, {place.longitude}
Place ID: {place.id}
요청자: {requester.name} ({requester.profile_id})
커버: {place.cover_image_url or "—"}
```

Only sent when `place.type == "gym"` (private-gym is auto-approved, not reviewed).

### 3. Place improvement request

```
✏️ <b>장소 개선 요청</b>
장소: {place.name} ({place.id})
변경 제안:
  • 이름: {changes.name or "—"}
  • 좌표: {changes.latitude}, {changes.longitude} 또는 "—"
  • 이미지: {changes.cover_image_url or "—"}
요청자: {requester.name} ({requester.profile_id})
Suggestion ID: {suggestion.id}
```

The coordinate line reads "—" only when both lat and lng are unset.

## Router Integration

All integration points follow the existing best-effort pattern (see the `registration_ack` block in `routers/places.py`): schedule the notification via `background_tasks.add_task(...)` after the primary write succeeds.

### `routers/authentications.py` — 4 signup endpoints

Endpoints: `POST /sign-up/line`, `POST /sign-up/kakao`, `POST /sign-up/apple`, `POST /sign-up/google`.

Each signup endpoint must:
- Add a `background_tasks: BackgroundTasks` dependency (none of the four currently has it).
- After `await user.save()`, add:
  ```python
  background_tasks.add_task(
      telegram_notifier.notify_new_user, user, provider="line"
  )
  ```
  The provider literal differs per endpoint (`"line"`, `"kakao"`, `"apple"`, `"google"`).

### `routers/places.py` — `POST /` (create place)

Inside the existing `if place.type == "gym":` block, after the `registration_ack` notification is scheduled:
```python
background_tasks.add_task(
    telegram_notifier.notify_place_registration_request, place, current_user
)
```

`private-gym` creations are **not** notified (auto-approved, no review queue).

### `routers/places.py` — `POST /suggestions`

After `created = await suggestion.save()` and the existing `place_suggestion_ack` notification block:
```python
background_tasks.add_task(
    telegram_notifier.notify_place_improvement_request, created, place, current_user
)
```

## Testing

### `tests/services/test_telegram_notifier_messages.py` — pure-function tests
- `_build_signup_text` for each of the 4 providers.
- `_build_place_request_text` with and without `cover_image_url`.
- `_build_suggestion_text` with every permutation of which `changes` fields are set.
- `None` / empty-string rendering as `—`.
- HTML escape for user-supplied fields containing `&<>`.
- KST timestamp formatting.

### `tests/services/test_telegram_notifier_send.py` — `_send` behavior
Uses `unittest.mock` to patch the aiohttp client. **No real network calls.**

Cases:
- 200 + `ok: true` → correct URL and JSON body sent.
- Non-2xx response → `logger.warning` called, no exception raised.
- Response `{"ok": false, ...}` → `logger.warning`, no exception.
- `aiohttp.ClientError` raised by the client → swallowed, `logger.warning`.
- `asyncio.TimeoutError` raised → swallowed, `logger.warning`.
- `config.get` raises `ValueError` (missing keys) → HTTP call is **not** made, `logger.error` emitted.

### Router integration tests
Not added. The existing `registration_ack` flow is not covered by router-level tests either; we stay consistent. The wiring (`background_tasks.add_task(telegram_notifier.notify_*, ...)`) is verified by code review.

### Manual verification checklist (post-deploy)
- [ ] Signup with a test account on each of line / kakao / apple / google — 4 DMs received.
- [ ] `POST /places` with `type="gym"` — 1 DM received.
- [ ] `POST /places` with `type="private-gym"` — **no** DM (negative check).
- [ ] `POST /places/suggestions` on an approved gym — 1 DM received.

## File Summary

New:
- `services/api/app/services/telegram_notifier.py`
- `services/api/tests/services/test_telegram_notifier_messages.py`
- `services/api/tests/services/test_telegram_notifier_send.py`

Modified:
- `services/api/app/routers/authentications.py` — 4 signup endpoints.
- `services/api/app/routers/places.py` — `POST /` (gym branch) and `POST /suggestions`.

Config (external):
- Secret Manager `api-secret` YAML gains a `telegram:` block (already done).
- `services/api/settings.yaml` gains the same block for local development.
