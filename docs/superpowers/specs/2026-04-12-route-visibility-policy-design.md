# Route Visibility Policy Design

**Date:** 2026-04-12
**Status:** Draft

## Goal

`Route.visibility`(PUBLIC/PRIVATE) 정책을 실제로 동작하게 만든다. 루트 에디터에 visibility 토글 UI를 추가하고, 남의 비공개 루트 상세 진입을 차단하되 활동 기록에는 정보를 그대로 노출한다.

## Context

- `Route.visibility`는 모델에 정의되어 있고 (`public` / `private`, 기본 `public`) 생성·수정 엔드포인트가 이미 값을 받고 있다.
- 그러나 모바일 에디터에는 토글 UI가 없어 모든 루트가 기본 PUBLIC으로 생성된다.
- 현재 visibility의 유일한 실제 효과는 `share.py`의 공유 링크 차단뿐이다.
- `GET /routes/{id}`는 `Route.user_id == current_user.id`로 필터되어 있어 남의 루트는 아예 볼 수 없다 (404).
- 피드/탐색 기능이 미래에 도입될 예정이며, 그 전에 visibility 정책을 먼저 바로잡는다.

## Policy Decisions

| # | 결정 | 내용 |
|---|---|---|
| 1 | 신규 루트 기본값 | `PUBLIC` |
| 2 | 토글 UI 위치 | 루트 에디터 메타 정보 영역(제목/설명 아래)의 Switch |
| 3 | PUBLIC→PRIVATE 전환 경고 | 다른 유저의 활동 기록이 있는 경우에만 확인 다이얼로그 |
| 4 | 경고 조건 전달 | 편집 진입 시 호출하는 `GET /routes/{id}`에 `withActivityCheck=true` 쿼리 파라미터 → 응답 `hasOtherUserActivities` 플래그 |
| 5 | visibility 저장 시점 | 토글 시 즉시 PATCH 금지. 로컬 state만 변경하고 **저장 버튼** 누를 때 다른 변경사항과 bundled PATCH |
| 6 | 엔드포인트 구조 | 단일 `GET /routes/{id}` 확장: 소유자 풀 데이터, 비소유자는 PUBLIC만 200, PRIVATE은 403 `{reason:"private"}` |
| 7 | 활동 기록 카드 정보 | 썸네일/제목/등급/색 등 기존 정보 그대로 노출 |
| 8 | 활동 기록 카드 뱃지 | `routeVisibility=private`이면 🔒 "비공개된 루트입니다.", `isDeleted=true`면 🗑 "삭제된 루트입니다." (삭제 우선) |
| 9 | 차단 화면 UX | 풀스크린 없음. route_viewer 진입 시 서버 응답에 따라 토스트 + `Navigator.pop()` |

## Out of Scope

- 피드/탐색 기능 자체
- 일별 활동 루트 그룹 일괄 삭제 (별도 스펙으로 분리)
- `share.py`의 공유 링크 차단 페이지 (기존 동작 유지)
- 기존 루트 데이터 마이그레이션 (모두 PUBLIC 기본이라 불필요)

## Architecture

### Backend (`services/api`)

| 파일 | 변경 |
|---|---|
| `app/routers/routes.py` | `GET /routes/{id}` 권한 확장: 소유자 아니면 PUBLIC만 통과, PRIVATE이면 403 `{reason:"private"}`. `?withActivityCheck=true` 시 소유자 응답에 `hasOtherUserActivities` 포함 |
| `app/routers/routes.py` | `RouteDetailView`에 `hasOtherUserActivities: Optional[bool]` 필드 추가 (소유자 + 플래그 요청 시에만 채움) |
| `app/routers/my.py` | `daily-routes` 응답 파이프라인에 routes 컬렉션 lookup 추가, 각 `DailyRouteItem`에 `routeVisibility`, `isDeleted` 채움 |
| `app/routers/my.py` | `DailyRouteItem`에 `routeVisibility: Visibility`, `isDeleted: bool` 필드 추가 |

### Mobile (`apps/mobile`)

