# 광고성 푸시 알림 수신 동의 설계

작성일: 2026-04-20
상태: 설계 확정, 구현 계획 대기

## 배경

현재 FCM 기반 푸시 파이프라인(`services/api/app/services/push_sender.py`, `apps/mobile/lib/services/push_service.dart`)은 거래/운영성 알림(`place_registration_ack`, `place_suggestion_ack`)만 발송한다. 향후 광고성 푸시를 보낼 여지를 고려해, **발송 계획보다 먼저 사용자 수신 동의를 수집·저장·검증하는 기반**을 마련한다.

정보통신망법 §50에 따라 영리목적의 광고성 정보 전송은 사전 동의가 필요하며, 동의 사실 증명 보존(§50 ⑥) 및 2년마다 재확인(§50 ⑧) 의무가 따른다. 본 설계는 법적 요구사항을 충족하면서도 현재 광고 발송이 없는 단계에 맞게 **YAGNI 원칙**으로 범위를 좁힌다.

## 적용 범위 결정

- **채널**: 푸시 한 채널만. 이메일/SMS는 추후 필요 시 필드 추가.
- **야간 발송**: 광고성 알림은 야간(21:00–08:00, 디바이스 로컬 기준)에 발송하지 않는다. 이 정책으로 **야간 수신 별도 동의는 받지 않는다**.
- **운영성 알림**: 사용자가 촉발한 행위에 대한 응답(`place_*_ack` 등)은 광고성에 해당하지 않아 **동의/야간 검사 없이 발송**한다.
- **재확인(reconfirm)**: 발송 게이트에서 "2년 경과 동의는 자동 무효"로 판정하는 안전장치만 이번 범위에 포함. 사용자 재동의 UI/배치는 광고 발송 착수 시점에 별도 스펙으로 분리.

## 데이터 모델

### `User` (`services/api/app/models/user.py`)

3개 필드 추가:

```python
marketing_push_consent: bool = False
marketing_push_consent_at: Optional[datetime] = None
marketing_push_consent_source: Optional[str] = None  # 'signup' | 'settings' | 'reconfirm'
```

- 동의 시: `(True, now, 'signup' | 'settings')`.
- 철회 시: `(False, now, 'settings')` — 가장 최근 액션만 보존. `at`/`source`가 시각과 경로를 증명.
- 기존 사용자: 기본값 `(False, None, None)`. 마이그레이션 불요.
- `'reconfirm'`은 장래 확장용으로 스키마에 남겨두되 이번 구현에서 쓰이지 않는다.

### `DeviceToken` (`services/api/app/models/device_token.py`)

1개 필드 추가:

```python
timezone: Optional[str] = Field(None, description="디바이스 IANA 타임존 (예: 'Asia/Seoul')")
```

- 빈 값이면 송신 시 `Asia/Seoul` 폴백.
- `locale` 필드는 **이미 존재**하며 발송기가 이를 사용해 다국어 렌더를 하고 있다. 모바일이 등록 시 실제로 전송하도록 연결만 한다(아래 "모바일" 참조).

### `Notification` — 변경 없음

**광고성 알림은 `Notification` 문서를 생성하지 않는다.** 광고는 인앱 알림 리스트/배지에 노출되지 않고 푸시 1회성으로만 발송된다. 따라서 `Notification` 모델에는 필드 변경이 없으며, `is_promotional` 같은 플래그도 추가하지 않는다.

## API

### 회원가입 엔드포인트 수정

영향 대상: `POST /authentications/sign-up/{line|kakao|apple|google}`

- 요청 body에 선택 필드 `marketingPushConsent: bool` 추가(기본 `false`).
- 서버 처리:
  - `True` → `User.marketing_push_consent=True`, `..._at=now`, `..._source='signup'`.
  - `False` → 세 필드 모두 기본값.

### 수신 동의 토글 엔드포인트 신설

`PATCH /my/marketing-consent`

```
request:  { "consent": bool }
response: 204
```

서버 처리:
- `True` → `(True, now, 'settings')`.
- `False` → `(False, now, 'settings')`. 철회 시각 보존을 위해 `at`도 갱신.

