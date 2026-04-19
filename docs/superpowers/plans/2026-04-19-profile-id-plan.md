# Profile ID (User Handle) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 모든 유저에게 자동생성 12자 unique `profile_id`를 부여하고, 프로필 편집 모드에서 다이얼로그로 변경 가능하게 한다.

**Architecture:** 백엔드는 공용 검증/생성 모듈(`app/core/profile_id.py`)을 만들고 신규 가입 4경로와 신규 PATCH/availability 엔드포인트가 이를 재사용한다. 기존 유저는 Beanie를 우회하는 raw-motor 스크립트로 1회 백필한 뒤 unique index를 생성한다. 모바일은 my_page 편집 모드에서 편집 아이콘을 노출하고, 별도 다이얼로그 위젯에서 실시간 availability 체크 후 즉시 PATCH를 호출한다.

**Tech Stack:** FastAPI + Beanie (MongoDB), Flutter + hooks_riverpod, pytest, flutter analyze.

**Spec:** `docs/superpowers/specs/2026-04-19-profile-id-design.md`

---

## File Structure

### 신규 파일 (backend)

- `services/api/app/core/profile_id_reserved.py` — exact-match `frozenset` + substring `tuple` 데이터.
- `services/api/app/core/profile_id.py` — 검증 함수, 자동생성 함수, 에러 코드 enum.
- `services/api/scripts/backfill_profile_ids.py` — 1회성 raw motor 백필 스크립트.
- `services/api/tests/core/test_profile_id.py` — 검증/생성/예약어 단위 테스트.

### 수정 파일 (backend)

- `services/api/app/models/user.py` — `profile_id: str` 필드, `profileId` unique index.
- `services/api/app/routers/authentications.py` — 4개 sign-up 경로에 `generate_unique_profile_id` 호출 삽입.
- `services/api/app/routers/users.py` — `UserProfileResponse.profile_id` 추가, PATCH/availability 엔드포인트 추가.
- `services/api/tests/routers/test_users.py` — profileId 직렬화, PATCH 검증 핸들러 테스트.

### 신규 파일 (mobile)

- `apps/mobile/lib/widgets/editors/profile_id_edit_dialog.dart` — 편집 다이얼로그 위젯.

### 수정 파일 (mobile)

- `apps/mobile/lib/providers/user_provider.dart` — `UserState.profileId` 추가, `updateProfileId` + `checkProfileIdAvailability` 추가.
- `apps/mobile/lib/providers/user_provider.g.dart` — `build_runner` 자동 생성 산출물.
- `apps/mobile/lib/pages/my_page.dart` — `@profileId` 표시, 편집 모드 시 편집 아이콘 → 다이얼로그 오픈.
- `apps/mobile/lib/l10n/app_ko.arb`, `app_en.arb`, `app_ja.arb`, `app_es.arb` — 12개 i18n 키 추가.

---

## Task 1: 예약어 리스트 데이터 모듈

**Files:**
- Create: `services/api/app/core/profile_id_reserved.py`

- [ ] **Step 1: 파일 생성**

```python
# services/api/app/core/profile_id_reserved.py
"""
예약어 / 욕설 데이터. profile_id.py의 검증 함수가 이 모듈을 참조한다.

RESERVED_EXACT: 정확히 일치하는 경우만 차단. O(1) 조회를 위해 frozenset.
PROFANITY_SUBSTRINGS: 부분 포함만 돼도 차단. 리스트 짧으니 선형 스캔.
"""

RESERVED_EXACT: frozenset[str] = frozenset(
    {
        # 시스템/관리
        "admin", "administrator", "root", "system", "superuser", "sudo",
        "moderator", "mod", "staff", "owner", "operator",
        # 플랫폼
        "besetter", "besetterofficial", "official", "support", "help",
        "helpdesk", "contact", "info", "faq", "guide", "docs", "notice",
        # API/경로
        "api", "www", "app", "web", "mobile", "ios", "android", "graphql",
        "rest", "static", "assets", "media", "images", "files", "upload",
        "download", "cdn",
        # 인증/보안
        "auth", "login", "logout", "signin", "signup", "register",
        "password", "token", "session", "security", "verify", "oauth", "sso",
        # 유저
        "user", "users", "me", "self", "profile", "account", "guest",
        "anonymous", "null", "undefined", "nobody", "everyone", "all",
        # 컨텐츠
        "home", "explore", "search", "discover", "feed", "trending",
        "popular", "new", "latest", "recommended",
        # 도메인 (클라이밍)
        "route", "routes", "place", "places", "gym", "gyms", "wall", "walls",
        "climb", "climber", "climbing", "boulder", "bouldering", "lead",
        "sport", "trad",
        # 결제/상거래
        "billing", "payment", "payments", "pay", "checkout", "cart", "order",
        "orders", "subscribe", "subscription", "plan", "pricing", "store",
        "shop",
        # 법률
        "terms", "tos", "privacy", "policy", "legal", "license", "copyright",
        "dmca", "abuse", "report",
        # 개발자
        "dev", "developer", "developers", "test", "tests", "testing",
        "staging", "production", "beta", "alpha", "debug",
    }
)

PROFANITY_SUBSTRINGS: tuple[str, ...] = (
    # 영문
    "fuck", "shit", "bitch", "asshole", "bastard", "dick", "pussy", "cock",
    "cunt", "whore", "slut", "faggot", "nigger", "retard", "nazi",
    # 한글 로마자
    "siba", "sibal", "ssibal", "gaesaeki", "gaesaekki", "jotna", "jonna",
    "byungshin", "byungsin", "michinnom", "michinnyeon", "gechaek",
    "gaechaek", "jibjang", "jotmani", "jotmanj", "jotmadchi",
)
```

- [ ] **Step 2: Commit**

```bash
git add services/api/app/core/profile_id_reserved.py
git commit -m "feat(api): add profile_id reserved words and profanity data"
```

---

## Task 2: profile_id 검증 및 자동생성 코어 모듈

**Files:**
- Create: `services/api/app/core/profile_id.py`
- Create: `services/api/tests/core/test_profile_id.py`

- [ ] **Step 1: 실패 테스트 작성 — 에러 코드 Enum**

```python
# services/api/tests/core/test_profile_id.py
"""Tests for profile_id validation and generation."""

from app.core.profile_id import (
    ProfileIdError,
    generate_profile_id,
    validate_profile_id,
)


def test_profile_id_error_codes_are_stable_strings():
    """ProfileIdError enum values are used in HTTP responses; must be stable."""
    assert ProfileIdError.TOO_SHORT.value == "PROFILE_ID_TOO_SHORT"
    assert ProfileIdError.TOO_LONG.value == "PROFILE_ID_TOO_LONG"
    assert ProfileIdError.INVALID_CHARS.value == "PROFILE_ID_INVALID_CHARS"
    assert ProfileIdError.INVALID_START_END.value == "PROFILE_ID_INVALID_START_END"
    assert ProfileIdError.CONSECUTIVE_SPECIAL.value == "PROFILE_ID_CONSECUTIVE_SPECIAL"
    assert ProfileIdError.RESERVED.value == "PROFILE_ID_RESERVED"
    assert ProfileIdError.TAKEN.value == "PROFILE_ID_TAKEN"
```

- [ ] **Step 2: Run tests — verify fail**

```
cd services/api && pytest tests/core/test_profile_id.py -v
```

Expected: FAIL — `ImportError: cannot import name 'ProfileIdError'`

- [ ] **Step 3: Minimal 구현 — 파일 생성**

