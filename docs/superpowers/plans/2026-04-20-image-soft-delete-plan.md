# Image Soft Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `DELETE /images/{image_id}` 엔드포인트를 추가해 이미지 업로더 본인이 이미지를 소프트 삭제할 수 있게 하고, 루트가 붙어 있을 때는 `?confirm=true` 확인 플래그를 요구한다.

**Architecture:** 비즈니스 로직을 순수 헬퍼 `_soft_delete_image` 로 분리하고 (테스트 가능), 엔드포인트는 HTTPException 매핑만 담당하는 얇은 래퍼로 둔다. 스키마 변경 없이 기존 `Image.is_deleted` / `Image.deleted_at` 필드를 재사용한다. 기존 이미지 리스트/조회/루트 생성 가드는 이미 `is_deleted != True` 필터를 쓰고 있어 회귀 방지만 신경 쓰면 된다.

**Tech Stack:** FastAPI, Beanie (MongoDB ODM), pytest + pytest-asyncio + mongomock-motor. Python 3.10, uv 패키지 매니저.

---

## Context for the Implementing Engineer

이 리포 / 기능의 관례:

- **모델:** `Image` 문서는 `services/api/app/models/image.py` 에 있다. `is_deleted: bool`, `deleted_at: Optional[datetime]` 필드는 이미 존재 — 새 스키마 작업 없다.
- **기존 가드 (변경 금지, 참조용):**
  - 리스트 `app/routers/images.py:92` → `Image.is_deleted != True`
  - 상세 `app/routers/images.py:286-292` → `And(Image.id == object_id, Image.user_id == current_user.id, Image.is_deleted != True)`
  - 루트 생성 `app/routers/routes.py:113-119` → `Image.find_one(Image.id == ..., Image.user_id == ..., Image.is_deleted != True)` → 없으면 404 `Image not found`
  - 루트 상세/리스트 `app/routers/routes.py:334, 444, 530` → `Image.get(...)` (필터 없음, 의도적) — 기존 루트는 이미지 소프트삭제 후에도 이미지 정보를 계속 받는다.
- **테스트 스타일:** `services/api/tests/routers/test_routes_image_route_count.py` 패턴을 따른다. `AsyncMongoMockClient` + `init_beanie` 로 실제 Beanie 쿼리를 돌린다. FastAPI TestClient 를 쓰지 않는다 (conftest 가 `app.dependencies` 를 mock 하므로). 대신 엔드포인트 함수 자체를 직접 호출해 테스트한다.
- **라우터 파일:** 비즈니스 로직과 엔드포인트가 한 파일(`images.py`)에 섞여 있다. 기존 관례를 따라 헬퍼와 엔드포인트 모두 `app/routers/images.py` 안에 둔다. 엔드포인트는 파일 아랫쪽의 다른 엔드포인트 근처에 붙이되, **`/{blob_path:path}` 아래에 두면 안 된다** (path catch-all 라우트라 `{image_id}` 매칭이 가려질 수 있음 → `delete_image` 는 `get_image` 바로 다음에 둔다).
- **에러 응답 포맷:** 구조화된 에러는 `detail` 에 `{"code": "...", ...}` 딕셔너리. 라우트 생성의 `PLACE_NOT_USABLE` 케이스(`routes.py:130-137`)를 참고.
- **커밋 컨벤션:** `feat(api): ...`, `fix(api): ...`. 본문은 선택, 왜를 설명. `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>` 트레일러 포함.

## File Structure

| 파일 | 변경 | 책임 |
|---|---|---|
| `services/api/app/routers/images.py` | Modify | `ImageDeleteOutcome` dataclass + `_soft_delete_image` 헬퍼 + `DELETE /images/{image_id}` 엔드포인트 추가 |
| `services/api/tests/routers/test_images_delete.py` | Create | 헬퍼 + 엔드포인트 단위 테스트 (mongomock 기반) |

## Testing Conventions

- 모든 테스트 파일 상단에 `pytestmark = pytest.mark.asyncio`.
- Mongomock 픽스처 사용: `AsyncMongoMockClient` → `init_beanie(document_models=[Image])`.
- 이미지 팩토리는 각 테스트 파일 안에 사내 헬퍼로 둔다 (기존 `test_routes_image_route_count.py` 의 `_make_image` 처럼).
- `datetime` 는 항상 tz-aware (`datetime(..., tzinfo=dt_tz.utc)` 또는 `datetime.now(timezone.utc)`).

