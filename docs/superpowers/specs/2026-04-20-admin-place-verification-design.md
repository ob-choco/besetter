# 운영자 어드민 — 장소 검수 툴 설계

## 개요

운영자가 사용자 제출 데이터를 검수할 수 있는 Next.js 기반 어드민 웹 앱을 `apps/admin`에 신설한다. v1에서는 장소(Place)와 관련된 두 개의 검수 대상을 다룬다.

- **신규 gym 검수** — `Place.status="pending"`으로 등록된 체육관을 `PASS` / `FAIL` / `MERGE`
- **수정 제안 검수** — `PlaceSuggestion.status="pending"` 항목을 `APPROVE` / `REJECT`

운영자는 Google Workspace(`olivebagel.com`) 계정으로 로그인한다. 어드민 앱은 v1에서는 **로컬 실행만** 지원하며 배포는 후속 과제로 남겨둔다.

## 목표 및 범위

**목표**
- 운영자가 한 화면에서 대기 중인 신규 gym을 빠르게 검수할 수 있다.
- MERGE는 source에 딸린 이미지/루트/활동까지 타깃 place로 재귀속되어, 등록자의 기존 기록이 유실되지 않는다.
- 수정 제안은 현재값 vs 제안값 diff 뷰로 필드 단위 비교 후 일괄 반영하거나 거절한다.
- 운영 결정은 해당 사용자에게 인앱 알림(+푸시)으로 전달된다.

**범위 안**
1. Next.js 앱 `apps/admin` 신설 (App Router, TypeScript)
2. Google OAuth 기반 인증: hosted domain `olivebagel.com` + 이메일 allowlist
3. MongoDB 직접 접근: 공식 `mongodb` Node 드라이버, Atlas 클러스터 동일
4. Firebase Admin SDK로 FCM 푸시 발송 (dev에서는 env 플래그로 스킵 가능)
5. 두 개의 검수 뷰: 신규 gym 큐, 수정 제안 큐 — 사이드바로 전환
6. 새 알림 타입 5종 추가 (`place_review_passed/failed`, `place_merged`, `place_suggestion_approved/rejected`)
7. `Place` 모델에 `rejectedReason: Optional[str]` 필드 추가 (FastAPI Beanie 모델 + Next.js 타입)

**범위 밖**
- 어드민 앱의 Cloud Run 배포 (로컬 실행만)
- 공유 패키지로 알림 템플릿 중앙화 (v1은 FastAPI/Next.js 중복 보유, 후속 리팩터)
- FastAPI 쪽 admin 엔드포인트 추가 (v1에서 API server는 손대지 않음)
- 검수 히스토리/감사 로그 DB 저장 (v1은 stdout 로깅만)
- 운영자 역할/권한 분리, 2FA, IP 제한
- 다중 운영자 동시 검수를 위한 실시간 락/큐 시그널

## 아키텍처 개요

```
브라우저 (운영자)
  │
  └─ Next.js (apps/admin) — 로컬 실행 (pnpm dev)
       │
       ├─ NextAuth.js (Google Provider, hd=olivebagel.com, email allowlist)
       │
       ├─ React (App Router) — sidebar / queue / detail / diff / merge dialog
       │
       └─ Route Handlers (/api/*)
             │
             ├─ MongoClient singleton  ──► MongoDB (동일 Atlas 클러스터)
             │      collections: places, placeSuggestions,
             │                   images, activities, users,
             │                   notifications, deviceTokens
             │
             └─ Firebase Admin SDK      ──► FCM HTTP v1 (ADMIN_FCM_ENABLED 필요)
```

**원칙**
- 서버 전용 자원(Mongo, Firebase Admin, 서비스 계정)은 route handler 또는 서버 컴포넌트에서만 접근. 클라이언트 번들에 creds 유출 금지.
- 모든 mutation은 route handler에서 수행, 클라이언트는 fetch만.

## 디렉토리 구조