```python
# services/api/app/core/profile_id.py
"""profile_id validation, generation, and availability helpers.

Used by:
- sign-up paths (authentications.py) — assign random id at user creation
- PATCH /users/me/profile-id — user-driven edits
- GET availability endpoint — real-time UX
- backfill script — one-shot migration
"""

from __future__ import annotations

import re
import secrets
from enum import Enum
from typing import Optional

from app.core.profile_id_reserved import PROFANITY_SUBSTRINGS, RESERVED_EXACT


class ProfileIdError(str, Enum):
    TOO_SHORT = "PROFILE_ID_TOO_SHORT"
    TOO_LONG = "PROFILE_ID_TOO_LONG"
    INVALID_CHARS = "PROFILE_ID_INVALID_CHARS"
    INVALID_START_END = "PROFILE_ID_INVALID_START_END"
    CONSECUTIVE_SPECIAL = "PROFILE_ID_CONSECUTIVE_SPECIAL"
    RESERVED = "PROFILE_ID_RESERVED"
    TAKEN = "PROFILE_ID_TAKEN"


# 헷갈리는 문자 제외: 0, o, 1, l, i
_ALPHABET: str = "abcdefghjkmnpqrstuvwxyz23456789"
_AUTOGEN_LENGTH: int = 12
_MIN_LENGTH: int = 8
_MAX_LENGTH: int = 16

_ALLOWED_CHARS_RE = re.compile(r"^[a-z0-9._]+$")
_ALPHANUM_RE = re.compile(r"[a-z0-9]")
_CONSECUTIVE_SPECIAL_RE = re.compile(r"[._]{2}")


def generate_profile_id() -> str:
    """Return a random 12-char profile_id from the safe alphabet."""
    return "".join(secrets.choice(_ALPHABET) for _ in range(_AUTOGEN_LENGTH))


def _contains_profanity(value: str) -> bool:
    return any(bad in value for bad in PROFANITY_SUBSTRINGS)


def validate_profile_id(value: str) -> Optional[ProfileIdError]:
    """Return the first validation error, or None if the value is valid."""
    if len(value) < _MIN_LENGTH:
        return ProfileIdError.TOO_SHORT
    if len(value) > _MAX_LENGTH:
        return ProfileIdError.TOO_LONG
    if not _ALLOWED_CHARS_RE.match(value):
        return ProfileIdError.INVALID_CHARS
    if not _ALPHANUM_RE.match(value[0]) or not _ALPHANUM_RE.match(value[-1]):
        return ProfileIdError.INVALID_START_END
    if _CONSECUTIVE_SPECIAL_RE.search(value):
        return ProfileIdError.CONSECUTIVE_SPECIAL
    if value in RESERVED_EXACT or _contains_profanity(value):
        return ProfileIdError.RESERVED
    return None
```

- [ ] **Step 4: Run tests — verify pass**

```
cd services/api && pytest tests/core/test_profile_id.py -v
```

Expected: PASS.

- [ ] **Step 5: validate_profile_id 테스트 추가**

```python
# append to services/api/tests/core/test_profile_id.py

import pytest


@pytest.mark.parametrize(
    "value",
    [
        "climber99",
        "climber_99",
        "climb.er99",
        "abcdefgh",          # 8 chars exact
        "abcdefghij012345",  # 16 chars exact
        "a1b2c3d4",
    ],
)
def test_validate_accepts_valid_values(value):
    assert validate_profile_id(value) is None


def test_validate_too_short():
    assert validate_profile_id("abc123") is ProfileIdError.TOO_SHORT


def test_validate_too_long():
    assert validate_profile_id("a" * 17) is ProfileIdError.TOO_LONG


@pytest.mark.parametrize("value", ["Climber99", "climber-99", "climber 99", "한글이름aa", "user@name"])
def test_validate_invalid_chars(value):
    assert validate_profile_id(value) is ProfileIdError.INVALID_CHARS


@pytest.mark.parametrize("value", ["_climber9", "9climber_", ".climber9", "climber9."])
def test_validate_invalid_start_end(value):
    assert validate_profile_id(value) is ProfileIdError.INVALID_START_END


@pytest.mark.parametrize("value", ["clim__ber", "clim..ber", "clim._ber", "clim_.ber"])
def test_validate_consecutive_special(value):
    assert validate_profile_id(value) is ProfileIdError.CONSECUTIVE_SPECIAL


@pytest.mark.parametrize("value", ["admin123", "climber99"])
def test_validate_accepts_substring_of_reserved(value):
    """`admin` is reserved (exact) but `admin123` is not."""
    assert validate_profile_id(value) is None


@pytest.mark.parametrize("value", ["admin", "besetter", "support", "me000000"])
def test_validate_reserved_exact(value):
    # "me000000" — reserved "me" only blocks exact match; 8-char padded should pass.
    # Adjust: exact match only. "me" itself is too short so can't be submitted directly.
    # Skip values that can't be length-valid.
    err = validate_profile_id(value)
    if len(value) < 8:
        assert err is ProfileIdError.TOO_SHORT
    else:
        assert err is ProfileIdError.RESERVED or err is None


def test_validate_profanity_substring():
    """Profanity is blocked by substring match (unlike exact-match reserved)."""
    assert validate_profile_id("fuck1234") is ProfileIdError.RESERVED
    assert validate_profile_id("abcshitab") is ProfileIdError.RESERVED
```

- [ ] **Step 6: Run — verify pass**

```
cd services/api && pytest tests/core/test_profile_id.py -v
```

Expected: PASS for all parametrized cases.

- [ ] **Step 7: generate_profile_id 테스트 추가**

```python
# append to services/api/tests/core/test_profile_id.py

def test_generate_profile_id_length_and_charset():
    for _ in range(50):
        value = generate_profile_id()
        assert len(value) == 12
        assert validate_profile_id(value) is None  # autogen values always valid


def test_generate_profile_id_is_random():
    seen = {generate_profile_id() for _ in range(100)}
    # With 31^12 entropy, 100 samples should never collide.
    assert len(seen) == 100
```

- [ ] **Step 8: Run — verify pass**

```
cd services/api && pytest tests/core/test_profile_id.py -v
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add services/api/app/core/profile_id.py services/api/tests/core/test_profile_id.py
git commit -m "feat(api): add profile_id validation and generation core module"
```

---

## Task 3: generate_unique_profile_id (DB 중복 체크 + 재시도)

**Files:**
- Modify: `services/api/app/core/profile_id.py`
- Modify: `services/api/tests/core/test_profile_id.py`

- [ ] **Step 1: 실패 테스트 작성**

```python
# append to services/api/tests/core/test_profile_id.py

from unittest.mock import AsyncMock, patch
import pytest

from app.core.profile_id import generate_unique_profile_id


@pytest.mark.asyncio
async def test_generate_unique_profile_id_first_try():
    """Returns the first candidate when not taken."""
    with patch("app.core.profile_id.User") as MockUser:
        MockUser.find_one = AsyncMock(return_value=None)
        result = await generate_unique_profile_id()
        assert len(result) == 12
        MockUser.find_one.assert_awaited_once()


@pytest.mark.asyncio
async def test_generate_unique_profile_id_retries_on_collision():
    """Retries when find_one returns an existing user."""
    existing = object()
    with patch("app.core.profile_id.User") as MockUser:
        MockUser.find_one = AsyncMock(side_effect=[existing, existing, None])
        result = await generate_unique_profile_id()
        assert len(result) == 12
        assert MockUser.find_one.await_count == 3


@pytest.mark.asyncio
async def test_generate_unique_profile_id_exhaustion_raises():
    """Raises after max_attempts collisions."""
    existing = object()
    with patch("app.core.profile_id.User") as MockUser:
        MockUser.find_one = AsyncMock(return_value=existing)
        with pytest.raises(RuntimeError, match="Failed to generate unique"):
            await generate_unique_profile_id(max_attempts=3)
```