---

## Task 1: Helper skeleton + happy path (no routes)

**Goal:** `_soft_delete_image` 가 없는 상태에서 "루트 없는 이미지" 소프트 삭제가 작동하는지 TDD 로 확인. `ImageDeleteOutcome` 타입도 이 태스크에서 도입.

**Files:**
- Create: `services/api/tests/routers/test_images_delete.py`
- Modify: `services/api/app/routers/images.py` — 새 import, `ImageDeleteOutcome`, `_soft_delete_image` 추가

- [ ] **Step 1: Write the failing test**

Create `services/api/tests/routers/test_images_delete.py`:

```python
"""Tests for DELETE /images/{image_id} and its _soft_delete_image helper."""

from __future__ import annotations

from datetime import datetime, timezone as dt_tz

import pytest
import pytest_asyncio
from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from bson import ObjectId
from mongomock_motor import AsyncMongoMockClient

from app.models.image import Image, ImageMetadata
from app.routers.images import ImageDeleteOutcome, _soft_delete_image


pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient()
    db = client.get_database("besetter-test")
    await init_beanie(database=db, document_models=[Image])
    yield db


def _make_image(
    *,
    user_id: PydanticObjectId,
    route_count: int = 0,
    is_deleted: bool = False,
) -> Image:
    return Image(
        url="https://example.com/x.jpg",
        filename="x.jpg",
        metadata=ImageMetadata(),
        user_id=user_id,
        uploaded_at=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
        route_count=route_count,
        is_deleted=is_deleted,
    )


async def test_soft_delete_flips_flag_and_returns_deleted(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id)
    await image.insert()

    now = datetime(2026, 4, 20, 12, 0, tzinfo=dt_tz.utc)
    outcome = await _soft_delete_image(
        image.id, user_id, confirm=False, now=now
    )

    assert outcome == ImageDeleteOutcome(status="deleted", route_count=0)

    refreshed = await Image.get(image.id)
    assert refreshed.is_deleted is True
    assert refreshed.deleted_at == now
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd services/api && uv run pytest tests/routers/test_images_delete.py::test_soft_delete_flips_flag_and_returns_deleted -v
```

Expected: FAIL — `ImportError: cannot import name 'ImageDeleteOutcome' from 'app.routers.images'`.

- [ ] **Step 3: Add imports and outcome dataclass**

Edit `services/api/app/routers/images.py`.

**Imports.** Currently (line 1-14) the file has `from datetime import datetime`, `from typing import List, Optional, Literal`, `from bson import ObjectId`, `from fastapi import APIRouter, Depends, Query, HTTPException, status`. You must add the following (place them alongside the existing import lines, grouped with stdlib/third-party/local as appropriate):

```python
from dataclasses import dataclass
from datetime import timezone
from beanie.odm.fields import PydanticObjectId
```

(Do NOT duplicate `datetime` — the existing `from datetime import datetime` stays; just add `timezone` via a separate import or change it to `from datetime import datetime, timezone`.)

Right above the router definition (before `router = APIRouter(...)`), add:

```python
@dataclass
class ImageDeleteOutcome:
    status: Literal["deleted", "not_found", "needs_confirmation"]
    route_count: int = 0
```

- [ ] **Step 4: Implement the helper**

Add the helper right after `ImageDeleteOutcome` (same file):

```python
async def _soft_delete_image(
    image_id: ObjectId,
    user_id: PydanticObjectId,
    *,
    confirm: bool,
    now: datetime,
) -> ImageDeleteOutcome:
    image = await Image.find_one(
        Image.id == image_id,
        Image.user_id == user_id,
        Image.is_deleted != True,
    )
    if image is None:
        return ImageDeleteOutcome(status="not_found")
    if image.route_count > 0 and not confirm:
        return ImageDeleteOutcome(
            status="needs_confirmation", route_count=image.route_count
        )
    image.is_deleted = True
    image.deleted_at = now
    await image.save()
    return ImageDeleteOutcome(status="deleted")
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd services/api && uv run pytest tests/routers/test_images_delete.py::test_soft_delete_flips_flag_and_returns_deleted -v
```

Expected: PASS (1 passed).

- [ ] **Step 6: Commit**