```
apps/admin/
  package.json
  tsconfig.json
  next.config.js
  .env.local.example
  src/
    app/
      layout.tsx                         # 공통 레이아웃 (사이드바 + 로그인 게이트)
      page.tsx                           # → /places 리디렉트
      places/page.tsx                    # 신규 gym 큐 + 상세 + merge 다이얼로그
      suggestions/page.tsx               # 수정 제안 큐 + diff 뷰
      api/
        auth/[...nextauth]/route.ts
        places/pending/route.ts          # GET
        places/[id]/route.ts             # GET
        places/[id]/pass/route.ts        # POST
        places/[id]/fail/route.ts        # POST { reason?: string }
        places/[id]/merge/route.ts       # POST { targetPlaceId }
        places/merge-candidates/route.ts # GET ?lat&lng&q
        suggestions/pending/route.ts     # GET
        suggestions/[id]/route.ts        # GET
        suggestions/[id]/approve/route.ts# POST
        suggestions/[id]/reject/route.ts # POST { reason?: string }
    lib/
      auth.ts                            # NextAuth config + session helper
      authz.ts                           # requireAdmin(session) 공통 가드
      mongo.ts                           # MongoClient singleton
      push.ts                            # Firebase Admin init
      notifications.ts                   # Notification insert + FCM fanout
      notification-templates.ts          # 5종 신규 템플릿 (ko/en/ja/es)
      place-ops.ts                       # PASS / FAIL / MERGE 비즈니스 로직
      suggestion-ops.ts                  # APPROVE / REJECT 비즈니스 로직
      db-types.ts                        # MongoDB 문서 TS 타입 (camelCase)
      normalize.ts                       # normalizeName 유틸 (Python 로직 포팅)
      zod-schemas.ts                     # 각 API body 검증 스키마
    components/
      sidebar.tsx
      queue-list.tsx
      place-detail.tsx
      merge-dialog.tsx
      suggestion-diff.tsx
```

## MongoDB 필드 네이밍 (camelCase)

Beanie `model_config`의 `alias_generator=to_camel` 탓에 실제 MongoDB 문서는 camelCase이다. Next.js에서 직접 접근하므로 모든 쿼리/업데이트 경로는 camelCase를 써야 한다.

- `places`: `name`, `normalizedName`, `type`, `location`, `coverImageUrl`, `createdBy`, `createdAt`, `status`, `mergedIntoPlaceId` (+ 신규 `rejectedReason`)
- `placeSuggestions`: `placeId`, `requestedBy`, `status`, `changes.{name, latitude, longitude, coverImageUrl}`, `createdAt`, `readAt`, `reviewedAt`
- `images`: `placeId`, `userId`, `isDeleted`, …
- `activities`: `routeSnapshot.placeId`, `routeSnapshot.placeName`, …
- `users`: `unreadNotificationCount`, `profileId`, `profileImageUrl`
- `notifications`: `userId`, `type`, `title`, `body`, `params`, `link`, `createdAt`
- `deviceTokens`: `userId`, `token`, `locale`

TypeScript 타입도 camelCase로 선언한다 (`PlaceDoc`, `PlaceSuggestionDoc`, `NotificationDoc` 등 `db-types.ts`).

## 인증 & 인가

**NextAuth.js + Google Provider**
- `hd=olivebagel.com` 파라미터로 Google OAuth 응답 `hd` 클레임이 일치하지 않으면 로그인 거부
- 성공 응답의 `email`이 `ADMIN_EMAIL_ALLOWLIST` (쉼표 구분 env) 에 포함되지 않으면 로그인 거부
- Session 전략: JWT, `NEXTAUTH_SECRET`

**API 가드**
- 모든 `/api/*` route handler 진입부에서 `requireAdmin(session)` 호출
  - 세션 없음 → 401
  - allowlist 불일치 → 403
- 클라이언트 페이지는 `layout.tsx`의 서버 컴포넌트에서 세션 체크, 미로그인 시 로그인 페이지로 리디렉트

## 환경변수

```
# .env.local.example
MONGODB_URI=
ADMIN_EMAIL_ALLOWLIST=htnnsc@olivebagel.com
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
NEXTAUTH_SECRET=
NEXTAUTH_URL=http://localhost:3000
FIREBASE_PROJECT_ID=
FIREBASE_SERVICE_ACCOUNT_JSON=   # (raw JSON 또는 파일 경로)
ADMIN_FCM_ENABLED=false          # true 일 때만 실제 FCM 발송
```

## 화면별 UX

### 공통 레이아웃
- 좌측 210px 사이드바: 운영자 이메일, "장소" 섹션 하위 "장소 검수" / "수정 제안" (각각 pending 카운트 뱃지)
- 우측 컨텐츠 영역: 선택된 툴의 전용 뷰

### 신규 gym 검수 (`/places`)
- 가운데 320px 큐: `status=pending` 최신순, 각 아이템에 `normalizedName` 또는 200m 반경 유사 후보 힌트 표시
- 우측 상세: 커버 이미지, 이름, 좌표, 등록자, 매달린 이미지/루트/활동 개수, 반경 200m approved 장소 목록
- 하단 액션: `PASS` (녹색) / `FAIL` (빨강) / `MERGE` (주황) + FAIL 선택 사유 입력

