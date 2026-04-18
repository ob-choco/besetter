# Profile ID (User Handle) Design

## Overview

모든 유저에게 고유한 `profile_id`(프로필 ID, 공개 식별자)를 부여한다. 가입 시 서버가 자동으로 12자의 임의 문자열을 생성해 unique하게 저장한다. 유저는 프로필 편집 모드에서 본인 프로필 ID를 원하는 값으로 자유롭게 변경할 수 있으며, 실시간으로 사용 가능 여부를 확인한다. 기존 유저는 배포 직전 1회성 백필 스크립트로 일괄 채운다.

MongoDB unique index로 무결성을 보장하고, 클라이언트에는 422/409 에러 코드 기반 구조화된 에러 응답으로 UI 메시지를 분리한다.

---

## Scope

포함:
- User 모델에 `profile_id` 필드 및 unique index 추가
- 신규 가입 4개 경로(line/kakao/apple/google)에 자동생성 로직 삽입
- 기존 유저 백필 스크립트
- 프로필 ID 검증/자동생성 공용 모듈
- `PATCH /users/me/profile-id`, `GET /users/me/profile-id/availability` 신규 엔드포인트
- `GET /users/me` 응답에 `profileId` 추가
- 내 프로필 화면에 `@profile_id` 표시
- 편집 모드 진입 시 프로필 ID 편집 아이콘 → 전용 다이얼로그 → PATCH 즉시 호출

비포함:
- 다른 유저 프로필 보기 기능 (현재 없음)
- 프로필 ID 기반 공유 링크(`/u/climber99` 같은) — 별도 스코프
- 프로필 ID 변경 이력 추적 / 쿨다운 / 횟수 제한 (자유 변경)

---

## Validation Rules

### 허용 규칙

- **Charset**: `[a-z0-9._]` — 소문자, 숫자, 점, 밑줄
- **길이**: 8 ~ 16자 (유저 편집 범위)
- **자동생성 길이**: 12자 고정
- **첫 글자**: 영숫자만 (`[a-z0-9]`)
- **끝 글자**: 영숫자만 (`[a-z0-9]`)
- **연속 특수문자 불허**: `..`, `__`, `._`, `_.` 모두 금지
- **예약어 불허** (아래 참조)

### 검증 정규식 (1차)

```
^(?=.{8,16}$)[a-z0-9]+([._][a-z0-9]+)*$
```

이 정규식은 길이, charset, 첫/끝, 연속 특수문자까지 한 번에 검증한다. 통과 후 2차로 예약어 체크.

### 에러 코드 우선순위

한 번에 하나의 에러 코드만 반환(순서 중요):

1. `PROFILE_ID_TOO_SHORT` — 8자 미만
2. `PROFILE_ID_TOO_LONG` — 16자 초과
3. `PROFILE_ID_INVALID_CHARS` — 허용 외 문자 포함
4. `PROFILE_ID_INVALID_START_END` — 첫/끝 글자가 영숫자 아님
5. `PROFILE_ID_CONSECUTIVE_SPECIAL` — `.`/`_` 연속
6. `PROFILE_ID_RESERVED` — 예약어 매칭
7. `PROFILE_ID_TAKEN` — 이미 사용 중 (unique index 충돌)

### 예약어 — 두 가지 매칭 전략

- **Exact match (O(1))** — `frozenset[str]` 기반. 시스템/플랫폼/API 경로/유저/컨텐츠/법률/개발자 등 카테고리 수백 개 수준. `admin`은 금지하되 `admin99`는 허용.
- **Substring match** — `tuple[str, ...]` 기반 선형 스캔. 욕설/혐오 표현 위주 30~50개. `fuck123`, `shitmaster` 같은 변형 차단.