| 파일 | 변경 |
|---|---|
| `lib/pages/editors/route_editor_page.dart` | 메타 정보 영역에 visibility Switch 추가. 편집 진입 시 `?withActivityCheck=true`로 로드, 로컬 state 관리, 저장 시 bundled PATCH. PUBLIC→PRIVATE 토글 + `hasOtherUserActivities=true`일 때 확인 다이얼로그 |
| `lib/pages/viewers/route_viewer.dart` | `GET /routes/{id}` 호출 결과 처리: 403 `reason=private` → 🔒 토스트 + pop, 404 → 🗑 토스트 + pop |
| `lib/widgets/viewers/activity_panel.dart` (혹은 daily route 카드 위젯) | 카드 내부에 visibility/isDeleted 뱃지 렌더 |
| 관련 모델 클래스 (route detail, daily route item) | `visibility`, `hasOtherUserActivities`, `routeVisibility`, `isDeleted` 필드 추가 |

## API Contracts

### `GET /routes/{route_id}`

**Query params:**
- `withActivityCheck: bool = false` — 소유자 요청일 때만 의미 있음

**Responses:**

```jsonc
// 200 — 소유자 요청 + withActivityCheck=true
{
  "id": "...",
  "visibility": "public" | "private",
  "hasOtherUserActivities": true,
  /* 기존 RouteDetailView 필드 전부 */
}

// 200 — 소유자 요청 + withActivityCheck=false (기본)
{
  "id": "...",
  "visibility": "public" | "private",
  /* 기존 RouteDetailView 필드 — hasOtherUserActivities 없음 */
}

// 200 — 비소유자 요청 + PUBLIC 루트
{
  "id": "...",
  "visibility": "public",
  /* 기존 RouteDetailView 필드 — hasOtherUserActivities 없음 */
}

// 403 — 비소유자 요청 + PRIVATE 루트
{ "detail": { "reason": "private" } }

// 404 — 존재하지 않거나 is_deleted=true
{ "detail": "Route not found" }
```

**Authorization rules:**

| 요청자 | 루트 상태 | 결과 |
|---|---|---|
| owner | any | 200 (기존과 동일) |
| non-owner | PUBLIC | 200 |
| non-owner | PRIVATE | 403 `{reason:"private"}` |
| any | soft-deleted | 404 |
| any | 없음 | 404 |

**`hasOtherUserActivities` 계산 (소유자 + `withActivityCheck=true`일 때만):**

```python
has_other = await Activity.find(
    Activity.route_id == route.id,
    Activity.user_id != current_user.id,
).limit(1).count() > 0
```

### `GET /my/daily-routes`

기존 응답 필드 유지 + 각 `DailyRouteItem`에 두 필드 추가:

```jsonc
{
  "summary": { /* 기존 */ },
  "routes": [
    {
      "routeId": "...",
      "routeSnapshot": { /* 기존 */ },
      "routeVisibility": "public" | "private",   // NEW
      "isDeleted": false,                          // NEW
      "totalCount": 12,
      "completedCount": 1,
      "attemptedCount": 11,
      "totalDuration": 3600
    }
  ]
}
```

구현은 aggregation 파이프라인에 routes 컬렉션 `$lookup` 추가 또는 결과 조립 단계에서 batch fetch 어느 쪽이든 가능하다. 구체적인 방식은 플랜 단계에서 결정한다.

### `POST /routes` / `PATCH /routes/{id}`

기존 그대로. `visibility` 필드는 이미 받고 있음. 변경 없음.

## UX Flows

### Create flow
1. 루트 에디터 첫 진입, Switch 기본값 ON(`public`)
2. 필요하면 OFF로 내림 → 로컬 state `private`
3. 저장 시 POST `/routes` 바디에 `visibility` 포함

### Edit flow
1. `GET /routes/{id}?withActivityCheck=true` 호출
2. 응답의 `hasOtherUserActivities`를 state에 보관
3. Switch는 로컬 state만 변경 — 서버 호출 없음
4. PUBLIC → PRIVATE 토글 시점:
   - `hasOtherUserActivities=true` → 확인 다이얼로그 노출
     > "비공개로 바꾸면 다른 사람의 활동 기록에도 🔒 표시로 바뀌고 상세 진입이 막혀요. 계속할까요?"
     - 취소 → Switch 원위치
     - 확인 → 로컬 state에 반영
   - `false` → 조용히 로컬 state에 반영