- [ ] **Step 2: Run — verify fail**

```
cd services/api && pytest tests/core/test_profile_id.py::test_generate_unique_profile_id_first_try -v
```

Expected: FAIL — `ImportError: cannot import name 'generate_unique_profile_id'`

- [ ] **Step 3: 구현 추가**

Append to `services/api/app/core/profile_id.py`:

```python
from app.models.user import User


async def generate_unique_profile_id(max_attempts: int = 5) -> str:
    """Return a random profile_id that isn't taken yet.

    Retries on collision (or on accidental profanity match). Raises if we can't
    find a free value within max_attempts.
    """
    for _ in range(max_attempts):
        candidate = generate_profile_id()
        if _contains_profanity(candidate):
            continue
        existing = await User.find_one({"profileId": candidate})
        if existing is None:
            return candidate
    raise RuntimeError("Failed to generate unique profile_id")
```

- [ ] **Step 4: Install pytest-asyncio if missing**

```
cd services/api && uv add --dev pytest-asyncio
```

If already installed: skip. Confirm `pytest.ini` or `pyproject.toml` has `asyncio_mode = "auto"` or add `@pytest.mark.asyncio`. (Tests above already mark explicitly.)

- [ ] **Step 5: Run tests — verify pass**

```
cd services/api && pytest tests/core/test_profile_id.py -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add services/api/app/core/profile_id.py services/api/tests/core/test_profile_id.py services/api/pyproject.toml services/api/uv.lock
git commit -m "feat(api): add generate_unique_profile_id with DB collision retry"
```

---

## Task 4: User 모델에 profile_id 필드 + unique index 추가

**Files:**
- Modify: `services/api/app/models/user.py`

- [ ] **Step 1: User 문서에 필드와 인덱스 추가**

Replace the contents of `services/api/app/models/user.py` (final version — note the new import and changes in User class only):

```python
from datetime import datetime
from typing import Optional
from beanie import Document
from pydantic import BaseModel
from pymongo import ASCENDING, IndexModel

from . import model_config


class LineUser(BaseModel):
    model_config = model_config

    unique_id: str

    signed_up_at: datetime
    last_login_at: datetime
    last_logout_at: Optional[datetime] = None

    email: Optional[str] = None
    name: Optional[str] = None
    profile_image_url: Optional[str] = None


class KakaoUser(BaseModel):
    model_config = model_config

    unique_id: str

    signed_up_at: datetime
    last_login_at: datetime
    last_logout_at: Optional[datetime] = None

    email: Optional[str] = None
    name: Optional[str] = None
    profile_image_url: Optional[str] = None


class AppleUser(BaseModel):
    model_config = model_config

    unique_id: str

    signed_up_at: datetime
    last_login_at: datetime
    last_logout_at: Optional[datetime] = None

    email: Optional[str] = None


class GoogleUser(BaseModel):
    model_config = model_config

    unique_id: str

    signed_up_at: datetime
    last_login_at: datetime
    last_logout_at: Optional[datetime] = None

    email: Optional[str] = None
    name: Optional[str] = None
    profile_image_url: Optional[str] = None


class User(Document):
    model_config = model_config

    profile_id: str
    name: Optional[str] = None
    email: Optional[str] = None
    profile_image_url: Optional[str] = None
    bio: Optional[str] = None
    unread_notification_count: int = 0

    refresh_token: Optional[str] = None

    line: Optional[LineUser] = None
    kakao: Optional[KakaoUser] = None
    apple: Optional[AppleUser] = None
    google: Optional[GoogleUser] = None

    is_deleted: bool = False
    deleted_at: Optional[datetime] = None

    created_at: datetime
    updated_at: datetime

    class Settings:
        name = "users"
        keep_nulls = True
        indexes = [
            IndexModel([("profileId", ASCENDING)], unique=True),
        ]
```

- [ ] **Step 2: 앱 부팅 smoke 체크 (lint)**

```
cd services/api && uv run ruff check app/models/user.py
```

Expected: no errors.

- [ ] **Step 3: 기존 User 관련 단위 테스트가 여전히 pass하는지 확인**

```
cd services/api && pytest tests/routers/test_users.py -v
```

Expected: 일부 테스트 FAIL — `_make_user` helper가 `profile_id`를 제공하지 않기 때문. 다음 태스크에서 수정. 지금은 import 에러나 수집 에러만 없으면 OK.

만약 import/수집 에러가 있으면 먼저 그것부터 해결.

- [ ] **Step 4: Commit**

```bash
git add services/api/app/models/user.py
git commit -m "feat(api): add profile_id field and unique index to User"
```

---

## Task 5: Sign-up 4경로에 profile_id 자동 부여

**Files:**
- Modify: `services/api/app/routers/authentications.py`

- [ ] **Step 1: import 추가**

Add to the imports block of `services/api/app/routers/authentications.py`:

```python
from app.core.profile_id import generate_unique_profile_id
```

- [ ] **Step 2: Line sign-up 수정**