예약어 리스트 전체 카테고리:
- 시스템/관리: `admin`, `administrator`, `root`, `system`, `superuser`, `sudo`, `moderator`, `mod`, `staff`, `owner`, `operator`
- 플랫폼: `besetter`, `besetterofficial`, `official`, `support`, `help`, `helpdesk`, `contact`, `info`, `faq`, `guide`, `docs`, `notice`
- API/경로: `api`, `www`, `app`, `web`, `mobile`, `ios`, `android`, `graphql`, `rest`, `static`, `assets`, `media`, `images`, `files`, `upload`, `download`, `cdn`
- 인증/보안: `auth`, `login`, `logout`, `signin`, `signup`, `register`, `password`, `token`, `session`, `security`, `verify`, `oauth`, `sso`
- 유저: `user`, `users`, `me`, `self`, `profile`, `account`, `guest`, `anonymous`, `null`, `undefined`, `nobody`, `everyone`, `all`
- 컨텐츠: `home`, `explore`, `search`, `discover`, `feed`, `trending`, `popular`, `new`, `latest`, `recommended`
- 도메인(클라이밍): `route`, `routes`, `place`, `places`, `gym`, `gyms`, `wall`, `walls`, `climb`, `climber`, `climbing`, `boulder`, `bouldering`, `lead`, `sport`, `trad`
- 결제/상거래: `billing`, `payment`, `payments`, `pay`, `checkout`, `cart`, `order`, `orders`, `subscribe`, `subscription`, `plan`, `pricing`, `store`, `shop`
- 법률: `terms`, `tos`, `privacy`, `policy`, `legal`, `license`, `copyright`, `dmca`, `abuse`, `report`
- 개발자: `dev`, `developer`, `developers`, `test`, `tests`, `testing`, `staging`, `production`, `beta`, `alpha`, `debug`

---

## Auto-Generation Algorithm

`services/api/app/core/profile_id.py`:

```python
import secrets

# 헷갈리는 문자 제외: 0, o, 1, l, i (대소문자 구분 없음 — 소문자만 씀)
_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"  # 31자

def generate_profile_id() -> str:
    return "".join(secrets.choice(_ALPHABET) for _ in range(12))


async def generate_unique_profile_id(max_attempts: int = 5) -> str:
    for _ in range(max_attempts):
        candidate = generate_profile_id()
        # 욕설 부분 포함 여부만 사후 필터 (exact-match 예약어는 alphabet상 불가능에 가까움)
        if _contains_profanity(candidate):
            continue
        if not await User.find_one({"profileId": candidate}):
            return candidate
    raise RuntimeError("Failed to generate unique profile_id")
```

- **엔트로피**: 31^12 ≈ 7.9 × 10^17. 100만 유저 기준 충돌 무시 가능.
- **헷갈리는 문자 제외**: `0`, `o`, `1`, `l`, `i` — 잘못 입력하기 쉬움.
- **특수문자 미포함**: 자동생성에는 `.`, `_`를 넣지 않음 → 연속 특수문자/시작끝 룰 자동 만족.
- **외부 의존성 없음**: `secrets` 표준 라이브러리만 사용.

---

## Data Model Changes

### User 모델 — `services/api/app/models/user.py`

```python
from pymongo import IndexModel, ASCENDING

class User(Document):
    ...
    profile_id: str  # Python 필드명. MongoDB에는 profileId로 저장됨 (model_config의 to_camel alias).
    ...

    class Settings:
        name = "users"
        keep_nulls = True
        indexes = [
            IndexModel([("profileId", ASCENDING)], unique=True),
        ]
```

- 타입: `str` (필수). 백필 후 전 유저 보유, 신규 유저는 가입 로직이 항상 생성.
- 인덱스: `profileId` unique. Beanie가 앱 기동 시 자동 생성.

### 배포 순서 (인덱스와 백필 충돌 방지)

1. 새 코드(profileId 필드 포함)가 적용된 서버는 아직 배포하지 않음.
2. 별도 환경에서 백필 스크립트 직접 실행 — 기존 유저 전원에게 profileId 채움.
3. DB 쿼리로 `profileId` 없는 유저 0건 확인.
4. 새 코드 배포 → Beanie가 기동 시 unique index 생성 → 이후 신규 가입은 unique index 보호를 받음.

---

## Backfill Script

`services/api/scripts/backfill_profile_ids.py`:

