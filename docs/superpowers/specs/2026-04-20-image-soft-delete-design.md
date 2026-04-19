# Image Soft Delete Design

**Date:** 2026-04-20
**Status:** Draft

## Goal

이미지 업로더 본인이 자기 이미지를 소프트 삭제할 수 있게 한다. 삭제된 이미지는

- 새로운 루트를 만드는 데 쓸 수 없다.
- 이미 그 이미지로 만들어진 루트는 계속 정상적으로 작동하며, 루트 상세에서 이미지도 그대로 보인다.
- 업로더 본인의 이미지 리스트/검색에서 사라진다.
- 복구는 유저가 할 수 없다 (관리자가 DB/검수툴로 처리).

## Context

- `Image` 모델에는 이미 `is_deleted: bool`, `deleted_at: Optional[datetime]` 필드가 존재한다 (`services/api/app/models/image.py:51-53`).
- 다음 경로에서 이미 `Image.is_deleted != True` 필터가 적용되고 있어 "삭제된 이미지가 리스트/검색에서 빠지고, 새로운 루트도 만들 수 없다" 는 요구사항은 가드만 해주면 자동으로 충족된다.
  - 내 이미지 리스트 `GET /images` — `app/routers/images.py:92`
  - 이미지 상세 — `app/routers/images.py:290`
  - 이미지 개수 (기본) — `app/routers/images.py:337`
  - 루트 생성 `POST /routes` — `app/routers/routes.py:113-119` (삭제된 이미지면 404 `Image not found`)
- 루트 상세/조회 경로는 `Image.get(route.image_id)` 를 쓰므로 `is_deleted` 를 필터하지 않는다. 즉 기존 루트는 이미지가 삭제돼도 이미지 URL 을 계속 받는다 (`app/routers/routes.py:334, 444, 530`).
- 현재 미존재 기능: 유저가 이미지를 삭제하는 엔드포인트 자체. `is_deleted` 플래그는 쓸 곳만 있고 켜는 경로가 없는 상태.
- `Image.route_count` 는 루트 생성/삭제 시 `_inc_image_route_count` 로 증감된다 (`app/routers/routes.py:41-49`). 이미지가 소프트 삭제된 뒤에도 이 증감 로직은 그대로 돌아야 한다 (기존 루트는 여전히 삭제 가능하고, 그럴 때 `route_count` 는 감소해야 정확).

## Policy Decisions

| # | 결정 | 내용 |
|---|---|---|
| 1 | 삭제 주체 | 이미지 업로더 본인만 |
| 2 | 삭제 방식 | Soft delete — `is_deleted=True`, `deleted_at=utcnow()` |
| 3 | 기존 루트 | 그대로 보존. 루트 상세에서 이미지 계속 표시 |
| 4 | 신규 루트 | 삭제된 이미지로 생성 불가 (기존 가드가 404 반환, 변경 없음) |
| 5 | `route_count>0` 일 때 | `?confirm=true` 없이는 409 `IMAGE_HAS_ROUTES`, 있으면 삭제 진행 |
| 6 | 재삭제 요청 | 이미 `is_deleted=True` → 404 (존재하지 않는 리소스 취급) |
| 7 | 복구 | 유저는 불가. 관리자만 DB/검수툴로 처리. 이번 스코프에 복구 엔드포인트 없음 |
| 8 | 스토리지 파일 | GCS 객체 삭제하지 않음. 기존 루트가 그 URL 로 이미지를 계속 받아야 하기 때문 |
| 9 | 에러 응답 포맷 | 기존 패턴 (`{"code": "...", ...}`) 재사용 |

## Out of Scope

- 모바일 UI (삭제 버튼/확인 다이얼로그 등) — 별도 디자인 세션에서 다룸
- 관리자 복구 엔드포인트 — 검수툴/DB 직접 수정으로 처리
- 스토리지 파일 정리 / hard delete 잡
- `is_deleted` 이미지를 볼 수 있는 "휴지통" 화면
- 루트 생성 시 기존 404 를 더 구체적인 코드 (예: `IMAGE_DELETED`) 로 바꾸는 작업 — 현재 404 로도 기능상 충분. 필요해지면 후속 이슈로.

## Architecture

### Backend (`services/api`)

| 파일 | 변경 |
|---|---|
| `app/routers/images.py` | 신규 엔드포인트 `DELETE /images/{image_id}` 추가 |
| `tests/routers/test_images.py` | 신규 엔드포인트 테스트 케이스 추가 (본인 삭제, 타인 차단, route_count 가드, confirm, 멱등 실패, 리스트/검색 제외, 기존 루트 영향 없음) |

모델 스키마 변경 없음 (`is_deleted`, `deleted_at` 재사용).

### Mobile

이번 스코프 아님.

## API Contract

### `DELETE /images/{image_id}`