### 내 정보 응답 확장

기존의 사용자 자신 조회 응답(`GET /users/me` 또는 동등한 엔드포인트)에 세 필드를 함께 노출하여 설정 페이지가 현재 값을 그릴 수 있게 한다. 별도 조회 엔드포인트를 신설하지 않는다.

### `POST /my/devices` 확장

기존 `RegisterDeviceRequest`에 `timezone: Optional[str]` 추가. 값이 오면 저장, 없으면 기존 레코드 유지.

## 모바일 UI

### `TermsPage` (`apps/mobile/lib/pages/terms_page.dart`)

기존 필수 체크박스 2개(서비스 이용약관, 개인정보처리방침) 아래에 **선택** 체크박스 1개를 추가한다.

- 라벨: `광고성 알림 수신 동의 (선택)` (l10n 키 신규).
- 초기값 `false`, `_canProceed` 판정에 영향 없음.
- `_handleSignUp`이 각 `sign-up/*` POST 요청 body에 `marketingPushConsent: _isMarketingAgreed`를 포함.
- 보조 안내문(옵션): "광고성 알림은 야간(21–08시)에 발송되지 않으며, 설정에서 언제든지 변경할 수 있습니다."

### `SettingsPage` (`apps/mobile/lib/pages/setting.dart`)

언어 설정 아래에 `ListTile` 추가:

```
leading: Icons.notifications_outlined
title:   '알림' (l10n 키 신규)
onTap:   NotificationSettingsPage로 push
```

### 신규 `NotificationSettingsPage`

경로: `apps/mobile/lib/pages/notification_settings_page.dart`

- `SwitchListTile`: "광고성 알림 수신".
  - 부제에 현재 동의 상태(마지막 변경 시각) 요약 표시.
  - 토글 시 `PATCH /my/marketing-consent` 호출. 실패 시 스낵바, 원복.
- 하단 안내 문구:
  - "운영 관련 알림(예: 내가 제보한 장소의 처리 결과)은 이 설정과 무관하게 발송될 수 있습니다."
  - "광고성 알림은 야간(21–08시)에 발송되지 않습니다."

### `PushService` (`apps/mobile/lib/services/push_service.dart`)

`registerWithServer()` 호출 시 body에 다음을 포함시킨다:

- `locale`: 기기 로케일(예: `'ko-KR'`). `PlatformDispatcher.instance.locale.toLanguageTag()` 등으로 획득.
- `timezone`: IANA 타임존(예: `'Asia/Seoul'`). `flutter_timezone` 패키지로 1회 조회.

`pubspec.yaml`에 `flutter_timezone` 의존성 추가.

## 발송 경로 (`push_sender.py`)

운영성과 광고성은 **서로 다른 진입점**으로 분리한다.

### 운영성: `send_to_user(user_id, notif: Notification)` — 기존 유지

기존 동작 그대로. `Notification` 문서는 호출자(예: 라우터)가 이미 저장한 뒤 이 함수에 넘긴다. 동의/TTL/야간 검사 없음.

### 광고성: 신규 `send_promotional(user_id, title_by_locale, body_by_locale, link=None, data=None)`

```python
CONSENT_TTL = timedelta(days=730)

async def send_promotional(
    user_id: PydanticObjectId,
    title_by_locale: dict[str, str],  # {"ko": "...", "en": "...", ...}
    body_by_locale: dict[str, str],
    link: Optional[str] = None,
    data: Optional[dict[str, str]] = None,
) -> None:
    user = await User.find_one(User.id == user_id)
    if (not user
        or not user.marketing_push_consent
        or not user.marketing_push_consent_at
        or datetime.now(timezone.utc) - user.marketing_push_consent_at > CONSENT_TTL):
        return  # 동의 없음 / 2년 경과 / 사용자 없음

    devices = await DeviceToken.find(DeviceToken.user_id == user_id).to_list()
    if not devices:
        return

    # ... FCM 토큰 및 세션 준비 (send_to_user와 동일 헬퍼 재사용) ...

    async def _maybe_send(d: DeviceToken):
        tz_name = d.timezone or "Asia/Seoul"
        local_hour = datetime.now(ZoneInfo(tz_name)).hour
        if local_hour >= 21 or local_hour < 8:
            return
        primary = _primary_locale(d.locale)  # 기존 헬퍼
        title = title_by_locale.get(primary) or title_by_locale.get(DEFAULT_LOCALE)
        body = body_by_locale.get(primary) or body_by_locale.get(DEFAULT_LOCALE)
        if not title or not body:
            return
        await _send_one_raw(session, project_id, access_token, d, title, body, link, data)

    await asyncio.gather(*[_maybe_send(d) for d in devices], return_exceptions=True)
```