```bash
git add services/api/app/routers/images.py services/api/tests/routers/test_images_delete.py
git commit -m "$(cat <<'EOF'
feat(api): add _soft_delete_image helper (happy path)

이미지 삭제 엔드포인트의 비즈니스 로직을 얇은 순수 헬퍼로 분리. 루트가 없는 이미지는 is_deleted/deleted_at 설정하고 'deleted' outcome 반환.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Not-found guards (missing / other user / already deleted)

**Goal:** 헬퍼의 단일 `find_one` 쿼리가 세 가지 "not_found" 케이스를 모두 커버하는지 고정. 이미 구현은 Task 1 에서 끝났으니 이 태스크는 **회귀 방지 테스트만** 추가한다.

**Files:**
- Modify: `services/api/tests/routers/test_images_delete.py`

- [ ] **Step 1: Add three failing-on-regression tests**

Append to `services/api/tests/routers/test_images_delete.py`:

```python
async def test_soft_delete_returns_not_found_when_image_missing(mongo_db):
    user_id = PydanticObjectId()
    nonexistent = ObjectId()

    outcome = await _soft_delete_image(
        nonexistent,
        user_id,
        confirm=False,
        now=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    )

    assert outcome == ImageDeleteOutcome(status="not_found")


async def test_soft_delete_returns_not_found_for_other_users_image(mongo_db):
    owner_id = PydanticObjectId()
    other_id = PydanticObjectId()
    image = _make_image(user_id=owner_id)
    await image.insert()

    outcome = await _soft_delete_image(
        image.id,
        other_id,
        confirm=False,
        now=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    )

    assert outcome == ImageDeleteOutcome(status="not_found")
    refreshed = await Image.get(image.id)
    assert refreshed.is_deleted is False


async def test_soft_delete_returns_not_found_when_already_deleted(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id, is_deleted=True)
    await image.insert()

    outcome = await _soft_delete_image(
        image.id,
        user_id,
        confirm=False,
        now=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    )

    assert outcome == ImageDeleteOutcome(status="not_found")
```

- [ ] **Step 2: Run the new tests to verify they pass**

```bash
cd services/api && uv run pytest tests/routers/test_images_delete.py -v
```

Expected: 4 passed (1 from Task 1 + 3 new).

- [ ] **Step 3: Commit**

```bash
git add services/api/tests/routers/test_images_delete.py
git commit -m "$(cat <<'EOF'
test(api): cover _soft_delete_image not_found branches

없는 이미지, 타인 이미지, 이미 삭제된 이미지 모두 헬퍼의 단일 find_one 쿼리에 의해 not_found 가 되는지 고정.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Route-count confirmation guard

**Goal:** `route_count > 0` 이면 `confirm=False` 로 호출 시 `needs_confirmation` 을 `route_count` 와 함께 반환하고, `confirm=True` 면 실제로 삭제되는지 TDD 로 확인. Task 1 에서 이미 구현은 되어 있지만 전용 테스트로 고정.

**Files:**
- Modify: `services/api/tests/routers/test_images_delete.py`

- [ ] **Step 1: Add tests**

Append to `services/api/tests/routers/test_images_delete.py`:

```python
async def test_soft_delete_requires_confirmation_when_routes_exist(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id, route_count=3)
    await image.insert()

    outcome = await _soft_delete_image(
        image.id,
        user_id,
        confirm=False,
        now=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    )

    assert outcome == ImageDeleteOutcome(
        status="needs_confirmation", route_count=3
    )

    refreshed = await Image.get(image.id)
    assert refreshed.is_deleted is False
    assert refreshed.deleted_at is None


async def test_soft_delete_proceeds_with_confirm_true_when_routes_exist(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id, route_count=3)
    await image.insert()

    now = datetime(2026, 4, 20, 9, 0, tzinfo=dt_tz.utc)
    outcome = await _soft_delete_image(
        image.id,
        user_id,
        confirm=True,
        now=now,
    )

    assert outcome == ImageDeleteOutcome(status="deleted", route_count=0)

    refreshed = await Image.get(image.id)
    assert refreshed.is_deleted is True
    assert refreshed.deleted_at == now
    assert refreshed.route_count == 3  # confirm does not touch route_count
```

- [ ] **Step 2: Run the new tests to verify they pass**

```bash
cd services/api && uv run pytest tests/routers/test_images_delete.py -v
```

Expected: 6 passed.

- [ ] **Step 3: Commit**