**Path/Query:**
- `image_id: str` (path) — ObjectId 문자열
- `confirm: bool` (query, optional, default `false`) — `route_count > 0` 일 때 삭제를 진행하려면 `true` 필요

**인증:** `get_current_user`.

**권한:** 이미지의 `user_id == current_user.id` 여야 한다.

**선결 조건:** `Image.is_deleted != True`.

**Responses:**

| 상태 | 조건 | 바디 |
|---|---|---|
| 204 No Content | 삭제 성공 | — |
| 400 Bad Request | `image_id` 형식 오류 | 기본 FastAPI validation |
| 401 Unauthorized | 인증 실패 | 기존 auth 의존성 |
| 404 Not Found | 이미지 없음 / 타인 이미지 / 이미 `is_deleted=True` | `{"detail": "Image not found"}` |
| 409 Conflict | `route_count > 0` 이고 `confirm != true` | `{"detail": {"code": "IMAGE_HAS_ROUTES", "route_count": N}}` |

**동작:**
1. `Image.find_one(id==image_id, user_id==current_user.id, is_deleted != True)` — 없으면 404.
2. `image.route_count > 0` 이고 `confirm` 이 truthy 가 아니면 409 `IMAGE_HAS_ROUTES` 응답 (`route_count` 같이 내려줌).
3. `image.is_deleted = True`, `image.deleted_at = datetime.now(timezone.utc)` 설정 후 `await image.save()`.
4. 연결된 `Route` 문서는 건드리지 않는다.
5. 204 반환.

**멱등성:** 같은 `DELETE` 를 두 번 호출하면 두 번째는 404. 클라이언트는 "이미 삭제됨" 과 "원래 없음" 을 구분할 필요가 없다고 가정.

**타인 이미지 조회 차단:** `user_id` 조건이 쿼리에 포함되므로 타인 이미지 id 로 호출해도 404. 별도 403 처리 없음.

## Guardrails (already in place — verify only)

다음 경로들은 이미 `is_deleted != True` 필터가 있어 "삭제된 이미지가 노출되지 않는다 / 새 루트 재료가 되지 않는다" 는 요구를 자동으로 만족한다. 이번 작업에서는 **회귀가 없는지만 테스트로 고정**한다.

- `GET /images` — 삭제 후 리스트에 안 보임
- `GET /images/count` — 기본 카운트에서 제외
- `GET /images/{id}` — 삭제 후 404
- `POST /routes` — 삭제된 이미지 id 로 호출 시 404

## Testing

### Unit / Router (`services/api/tests/routers/test_images.py`)

| # | 시나리오 | 기대 |
|---|---|---|
| 1 | 본인 이미지, `route_count==0` 삭제 | 204, DB 상 `is_deleted=True`, `deleted_at` 세팅 |
| 2 | 본인 이미지, `route_count>0`, `confirm` 없음 | 409 `{"code": "IMAGE_HAS_ROUTES", "route_count": N}`, DB 변경 없음 |
| 3 | 본인 이미지, `route_count>0`, `confirm=true` | 204, `is_deleted=True` |
| 4 | 타인 이미지 | 404 |
| 5 | 이미 `is_deleted=True` 이미지 재삭제 | 404 |
| 6 | 존재하지 않는 `image_id` (유효 ObjectId) | 404 |
| 7 | 잘못된 `image_id` 포맷 | 400 |
| 8 | 인증 없음 | 401 |
| 9 | 삭제 이후 `GET /images` 리스트 | 해당 이미지 미포함 |
| 10 | 삭제 이후 `GET /images/{id}` 상세 | 404 |
| 11 | 삭제 이후 `POST /routes` with 그 image_id | 404 `Image not found` |
| 12 | 삭제 이후 기존 루트 상세 `GET /routes/{id}` | 200, `image_url` 그대로 포함 |
| 13 | 삭제된 이미지의 기존 루트 삭제 | 204, `Image.route_count` 1 감소 (`_inc_image_route_count` 는 `is_deleted` 필터 없이 직접 `update_one` 이라 정상 동작) |

### Integration notes

- 테스트는 `ObjectId` 고정 생성 + 실제 `Image`, `Route` 문서 삽입 패턴을 기존 `test_images.py` 에 맞춘다.
- `route_count` 는 실제 루트 생성 헬퍼로 올리지 않고, 직접 필드를 세팅해서 조건부 분기만 검증해도 충분 (스피드용). 단 케이스 #12–#13 은 실제 Route 문서가 있어야 하므로 생성 필요.

## Migration / Rollout

- 스키마 변경 없음. 기존 `is_deleted` 값이 `False` 인 레코드는 그대로 유효.
- 서버 배포만으로 즉시 기능 on. 기존 클라이언트는 엔드포인트를 호출하지 않으므로 영향 없음.
- 모바일은 별도 디자인 후 이 엔드포인트를 소비한다.

## Open Questions

없음.