### MERGE 타깃 선택 다이얼로그
- 상단: source 요약 (이관될 이미지/루트/활동 개수 재확인)
- 입력: 이름 검색 + "1km 반경" 토글
- 결과: `status=approved` 장소 거리순 (이름 검색 시 거리 정렬은 해제) — 각 카드에 이미지/루트 개수
- 확정: "선택 장소로 MERGE"
- 빈 상태: "1km 반경 내 approved 장소가 없습니다"

### 수정 제안 검수 (`/suggestions`)
- 큐 아이템: 타깃 place 이름 + 제안된 필드 태그 (이름/좌표/커버)
- 상세: 필드별 diff 카드 — 왼쪽 CURRENT(빨강 바) / 오른쪽 PROPOSED(초록 바). 제안 없는 필드는 점선 카드로 축소 표시.
- 하단 액션: `APPROVE` / `REJECT` + 선택 사유 입력

## API 계약 (모두 `/api/...`)

### `GET /places/pending` → 큐 리스트
- 쿼리: 없음 (v1은 createdAt asc 고정)
- 응답: `PlaceDoc` 배열 + 각 아이템에 `{ nearestApproved?: { name, distanceMeters } }` 힌트 주입
- 구현: `places.find({ type:"gym", status:"pending" }).sort({ createdAt: 1 })`

### `GET /places/:id` → 상세
- 응답: `PlaceDoc` + `creatorProfile` (users 조인) + `{ imageCount, routeCount, activityCount }` + `nearbyApproved: PlaceWithDistance[]` (200m)

### `GET /places/merge-candidates?lat&lng&q`
- `q` 비었으면: `$nearSphere` 반경 1km, approved 장소 거리순
- `q` 있으면: `normalizedName: { $regex }`, approved 장소, 거리 필드 포함해서 반환하되 정렬은 이름/관련도로
- 응답: `Array<PlaceDoc & { distanceMeters?: number, imageCount: number, routeCount: number }>`

### `POST /places/:id/pass`
```ts
{
  const result = await places.updateOne(
    { _id: id, status: "pending" },
    { $set: { status: "approved" } }
  );
  if (result.modifiedCount === 0) return 409;
  await notify(place.createdBy, "place_review_passed", { place_name: place.name }, `/places/${id}`);
}
```

### `POST /places/:id/fail`
Body: `{ reason?: string (1..500) }`
```ts
const set = { status: "rejected" } as any;
if (reason) set.rejectedReason = reason;
const result = await places.updateOne({ _id: id, status:"pending" }, { $set: set });
if (result.modifiedCount === 0) return 409;
await notify(place.createdBy, "place_review_failed", { place_name, reason }, `/places/${id}`);
```
자식 데이터(이미지/루트/활동)는 건드리지 않는다. 검색 노출은 기존 `status: "approved"` 필터로 이미 차단된다.

### `POST /places/:id/merge`
Body: `{ targetPlaceId: ObjectId }`
Transaction (Atlas replica set 전제):
```ts
await session.withTransaction(async () => {
  // 1. source 상태 확인
  const src = await places.findOne({ _id: sourceId, status:"pending" }, { session });
  if (!src) throw 409;
  // 2. target 상태 확인
  const tgt = await places.findOne({ _id: targetId, status:"approved", type:"gym" }, { session });
  if (!tgt) throw 400;
  if (sourceId.equals(targetId)) throw 400;
  // 3. 재귀속
  await images.updateMany({ placeId: sourceId }, { $set: { placeId: targetId } }, { session });
  await activities.updateMany(
    { "routeSnapshot.placeId": sourceId },
    { $set: { "routeSnapshot.placeId": targetId, "routeSnapshot.placeName": tgt.name } },
    { session },
  );
  await places.updateOne(
    { _id: sourceId, status:"pending" },
    { $set: { status:"merged", mergedIntoPlaceId: targetId } },
    { session },
  );
});
await notify(src.createdBy, "place_merged", { place_name: src.name, target_name: tgt.name }, `/places/${targetId}`);
```