In `services/api/app/routers/authentications.py` around line 171–188 (the `sign-up/line` endpoint's User construction), replace:

```python
    now = datetime.now(tz=pytz.UTC)

    user = User(
        id=ObjectId(),
        line=LineUser(
            unique_id=result["sub"],
            name=result["name"],
            profile_image_url=result.get("picture"),
            email=result.get("email"),
            last_login_at=now,
            signed_up_at=now,
        ),
        name=result["name"],
        email=result.get("email"),
        profile_image_url=result.get("picture"),
        created_at=now,
        updated_at=now,
    )
```

with:

```python
    now = datetime.now(tz=pytz.UTC)
    profile_id = await generate_unique_profile_id()

    user = User(
        id=ObjectId(),
        profile_id=profile_id,
        line=LineUser(
            unique_id=result["sub"],
            name=result["name"],
            profile_image_url=result.get("picture"),
            email=result.get("email"),
            last_login_at=now,
            signed_up_at=now,
        ),
        name=result["name"],
        email=result.get("email"),
        profile_image_url=result.get("picture"),
        created_at=now,
        updated_at=now,
    )
```

- [ ] **Step 3: Kakao sign-up 수정**

In the same file around line 266–283 (the `sign-up/kakao` endpoint), replace:

```python
    now = datetime.now(tz=pytz.UTC)

    user = User(
        id=ObjectId(),
        kakao=KakaoUser(
            unique_id=result["sub"],
            name=result.get("nickname"),
            profile_image_url=result.get("picture"),
            email=result.get("email"),
            last_login_at=now,
            signed_up_at=now,
        ),
        name=result.get("nickname"),
        email=result.get("email"),
        profile_image_url=result.get("picture"),
        created_at=now,
        updated_at=now,
    )
```

with:

```python
    now = datetime.now(tz=pytz.UTC)
    profile_id = await generate_unique_profile_id()

    user = User(
        id=ObjectId(),
        profile_id=profile_id,
        kakao=KakaoUser(
            unique_id=result["sub"],
            name=result.get("nickname"),
            profile_image_url=result.get("picture"),
            email=result.get("email"),
            last_login_at=now,
            signed_up_at=now,
        ),
        name=result.get("nickname"),
        email=result.get("email"),
        profile_image_url=result.get("picture"),
        created_at=now,
        updated_at=now,
    )
```

- [ ] **Step 4: Apple sign-up 수정**

In the same file around line 391–404 (the `sign-up/apple` endpoint), replace:

```python
    now = datetime.now(tz=pytz.UTC)

    user = User(
        id=ObjectId(),
        apple=AppleUser(
            unique_id=unique_id,
            email=payload.get("email"),
            last_login_at=now,
            signed_up_at=now,
        ),
        email=payload.get("email"),
        created_at=now,
        updated_at=now,
    )
```

with:

```python
    now = datetime.now(tz=pytz.UTC)
    profile_id = await generate_unique_profile_id()

    user = User(
        id=ObjectId(),
        profile_id=profile_id,
        apple=AppleUser(
            unique_id=unique_id,
            email=payload.get("email"),
            last_login_at=now,
            signed_up_at=now,
        ),
        email=payload.get("email"),
        created_at=now,
        updated_at=now,
    )
```

- [ ] **Step 5: Google sign-up 수정**

In the same file around line 459–476 (the `sign-up/google` endpoint), replace:

```python
    now = datetime.now(tz=pytz.UTC)

    user = User(
        id=ObjectId(),
        google=GoogleUser(
            unique_id=unique_id,
            email=id_info.get("email"),
            name=id_info.get("name"),
            profile_image_url=id_info.get("picture"),
            last_login_at=now,
            signed_up_at=now,
        ),
        email=id_info.get("email"),
        name=id_info.get("name"),
        profile_image_url=id_info.get("picture"),
        created_at=now,
        updated_at=now,
    )
```

with:

```python
    now = datetime.now(tz=pytz.UTC)
    profile_id = await generate_unique_profile_id()

    user = User(
        id=ObjectId(),
        profile_id=profile_id,
        google=GoogleUser(
            unique_id=unique_id,
            email=id_info.get("email"),
            name=id_info.get("name"),
            profile_image_url=id_info.get("picture"),
            last_login_at=now,
            signed_up_at=now,
        ),
        email=id_info.get("email"),
        name=id_info.get("name"),
        profile_image_url=id_info.get("picture"),
        created_at=now,
        updated_at=now,
    )
```

- [ ] **Step 6: Lint**

```
cd services/api && uv run ruff check app/routers/authentications.py
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add services/api/app/routers/authentications.py
git commit -m "feat(api): assign profile_id during OAuth sign-up"
```

---

## Task 6: GET /users/me 응답에 profileId 추가

**Files:**
- Modify: `services/api/app/routers/users.py`
- Modify: `services/api/tests/routers/test_users.py`

- [ ] **Step 1: 실패 테스트 작성**

Replace the top of `services/api/tests/routers/test_users.py` so every test helper and existing test passes the new required field. Change the `_make_user` helper signature and add profile_id tests:

```python
from types import SimpleNamespace

from bson import ObjectId

from app.routers.users import UserProfileResponse, _build_profile_response


def _make_user(
    *,
    id: ObjectId,
    profile_id: str = "testuser01",
    name: str | None = None,
    email: str | None = None,
    bio: str | None = None,
    profile_image_url: str | None = None,
    unread_notification_count: int = 0,
) -> SimpleNamespace:
    return SimpleNamespace(
        id=id,
        profile_id=profile_id,
        name=name,
        email=email,
        bio=bio,
        profile_image_url=profile_image_url,
        unread_notification_count=unread_notification_count,
    )


def test_user_profile_response_serializes_id():
    resp = UserProfileResponse(
        id="507f1f77bcf86cd799439011",
        profile_id="climber99",
        name="alice",
        email=None,
        bio=None,
        profile_image_url=None,
    )
    dumped = resp.model_dump(by_alias=True)
    assert dumped["id"] == "507f1f77bcf86cd799439011"


def test_user_profile_response_serializes_profile_id_camelcase():
    """profile_id field should emit as profileId in JSON."""
    resp = UserProfileResponse(
        id="507f1f77bcf86cd799439011",
        profile_id="climber99",
    )
    dumped = resp.model_dump(by_alias=True)
    assert dumped["profileId"] == "climber99"


def test_build_profile_response_populates_profile_id():
    oid = ObjectId()
    user = _make_user(id=oid, profile_id="kx9m2pq7vn3a", name="alice")
    resp = _build_profile_response(user)
    assert resp.profile_id == "kx9m2pq7vn3a"


def test_build_profile_response_populates_id_as_string():
    oid = ObjectId()
    user = _make_user(id=oid, name="alice", email="a@example.com")

    resp = _build_profile_response(user)

    assert resp.id == str(oid)
    assert resp.name == "alice"
    assert resp.email == "a@example.com"
    assert resp.profile_image_url is None


def test_build_profile_response_passes_through_nulls():
    oid = ObjectId()
    user = _make_user(id=oid)

    resp = _build_profile_response(user)

    assert resp.id == str(oid)
    assert resp.name is None
    assert resp.email is None
    assert resp.bio is None
    assert resp.profile_image_url is None
```

- [ ] **Step 2: Run — verify fail**

```
cd services/api && pytest tests/routers/test_users.py -v
```

Expected: FAIL — `UserProfileResponse` doesn't accept `profile_id` or `_build_profile_response` doesn't set it.

- [ ] **Step 3: UserProfileResponse에 profile_id 추가**

Modify `services/api/app/routers/users.py` — update `UserProfileResponse`:

```python
class UserProfileResponse(BaseModel):
    model_config = model_config

    id: str = Field(alias="id")
    profile_id: str
    name: Optional[str] = None
    email: Optional[str] = None
    bio: Optional[str] = None
    profile_image_url: Optional[str] = None
    unread_notification_count: int = 0
```

And update `_build_profile_response`:

```python
def _build_profile_response(user: User) -> UserProfileResponse:
    signed_url = None
    if user.profile_image_url:
        blob_path = extract_blob_path_from_url(user.profile_image_url)
        if blob_path:
            signed_url = generate_signed_url(blob_path)
        else:
            signed_url = user.profile_image_url

    return UserProfileResponse(
        id=str(user.id),
        profile_id=user.profile_id,
        name=user.name,
        email=user.email,
        bio=user.bio,
        profile_image_url=signed_url,
        unread_notification_count=max(0, user.unread_notification_count),
    )
```

- [ ] **Step 4: Run — verify pass**

```
cd services/api && pytest tests/routers/test_users.py -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/users.py services/api/tests/routers/test_users.py
git commit -m "feat(api): return profileId in GET /users/me response"
```

---

## Task 7: PATCH /users/me/profile-id 엔드포인트

**Files:**
- Modify: `services/api/app/routers/users.py`
- Modify: `services/api/tests/routers/test_users.py`

- [ ] **Step 1: 실패 테스트 작성 — 검증 헬퍼**

We will introduce a pure helper `_validate_profile_id_or_raise` that maps `ProfileIdError` into a FastAPI `HTTPException` with structured detail. Test the mapping at unit level:

Append to `services/api/tests/routers/test_users.py`:

```python
import pytest
from fastapi import HTTPException, status as http_status

from app.routers.users import _validate_profile_id_or_raise


@pytest.mark.parametrize(
    "value,expected_code",
    [
        ("abc", "PROFILE_ID_TOO_SHORT"),
        ("a" * 17, "PROFILE_ID_TOO_LONG"),
        ("Climber99", "PROFILE_ID_INVALID_CHARS"),
        ("_climber9", "PROFILE_ID_INVALID_START_END"),
        ("clim__ber", "PROFILE_ID_CONSECUTIVE_SPECIAL"),
        ("admin123_admin", "PROFILE_ID_RESERVED"),
    ],
)
def test_validate_profile_id_or_raise_maps_errors(value, expected_code):
    # Note: admin123_admin is chosen to fail RESERVED via profanity-style exact-match
    # only if it appears in RESERVED_EXACT. Instead use "administrator" or "admin" —
    # but those have length issues. Use "besetterofficial" (16 chars) for a clean RESERVED.
    # Re-parametrize below if needed.
    with pytest.raises(HTTPException) as exc_info:
        _validate_profile_id_or_raise(value)
    assert exc_info.value.status_code == http_status.HTTP_422_UNPROCESSABLE_ENTITY
    assert exc_info.value.detail["code"] == expected_code


def test_validate_profile_id_or_raise_reserved_exact():
    with pytest.raises(HTTPException) as exc_info:
        _validate_profile_id_or_raise("besetterofficial")
    assert exc_info.value.detail["code"] == "PROFILE_ID_RESERVED"


def test_validate_profile_id_or_raise_accepts_valid():
    # Should not raise.
    _validate_profile_id_or_raise("climber99")
```

Remove the `admin123_admin` row from the parametrize — replace with a case that actually fails RESERVED. Use this parametrize instead:

```python
@pytest.mark.parametrize(
    "value,expected_code",
    [
        ("abc", "PROFILE_ID_TOO_SHORT"),
        ("a" * 17, "PROFILE_ID_TOO_LONG"),
        ("Climber99", "PROFILE_ID_INVALID_CHARS"),
        ("_climber9", "PROFILE_ID_INVALID_START_END"),
        ("clim__ber", "PROFILE_ID_CONSECUTIVE_SPECIAL"),
        ("fuckmaster", "PROFILE_ID_RESERVED"),  # profanity substring
    ],
)
def test_validate_profile_id_or_raise_maps_errors(value, expected_code):
    with pytest.raises(HTTPException) as exc_info:
        _validate_profile_id_or_raise(value)
    assert exc_info.value.status_code == http_status.HTTP_422_UNPROCESSABLE_ENTITY
    assert exc_info.value.detail["code"] == expected_code
```

- [ ] **Step 2: Run — verify fail**

```
cd services/api && pytest tests/routers/test_users.py -v
```

Expected: FAIL — `ImportError: cannot import name '_validate_profile_id_or_raise'`

- [ ] **Step 3: users.py에 PATCH 엔드포인트 구현**

Add to `services/api/app/routers/users.py`:

1. Add imports at top (near the existing imports):

```python
from pydantic import BaseModel, Field
from pymongo.errors import DuplicateKeyError

from app.core.profile_id import ProfileIdError, validate_profile_id
```

2. Add schema and helper near the top (below `UserProfileResponse`):

```python
class UpdateProfileIdRequest(BaseModel):
    model_config = model_config

    profile_id: str


_PROFILE_ID_ERROR_MESSAGES: dict[ProfileIdError, str] = {
    ProfileIdError.TOO_SHORT: "8자 이상 입력해 주세요",
    ProfileIdError.TOO_LONG: "16자 이하로 입력해 주세요",
    ProfileIdError.INVALID_CHARS: "소문자, 숫자, 점(.), 밑줄(_)만 사용할 수 있습니다",
    ProfileIdError.INVALID_START_END: "첫 글자와 끝 글자는 영문 소문자 또는 숫자여야 합니다",
    ProfileIdError.CONSECUTIVE_SPECIAL: "점(.)과 밑줄(_)을 연속해서 쓸 수 없습니다",
    ProfileIdError.RESERVED: "사용할 수 없는 프로필 ID입니다",
    ProfileIdError.TAKEN: "이미 사용 중인 프로필 ID입니다",
}


def _validate_profile_id_or_raise(value: str) -> None:
    err = validate_profile_id(value)
    if err is None:
        return
    raise HTTPException(
        status_code=http_status.HTTP_422_UNPROCESSABLE_ENTITY,
        detail={"code": err.value, "message": _PROFILE_ID_ERROR_MESSAGES[err]},
    )
```

3. Add endpoint below `update_my_profile`:

```python
@router.patch("/me/profile-id", response_model=UserProfileResponse)
async def update_my_profile_id(
    body: UpdateProfileIdRequest,
    current_user: User = Depends(get_current_user),
):
    """Change the caller's profile_id. Returns the full profile on success.

    422 on validation failure, 409 on uniqueness collision.
    """
    new_value = body.profile_id
    _validate_profile_id_or_raise(new_value)

    if new_value == current_user.profile_id:
        return _build_profile_response(current_user)

    current_user.profile_id = new_value
    current_user.updated_at = datetime.now(tz=timezone.utc)
    try:
        await current_user.save()
    except DuplicateKeyError:
        raise HTTPException(
            status_code=http_status.HTTP_409_CONFLICT,
            detail={
                "code": ProfileIdError.TAKEN.value,
                "message": _PROFILE_ID_ERROR_MESSAGES[ProfileIdError.TAKEN],
            },
        )

    return _build_profile_response(current_user)
```

- [ ] **Step 4: Run — verify pass**

```
cd services/api && pytest tests/routers/test_users.py -v
```

Expected: PASS for all tests in this file.

- [ ] **Step 5: Lint**

```
cd services/api && uv run ruff check app/routers/users.py
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add services/api/app/routers/users.py services/api/tests/routers/test_users.py
git commit -m "feat(api): add PATCH /users/me/profile-id endpoint"
```

---

## Task 8: GET /users/me/profile-id/availability 엔드포인트

**Files:**
- Modify: `services/api/app/routers/users.py`
- Modify: `services/api/tests/routers/test_users.py`

- [ ] **Step 1: 실패 테스트 작성**

Append to `services/api/tests/routers/test_users.py`:

```python
from app.routers.users import (
    ProfileIdAvailabilityResponse,
    _compute_profile_id_availability,
)


def test_availability_response_schema_camelcase():
    resp = ProfileIdAvailabilityResponse(
        value="climber99",
        available=True,
        reason=None,
    )
    dumped = resp.model_dump(by_alias=True)
    assert dumped == {"value": "climber99", "available": True, "reason": None}


def test_compute_availability_reserved_short_circuits_db():
    """Validation failure returns immediately without touching DB."""
    current = _make_user(id=ObjectId(), profile_id="owner001x")

    async def never(_query):
        raise AssertionError("DB must not be hit when validation fails")

    # Sync helper returns validation error without calling the DB probe.
    result = _compute_profile_id_availability(
        value="_bad_start",
        current_user=current,
        exists=None,  # not consulted
    )
    assert result.available is False
    assert result.reason == "PROFILE_ID_INVALID_START_END"


def test_compute_availability_self_is_available():
    """The caller's current profile_id is always available to them."""
    current = _make_user(id=ObjectId(), profile_id="climber99")
    result = _compute_profile_id_availability(
        value="climber99",
        current_user=current,
        exists=True,  # not consulted because of self-match
    )
    assert result.available is True
    assert result.reason is None


def test_compute_availability_taken_by_another():
    current = _make_user(id=ObjectId(), profile_id="owner_a")
    result = _compute_profile_id_availability(
        value="someone1",
        current_user=current,
        exists=True,
    )
    assert result.available is False
    assert result.reason == "PROFILE_ID_TAKEN"


def test_compute_availability_free():
    current = _make_user(id=ObjectId(), profile_id="owner_a")
    result = _compute_profile_id_availability(
        value="newname01",
        current_user=current,
        exists=False,
    )
    assert result.available is True
    assert result.reason is None
```

- [ ] **Step 2: Run — verify fail**

```
cd services/api && pytest tests/routers/test_users.py -v
```

Expected: FAIL — `ImportError`.

- [ ] **Step 3: 구현 추가**

Add to `services/api/app/routers/users.py`:

1. Response schema and helper (near top, after `UpdateProfileIdRequest`):

```python
class ProfileIdAvailabilityResponse(BaseModel):
    model_config = model_config

    value: str
    available: bool
    reason: Optional[str] = None


def _compute_profile_id_availability(
    *,
    value: str,
    current_user: User,
    exists: Optional[bool],
) -> ProfileIdAvailabilityResponse:
    """Decide availability given validation + optional DB-existence probe.

    `exists` is what a `find_one({"profileId": value})` returned (True if
    another user owns it, False if free, None if DB probe was skipped).
    """
    if value == current_user.profile_id:
        return ProfileIdAvailabilityResponse(value=value, available=True, reason=None)

    err = validate_profile_id(value)
    if err is not None:
        return ProfileIdAvailabilityResponse(
            value=value, available=False, reason=err.value,
        )

    if exists:
        return ProfileIdAvailabilityResponse(
            value=value,
            available=False,
            reason=ProfileIdError.TAKEN.value,
        )
    return ProfileIdAvailabilityResponse(value=value, available=True, reason=None)
```

2. Endpoint:

```python
@router.get("/me/profile-id/availability", response_model=ProfileIdAvailabilityResponse)
async def check_profile_id_availability(
    value: str,
    current_user: User = Depends(get_current_user),
):
    """Return whether `value` can be used as the caller's new profile_id.

    Always 200. No 409/422 — instead reports reason in the body.
    """
    # Self-match and validation don't need DB.
    if value == current_user.profile_id:
        return _compute_profile_id_availability(
            value=value, current_user=current_user, exists=None,
        )
    if validate_profile_id(value) is not None:
        return _compute_profile_id_availability(
            value=value, current_user=current_user, exists=None,
        )

    other = await User.find_one({"profileId": value})
    exists = other is not None and other.id != current_user.id
    return _compute_profile_id_availability(
        value=value, current_user=current_user, exists=exists,
    )
```

- [ ] **Step 4: Run — verify pass**

```
cd services/api && pytest tests/routers/test_users.py -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/users.py services/api/tests/routers/test_users.py
git commit -m "feat(api): add GET /users/me/profile-id/availability endpoint"
```

---

## Task 9: 백필 스크립트 (raw motor, idempotent)

**Files:**
- Create: `services/api/scripts/__init__.py`
- Create: `services/api/scripts/backfill_profile_ids.py`

- [ ] **Step 1: scripts 디렉토리 생성**

```bash
mkdir -p services/api/scripts
```

- [ ] **Step 2: __init__.py 작성**

Create `services/api/scripts/__init__.py`:

```python
```

(Empty file — just marks the directory as a package.)

- [ ] **Step 3: 백필 스크립트 작성**

Create `services/api/scripts/backfill_profile_ids.py`:

```python
"""One-shot backfill: assign a profile_id to every user that lacks one.

Run BEFORE deploying the new User model (which requires profile_id). After this
completes, deploy — Beanie will then create the unique index for profileId.

Bypasses Beanie: the new User model would fail Pydantic validation on legacy
documents that lack profileId. Raw motor updates only the profileId field.

Idempotent: restricts to `{profileId: {$exists: False}}` so re-runs skip done users.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

from motor.motor_asyncio import AsyncIOMotorClient

from app.core.config import get
from app.core.profile_id import _contains_profanity, generate_profile_id

log = logging.getLogger(__name__)


async def main() -> None:
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

- [ ] **Step 4: Lint**

```
cd services/api && uv run ruff check scripts/backfill_profile_ids.py
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add services/api/scripts/__init__.py services/api/scripts/backfill_profile_ids.py
git commit -m "feat(api): add one-shot backfill script for legacy users' profile_id"
```

---

## Task 10: UserState에 profileId 추가 + provider 메서드 2개

**Files:**
- Modify: `apps/mobile/lib/providers/user_provider.dart`
- Modify: `apps/mobile/lib/providers/user_provider.g.dart` (auto-generated)

- [ ] **Step 1: UserState 업데이트**

Replace the entire contents of `apps/mobile/lib/providers/user_provider.dart` with:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/http_client.dart';

part 'user_provider.g.dart';

class ProfileIdAvailability {
  final String value;
  final bool available;
  final String? reason;

  const ProfileIdAvailability({
    required this.value,
    required this.available,
    this.reason,
  });

  factory ProfileIdAvailability.fromJson(Map<String, dynamic> json) {
    return ProfileIdAvailability(
      value: json['value'] as String,
      available: json['available'] as bool,
      reason: json['reason'] as String?,
    );
  }
}

class ProfileIdUpdateError implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const ProfileIdUpdateError({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'ProfileIdUpdateError($statusCode, $code): $message';
}

class UserState {
  final String id;
  final String profileId;
  final String? name;
  final String? email;
  final String? bio;
  final String? profileImageUrl;
  final int unreadNotificationCount;

  const UserState({
    required this.id,
    required this.profileId,
    this.name,
    this.email,
    this.bio,
    this.profileImageUrl,
    this.unreadNotificationCount = 0,
  });

  UserState copyWith({
    String? id,
    String? profileId,
    String? name,
    String? email,
    String? bio,
    String? profileImageUrl,
    int? unreadNotificationCount,
  }) {
    return UserState(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      name: name ?? this.name,
      email: email ?? this.email,
      bio: bio ?? this.bio,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      unreadNotificationCount:
          unreadNotificationCount ?? this.unreadNotificationCount,
    );
  }

  factory UserState.fromJson(Map<String, dynamic> json) {
    return UserState(
      id: json['id'] as String,
      profileId: json['profileId'] as String,
      name: json['name'] as String?,
      email: json['email'] as String?,
      bio: json['bio'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      unreadNotificationCount:
          (json['unreadNotificationCount'] as int?) ?? 0,
    );
  }
}

@Riverpod(keepAlive: true)
class UserProfile extends _$UserProfile {
  @override
  Future<UserState> build() async {
    return _fetchProfile();
  }

  Future<UserState> _fetchProfile() async {
    final response = await AuthorizedHttpClient.get('/users/me');
    if (response.statusCode == 200) {
      return UserState.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    }
    throw Exception('Failed to load profile');
  }

  Future<void> updateProfile({
    String? name,
    String? bio,
    File? imageFile,
  }) async {
    final fields = <String, String>{};
    if (name != null) fields['name'] = name;
    if (bio != null) fields['bio'] = bio;

    final response = await AuthorizedHttpClient.multipartRequest(
      '/users/me',
      imageFile?.path,
      fieldName: 'profileImage',
      fields: fields,
      method: 'PATCH',
    );

    if (response.statusCode == 200) {
      state = AsyncData(
        UserState.fromJson(jsonDecode(utf8.decode(response.bodyBytes))),
      );
    } else {
      throw Exception('Failed to update profile');
    }
  }

  Future<ProfileIdAvailability> checkProfileIdAvailability(String value) async {
    final encoded = Uri.encodeQueryComponent(value);
    final response = await AuthorizedHttpClient.get(
      '/users/me/profile-id/availability?value=$encoded',
    );
    if (response.statusCode == 200) {
      return ProfileIdAvailability.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    }
    throw Exception('Failed to check profile_id availability');
  }

  Future<void> updateProfileId(String value) async {
    final response = await AuthorizedHttpClient.patch(
      '/users/me/profile-id',
      body: jsonEncode({'profileId': value}),
      extraHeaders: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200) {
      state = AsyncData(
        UserState.fromJson(jsonDecode(utf8.decode(response.bodyBytes))),
      );
      return;
    }
    // Parse structured error.
    try {
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final detail = body['detail'];
      if (detail is Map<String, dynamic>) {
        throw ProfileIdUpdateError(
          statusCode: response.statusCode,
          code: (detail['code'] as String?) ?? 'UNKNOWN',
          message: (detail['message'] as String?) ?? '',
        );
      }
    } catch (e) {
      if (e is ProfileIdUpdateError) rethrow;
    }
    throw ProfileIdUpdateError(
      statusCode: response.statusCode,
      code: 'UNKNOWN',
      message: 'Failed to update profile_id',
    );
  }
}
```

- [ ] **Step 2: AuthorizedHttpClient.patch 시그니처 확인**

```
cd apps/mobile && grep -n "patch(" lib/services/http_client.dart
```

If the existing `patch` signature doesn't accept `body` and `extraHeaders`, adapt the call in `updateProfileId` to use whatever form the client offers (e.g., use `AuthorizedHttpClient.multipartRequest` or add a JSON helper). Report as a blocker if the client has no JSON patch.

- [ ] **Step 3: build_runner 재생성**

```
cd apps/mobile && dart run build_runner build --delete-conflicting-outputs
```

Expected: regenerates `user_provider.g.dart`.

- [ ] **Step 4: flutter analyze**

```
cd apps/mobile && flutter analyze lib/providers/user_provider.dart
```

Expected: no errors. If `extraHeaders` naming differs in the HttpClient, fix to match.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/providers/user_provider.dart apps/mobile/lib/providers/user_provider.g.dart
git commit -m "feat(mobile): add profileId to UserState and provider methods"
```

---

## Task 11: i18n 키 12종 추가 (4개 locale)

**Files:**
- Modify: `apps/mobile/lib/l10n/app_ko.arb`
- Modify: `apps/mobile/lib/l10n/app_en.arb`
- Modify: `apps/mobile/lib/l10n/app_ja.arb`
- Modify: `apps/mobile/lib/l10n/app_es.arb`

- [ ] **Step 1: 12개 key의 각 locale 값 준비**

Keys and translations (insert into each `.arb`; preserve existing keys and commas):

| key | ko | en | ja | es |
|---|---|---|---|---|
| `profileIdLabel` | `프로필 ID` | `Profile ID` | `プロフィールID` | `ID de perfil` |
| `editProfileIdTitle` | `프로필 ID 수정` | `Edit profile ID` | `プロフィールIDを編集` | `Editar ID de perfil` |
| `profileIdHintChecking` | `확인 중...` | `Checking...` | `確認中...` | `Comprobando...` |
| `profileIdHintAvailable` | `사용 가능한 프로필 ID입니다` | `Available` | `使用可能です` | `Disponible` |
| `profileIdErrorTooShort` | `8자 이상 입력해 주세요` | `Must be at least 8 characters` | `8文字以上入力してください` | `Debe tener al menos 8 caracteres` |
| `profileIdErrorTooLong` | `16자 이하로 입력해 주세요` | `Must be 16 characters or fewer` | `16文字以下で入力してください` | `Debe tener 16 caracteres o menos` |
| `profileIdErrorInvalidChars` | `소문자, 숫자, 점(.), 밑줄(_)만 사용할 수 있습니다` | `Only lowercase letters, digits, dots (.) and underscores (_) are allowed` | `小文字、数字、ドット(.)、アンダースコア(_)のみ使用できます` | `Solo se permiten minúsculas, dígitos, puntos (.) y guiones bajos (_)` |
| `profileIdErrorInvalidStartEnd` | `첫 글자와 끝 글자는 영문 소문자 또는 숫자여야 합니다` | `Must start and end with a lowercase letter or digit` | `最初と最後の文字は英小文字または数字である必要があります` | `Debe empezar y terminar con una letra minúscula o un dígito` |
| `profileIdErrorConsecutiveSpecial` | `점(.)과 밑줄(_)을 연속해서 쓸 수 없습니다` | `Dots (.) and underscores (_) cannot be used consecutively` | `ドット(.)とアンダースコア(_)は連続して使用できません` | `Los puntos (.) y guiones bajos (_) no pueden usarse consecutivamente` |
| `profileIdErrorReserved` | `사용할 수 없는 프로필 ID입니다` | `This profile ID is not allowed` | `使用できないプロフィールIDです` | `Este ID de perfil no está permitido` |
| `profileIdErrorTaken` | `이미 사용 중인 프로필 ID입니다` | `This profile ID is already taken` | `すでに使用されているプロフィールIDです` | `Este ID de perfil ya está en uso` |
| `profileIdUpdated` | `프로필 ID가 변경됐어요` | `Profile ID updated` | `プロフィールIDが変更されました` | `ID de perfil actualizado` |

- [ ] **Step 2: `app_ko.arb` 수정**

Open `apps/mobile/lib/l10n/app_ko.arb` and insert these entries before the closing `}`:

```json
  "profileIdLabel": "프로필 ID",
  "editProfileIdTitle": "프로필 ID 수정",
  "profileIdHintChecking": "확인 중...",
  "profileIdHintAvailable": "사용 가능한 프로필 ID입니다",
  "profileIdErrorTooShort": "8자 이상 입력해 주세요",
  "profileIdErrorTooLong": "16자 이하로 입력해 주세요",
  "profileIdErrorInvalidChars": "소문자, 숫자, 점(.), 밑줄(_)만 사용할 수 있습니다",
  "profileIdErrorInvalidStartEnd": "첫 글자와 끝 글자는 영문 소문자 또는 숫자여야 합니다",
  "profileIdErrorConsecutiveSpecial": "점(.)과 밑줄(_)을 연속해서 쓸 수 없습니다",
  "profileIdErrorReserved": "사용할 수 없는 프로필 ID입니다",
  "profileIdErrorTaken": "이미 사용 중인 프로필 ID입니다",
  "profileIdUpdated": "프로필 ID가 변경됐어요"