```python
"""
배포 직전 1회성 스크립트.
실행 순서:
  1. 기존 유저 전원에게 profileId 채움 (raw motor 쿼리, Beanie 미경유)
  2. 모두 채워진 것 확인 후 새 코드(profile_id 필수 필드) 배포
  3. 배포된 Beanie가 unique index 자동 생성

중도 재실행 안전: profileId가 이미 있는 유저는 건너뜀 (idempotent).
Beanie 우회 이유: 새 User 모델은 profile_id가 required라서 기존 document를
Beanie로 로드하면 Pydantic ValidationError 발생. raw motor로 필드 쓰기만 수행.
"""
import asyncio
import logging
from datetime import datetime, timezone

from motor.motor_asyncio import AsyncIOMotorClient

from app.core.config import get
from app.core.profile_id import generate_profile_id, _contains_profanity

log = logging.getLogger(__name__)


async def main():
    client = AsyncIOMotorClient(get("mongodb.url"))
    db = client[get("mongodb.name")]
    users = db["users"]

    cursor = users.find({"profileId": {"$exists": False}}, {"_id": 1})
    processed = 0
    failed = 0
    async for doc in cursor:
        for _ in range(10):
            candidate = generate_profile_id()
            if _contains_profanity(candidate):
                continue
            if await users.find_one({"profileId": candidate}, {"_id": 1}):
                continue
            await users.update_one(
                {"_id": doc["_id"]},
                {
                    "$set": {
                        "profileId": candidate,
                        "updatedAt": datetime.now(tz=timezone.utc),
                    }
                },
            )
            processed += 1
            break
        else:
            log.error("Failed to assign profileId for user %s", doc["_id"])
            failed += 1

    log.info("Backfilled %d users (%d failed)", processed, failed)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
```

- **Beanie 우회**: raw motor collection으로 직접 쿼리/업데이트. 새 User 모델의 required field 검증을 피함.
- **Idempotent**: `$exists: False` 필터로 이미 채운 유저 자동 제외.
- **soft-deleted 유저 포함**: `is_deleted=True` 유저에게도 채움. 추후 복원 시 응답 일관성을 위함.
- **unique index 없는 상태에서 실행**: `find_one`으로 사전 체크. 스크립트 실행 중 동시 신규 가입은 없다고 가정(배포 직전 실행).

---

## API Endpoints

### 1. `GET /users/me` (기존 확장)

응답 `UserProfileResponse`에 `profileId` 필드 추가:

```json
{
  "id": "...",
  "profileId": "climber_99",
  "name": "이한결",
  "email": "...",
  "bio": "...",
  "profileImageUrl": "...",
  "unreadNotificationCount": 0
}
```

`_build_profile_response` 헬퍼에 `profile_id=user.profile_id` 추가.

### 2. `PATCH /users/me/profile-id` (신규)

핸들 전용. name/bio/profile_image와 의미 분리(409 충돌 에러가 handle에만 발생).

```
요청: {"profileId": "climber_99"}
응답 200: UserProfileResponse (업데이트된 전체 프로필)

에러 422 (구조화 detail):
{
  "detail": {
    "code": "PROFILE_ID_TOO_SHORT" | "PROFILE_ID_TOO_LONG" |
            "PROFILE_ID_INVALID_CHARS" | "PROFILE_ID_INVALID_START_END" |
            "PROFILE_ID_CONSECUTIVE_SPECIAL" | "PROFILE_ID_RESERVED",
    "message": "..."
  }
}

에러 409 (중복):
{
  "detail": {
    "code": "PROFILE_ID_TAKEN",
    "message": "이미 사용 중인 프로필 ID입니다"
  }
}
```

처리 순서:
1. 정규식 검증 → 422 (`TOO_SHORT`/`TOO_LONG`/`INVALID_CHARS`/`INVALID_START_END`/`CONSECUTIVE_SPECIAL`)
2. 예약어 검증 (`RESERVED_EXACT` frozenset → `PROFANITY_SUBSTRINGS` 선형 스캔) → 422 (`RESERVED`)
3. `user.profile_id = new_value; await user.save()` → DuplicateKeyError catch → 409 (`TAKEN`)
4. 성공 시 `user.updated_at` 갱신, `_build_profile_response(user)` 반환.

### 3. `GET /users/me/profile-id/availability?value=...` (신규)

실시간 UX용. 항상 200을 반환하며 `available: bool`로 응답.