### `POST /suggestions/:id/approve`
- suggestion `status=pending` + target place `status=approved` 확인 (아니면 409)
- `changes`에 null이 아닌 필드만 `$set`:
  - `name` → `name` + `normalizedName: normalize(newName)` 동시 업데이트
  - `latitude`/`longitude` 둘 다 제안된 경우 → `location.coordinates: [lng, lat]`
  - `coverImageUrl` → 그대로 대입 (GCS 블롭은 이미 사용자 제출 시 업로드됨)
- `placeSuggestions.updateOne` → `status=approved`, `reviewedAt=now`
- notify `requestedBy`, `place_suggestion_approved`

### `POST /suggestions/:id/reject`
Body: `{ reason?: string (1..500) }`
- `placeSuggestions.updateOne` → `status=rejected`, `reviewedAt=now`
- notify `requestedBy`, `place_suggestion_rejected`

## Notification 발송

### 공통 유틸 (`lib/notifications.ts`)
```ts
async function notify(userId, type, params, link) {
  const notif = {
    userId, type, title: "", body: "",     // 렌더링은 조회 시점 (모바일)
    params, link, createdAt: new Date(),
  };
  const { insertedId } = await notifications.insertOne(notif);
  await users.updateOne({ _id: userId }, { $inc: { unreadNotificationCount: 1 } });
  // push: background (await 하지 않음)
  void sendPush(userId, { ...notif, _id: insertedId });
}
```

### 푸시 발송 (`lib/push.ts`)
- `ADMIN_FCM_ENABLED !== "true"` 이면 early return (로그만)
- Firebase Admin SDK로 `deviceTokens.find({ userId })` → 각 token에 대해 HTTP v1 send
- title/body는 `notification-templates.ts`에서 device.locale(primary)에 맞춰 렌더링 (FastAPI의 `_primary_locale` 로직 포팅)
- 404 / INVALID_ARGUMENT / SENDER_ID_MISMATCH는 stale token으로 간주하고 `deviceTokens.deleteOne({ token })` — FastAPI와 동일

### 신규 Notification 템플릿 5종

**`place_review_passed`**
- title: "암장이 등록되었어요"
- body: "{place_name} 등록이 승인되었어요. 지금 바로 확인해보세요!"

**`place_review_failed`**
- title: "암장 등록이 반려되었어요"
- body (reason 있음): "{place_name} 등록이 반려되었어요. 사유: {reason}"
- body (reason 없음): "{place_name} 등록이 반려되었어요."

**`place_merged`**
- title: "등록한 암장이 병합되었어요"
- body: "{place_name} 은(는) 기존 {target_name}(으)로 병합되었어요. 올려주신 기록은 그대로 옮겨졌습니다."

**`place_suggestion_approved`**
- title: "수정 제안이 반영되었어요"
- body: "{place_name}에 대한 수정 제안이 반영되었습니다. 감사합니다 🙌"

**`place_suggestion_rejected`**
- title: "수정 제안이 반려되었어요"
- body (reason 있음): "{place_name}에 대한 수정 제안이 반려되었어요. 사유: {reason}"
- body (reason 없음): "{place_name}에 대한 수정 제안이 반려되었어요."

4개 로케일(ko/en/ja/es) 모두 작성. 동일한 템플릿을 **양쪽에 추가**한다.
- `services/api/app/services/notification_templates.py` — 모바일 알림 목록 렌더링
- `apps/admin/src/lib/notification-templates.ts` — 푸시 발송 시 렌더링

v1의 의도적 중복. 후속 과제로 shared 패키지 혹은 DB 저장 중 선택.

## Place 모델 확장

### FastAPI (`services/api/app/models/place.py`)
```python
class Place(Document):
    # 기존 필드 유지
    rejected_reason: Optional[str] = Field(None, description="FAIL 사유 (운영자 입력, 선택)")
```
저장 시 `alias_generator=to_camel`로 `rejectedReason` 키로 저장된다. 기존 쿼리·인덱스 변경 없음. Beanie의 기본 동작상 모르는 필드가 있어도 읽기 쿼리는 깨지지 않는다.

### TypeScript (`apps/admin/src/lib/db-types.ts`)
```ts
export type PlaceDoc = {
  _id: ObjectId;
  name: string;
  normalizedName: string;
  type: "gym" | "private-gym";
  status: "pending" | "approved" | "rejected" | "merged";
  location?: { type: "Point"; coordinates: [number, number] };
  coverImageUrl?: string | null;
  createdBy: ObjectId;
  createdAt: Date;
  mergedIntoPlaceId?: ObjectId | null;
  rejectedReason?: string | null;
};
```

## 동시성 / 트랜잭션