```

Ensure the previous last entry now ends with a comma.

- [ ] **Step 3: `app_en.arb`, `app_ja.arb`, `app_es.arb` 수정**

Repeat Step 2 for the other three locales using the corresponding column from the table above.

- [ ] **Step 4: 생성**

```
cd apps/mobile && flutter gen-l10n
```

Expected: no errors; regenerates `AppLocalizations` with new getters.

- [ ] **Step 5: analyze**

```
cd apps/mobile && flutter analyze lib/l10n
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/l10n/app_ko.arb apps/mobile/lib/l10n/app_en.arb apps/mobile/lib/l10n/app_ja.arb apps/mobile/lib/l10n/app_es.arb
git commit -m "feat(mobile): add profile_id i18n keys for ko/en/ja/es"
```

---

## Task 12: ProfileIdEditDialog 위젯 (실시간 availability + PATCH)

**Files:**
- Create: `apps/mobile/lib/widgets/editors/profile_id_edit_dialog.dart`

- [ ] **Step 1: 다이얼로그 위젯 작성**

Create `apps/mobile/lib/widgets/editors/profile_id_edit_dialog.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/user_provider.dart';

enum _HintState { idle, checking, available, error }

class ProfileIdEditDialog extends ConsumerStatefulWidget {
  final String currentProfileId;