- **`Notification` 문서는 생성하지 않는다.**
- title/body를 호출자가 로케일별 dict로 직접 전달(템플릿 없음). 향후 캠페인 수가 늘면 `notification_templates.py`에 타입을 추가해 템플릿 기반으로 전환 가능 — 이번 범위에서는 미구현.
- 기존 `_send_one`은 `Notification`을 받는 구조이므로, `title`/`body`/`link`/`data`만 받는 경량 버전 `_send_one_raw`(또는 파라미터 분해)를 추출해 두 경로가 공용으로 사용한다. 토큰 무효 처리는 동일 로직.

## 딥링크 (탭 핸들러)

푸시 탭 시 기본 동작: **홈 탭으로 이동**. `data['link']`를 읽어 경로별로 분기하는 라우팅은 이번 범위에서 구현하지 않고, 향후 확장 여지로 핸들러만 깔아둔다.

`apps/mobile/lib/services/push_service.dart`:

- `FirebaseMessaging.onMessageOpenedApp` 콜백 — 탭해서 앱이 백그라운드에서 올라온 경우 → `Navigator.pushNamedAndRemoveUntil('/home', (r) => false)`.
- `FirebaseMessaging.getInitialMessage()` — 앱이 terminated 상태에서 푸시로 기동된 경우 → 마찬가지로 홈으로.
- `FirebaseMessaging.onMessage` — foreground 수신 시 라우팅 없음(기존 디버그 로그 유지, 필요 시 스낵바).
- 서버가 보내는 `data['link']`는 **현재 무시**. 필드는 계속 실려 보내지되 클라이언트 해석은 후속 작업으로 미룬다.

## 테스트 범위

`services/api/tests/services/test_push_sender.py`에 케이스 추가:

1. `send_promotional` + 미동의 → 어떤 디바이스로도 발송되지 않음.
2. `send_promotional` + 동의(`consent_at=now`) + 디바이스 로컬 22시 → 스킵.
3. `send_promotional` + 동의 + 디바이스 로컬 10시 → 발송. 디바이스 `locale`에 맞는 title/body 선택 확인.
4. `send_promotional` + 동의(`consent_at`이 731일 전) → TTL 초과로 미발송.
5. `send_promotional`은 **`Notification` 문서를 생성하지 않는다** — 호출 전후로 컬렉션 카운트가 동일한지 검증.
6. `send_to_user`(운영성) + 미동의 + 디바이스 로컬 23시 → 발송(기존 동작 유지).
7. `DeviceToken.timezone` 누락 시 `Asia/Seoul` 폴백.

라우터 테스트:

- `POST /authentications/sign-up/{provider}`에 `marketingPushConsent=True`로 호출 시 세 필드가 `(True, ~now, 'signup')`으로 기록.
- `PATCH /my/marketing-consent` 토글 시 `(bool, ~now, 'settings')` 기록.
- `POST /my/devices`에 `timezone`을 실어 보내면 저장되는지.

## 범위 외 (TODO 후속)

- 사용자가 직접 재동의하는 UI(JIT 모달 또는 배너) — 광고 발송 착수 시점에 별도 스펙(`reconfirm-flow-design.md`)으로 분리.
- 만료 도래 전 사전 고지 푸시/이메일, 자동 철회 배치.
- 이메일/SMS 채널 확장 시 `User`에 `marketing_email_consent_*` 세트 추가.