```
요청: GET /users/me/profile-id/availability?value=climber_99
응답 200:
{
  "value": "climber_99",
  "available": true,
  "reason": null
}

또는:
{
  "value": "admin",
  "available": false,
  "reason": "PROFILE_ID_RESERVED"
}
```

- `reason`은 PATCH에서 쓰는 422/409 코드 그대로 재사용.
- 본인의 현재 프로필 ID는 `available: true`로 반환(본인이 다시 써도 되므로).
- Race condition(availability→PATCH 사이 선점)은 PATCH의 409로 catch.

---

## Sign-Up Logic

`services/api/app/routers/authentications.py`의 4개 sign-up 엔드포인트(`line`, `kakao`, `apple`, `google`) — User 생성 직전에 핸들 생성:

```python
from app.core.profile_id import generate_unique_profile_id

...
profile_id = await generate_unique_profile_id()
user = User(
    id=ObjectId(),
    profile_id=profile_id,
    line=LineUser(...),  # or kakao/apple/google
    ...
)
```

각 경로에 동일한 한 줄씩 추가. 기존의 4경로 중복 구조는 이번 스코프에서 리팩토링하지 않는다.

---

## Mobile UI

### User 모델 (모바일)

`apps/mobile/lib/models/`의 User/Profile 관련 모델에 `profileId` 추가. JSON 역직렬화/직렬화 반영.

### 내 프로필 화면 — `my_page.dart`

**기본 상태 (읽기 전용)**:

```
[프로필 이미지]
  이한결
  @climber_99
  bio...
```

- `@profile_id`는 이름 바로 아래 표시. muted 스타일(예: `Theme.of(context).colorScheme.onSurfaceVariant`).
- 탭 액션 없음. 편집은 오직 상단 편집 버튼으로 진입.

**편집 모드 (`isEditing.value == true`)**:

```
[프로필 이미지]
  [이름 입력 필드]
  @climber_99  [✏️]   ← 편집 아이콘
  [bio 입력 필드]
```

- `@climber_99` 옆에 ✏️ 편집 아이콘 노출.
- 편집 아이콘 탭 → 프로필 ID 편집 다이얼로그 오픈.
- 이름/bio 저장과 **독립적**: 다이얼로그 내 확인 버튼에서 `PATCH /users/me/profile-id`를 즉시 호출.

### 프로필 ID 편집 다이얼로그

```
┌─ 프로필 ID 수정 ────────────────┐
│                                │
│ [@][climber_99____________ ]  │
│                                │
│  ✓ 사용 가능한 프로필 ID입니다  │
│                                │
│          [취소]  [확인]        │
└────────────────────────────────┘
```

동작:
- `TextField`, 프리픽스 `@`. `inputFormatters`로 `[a-z0-9._]`만 키입력 단계에서 허용. `maxLength: 16`.
- 입력 변화 시 500ms debounce → `GET /users/me/profile-id/availability?value=...` 호출.
- 상태별 힌트:
  - 빈 값 또는 현재 프로필 ID와 동일: 힌트 없음, 확인 버튼 비활성
  - 로딩 중: `확인 중...` + 스피너
  - `available: true`: 녹색 ✓ `사용 가능한 프로필 ID입니다`, 확인 버튼 활성
  - `available: false`: 빨간 ✗ + `reason` 코드별 메시지(아래), 확인 버튼 비활성
- **확인 버튼** (활성 시): `PATCH /users/me/profile-id` 호출 →
  - 성공: `ref.invalidate(userProfileProvider)` → 다이얼로그 pop(`true`) → 스낵바 `프로필 ID가 변경됐어요`
  - 409: `이미 사용 중인 프로필 ID입니다` inline 표시, 다이얼로그 유지
  - 422: 해당 코드 메시지 inline 표시, 다이얼로그 유지
- **취소 버튼**: 다이얼로그 pop(`false`), 변경 없음.

### reason 코드별 한글 메시지