- 모든 mutating update는 조건부 update 패턴 (`{_id, status: "pending"}`) + `modifiedCount` 검사 → race 시 **409 Conflict**
- UI는 409 응답을 받으면 큐 자동 리프레시 + 토스트 "이미 다른 운영자가 처리했습니다"
- MERGE는 `session.withTransaction()` 내부에서 images/activities/places 업데이트를 묶는다
  - Atlas는 replica set이라 지원됨
  - 로컬에서 트랜잭션이 필요하면 `mongod --replSet rs0` 초기화 필요 — `.env.local.example`에 메모
  - 트랜잭션 실패 시 전체 롤백 + 500 + FCM 미발송

## Dev 안전장치

어드민이 로컬에서 실행되더라도 Mongo/Firebase 자원은 프로덕션일 수 있다. 실수로 실제 사용자에게 푸시가 가지 않도록:

- `ADMIN_FCM_ENABLED=false` 를 기본값으로 (`.env.local.example`)
- `false`일 때 `sendPush`는 "[dev] FCM skipped" 로그만 출력하고 종료
- Notification 문서 insert와 `unreadNotificationCount` 증가는 그대로 수행됨 → 앱을 켜면 인앱 알림은 보임

## 입력 검증 (`zod-schemas.ts`)

- `FailBody`: `{ reason?: z.string().min(1).max(500).optional() }`
- `MergeBody`: `{ targetPlaceId: z.string().regex(/^[a-f0-9]{24}$/) }`
- `RejectBody`: `{ reason?: z.string().min(1).max(500).optional() }`
- `MergeCandidatesQuery`: `{ lat: z.coerce.number(), lng: z.coerce.number(), q?: z.string().min(1).max(100).optional() }`

검증 실패 → 422 + 필드별 에러 메시지

## 엣지 케이스

| 상황 | 처리 |
|---|---|
| PASS/FAIL/MERGE: place 이미 `approved/rejected/merged` | 409 |
| MERGE: target `status != approved` | 400 |
| MERGE: target `type != gym` (private-gym 방지) | 400 |
| MERGE: source == target | 400 |
| suggestion APPROVE: target place `status != approved` | 409 |
| suggestion `changes` 모두 null | 400 (이론상 발생 X, 생성 API가 이미 막음) |
| cover image 제안 GCS 블롭 누락 | 검증 안 함 — 운영자 육안 확인 책임 |
| 세션 만료 / allowlist 제거 | 401 → 로그인 페이지로 |

## 로깅

모든 mutation 성공/실패 시 `console.log({ op, actor: session.user.email, placeId, targetId?, result })` 형태로 stdout. v1은 DB 감사 테이블을 만들지 않는다.

## 테스트 전략

**단위 테스트** (`mongodb-memory-server` 사용, transaction 포함 시나리오)
- `place-ops.ts`
  - PASS: happy path + 이미 approved인 place (409)
  - FAIL: reason 있음/없음 + 이미 approved인 place (409)
  - MERGE: happy (images, activities 재귀속 검증) + source 이미 처리 (409) + target rejected (400) + target private-gym (400) + source==target (400)
- `suggestion-ops.ts`
  - APPROVE: name만 / 좌표만 / 커버만 / 모두 조합 + target rejected (409)
  - REJECT: reason 있음/없음
- `notifications.ts`
  - `notify`가 Notification insert + unread 증가 + (ADMIN_FCM_ENABLED=false) 푸시 스킵 검증
- `normalize.ts`
  - Python `normalize_name`과 동일 결과 (한글/일본어/영문 fixtures)

**auth 가드** — route handler가 미인증 요청에 401, 잘못된 도메인에 403 스모크 1-2개

**UI 수동 확인** — 로컬 전용이며 운영 툴 규모상 e2e는 생략. 구현 후 실제 브라우저에서 각 액션 1회씩 검증.

## 구현 순서 (참고용 큰 덩어리)

1. `apps/admin` scaffold + NextAuth + 로그인 가드
2. `lib/mongo.ts` + `db-types.ts` + 기본 GET 엔드포인트 2종 + 사이드바/큐 리스트 페이지
3. `lib/notifications.ts` + `lib/push.ts` + `notification-templates.ts` + FastAPI 템플릿 동기화
4. `place-ops.ts` (PASS/FAIL 먼저, 그 다음 MERGE) + 각 API + UI 액션
5. `suggestion-ops.ts` + API + diff UI
6. 단위 테스트
7. `Place.rejected_reason` 필드 추가 (FastAPI)