```bash
git add services/api/tests/routers/test_images_delete.py
git commit -m "$(cat <<'EOF'
test(api): cover _soft_delete_image confirm gate

route_count>0 이면 confirm=False 호출은 needs_confirmation(route_count 동봉), confirm=True 는 실제 삭제. route_count 자체는 건드리지 않는 것도 확인.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: DELETE endpoint wiring

**Goal:** `DELETE /images/{image_id}?confirm=...` 엔드포인트를 추가하고 헬퍼 outcome 을 HTTP 응답으로 매핑한다.

**Files:**
- Modify: `services/api/app/routers/images.py`
- Modify: `services/api/tests/routers/test_images_delete.py`

- [ ] **Step 1: Write the failing endpoint test**

Append to `services/api/tests/routers/test_images_delete.py` (추가 imports 먼저):

파일 상단의 import 블록에 추가:

```python
from unittest.mock import MagicMock
from fastapi import HTTPException
from app.routers.images import delete_image
```

그리고 파일 하단에 테스트 4 개 추가:

```python
def _mock_user(user_id: PydanticObjectId) -> MagicMock:
    user = MagicMock()
    user.id = user_id
    return user


async def test_delete_image_endpoint_returns_none_on_success(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id)
    await image.insert()

    result = await delete_image(
        image_id=str(image.id),
        confirm=False,
        current_user=_mock_user(user_id),
    )

    assert result is None
    refreshed = await Image.get(image.id)
    assert refreshed.is_deleted is True


async def test_delete_image_endpoint_raises_400_on_bad_object_id(mongo_db):
    user_id = PydanticObjectId()

    with pytest.raises(HTTPException) as exc_info:
        await delete_image(
            image_id="not-a-valid-object-id",
            confirm=False,
            current_user=_mock_user(user_id),
        )

    assert exc_info.value.status_code == 400


async def test_delete_image_endpoint_raises_404_when_missing(mongo_db):
    user_id = PydanticObjectId()

    with pytest.raises(HTTPException) as exc_info:
        await delete_image(
            image_id=str(ObjectId()),
            confirm=False,
            current_user=_mock_user(user_id),
        )

    assert exc_info.value.status_code == 404


async def test_delete_image_endpoint_raises_409_with_route_count(mongo_db):
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id, route_count=5)
    await image.insert()

    with pytest.raises(HTTPException) as exc_info:
        await delete_image(
            image_id=str(image.id),
            confirm=False,
            current_user=_mock_user(user_id),
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == {
        "code": "IMAGE_HAS_ROUTES",
        "route_count": 5,
    }
```

- [ ] **Step 2: Run the new tests to verify they fail**

```bash
cd services/api && uv run pytest tests/routers/test_images_delete.py -v -k delete_image_endpoint
```

Expected: FAIL — `ImportError: cannot import name 'delete_image' from 'app.routers.images'`.

- [ ] **Step 3: Add the endpoint**

Edit `services/api/app/routers/images.py`. Find the `get_image` handler (currently at `@router.get("/{image_id}", response_model=ImageServiceView)` around line 271). Add the DELETE handler **immediately after the `get_image` function** (before `@router.get("/count", ...)` and well before `@router.get("/{blob_path:path}")`, so the path-catchall doesn't shadow it):

```python
@router.delete("/{image_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_image(
    image_id: str,
    confirm: bool = Query(False, description="route_count>0 일 때 삭제를 강제로 진행"),
    current_user: User = Depends(get_current_user),
):
    try:
        object_id = ObjectId(image_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="유효하지 않은 이미지 ID입니다.",
        )

    outcome = await _soft_delete_image(
        object_id,
        current_user.id,
        confirm=confirm,
        now=datetime.now(timezone.utc),
    )

    if outcome.status == "not_found":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="이미지를 찾을 수 없습니다.",
        )
    if outcome.status == "needs_confirmation":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "IMAGE_HAS_ROUTES",
                "route_count": outcome.route_count,
            },
        )
    return None
```

- [ ] **Step 4: Run the full test file to verify all tests pass**

```bash
cd services/api && uv run pytest tests/routers/test_images_delete.py -v
```

Expected: 10 passed (6 helper + 4 endpoint).

- [ ] **Step 5: Run the neighboring routers' tests to verify no regression**

```bash
cd services/api && uv run pytest tests/routers/test_routes_image_route_count.py tests/routers/test_routes.py -v
```

Expected: all pass. If any route-related test broke, the DELETE endpoint was inserted in the wrong place (likely after the `/{blob_path:path}` catch-all). Move it to right after `get_image`.

- [ ] **Step 6: Commit**

```bash
git add services/api/app/routers/images.py services/api/tests/routers/test_images_delete.py
git commit -m "$(cat <<'EOF'
feat(api): add DELETE /images/{image_id} for soft delete