- `PROFILE_ID_TOO_SHORT` → `8자 이상 입력해 주세요`
- `PROFILE_ID_TOO_LONG` → `16자 이하로 입력해 주세요`
- `PROFILE_ID_INVALID_CHARS` → `소문자, 숫자, 점(.), 밑줄(_)만 사용할 수 있습니다`
- `PROFILE_ID_INVALID_START_END` → `첫 글자와 끝 글자는 영문 소문자 또는 숫자여야 합니다`
- `PROFILE_ID_CONSECUTIVE_SPECIAL` → `점(.)과 밑줄(_)을 연속해서 쓸 수 없습니다`
- `PROFILE_ID_RESERVED` → `사용할 수 없는 프로필 ID입니다`
- `PROFILE_ID_TAKEN` → `이미 사용 중인 프로필 ID입니다`

### i18n

위 메시지 7종 + `사용 가능한 프로필 ID입니다`, `확인 중...`, `프로필 ID`(라벨), `프로필 ID 수정`(다이얼로그 제목), `프로필 ID가 변경됐어요`(스낵바) 등을 4개 locale(`app_ko.arb` / `app_en.arb` / `app_ja.arb` / `app_es.arb`)에 추가. 기존 i18n 컨벤션 유지.

### API 클라이언트

```dart
Future<AvailabilityResult> checkProfileIdAvailability(String value);
// {available, reason} 반환. 에러 던지지 않음.

Future<UserProfile> updateProfileId(String value);
// 성공 시 업데이트된 UserProfile 반환.
// 422/409 시 code 필드를 담은 ProfileIdError 예외 던짐 → UI에서 catch.
```

---

## Error Handling Patterns

- 기존 `PLACE_NOT_USABLE` 패턴과 동일하게 `detail = {"code": "...", "message": "..."}` 구조를 사용.
- 모바일 API 레이어에서 `detail`의 `code` 필드를 추출해 타입드 예외(`ProfileIdError`)로 변환.
- UI는 예외의 `code`를 switch해서 해당 reason 메시지 inline 표시.

---

## Testing

### 백엔드 단위 테스트

- `profile_id.py` — 정규식 검증, 자동생성 분포, 예약어 체크(exact/substring 분리).
- `generate_unique_profile_id` — mock collision 시 재시도, max_attempts 초과 시 에러.

### 백엔드 통합 테스트

- `PATCH /users/me/profile-id` 엔드포인트:
  - 각 422 케이스(TOO_SHORT/TOO_LONG/INVALID_CHARS/INVALID_START_END/CONSECUTIVE_SPECIAL/RESERVED)
  - 409 TAKEN (다른 유저가 선점된 값 요청)
  - 200 성공
- `GET /users/me/profile-id/availability`:
  - 사용 가능 / 예약어 / 중복 / 본인 현재값
  - 검증 실패(형식 오류) 시 `available: false` + 해당 reason.

### 백필 스크립트

- 수동 1회 실행이라 단위 테스트 불필요. 스테이징 DB에서 dry-run 후 프로덕션 실행.

### 모바일

- `flutter analyze` 통과 필수.
- 위젯 테스트는 기존 관례를 따르되 추가 부담은 지지 않음.

---

## Rollout Plan

1. 코드 변경 구현 완료 및 로컬/스테이징 테스트 통과.
2. 스테이징 DB로 백필 스크립트 dry-run → 샘플 유저 `profileId` 확인.
3. 프로덕션 DB로 백필 스크립트 실행 → `profileId` 없는 유저 0건 확인.
4. API 서버 배포 → Beanie가 `profileId` unique index 생성 → 기동 후 로그 확인.
5. 모바일 앱 배포(스토어 심사 후) → 기존 유저는 다음 로그인 시 `GET /users/me`로 `profileId` 수신.

---

## Open Questions / Non-Goals

- 다른 유저 프로필 페이지는 이번 스코프 외. 추후 추가 시 `@profile_id` 기반 URL(예: `/u/climber_99`)을 재사용할 수 있게 설계는 열어둠.
- 프로필 ID 변경 알림(다른 기기에 로그인 중인 본인에게 푸시)은 필요 없음 — `ref.invalidate(userProfileProvider)`로 당 기기만 갱신.
- 욕설 리스트는 향후 커지면 Aho–Corasick 등으로 교체 고려. 지금은 선형 스캔(YAGNI).