5. 저장 버튼 → PATCH `/routes/{id}` 한 번으로 모든 변경 bundled 전송
6. 편집 화면을 그냥 나가면 로컬 변경 폐기 (기존 UX 동일)

### My page · 일일 루트 카드
1. `GET /my/daily-routes` 로 카드 목록 로드
2. 각 카드 렌더:
   - `isDeleted=true` → 🗑 "삭제된 루트입니다." 한 줄 (최우선)
   - `routeVisibility="private"` → 🔒 "비공개된 루트입니다." 한 줄
   - 그 외 → 일반 카드
3. 카드 탭 → route_viewer 진입 시도 (뱃지와 무관하게 탭은 항상 가능)

### Route viewer
1. `GET /routes/{id}` 호출
2. 응답 처리:
   - 200 → 정상 렌더
   - 403 `{reason:"private"}` → 토스트 "🔒 비공개된 루트입니다" + `Navigator.pop()`
   - 404 → 토스트 "🗑 삭제된 루트입니다" + `Navigator.pop()`
   - 그 외 에러 → 기존 에러 처리

## Edge Cases

- **소유자가 자기 루트를 뷰어로 본다**: `withActivityCheck` 미전달(기본 false) → 추가 쿼리 비용 없음
- **편집 중 race**: 편집 화면 로드 이후 다른 유저가 활동 기록을 새로 만들면 `hasOtherUserActivities`가 stale이 될 수 있음. 다이얼로그가 안 뜨는 정도의 UX 손실만 있고 데이터는 일관됨 (저장 후에는 서버 정책이 적용)
- **403 vs 404 구분**: 존재하지 않는 루트 ≠ 비공개 루트. 두 경우 서로 다른 토스트 메시지로 구분
- **soft-deleted 루트가 PUBLIC 상태**: 404가 visibility 체크보다 우선 (기존 `is_deleted != True` 필터 유지)
- **daily-routes의 routeSnapshot과 현재 Route 불일치**: snapshot은 활동 당시 상태를 보존 (의도된 동작). `routeVisibility`/`isDeleted`만 현재 상태 반영

## Testing

### Backend

- `GET /routes/{id}` 비소유자 + PUBLIC → 200
- `GET /routes/{id}` 비소유자 + PRIVATE → 403 `{reason:"private"}`
- `GET /routes/{id}` soft-deleted → 404 (visibility 무관)
- `GET /routes/{id}?withActivityCheck=true` 소유자 + 다른 유저 활동 있음 → `hasOtherUserActivities=true`
- `GET /routes/{id}?withActivityCheck=true` 소유자 + 다른 유저 활동 없음 → `hasOtherUserActivities=false`
- `GET /routes/{id}?withActivityCheck=true` 비소유자 호출 → 플래그 응답에서 제외
- `GET /routes/{id}` 기본 호출(withActivityCheck 미전달) → 플래그 응답에서 제외
- `GET /my/daily-routes` 응답 각 항목에 `routeVisibility`, `isDeleted` 존재
- `GET /my/daily-routes` soft-deleted 루트 항목 → `isDeleted=true`
- `GET /my/daily-routes` private 루트 항목 → `routeVisibility="private"`

### Mobile (가능한 범위)

- 루트 에디터 visibility Switch UI 렌더 및 토글
- PUBLIC→PRIVATE 토글 + `hasOtherUserActivities=true` → 다이얼로그 노출
- 다이얼로그 취소 → Switch 원위치
- PUBLIC→PRIVATE 토글 + `hasOtherUserActivities=false` → 다이얼로그 없음
- 저장 시 PATCH 바디에 visibility 포함
- daily-routes 카드: 일반/private/deleted 3가지 상태 렌더
- route_viewer: 403 `reason=private` → 토스트+pop
- route_viewer: 404 → 토스트+pop

## Implementation Notes

- `hasOtherUserActivities`는 `limit(1).count()`로 존재 여부만 확인 (전수 집계 불필요)
- `daily-routes`의 routes lookup은 기존 aggregation 뒤에 `$lookup` 단계 추가를 우선 검토. batch fetch 대비 RTT 1회에 처리 가능
- 구현 세부사항은 writing-plans 단계에서 다룸
