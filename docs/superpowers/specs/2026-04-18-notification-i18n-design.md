# Notification i18n Design

Date: 2026-04-18

## Problem

알림 메시지(`title`, `body`)가 현재 생성 시점에 한국어로 렌더링되어 DB에 저장된다. 모바일 앱은 ko/en/ja/es를 지원하지만 알림은 항상 한국어로만 표시된다. 다국어 사용자에게 일관된 경험을 제공하려면 알림도 사용자의 언어로 보여야 한다.

## Goals

- 알림을 **요청 시점(GET)** 에 사용자 언어로 서버에서 렌더링한다.
- 사용자가 언어 설정을 바꾸면 과거 알림도 새 언어로 보인다.
- 기존 DB 레코드(한국어 `title`/`body`가 저장된)는 변경 없이 계속 표시된다(폴백).
- 신규 알림 타입 추가 시 템플릿 정의만으로 다국어 지원이 확장된다.

## Non-goals

- Place 자체의 i18n (이름 등). 지금은 생성 시점의 `place_name` 스냅샷을 `params`에 저장. 미래 개선 포인트로 기록.
- Push 알림 (FCM 등) i18n. 이번 범위는 인앱 알림 리스트(`GET /notifications`)만.
- 사용자별 locale을 User 프로필에 저장하는 작업. Accept-Language 헤더로만 결정.

## Design

### Locale 결정

- HTTP `Accept-Language` 헤더 파싱.
- 지원 로캘: `ko`, `en`, `ja`, `es` (모바일 ARB 파일과 동일).
- 폴백: `ko`.
- 파서는 첫 언어 태그의 primary subtag만 사용 (예: `ko-KR` → `ko`, `en-US` → `en`). quality value(`q=`) 분기는 일단 고려하지 않음.

### 스키마 변경: `Notification`

`app/models/notification.py`에 필드 추가:

```python
class Notification(Document):
    ...
    params: dict = Field(default_factory=dict, description="템플릿 렌더용 변수 스냅샷")
```

- 기존 `title`, `body` 필드는 **유지**한다. 스키마 이전 레코드는 이 두 필드를 그대로 반환하는 폴백 경로로 쓰인다.
- 신규 알림 생성 시 `title`/`body`는 빈 문자열로 저장하고 `params`를 채운다.

### 템플릿 저장소

`app/services/notification_templates.py`에 Python 상수로 정의.

```python
TEMPLATES = {
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

SUPPORTED_LOCALES = ("ko", "en", "ja", "es")
DEFAULT_LOCALE = "ko"
```

### 렌더러

`app/services/notification_renderer.py`:

```python
def render(notif: Notification, locale: str) -> tuple[str, str]:
    """Return (title, body) for a notification in the given locale.

    Falls back to stored title/body if template is missing or params is empty.
    """
    t = TEMPLATES.get(notif.type)
    if not t or not notif.params:
        return notif.title, notif.body

    def _pick(field: str) -> str:
        by_locale = t.get(field, {})
        tmpl = by_locale.get(locale) or by_locale.get(DEFAULT_LOCALE)
        if not tmpl:
            return getattr(notif, field)
        try:
            return tmpl.format(**notif.params)
        except (KeyError, IndexError):
            return getattr(notif, field)

    return _pick("title"), _pick("body")
```

### 라우터 변경

`app/routers/notifications.py`:

- `list_notifications`에 `accept_language: str = Header(None)` 인자 추가.
- 파싱하여 `locale` 결정.
- `notification_to_view`에 `locale`을 넘겨 `render(...)` 결과로 `title`/`body` 치환.

### 생성 사이트 변경

`app/routers/places.py` 2곳 (line 156, line 458):

- `Notification(...)` 생성 시 `title=""`, `body=""`로 두고 `params={"place_name": place.name}`로 저장.
- 기존 하드코딩된 문구는 제거.

예:
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

### 모바일 변경

`apps/mobile/lib/services/http_client.dart`에 요청 헤더로 `Accept-Language: <current_locale>`를 추가한다. 현재 앱 locale은 `Localizations.localeOf` 또는 앱의 locale provider에서 읽어 Dio interceptor로 주입.

### 테스트

`services/api/tests/routers/test_notifications.py`에 추가:
- 각 타입 × 각 지원 로캘에서 예상 title/body 반환.
- Accept-Language가 지원되지 않는 값(`fr`)이면 ko로 폴백.
- `params`가 비어 있는 구 레코드는 저장된 title/body 그대로 반환.
- 알 수 없는 `type`은 저장된 title/body 폴백.
- 템플릿에 없는 변수 참조 시 저장된 값 폴백(에러 아님).

`services/api/tests/routers/test_places.py` (기존 테스트가 있다면):
- 등록/제안 시 `Notification`에 `params.place_name`이 올바르게 저장되는지 확인.

## Migration

별도 DB 마이그레이션은 없다. 기존 레코드는 `params`가 빈 딕셔너리로 기본값이 들어가고, 렌더러가 폴백 경로로 저장된 `title`/`body`를 반환한다.

## Future improvements (TODO)

- **Place의 i18n 반영**: `params`에 스냅샷 문자열 대신 참조 디스크립터 저장.
  ```python
  params = {"place": {"kind": "place_ref", "id": "...", "fallback_name": "..."}}
  ```
  렌더 시점에 Place를 배치 조회해 현재 로캘 기준 이름 사용. Place가 삭제된 경우 `fallback_name` 사용.
- **Push 알림 i18n**: FCM 메시지 렌더에도 동일 템플릿 재사용.
- **User locale 저장**: 프로필에 `locale` 필드 추가 시 Accept-Language가 없는 서버사이드 알림 생성 등에 사용 가능.
- **Accept-Language quality value**: 현재는 첫 태그만 사용. 필요 시 `q=` 우선순위 고려.