업로더 본인이 자기 이미지를 소프트 삭제. route_count>0 이면 ?confirm=true 없이는 409 IMAGE_HAS_ROUTES(route_count 동봉). 이미 삭제된/타인/없는 이미지는 404. 기존 루트는 Image.get() 으로 필터 없이 조회하므로 소프트 삭제 후에도 그대로 표시된다.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Lock in existing guardrails with a regression test

**Goal:** 스펙의 "이미 적용된 가드 (회귀 방지만)" 리스트 중 가장 취약한 지점 — **루트 생성이 삭제된 이미지를 거부** — 을 명시적 테스트로 고정. 이게 실수로 풀리면 소프트 삭제의 핵심 약속이 무너지니 따로 잡는다.

**Files:**
- Modify: `services/api/tests/routers/test_images_delete.py`

- [ ] **Step 1: Write the failing-on-regression test**

Append to `services/api/tests/routers/test_images_delete.py`:

```python
async def test_soft_deleted_image_excluded_from_owner_listing_query(mongo_db):
    """After soft-delete, the exact query used by GET /images (`is_deleted != True`) must not include the image.

    If this ever breaks, the owner will see 'zombie' deleted images in their gallery.
    """
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id)
    await image.insert()
    await _soft_delete_image(
        image.id, user_id, confirm=False,
        now=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    )

    results = await Image.find(
        Image.user_id == user_id,
        Image.is_deleted != True,
    ).to_list()

    assert results == []


async def test_soft_deleted_image_excluded_from_route_creation_query(mongo_db):
    """Route creation uses `Image.find_one(..., is_deleted != True)` at routes.py:113-119.

    Lock that a soft-deleted image cannot be the source of a new route.
    """
    user_id = PydanticObjectId()
    image = _make_image(user_id=user_id)
    await image.insert()
    await _soft_delete_image(
        image.id, user_id, confirm=False,
        now=datetime(2026, 4, 20, tzinfo=dt_tz.utc),
    )

    found = await Image.find_one(
        Image.id == image.id,
        Image.user_id == user_id,
        Image.is_deleted != True,
    )

    assert found is None
```

- [ ] **Step 2: Run the new tests to verify they pass**

```bash
cd services/api && uv run pytest tests/routers/test_images_delete.py -v
```

Expected: 12 passed.

- [ ] **Step 3: Run the full test suite to verify nothing else broke**

```bash
cd services/api && uv run pytest -v
```

Expected: all pass. If you see collection errors, ensure imports from `app.routers.images` work without raising at import time (no top-level side effects should have been introduced).

- [ ] **Step 4: Commit**

```bash
git add services/api/tests/routers/test_images_delete.py
git commit -m "$(cat <<'EOF'
test(api): lock guardrails against soft-deleted images

listing 쿼리와 route-creation 쿼리 양쪽이 소프트 삭제된 이미지를 제외한다는 계약을 고정. 누가 실수로 is_deleted 필터를 빼면 이 테스트가 먼저 잡아낸다.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Out of Scope (do NOT do these)

- 모바일 UI (삭제 버튼, 확인 다이얼로그 등)
- 관리자 복구 엔드포인트
- GCS 파일 정리 / hard delete 잡
- 삭제된 이미지 전용 휴지통 화면
- 루트 생성 경로의 404 → `IMAGE_DELETED` 로 변경 (현 404 가 기능상 충분)
- `Image.route_count` 관련 코드 수정 (이 스펙의 관심사 아님)

## Verification Checklist

구현 완료 후 PR 전 스스로 확인:

- [ ] `uv run pytest tests/routers/test_images_delete.py -v` — 12 passed
- [ ] `uv run pytest` 전체 통과
- [ ] `DELETE /images/{id}` 엔드포인트가 `/{blob_path:path}` 보다 **위쪽**에 정의되어 있는지 (shadowing 방지)
- [ ] 스펙의 Policy Decisions 9 행과 실제 응답이 일치하는지 (204/404/409, detail 포맷)
- [ ] 엔드포인트 함수 시그니처: `image_id: str`, `confirm: bool = Query(False)`, `current_user: User = Depends(get_current_user)`