  const ProfileIdEditDialog({super.key, required this.currentProfileId});

  @override
  ConsumerState<ProfileIdEditDialog> createState() =>
      _ProfileIdEditDialogState();

  /// Shows the dialog. Returns true if the profile_id was changed.
  static Future<bool> show(
    BuildContext context, {
    required String currentProfileId,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          ProfileIdEditDialog(currentProfileId: currentProfileId),
    );
    return result ?? false;
  }
}

class _ProfileIdEditDialogState extends ConsumerState<ProfileIdEditDialog> {
  late final TextEditingController _controller;
  Timer? _debounce;
  _HintState _hintState = _HintState.idle;
  String? _reason;
  bool _submitting = false;
  String _lastCheckedValue = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentProfileId);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final value = _controller.text;
    _debounce?.cancel();

    if (value.isEmpty || value == widget.currentProfileId) {
      setState(() {
        _hintState = _HintState.idle;
        _reason = null;
      });
      return;
    }

    setState(() {
      _hintState = _HintState.checking;
      _reason = null;
    });

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      await _runAvailabilityCheck(value);
    });
  }

  Future<void> _runAvailabilityCheck(String value) async {
    try {
      final result = await ref
          .read(userProfileProvider.notifier)
          .checkProfileIdAvailability(value);
      if (!mounted || _controller.text != value) return;
      _lastCheckedValue = value;
      setState(() {
        if (result.available) {
          _hintState = _HintState.available;
          _reason = null;
        } else {
          _hintState = _HintState.error;
          _reason = result.reason;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hintState = _HintState.error;
        _reason = 'UNKNOWN';
      });
    }
  }

  String? _reasonMessage(BuildContext context, String? reason) {
    if (reason == null) return null;
    final l10n = AppLocalizations.of(context)!;
    switch (reason) {
      case 'PROFILE_ID_TOO_SHORT':
        return l10n.profileIdErrorTooShort;
      case 'PROFILE_ID_TOO_LONG':
        return l10n.profileIdErrorTooLong;
      case 'PROFILE_ID_INVALID_CHARS':
        return l10n.profileIdErrorInvalidChars;
      case 'PROFILE_ID_INVALID_START_END':
        return l10n.profileIdErrorInvalidStartEnd;
      case 'PROFILE_ID_CONSECUTIVE_SPECIAL':
        return l10n.profileIdErrorConsecutiveSpecial;
      case 'PROFILE_ID_RESERVED':
        return l10n.profileIdErrorReserved;
      case 'PROFILE_ID_TAKEN':
        return l10n.profileIdErrorTaken;
      default:
        return null;
    }
  }

  Widget _buildHint(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (_hintState) {
      case _HintState.idle:
        return const SizedBox(height: 20);
      case _HintState.checking:
        return Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 8),
            Text(l10n.profileIdHintChecking),
          ],
        );
      case _HintState.available:
        return Row(
          children: [
            const Icon(Icons.check, size: 16, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              l10n.profileIdHintAvailable,
              style: const TextStyle(color: Colors.green),
            ),
          ],
        );
      case _HintState.error:
        final msg = _reasonMessage(context, _reason) ?? '';
        return Row(
          children: [
            const Icon(Icons.close, size: 16, color: Colors.red),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
    }
  }

  bool get _canSubmit {
    if (_submitting) return false;
    if (_hintState != _HintState.available) return false;
    // Guard against a race where text changed after the last check.
    if (_controller.text != _lastCheckedValue) return false;
    return true;
  }

  Future<void> _onSubmit() async {
    final value = _controller.text;
    setState(() => _submitting = true);
    try {
      await ref.read(userProfileProvider.notifier).updateProfileId(value);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileIdUpdated)),
      );
      Navigator.of(context).pop(true);
    } on ProfileIdUpdateError catch (e) {
      if (!mounted) return;
      setState(() {
        _hintState = _HintState.error;
        _reason = e.code;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hintState = _HintState.error;
        _reason = 'UNKNOWN';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.editProfileIdTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 16,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9._]')),
            ],
            decoration: InputDecoration(
              prefixText: '@',
              labelText: l10n.profileIdLabel,
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          _buildHint(context),
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        ElevatedButton(
          onPressed: _canSubmit ? _onSubmit : null,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: flutter analyze**

```
cd apps/mobile && flutter analyze lib/widgets/editors/profile_id_edit_dialog.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/editors/profile_id_edit_dialog.dart
git commit -m "feat(mobile): add ProfileIdEditDialog with debounced availability check"
```

---

## Task 13: my_page 통합 — `@profileId` 표시 + 편집 아이콘

**Files:**
- Modify: `apps/mobile/lib/pages/my_page.dart`

- [ ] **Step 1: import 추가 및 위치 확인**

Add to the import block at the top of `apps/mobile/lib/pages/my_page.dart`:

```dart
import '../widgets/editors/profile_id_edit_dialog.dart';
```

- [ ] **Step 2: 이름(name) 섹션 바로 아래에 profile_id 표시 섹션 삽입**

Open `apps/mobile/lib/pages/my_page.dart`. Locate the block where the user's name is rendered (both edit and read-only branches are inside the same `if (isEditing) ... else ...` around lines 520–570). Find the closing of that `if/else` block (after the read-only `Text(user.name ?? '', ...)` closes).

Immediately after the name block (still inside the same widget tree), insert:

```dart
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '@${user.profileId}',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (isEditing) ...[
              const SizedBox(width: 6),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 18,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  await ProfileIdEditDialog.show(
                    context,
                    currentProfileId: user.profileId,
                  );
                },
              ),
            ],
          ],
        ),
```

Notes for the implementer:
- The insertion point is inside the `_ProfileSection` widget (or wherever the name is rendered). `user` is the `UserState` already available in that scope. `isEditing` is the bool flag already in scope.
- Do NOT call `ref.invalidate(userProfileProvider)` here — the dialog itself calls `updateProfileId`, which sets the notifier state directly.

- [ ] **Step 3: flutter analyze**

```
cd apps/mobile && flutter analyze lib/pages/my_page.dart
```

Expected: no errors.

- [ ] **Step 4: 전체 빌드 확인**

```
cd apps/mobile && flutter analyze
```

Expected: no errors across the whole project.

- [ ] **Step 5: 수동 smoke 체크 (UI)**

Launch the app (`cd apps/mobile && flutter run`), sign in, open my_page. Verify:
- `@<handle>` is shown below the name in read-only mode (no edit icon).
- Tap the top-right edit button → edit icon appears next to `@<handle>`.
- Tap the small edit icon → dialog opens, prefilled with current handle.
- Type a value shorter than 8 chars → red "8자 이상 입력해 주세요" after 500ms.
- Type `admin` → would be too short (5 chars). Try `administrator` → red "사용할 수 없는 프로필 ID입니다".
- Type a new valid value → green check + "사용 가능한 프로필 ID입니다"; 확인 active.
- Tap 확인 → dialog closes, snackbar `프로필 ID가 변경됐어요`, my_page now shows the new handle.
- Reopen the dialog with the current value → idle (no hint); 확인 disabled.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/pages/my_page.dart
git commit -m "feat(mobile): show @profile_id on my_page with edit icon in edit mode"
```

---

## Final Verification

- [ ] **Step 1: 백엔드 전체 테스트**

```
cd services/api && pytest
```

Expected: all tests pass.

- [ ] **Step 2: 백엔드 lint**

```
cd services/api && uv run ruff check app scripts tests
```

Expected: no errors.

- [ ] **Step 3: 모바일 analyze**

```
cd apps/mobile && flutter analyze
```

Expected: no errors.

- [ ] **Step 4: 배포 체크리스트 검토**

사람이 확인 (실제 배포는 별도 주문이 올 때 진행):

1. 스테이징 DB에서 `backfill_profile_ids.py` dry-run — 샘플 유저에 profileId 생성 확인.
2. 프로덕션 DB에서 `backfill_profile_ids.py` 실행 — `db.users.count({profileId: {$exists: false}}) === 0` 확인.
3. 새 API 서버 배포 → 앱 기동 로그에 unique index 생성 확인.
4. 모바일 앱 배포.
