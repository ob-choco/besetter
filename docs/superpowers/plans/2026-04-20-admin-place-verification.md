# 운영자 어드민 — 장소 검수 툴 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `apps/admin` — a local-only Next.js admin app that lets operators review pending gyms (PASS/FAIL/MERGE) and place suggestions (APPROVE/REJECT), gated by Google Workspace OAuth (`olivebagel.com` + email allowlist) and writing directly to MongoDB.

**Architecture:** Next.js 15 App Router + TypeScript. NextAuth.js handles Google OAuth with `hd=olivebagel.com`; `requireAdmin` gate on every API route checks allowlist. MongoDB is accessed via the official `mongodb` Node driver (camelCase fields — matches Beanie's `to_camel` aliasing). FCM push is sent via Firebase Admin SDK, gated by `ADMIN_FCM_ENABLED` env so dev work against prod Mongo doesn't accidentally spam users. MERGE uses a MongoDB transaction to atomically re-parent images + activities + the source place. Notification templates are duplicated across FastAPI (for mobile list rendering) and admin (for push rendering) in v1.

**Tech Stack:** Next.js 15 (App Router, TS) · NextAuth.js v4 · `mongodb` 6.x Node driver · `firebase-admin` 12.x · `zod` · Vitest + `mongodb-memory-server` · pnpm. FastAPI 쪽은 기존 Beanie + pytest + mongomock-motor 패턴 그대로.

**Spec:** `docs/superpowers/specs/2026-04-20-admin-place-verification-design.md`

---

## Context for the Implementing Engineer

### Repo layout
- `apps/mobile/` — Flutter 앱 (기존)
- `services/api/` — FastAPI + Beanie (MongoDB) + FCM push
- `apps/admin/` — **이번에 신설할 Next.js 앱**

### MongoDB field naming — ALWAYS camelCase on disk
Beanie `model_config` 가 `alias_generator=to_camel` + `id→_id` 라서 실제 MongoDB 문서 키는 camelCase다. Next.js에서 드라이버로 직접 접근하므로 필드명은 Python 모델의 snake_case 가 아니라 **camelCase 를 써야 한다**.

대표 예시:
- `Place.created_by` → MongoDB: `createdBy`
- `Place.normalized_name` → `normalizedName`
- `Place.merged_into_place_id` → `mergedIntoPlaceId`
- `Image.place_id` → `placeId`, `Image.is_deleted` → `isDeleted`
- `Activity.route_snapshot.place_id` → `routeSnapshot.placeId`
- `User.unread_notification_count` → `unreadNotificationCount`
- `Notification.user_id` → `userId`

`_id` 는 ObjectId 타입이다. TS에서는 `import { ObjectId } from "mongodb"`.

### Existing notification infrastructure (FastAPI)
- `services/api/app/services/push_sender.py` — `send_to_user(user_id, notif)` — FCM HTTP v1, per-device locale 렌더링, 만료 토큰 삭제. 참고용.
- `services/api/app/services/notification_templates.py` — `TEMPLATES[type][title|body][locale]` 구조. 새 타입을 추가할 때 이 파일에 4개 로케일(ko/en/ja/es) 전부 채운다.
- `services/api/app/services/notification_renderer.py` — `render(notif, locale)` — 조회 시점에 템플릿을 `params` 로 format.
- Notification insert 규약:
  - `title`, `body` 는 빈 문자열로 저장 (렌더링은 조회 시점에 함)
  - `params` 에 플레이스홀더 값 채움
  - `link` 는 앱 내 경로 (예: `/places/<id>`)
  - 저장 후 `users.updateOne({_id: userId}, { $inc: { unreadNotificationCount: 1 }})`
  - 그다음 `push_sender.send_to_user(userId, notif)` (FastAPI) 또는 Firebase Admin fanout (admin)

### Place.status 의미
- `pending` — gym 신규 등록, 검수 대기 (검색 노출 X, 등록자 본인에게만 `nearby`/`instant-search`에 노출)
- `approved` — 공개. 모든 read endpoint 가 이 상태만 노출
- `rejected` — 반려. 검색·매핑에서 자동 제외 (기존 필터 덕)
- `merged` — 다른 place로 병합됨. `mergedIntoPlaceId` 세팅

### 테스트 스타일
- **FastAPI**: mongomock-motor + Beanie `init_beanie`. FastAPI TestClient 를 쓰지 않고 엔드포인트 함수를 직접 호출 (conftest가 `app.dependencies`를 mock).
- **Next.js (admin)**: Vitest + `mongodb-memory-server`(실제 replica set 모드, transaction 필요). 각 테스트마다 fresh client + fresh DB. 비즈니스 로직은 `src/lib/*-ops.ts` 로 뽑아서 route handler 밖에서 테스트.

### Commit conventions
- FastAPI 변경: `feat(api): ...`, `fix(api): ...`, `test(api): ...`
- admin 앱 변경: `feat(admin): ...`, `fix(admin): ...`, `test(admin): ...`
- 각 태스크 끝의 커밋은 해당 태스크의 파일만 포함한다 (기존 워킹트리의 무관한 변경은 건드리지 않는다). `git add <file>` 로 명시적으로 추가.

---

## File Structure

### 신규 (apps/admin)
| 파일 | 책임 |
|---|---|
| `apps/admin/package.json` | Next.js 15 + 의존성 |
| `apps/admin/tsconfig.json` | TS 설정 |
| `apps/admin/next.config.js` | Next.js 설정 (standalone 비활성, serverActions 기본값) |
| `apps/admin/vitest.config.ts` | Vitest + `mongodb-memory-server` replica set |
| `apps/admin/.env.local.example` | 환경변수 템플릿 |
| `apps/admin/.gitignore` | `node_modules`, `.next`, `.env.local` |
| `apps/admin/src/app/layout.tsx` | 공통 레이아웃 + 사이드바 + 로그인 게이트 |
| `apps/admin/src/app/page.tsx` | → `/places` 리디렉트 |
| `apps/admin/src/app/providers.tsx` | NextAuth SessionProvider 래퍼 |
| `apps/admin/src/app/places/page.tsx` | 신규 gym 큐 + 상세 + merge 다이얼로그 |
| `apps/admin/src/app/suggestions/page.tsx` | 수정 제안 큐 + diff 뷰 |
| `apps/admin/src/app/api/auth/[...nextauth]/route.ts` | NextAuth route handler |
| `apps/admin/src/app/api/places/pending/route.ts` | GET |
| `apps/admin/src/app/api/places/[id]/route.ts` | GET |
| `apps/admin/src/app/api/places/[id]/pass/route.ts` | POST |
| `apps/admin/src/app/api/places/[id]/fail/route.ts` | POST |
| `apps/admin/src/app/api/places/[id]/merge/route.ts` | POST |
| `apps/admin/src/app/api/places/merge-candidates/route.ts` | GET |
| `apps/admin/src/app/api/suggestions/pending/route.ts` | GET |
| `apps/admin/src/app/api/suggestions/[id]/route.ts` | GET |
| `apps/admin/src/app/api/suggestions/[id]/approve/route.ts` | POST |
| `apps/admin/src/app/api/suggestions/[id]/reject/route.ts` | POST |
| `apps/admin/src/lib/auth.ts` | NextAuth config (provider + callbacks + session) |
| `apps/admin/src/lib/authz.ts` | `requireAdmin(session)` 공통 가드 |
| `apps/admin/src/lib/mongo.ts` | MongoClient singleton |
| `apps/admin/src/lib/db-types.ts` | MongoDB 문서 TS 타입 (camelCase) |
| `apps/admin/src/lib/normalize.ts` | `normalizeName` (Python 포팅) |
| `apps/admin/src/lib/notification-templates.ts` | 5종 템플릿 (ko/en/ja/es) |
| `apps/admin/src/lib/push.ts` | Firebase Admin 초기화 + `sendPush` |
| `apps/admin/src/lib/notifications.ts` | `notify` 헬퍼 (insert + unread + push) |
| `apps/admin/src/lib/place-ops.ts` | `passPlace` / `failPlace` / `mergePlace` |
| `apps/admin/src/lib/suggestion-ops.ts` | `approveSuggestion` / `rejectSuggestion` |
| `apps/admin/src/lib/zod-schemas.ts` | 입력 검증 스키마 |
| `apps/admin/src/components/sidebar.tsx` | 좌측 네비 |
| `apps/admin/src/components/queue-list.tsx` | 가운데 큐 리스트 (신규 gym/제안 공용 + 타입 prop) |
| `apps/admin/src/components/place-detail.tsx` | 신규 gym 상세 패널 |
| `apps/admin/src/components/merge-dialog.tsx` | MERGE 타깃 선택 다이얼로그 |
| `apps/admin/src/components/suggestion-diff.tsx` | 수정 제안 diff 뷰 |
| `apps/admin/tests/setup.ts` | Vitest 셋업 (MongoMemoryReplSet 전역) |
| `apps/admin/tests/lib/normalize.test.ts` | `normalizeName` 파리티 테스트 |
| `apps/admin/tests/lib/notifications.test.ts` | `notify` 동작 테스트 |
| `apps/admin/tests/lib/place-ops.test.ts` | PASS/FAIL/MERGE 비즈니스 로직 |
| `apps/admin/tests/lib/suggestion-ops.test.ts` | APPROVE/REJECT 비즈니스 로직 |

### 수정 (FastAPI)
| 파일 | 변경 |
|---|---|
| `services/api/app/models/place.py` | `Place.rejected_reason: Optional[str]` 필드 추가 |
| `services/api/app/services/notification_templates.py` | 5개 신규 타입의 ko/en/ja/es 템플릿 추가 |
| `services/api/tests/services/test_notification_templates.py` (기존 있으면 확장, 없으면 신설) | 신규 템플릿 존재 검증 |

---

## Environment setup notes (operator-facing — does not block work)

로컬에서 MERGE transaction 을 실행하려면 MongoDB replica set 이 필요하다. `.env.local.example` 하단에 메모로 남긴다:
```
# To exercise MERGE transactions locally, Mongo must run as a replica set.
# Example: docker run --rm -p 27017:27017 mongo:7 --replSet rs0
# then inside mongosh: rs.initiate()
```

---

## Phase 0 — Scaffold

### Task 1: Create apps/admin package manifest and tsconfig

**Files:**
- Create: `apps/admin/package.json`
- Create: `apps/admin/tsconfig.json`
- Create: `apps/admin/next.config.js`
- Create: `apps/admin/.gitignore`
- Create: `apps/admin/.env.local.example`

- [ ] **Step 1: Create `apps/admin/package.json`**

```json
{
  "name": "besetter-admin",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "firebase-admin": "^12.5.0",
    "mongodb": "^6.10.0",
    "next": "^15.1.0",
    "next-auth": "^4.24.11",
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@types/node": "^20.19.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "eslint": "^9.16.0",
    "eslint-config-next": "^15.1.0",
    "mongodb-memory-server": "^10.1.4",
    "typescript": "^5.7.2",
    "vitest": "^2.1.8"
  }
}
```

- [ ] **Step 2: Create `apps/admin/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": false,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
```

- [ ] **Step 3: Create `apps/admin/next.config.js`**

```js
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  experimental: {
    serverActions: { allowedOrigins: ["localhost:3000"] }
  }
};
module.exports = nextConfig;
```

- [ ] **Step 4: Create `apps/admin/.gitignore`**

```
node_modules
.next
next-env.d.ts
.env.local
.env*.local
coverage
```

- [ ] **Step 5: Create `apps/admin/.env.local.example`**

```
# MongoDB — same cluster as services/api, direct driver access.
MONGODB_URI=mongodb://localhost:27017/besetter
MONGODB_DB=besetter

# Admin access allowlist. Comma-separated emails under @olivebagel.com.
ADMIN_EMAIL_ALLOWLIST=htnnsc@olivebagel.com

# Google OAuth (Workspace app). Restricted via hd=olivebagel.com.
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
NEXTAUTH_SECRET=
NEXTAUTH_URL=http://localhost:3000

# Firebase Admin (FCM push). JSON string of service-account key.
FIREBASE_PROJECT_ID=
FIREBASE_SERVICE_ACCOUNT_JSON=

# Set to "true" to actually dispatch FCM push. Default false so dev work
# against prod Mongo does not spam users.
ADMIN_FCM_ENABLED=false

# To exercise MERGE transactions locally, Mongo must run as a replica set.
# Example: docker run --rm -p 27017:27017 mongo:7 --replSet rs0
# then inside mongosh: rs.initiate()
```

- [ ] **Step 6: Commit**

```bash
git add apps/admin/package.json apps/admin/tsconfig.json apps/admin/next.config.js apps/admin/.gitignore apps/admin/.env.local.example
git commit -m "$(cat <<'EOF'
feat(admin): scaffold apps/admin package manifest and config

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Install dependencies and verify Next.js dev server starts

**Files:**
- (No file edits; produces `pnpm-lock.yaml` / `package-lock.json` in the app dir.)

- [ ] **Step 1: Install**

```bash
cd apps/admin && pnpm install
```

If pnpm unavailable, `npm install` is acceptable but commit the resulting lockfile (`package-lock.json`) instead.

- [ ] **Step 2: Create a smoke `src/app/layout.tsx` + `src/app/page.tsx` stub so dev server has something to serve**

`apps/admin/src/app/layout.tsx`:
```tsx
export const metadata = { title: "besetter admin" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <body style={{ margin: 0, fontFamily: "system-ui, sans-serif", background: "#0f1117", color: "#dde1ea" }}>
        {children}
      </body>
    </html>
  );
}
```

`apps/admin/src/app/page.tsx`:
```tsx
export default function Page() {
  return <main style={{ padding: 24 }}>besetter admin — coming up</main>;
}
```

- [ ] **Step 3: Start dev server**

```bash
cd apps/admin && pnpm dev
```

Expected: server boots on `http://localhost:3000` and `curl localhost:3000` returns HTML containing "besetter admin — coming up". Stop with Ctrl-C.

- [ ] **Step 4: Commit**

```bash
git add apps/admin/src/app/layout.tsx apps/admin/src/app/page.tsx apps/admin/pnpm-lock.yaml
git commit -m "$(cat <<'EOF'
feat(admin): add root layout + landing stub and install deps

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 1 — Mongo access layer, TS types, normalize utility

### Task 3: MongoClient singleton

**Files:**
- Create: `apps/admin/src/lib/mongo.ts`

- [ ] **Step 1: Create `apps/admin/src/lib/mongo.ts`**

```ts
import { MongoClient, type Db } from "mongodb";

let clientPromise: Promise<MongoClient> | null = null;

export function getMongoClient(): Promise<MongoClient> {
  if (clientPromise) return clientPromise;
  const uri = process.env.MONGODB_URI;
  if (!uri) throw new Error("MONGODB_URI is not set");
  clientPromise = new MongoClient(uri).connect();
  return clientPromise;
}

export async function getDb(): Promise<Db> {
  const client = await getMongoClient();
  const dbName = process.env.MONGODB_DB;
  if (!dbName) throw new Error("MONGODB_DB is not set");
  return client.db(dbName);
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/admin/src/lib/mongo.ts
git commit -m "$(cat <<'EOF'
feat(admin): add MongoClient singleton

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: MongoDB document TS types (camelCase)

**Files:**
- Create: `apps/admin/src/lib/db-types.ts`

- [ ] **Step 1: Create `apps/admin/src/lib/db-types.ts`**

```ts
import type { ObjectId } from "mongodb";

export type GeoJsonPoint = {
  type: "Point";
  /** [longitude, latitude] */
  coordinates: [number, number];
};

export type PlaceStatus = "pending" | "approved" | "rejected" | "merged";

export type PlaceDoc = {
  _id: ObjectId;
  name: string;
  normalizedName: string;
  type: "gym" | "private-gym";
  status: PlaceStatus;
  location?: GeoJsonPoint | null;
  coverImageUrl?: string | null;
  createdBy: ObjectId;
  createdAt: Date;
  mergedIntoPlaceId?: ObjectId | null;
  rejectedReason?: string | null;
};

export type PlaceSuggestionStatus = "pending" | "approved" | "rejected";

export type PlaceSuggestionChanges = {
  name?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  coverImageUrl?: string | null;
};

export type PlaceSuggestionDoc = {
  _id: ObjectId;
  placeId: ObjectId;
  requestedBy: ObjectId;
  status: PlaceSuggestionStatus;
  changes: PlaceSuggestionChanges;
  createdAt: Date;
  readAt?: Date | null;
  reviewedAt?: Date | null;
};

export type ImageDoc = {
  _id: ObjectId;
  url: string;
  filename: string;
  userId: ObjectId;
  placeId?: ObjectId | null;
  isDeleted?: boolean;
  uploadedAt: Date;
};

export type ActivityDoc = {
  _id: ObjectId;
  routeId: ObjectId;
  userId: ObjectId;
  routeSnapshot: {
    title?: string | null;
    gradeType: string;
    grade: string;
    gradeColor?: string | null;
    placeId?: ObjectId | null;
    placeName?: string | null;
    imageUrl?: string | null;
    overlayImageUrl?: string | null;
  };
};

export type UserDoc = {
  _id: ObjectId;
  profileId: string;
  name?: string | null;
  email?: string | null;
  profileImageUrl?: string | null;
  unreadNotificationCount: number;
};

export type NotificationType =
  | "place_registration_ack"
  | "place_suggestion_ack"
  | "place_review_passed"
  | "place_review_failed"
  | "place_merged"
  | "place_suggestion_approved"
  | "place_suggestion_rejected";

export type NotificationDoc = {
  _id?: ObjectId;
  userId: ObjectId;
  type: NotificationType;
  title: string;
  body: string;
  params: Record<string, string>;
  link?: string | null;
  createdAt: Date;
  readAt?: Date | null;
};

export type DeviceTokenDoc = {
  _id: ObjectId;
  userId: ObjectId;
  token: string;
  locale?: string | null;
};
```

- [ ] **Step 2: Commit**

```bash
git add apps/admin/src/lib/db-types.ts
git commit -m "$(cat <<'EOF'
feat(admin): add TypeScript types mirroring MongoDB collections (camelCase)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Vitest + mongodb-memory-server setup (replica set)

**Files:**
- Create: `apps/admin/vitest.config.ts`
- Create: `apps/admin/tests/setup.ts`

- [ ] **Step 1: Create `apps/admin/vitest.config.ts`**

```ts
import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    setupFiles: ["./tests/setup.ts"],
    testTimeout: 30_000,
  },
  resolve: {
    alias: { "@": path.resolve(__dirname, "src") },
  },
});
```

- [ ] **Step 2: Create `apps/admin/tests/setup.ts`**

```ts
import { MongoMemoryReplSet } from "mongodb-memory-server";
import { afterAll, beforeAll } from "vitest";

let replSet: MongoMemoryReplSet | null = null;

beforeAll(async () => {
  replSet = await MongoMemoryReplSet.create({
    replSet: { count: 1 },
  });
  process.env.MONGODB_URI = replSet.getUri();
  process.env.MONGODB_DB = "besetter_test";
});

afterAll(async () => {
  await replSet?.stop();
});
```

- [ ] **Step 3: Sanity test — `apps/admin/tests/setup.smoke.test.ts`**

```ts
import { MongoClient } from "mongodb";
import { expect, test } from "vitest";

test("memory replset is reachable and supports transactions", async () => {
  const client = new MongoClient(process.env.MONGODB_URI!);
  await client.connect();
  const session = client.startSession();
  try {
    await session.withTransaction(async () => {
      await client.db("besetter_test").collection("smoke").insertOne({ ok: 1 }, { session });
    });
    const doc = await client.db("besetter_test").collection("smoke").findOne({ ok: 1 });
    expect(doc).not.toBeNull();
  } finally {
    await session.endSession();
    await client.close();
  }
});
```

- [ ] **Step 4: Run it**

```bash
cd apps/admin && pnpm test
```

Expected: 1 passed. If this fails with "Transactions are not supported", the mongodb-memory-server is not running as a replica set — double check step 2.

- [ ] **Step 5: Commit**

```bash
git add apps/admin/vitest.config.ts apps/admin/tests/setup.ts apps/admin/tests/setup.smoke.test.ts
git commit -m "$(cat <<'EOF'
test(admin): add vitest + mongodb-memory-server replica set harness

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `normalizeName` utility + parity test

**Files:**
- Create: `apps/admin/src/lib/normalize.ts`
- Create: `apps/admin/tests/lib/normalize.test.ts`

- [ ] **Step 1: Create failing test `apps/admin/tests/lib/normalize.test.ts`**

Python reference (`services/api/app/models/place.py:19-26`):
```py
normalized = re.sub(r"[^\w]", "", name, flags=re.UNICODE)
normalized = normalized.replace("_", "")
return normalized.lower()
```
Equivalent JS must strip everything except Unicode letters and digits (and strip underscore explicitly since `\p{L}\p{N}` already excludes it).

```ts
import { describe, expect, test } from "vitest";
import { normalizeName } from "@/lib/normalize";

describe("normalizeName", () => {
  test("strips spaces and symbols, lowercases latin", () => {
    expect(normalizeName("The Climbing Park!")).toBe("theclimbingpark");
  });
  test("preserves Korean characters", () => {
    expect(normalizeName("강남 클라이밍 파크")).toBe("강남클라이밍파크");
  });
  test("preserves Japanese characters", () => {
    expect(normalizeName("クライミング ジム")).toBe("クライミングジム");
  });
  test("strips underscores", () => {
    expect(normalizeName("Gym_One_Two")).toBe("gymonetwo");
  });
  test("preserves digits", () => {
    expect(normalizeName("Gym 42")).toBe("gym42");
  });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd apps/admin && pnpm test normalize
```
Expected: FAIL — module `@/lib/normalize` does not exist.

- [ ] **Step 3: Implement `apps/admin/src/lib/normalize.ts`**

```ts
export function normalizeName(name: string): string {
  return name.replace(/[^\p{L}\p{N}]/gu, "").toLowerCase();
}
```

- [ ] **Step 4: Run to verify**

```bash
cd apps/admin && pnpm test normalize
```
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add apps/admin/src/lib/normalize.ts apps/admin/tests/lib/normalize.test.ts
git commit -m "$(cat <<'EOF'
feat(admin): add normalizeName utility mirroring services/api

Matches Python normalize_name: strips non-letter/digit characters
(Unicode-aware) and lowercases.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — Auth: NextAuth Google + allowlist guard

### Task 7: NextAuth config

**Files:**
- Create: `apps/admin/src/lib/auth.ts`
- Create: `apps/admin/src/app/api/auth/[...nextauth]/route.ts`
- Create: `apps/admin/src/app/providers.tsx`
- Modify: `apps/admin/src/app/layout.tsx`

- [ ] **Step 1: Create `apps/admin/src/lib/auth.ts`**

```ts
import type { NextAuthOptions } from "next-auth";
import GoogleProvider from "next-auth/providers/google";

function allowlist(): string[] {
  return (process.env.ADMIN_EMAIL_ALLOWLIST ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
}

export const authOptions: NextAuthOptions = {
  providers: [
    GoogleProvider({
      clientId: process.env.GOOGLE_CLIENT_ID ?? "",
      clientSecret: process.env.GOOGLE_CLIENT_SECRET ?? "",
      authorization: {
        params: { hd: "olivebagel.com", prompt: "select_account" },
      },
    }),
  ],
  session: { strategy: "jwt" },
  secret: process.env.NEXTAUTH_SECRET,
  callbacks: {
    async signIn({ profile }) {
      // Google profile has `hd` when account is Workspace-managed.
      const hd = (profile as { hd?: string } | undefined)?.hd;
      if (hd !== "olivebagel.com") return false;
      const email = profile?.email?.toLowerCase();
      if (!email || !allowlist().includes(email)) return false;
      return true;
    },
    async session({ session, token }) {
      if (token?.email && session.user) {
        session.user.email = token.email;
      }
      return session;
    },
  },
};
```

- [ ] **Step 2: Create `apps/admin/src/app/api/auth/[...nextauth]/route.ts`**

```ts
import NextAuth from "next-auth";
import { authOptions } from "@/lib/auth";

const handler = NextAuth(authOptions);
export { handler as GET, handler as POST };
```

- [ ] **Step 3: Create `apps/admin/src/app/providers.tsx`** (client component for SessionProvider)

```tsx
"use client";
import { SessionProvider } from "next-auth/react";
import type { ReactNode } from "react";

export function Providers({ children }: { children: ReactNode }) {
  return <SessionProvider>{children}</SessionProvider>;
}
```

- [ ] **Step 4: Update `apps/admin/src/app/layout.tsx`** to wrap children in `Providers`

```tsx
import { Providers } from "./providers";

export const metadata = { title: "besetter admin" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <body style={{ margin: 0, fontFamily: "system-ui, sans-serif", background: "#0f1117", color: "#dde1ea" }}>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
```

- [ ] **Step 5: Commit**

```bash
git add apps/admin/src/lib/auth.ts apps/admin/src/app/api/auth apps/admin/src/app/providers.tsx apps/admin/src/app/layout.tsx
git commit -m "$(cat <<'EOF'
feat(admin): add NextAuth with Google + hd=olivebagel.com + email allowlist

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: `requireAdmin` server-side guard

**Files:**
- Create: `apps/admin/src/lib/authz.ts`

- [ ] **Step 1: Create `apps/admin/src/lib/authz.ts`**

```ts
import { getServerSession } from "next-auth/next";
import { NextResponse } from "next/server";
import { authOptions } from "@/lib/auth";

export type AdminSession = { email: string };

export async function requireAdmin(): Promise<
  { ok: true; admin: AdminSession } | { ok: false; response: NextResponse }
> {
  const session = await getServerSession(authOptions);
  const email = session?.user?.email?.toLowerCase();
  if (!email) {
    return { ok: false, response: NextResponse.json({ error: "unauthorized" }, { status: 401 }) };
  }
  const allowlist = (process.env.ADMIN_EMAIL_ALLOWLIST ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  if (!allowlist.includes(email)) {
    return { ok: false, response: NextResponse.json({ error: "forbidden" }, { status: 403 }) };
  }
  return { ok: true, admin: { email } };
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/admin/src/lib/authz.ts
git commit -m "$(cat <<'EOF'
feat(admin): add requireAdmin server-side guard for API routes

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Server-side layout gate — redirect unauthenticated to signin

**Files:**
- Modify: `apps/admin/src/app/layout.tsx`
- Create: `apps/admin/src/app/signin/page.tsx`

- [ ] **Step 1: Create `apps/admin/src/app/signin/page.tsx`** (client component with signIn button)

```tsx
"use client";
import { signIn } from "next-auth/react";

export default function SigninPage() {
  return (
    <main style={{ display: "flex", alignItems: "center", justifyContent: "center", minHeight: "100vh" }}>
      <button
        onClick={() => signIn("google", { callbackUrl: "/" })}
        style={{
          padding: "12px 22px",
          background: "#6495ff",
          color: "#fff",
          border: 0,
          borderRadius: 6,
          fontWeight: 600,
          cursor: "pointer",
        }}
      >
        Google 계정으로 로그인 (@olivebagel.com)
      </button>
    </main>
  );
}
```

- [ ] **Step 2: Replace `apps/admin/src/app/layout.tsx` with a server-component shell that redirects unauthenticated users**

```tsx
import { getServerSession } from "next-auth/next";
import { redirect } from "next/navigation";
import { authOptions } from "@/lib/auth";
import { Providers } from "./providers";
import { Sidebar } from "@/components/sidebar";

export const metadata = { title: "besetter admin" };

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const session = await getServerSession(authOptions);
  // /signin itself must render without the shell; use a header-only check via children wrapping.
  // We inline the gating instead of a middleware to keep things simple for v1.
  return (
    <html lang="ko">
      <body style={{ margin: 0, fontFamily: "system-ui, sans-serif", background: "#0f1117", color: "#dde1ea" }}>
        <Providers>
          {session?.user?.email ? (
            <div style={{ display: "flex", minHeight: "100vh" }}>
              <Sidebar email={session.user.email} />
              <div style={{ flex: 1 }}>{children}</div>
            </div>
          ) : (
            children
          )}
        </Providers>
      </body>
    </html>
  );
}
```

NOTE: The sidebar renders only when signed in. Unsigned users see pages directly — `signin/page.tsx` shows the login button, and `page.tsx` redirects unsigned visitors.

- [ ] **Step 3: Update `apps/admin/src/app/page.tsx`** to redirect unauthenticated to `/signin`, authenticated to `/places`

```tsx
import { getServerSession } from "next-auth/next";
import { redirect } from "next/navigation";
import { authOptions } from "@/lib/auth";

export default async function IndexPage() {
  const session = await getServerSession(authOptions);
  if (!session?.user?.email) redirect("/signin");
  redirect("/places");
}
```

- [ ] **Step 4: Create a minimal placeholder `apps/admin/src/components/sidebar.tsx`** so the layout compiles (full version in Task 14).

```tsx
"use client";

export function Sidebar({ email }: { email: string }) {
  return (
    <aside
      style={{
        width: 210,
        background: "#151821",
        borderRight: "1px solid #262b38",
        padding: "16px 0",
        color: "#c5c9d4",
        minHeight: "100vh",
      }}
    >
      <div style={{ padding: "0 16px 14px", borderBottom: "1px solid #262b38", marginBottom: 10 }}>
        <div style={{ fontWeight: 600, color: "#fff" }}>besetter admin</div>
        <div style={{ fontSize: 11, color: "#8b93a7", marginTop: 3 }}>{email}</div>
      </div>
      <div style={{ padding: "8px 16px", color: "#6b7388", fontSize: 12 }}>(tools ↓)</div>
    </aside>
  );
}
```

- [ ] **Step 5: Commit**

```bash
git add apps/admin/src/app/layout.tsx apps/admin/src/app/page.tsx apps/admin/src/app/signin apps/admin/src/components/sidebar.tsx
git commit -m "$(cat <<'EOF'
feat(admin): gate app shell behind NextAuth session + minimal signin page

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — FastAPI Place.rejected_reason + Notification templates

### Task 10: Add `rejected_reason` to `Place` Beanie model

**Files:**
- Modify: `services/api/app/models/place.py` (around line 47 — after `merged_into_place_id`)

- [ ] **Step 1: Edit `services/api/app/models/place.py`** — add below `merged_into_place_id`:

```python
    rejected_reason: Optional[str] = Field(
        default=None,
        description="FAIL 시 운영자가 남긴 반려 사유 (선택).",
    )
```

- [ ] **Step 2: Verify test suite still passes** (no new tests required — field is optional and backward-compatible)

```bash
cd services/api && uv run pytest -q
```
Expected: all green.

- [ ] **Step 3: Commit**

```bash
git add services/api/app/models/place.py
git commit -m "$(cat <<'EOF'
feat(api): add Place.rejected_reason optional field for admin FAIL

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Add 5 notification templates on the FastAPI side

**Files:**
- Modify: `services/api/app/services/notification_templates.py`

- [ ] **Step 1: Append the five new entries** inside `TEMPLATES` dict (same style as existing `place_registration_ack`):

```python
    "place_review_passed": {
        "title": {
            "ko": "암장이 등록되었어요",
            "en": "Your gym has been approved",
            "ja": "クライミングジムが登録されました",
            "es": "Tu gimnasio ha sido aprobado",
        },
        "body": {
            "ko": "{place_name} 등록이 승인되었어요. 지금 바로 확인해보세요!",
            "en": "{place_name} has been approved. Check it out!",
            "ja": "{place_name} の登録が承認されました。今すぐ確認してみてください！",
            "es": "¡{place_name} ha sido aprobado. Échale un vistazo!",
        },
    },
    "place_review_failed": {
        "title": {
            "ko": "암장 등록이 반려되었어요",
            "en": "Your gym registration was rejected",
            "ja": "クライミングジムの登録が却下されました",
            "es": "Se rechazó el registro de tu gimnasio",
        },
        "body": {
            "ko": "{place_name} 등록이 반려되었어요.{reason_suffix}",
            "en": "{place_name} was rejected.{reason_suffix}",
            "ja": "{place_name} の登録は却下されました。{reason_suffix}",
            "es": "El registro de {place_name} fue rechazado.{reason_suffix}",
        },
    },
    "place_merged": {
        "title": {
            "ko": "등록한 암장이 병합되었어요",
            "en": "Your gym was merged into an existing one",
            "ja": "登録したジムが既存のスポットに統合されました",
            "es": "Tu gimnasio fue fusionado con uno existente",
        },
        "body": {
            "ko": "{place_name} 은(는) 기존 {target_name}(으)로 병합되었어요. 올려주신 기록은 그대로 옮겨졌습니다.",
            "en": "{place_name} was merged into {target_name}. Your uploads have been moved over.",
            "ja": "{place_name} は {target_name} に統合されました。アップロードいただいた記録はそのまま移動されました。",
            "es": "{place_name} se fusionó con {target_name}. Tus registros se han movido.",
        },
    },
    "place_suggestion_approved": {
        "title": {
            "ko": "수정 제안이 반영되었어요",
            "en": "Your suggestion was applied",
            "ja": "修正提案が反映されました",
            "es": "Se aplicó tu sugerencia",
        },
        "body": {
            "ko": "{place_name}에 대한 수정 제안이 반영되었습니다. 감사합니다 🙌",
            "en": "Your suggestion for {place_name} has been applied. Thank you 🙌",
            "ja": "{place_name} の修正提案が反映されました。ありがとうございます 🙌",
            "es": "Tu sugerencia para {place_name} se aplicó. ¡Gracias! 🙌",
        },
    },
    "place_suggestion_rejected": {
        "title": {
            "ko": "수정 제안이 반려되었어요",
            "en": "Your suggestion was rejected",
            "ja": "修正提案が却下されました",
            "es": "Se rechazó tu sugerencia",
        },
        "body": {
            "ko": "{place_name}에 대한 수정 제안이 반려되었어요.{reason_suffix}",
            "en": "Your suggestion for {place_name} was rejected.{reason_suffix}",
            "ja": "{place_name} の修正提案は却下されました。{reason_suffix}",
            "es": "Tu sugerencia para {place_name} fue rechazada.{reason_suffix}",
        },
    },
```

NOTE on `reason_suffix`: both admin and API renderers fill this placeholder. Convention: if reason supplied, pass `" 사유: {reason}"` (with leading space) in `params.reason_suffix`; otherwise pass empty string. Prevents conditional template logic.

- [ ] **Step 2: Verify rendering does not break on empty `reason_suffix`**

Add a smoke test `services/api/tests/services/test_notification_templates_admin.py`:

```python
from app.services.notification_templates import TEMPLATES
from app.services.notification_renderer import render
from app.models.notification import Notification
from beanie.odm.fields import PydanticObjectId
from datetime import datetime, timezone


def _make_notif(type_: str, params: dict) -> Notification:
    return Notification(
        user_id=PydanticObjectId(),
        type=type_,
        title="",
        body="",
        params=params,
        link=None,
        created_at=datetime.now(timezone.utc),
    )


def test_place_review_passed_renders_ko():
    notif = _make_notif("place_review_passed", {"place_name": "강남 클라이밍 파크"})
    title, body = render(notif, "ko")
    assert "강남 클라이밍 파크" in body
    assert title == "암장이 등록되었어요"


def test_place_review_failed_with_reason_suffix():
    notif = _make_notif("place_review_failed", {
        "place_name": "강남 클라이밍 파크",
        "reason_suffix": " 사유: 중복 등록",
    })
    _, body = render(notif, "ko")
    assert "반려되었어요" in body
    assert "사유: 중복 등록" in body


def test_place_review_failed_without_reason_suffix():
    notif = _make_notif("place_review_failed", {
        "place_name": "강남 클라이밍 파크",
        "reason_suffix": "",
    })
    _, body = render(notif, "ko")
    assert "반려되었어요" in body
    assert "사유" not in body


def test_place_merged_contains_both_names():
    notif = _make_notif("place_merged", {
        "place_name": "강남클라이밍파크",
        "target_name": "강남 클라이밍 파크",
    })
    _, body = render(notif, "ko")
    assert "강남클라이밍파크" in body
    assert "강남 클라이밍 파크" in body


def test_all_new_types_have_four_locales():
    for t in (
        "place_review_passed",
        "place_review_failed",
        "place_merged",
        "place_suggestion_approved",
        "place_suggestion_rejected",
    ):
        for field in ("title", "body"):
            for loc in ("ko", "en", "ja", "es"):
                assert TEMPLATES[t][field].get(loc), f"missing {t}.{field}.{loc}"
```

- [ ] **Step 3: Run tests**

```bash
cd services/api && uv run pytest tests/services/test_notification_templates_admin.py -q
```
Expected: 5 passed.

- [ ] **Step 4: Commit**

```bash
git add services/api/app/services/notification_templates.py services/api/tests/services/test_notification_templates_admin.py
git commit -m "$(cat <<'EOF'
feat(api): add notification templates for admin verification flows

Adds ko/en/ja/es templates for place_review_passed,
place_review_failed, place_merged, place_suggestion_approved,
and place_suggestion_rejected. Uses a reason_suffix param so the
reject/fail templates render cleanly with or without a reason.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — Admin notification templates + push helper + notify

### Task 12: Mirror templates in admin (`notification-templates.ts`)

**Files:**
- Create: `apps/admin/src/lib/notification-templates.ts`
- Create: `apps/admin/tests/lib/notification-templates.test.ts`

- [ ] **Step 1: Create `apps/admin/src/lib/notification-templates.ts`**

```ts
import type { NotificationType } from "@/lib/db-types";

export type Locale = "ko" | "en" | "ja" | "es";
export const DEFAULT_LOCALE: Locale = "ko";
export const SUPPORTED_LOCALES: Locale[] = ["ko", "en", "ja", "es"];

type TemplateEntry = Record<"title" | "body", Record<Locale, string>>;

/**
 * Mirrors services/api/app/services/notification_templates.py for the five
 * admin-driven types. When either file changes, update both.
 */
export const TEMPLATES: Record<Extract<
  NotificationType,
  "place_review_passed" | "place_review_failed" | "place_merged" | "place_suggestion_approved" | "place_suggestion_rejected"
>, TemplateEntry> = {
  place_review_passed: {
    title: {
      ko: "암장이 등록되었어요",
      en: "Your gym has been approved",
      ja: "クライミングジムが登録されました",
      es: "Tu gimnasio ha sido aprobado",
    },
    body: {
      ko: "{place_name} 등록이 승인되었어요. 지금 바로 확인해보세요!",
      en: "{place_name} has been approved. Check it out!",
      ja: "{place_name} の登録が承認されました。今すぐ確認してみてください！",
      es: "¡{place_name} ha sido aprobado. Échale un vistazo!",
    },
  },
  place_review_failed: {
    title: {
      ko: "암장 등록이 반려되었어요",
      en: "Your gym registration was rejected",
      ja: "クライミングジムの登録が却下されました",
      es: "Se rechazó el registro de tu gimnasio",
    },
    body: {
      ko: "{place_name} 등록이 반려되었어요.{reason_suffix}",
      en: "{place_name} was rejected.{reason_suffix}",
      ja: "{place_name} の登録は却下されました。{reason_suffix}",
      es: "El registro de {place_name} fue rechazado.{reason_suffix}",
    },
  },
  place_merged: {
    title: {
      ko: "등록한 암장이 병합되었어요",
      en: "Your gym was merged into an existing one",
      ja: "登録したジムが既存のスポットに統合されました",
      es: "Tu gimnasio fue fusionado con uno existente",
    },
    body: {
      ko: "{place_name} 은(는) 기존 {target_name}(으)로 병합되었어요. 올려주신 기록은 그대로 옮겨졌습니다.",
      en: "{place_name} was merged into {target_name}. Your uploads have been moved over.",
      ja: "{place_name} は {target_name} に統合されました。アップロードいただいた記録はそのまま移動されました。",
      es: "{place_name} se fusionó con {target_name}. Tus registros se han movido.",
    },
  },
  place_suggestion_approved: {
    title: {
      ko: "수정 제안이 반영되었어요",
      en: "Your suggestion was applied",
      ja: "修正提案が反映されました",
      es: "Se aplicó tu sugerencia",
    },
    body: {
      ko: "{place_name}에 대한 수정 제안이 반영되었습니다. 감사합니다 🙌",
      en: "Your suggestion for {place_name} has been applied. Thank you 🙌",
      ja: "{place_name} の修正提案が反映されました。ありがとうございます 🙌",
      es: "Tu sugerencia para {place_name} se aplicó. ¡Gracias! 🙌",
    },
  },
  place_suggestion_rejected: {
    title: {
      ko: "수정 제안이 반려되었어요",
      en: "Your suggestion was rejected",
      ja: "修正提案が却下されました",
      es: "Se rechazó tu sugerencia",
    },
    body: {
      ko: "{place_name}에 대한 수정 제안이 반려되었어요.{reason_suffix}",
      en: "Your suggestion for {place_name} was rejected.{reason_suffix}",
      ja: "{place_name} の修正提案は却下されました。{reason_suffix}",
      es: "Tu sugerencia para {place_name} fue rechazada.{reason_suffix}",
    },
  },
};

export function primaryLocale(raw: string | null | undefined): Locale {
  if (!raw) return DEFAULT_LOCALE;
  const primary = raw.split("-", 2)[0].split("_", 2)[0].toLowerCase() as Locale;
  return SUPPORTED_LOCALES.includes(primary) ? primary : DEFAULT_LOCALE;
}

export function renderTemplate(
  type: keyof typeof TEMPLATES,
  locale: Locale,
  params: Record<string, string>,
): { title: string; body: string } {
  const entry = TEMPLATES[type];
  const fill = (s: string) => s.replace(/\{(\w+)\}/g, (_m, k) => params[k] ?? "");
  return { title: fill(entry.title[locale]), body: fill(entry.body[locale]) };
}
```

- [ ] **Step 2: Create `apps/admin/tests/lib/notification-templates.test.ts`**

```ts
import { describe, expect, test } from "vitest";
import { primaryLocale, renderTemplate } from "@/lib/notification-templates";

describe("primaryLocale", () => {
  test.each([
    [null, "ko"],
    [undefined, "ko"],
    ["", "ko"],
    ["ko-KR", "ko"],
    ["en-US", "en"],
    ["ja_JP", "ja"],
    ["de-DE", "ko"],
    ["es", "es"],
  ])("%s → %s", (input, expected) => {
    expect(primaryLocale(input as string | null)).toBe(expected);
  });
});

describe("renderTemplate", () => {
  test("place_review_passed ko", () => {
    const { title, body } = renderTemplate("place_review_passed", "ko", { place_name: "X짐" });
    expect(title).toBe("암장이 등록되었어요");
    expect(body).toContain("X짐");
  });
  test("place_review_failed with reason_suffix", () => {
    const { body } = renderTemplate("place_review_failed", "ko", {
      place_name: "X짐",
      reason_suffix: " 사유: 중복 등록",
    });
    expect(body).toContain("사유: 중복 등록");
  });
  test("place_review_failed without reason_suffix", () => {
    const { body } = renderTemplate("place_review_failed", "ko", {
      place_name: "X짐",
      reason_suffix: "",
    });
    expect(body).not.toContain("사유");
  });
  test("place_merged contains both names", () => {
    const { body } = renderTemplate("place_merged", "ko", {
      place_name: "A",
      target_name: "B",
    });
    expect(body).toContain("A");
    expect(body).toContain("B");
  });
});
```

- [ ] **Step 3: Run tests**

```bash
cd apps/admin && pnpm test notification-templates
```
Expected: all passed.

- [ ] **Step 4: Commit**

```bash
git add apps/admin/src/lib/notification-templates.ts apps/admin/tests/lib/notification-templates.test.ts
git commit -m "$(cat <<'EOF'
feat(admin): add notification template mirror + renderer

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: `push.ts` — Firebase Admin init + `sendPush` (dev-gated)

**Files:**
- Create: `apps/admin/src/lib/push.ts`

- [ ] **Step 1: Create `apps/admin/src/lib/push.ts`**

```ts
import { cert, getApps, initializeApp, type ServiceAccount } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import type { ObjectId } from "mongodb";
import { getDb } from "@/lib/mongo";
import type { DeviceTokenDoc, NotificationDoc } from "@/lib/db-types";
import { primaryLocale, renderTemplate, type Locale } from "@/lib/notification-templates";

function fcmEnabled(): boolean {
  return process.env.ADMIN_FCM_ENABLED === "true";
}

function ensureApp() {
  if (getApps().length > 0) return;
  const json = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!json) throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON is not set");
  const parsed = JSON.parse(json) as ServiceAccount;
  initializeApp({
    credential: cert(parsed),
    projectId: process.env.FIREBASE_PROJECT_ID,
  });
}

type AdminNotificationInput = {
  userId: ObjectId;
  type: Extract<
    NotificationDoc["type"],
    "place_review_passed" | "place_review_failed" | "place_merged" | "place_suggestion_approved" | "place_suggestion_rejected"
  >;
  notificationId: ObjectId;
  params: Record<string, string>;
  link?: string | null;
};

export async function sendPush(input: AdminNotificationInput): Promise<void> {
  if (!fcmEnabled()) {
    console.log("[push] ADMIN_FCM_ENABLED=false — skipping fan-out", {
      userId: input.userId.toString(),
      type: input.type,
    });
    return;
  }
  ensureApp();
  const db = await getDb();
  const devices = await db
    .collection<DeviceTokenDoc>("deviceTokens")
    .find({ userId: input.userId })
    .toArray();
  if (devices.length === 0) return;

  const messaging = getMessaging();
  await Promise.all(
    devices.map(async (device) => {
      const loc: Locale = primaryLocale(device.locale);
      const { title, body } = renderTemplate(input.type, loc, input.params);
      const data: Record<string, string> = {
        type: input.type,
        notificationId: input.notificationId.toString(),
      };
      if (input.link) data.link = input.link;
      try {
        await messaging.send({
          token: device.token,
          notification: { title, body },
          data,
        });
      } catch (err) {
        const code = (err as { code?: string }).code ?? "";
        console.warn("[push] send failed", {
          token: device.token.slice(0, 16),
          code,
        });
        // Drop stale tokens mirroring services/api push_sender behavior.
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token" ||
          code === "messaging/mismatched-credential"
        ) {
          await db.collection<DeviceTokenDoc>("deviceTokens").deleteOne({ token: device.token });
        }
      }
    }),
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/admin/src/lib/push.ts
git commit -m "$(cat <<'EOF'
feat(admin): add FCM sendPush helper with ADMIN_FCM_ENABLED gate

Mirrors services/api push_sender: per-device locale rendering, stale
token cleanup on known FCM error codes. Skipped entirely when
ADMIN_FCM_ENABLED != "true" so dev work against prod Mongo does not
spam real users.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: `notifications.ts` — `notify` helper + tests

**Files:**
- Create: `apps/admin/src/lib/notifications.ts`
- Create: `apps/admin/tests/lib/notifications.test.ts`

- [ ] **Step 1: Create failing test `apps/admin/tests/lib/notifications.test.ts`**

```ts
import { MongoClient, ObjectId } from "mongodb";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { notify } from "@/lib/notifications";

vi.mock("@/lib/push", () => ({
  sendPush: vi.fn(async () => {}),
}));

import { sendPush } from "@/lib/push";

let client: MongoClient;
const DB = "besetter_test";

beforeEach(async () => {
  client = new MongoClient(process.env.MONGODB_URI!);
  await client.connect();
  const db = client.db(DB);
  await Promise.all([
    db.collection("notifications").deleteMany({}),
    db.collection("users").deleteMany({}),
    db.collection("deviceTokens").deleteMany({}),
  ]);
  vi.mocked(sendPush).mockClear();
});

afterEach(async () => {
  await client.close();
});

describe("notify", () => {
  test("inserts notification, increments unread count, and calls sendPush", async () => {
    const userId = new ObjectId();
    const db = client.db(DB);
    await db.collection("users").insertOne({
      _id: userId,
      profileId: "u1",
      unreadNotificationCount: 0,
    } as any);

    await notify({
      userId,
      type: "place_review_passed",
      params: { place_name: "X짐" },
      link: `/places/${new ObjectId().toString()}`,
    });

    const notifs = await db.collection("notifications").find({ userId }).toArray();
    expect(notifs).toHaveLength(1);
    expect(notifs[0]!.type).toBe("place_review_passed");
    expect(notifs[0]!.title).toBe("");
    expect(notifs[0]!.body).toBe("");
    expect(notifs[0]!.params.place_name).toBe("X짐");

    const user = await db.collection("users").findOne({ _id: userId });
    expect(user!.unreadNotificationCount).toBe(1);

    expect(sendPush).toHaveBeenCalledTimes(1);
    expect(vi.mocked(sendPush).mock.calls[0]![0]!.type).toBe("place_review_passed");
  });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd apps/admin && pnpm test notifications
```
Expected: FAIL — module `@/lib/notifications` missing.

- [ ] **Step 3: Create `apps/admin/src/lib/notifications.ts`**

```ts
import type { ObjectId } from "mongodb";
import { getDb } from "@/lib/mongo";
import type { NotificationDoc, UserDoc } from "@/lib/db-types";
import { sendPush } from "@/lib/push";

type AdminNotificationType = Extract<
  NotificationDoc["type"],
  "place_review_passed" | "place_review_failed" | "place_merged" | "place_suggestion_approved" | "place_suggestion_rejected"
>;

export async function notify(input: {
  userId: ObjectId;
  type: AdminNotificationType;
  params: Record<string, string>;
  link?: string | null;
}): Promise<void> {
  const db = await getDb();
  const doc: NotificationDoc = {
    userId: input.userId,
    type: input.type,
    title: "",
    body: "",
    params: input.params,
    link: input.link ?? null,
    createdAt: new Date(),
  };
  const res = await db.collection<NotificationDoc>("notifications").insertOne(doc);
  await db.collection<UserDoc>("users").updateOne(
    { _id: input.userId },
    { $inc: { unreadNotificationCount: 1 } },
  );
  // sendPush is best-effort; failures do not block the caller.
  try {
    await sendPush({
      userId: input.userId,
      type: input.type,
      notificationId: res.insertedId,
      params: input.params,
      link: input.link ?? null,
    });
  } catch (err) {
    console.warn("[notify] sendPush failed", err);
  }
}
```

- [ ] **Step 4: Run**

```bash
cd apps/admin && pnpm test notifications
```
Expected: 1 passed.

- [ ] **Step 5: Commit**

```bash
git add apps/admin/src/lib/notifications.ts apps/admin/tests/lib/notifications.test.ts
git commit -m "$(cat <<'EOF'
feat(admin): add notify helper (insert + unread + push)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5 — Places: list, detail, merge candidates

### Task 15: `place-ops.ts` skeleton + `getPendingPlaces`

**Files:**
- Create: `apps/admin/src/lib/place-ops.ts`
- Create: `apps/admin/tests/lib/place-ops.test.ts`

- [ ] **Step 1: Create failing test `apps/admin/tests/lib/place-ops.test.ts`**

```ts
import { MongoClient, ObjectId } from "mongodb";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { getPendingPlaces } from "@/lib/place-ops";

const DB = "besetter_test";
let client: MongoClient;

beforeEach(async () => {
  client = new MongoClient(process.env.MONGODB_URI!);
  await client.connect();
  const db = client.db(DB);
  await Promise.all([
    db.collection("places").deleteMany({}),
    db.collection("users").deleteMany({}),
  ]);
});
afterEach(async () => { await client.close(); });

describe("getPendingPlaces", () => {
  test("returns only type=gym and status=pending, oldest first", async () => {
    const db = client.db(DB);
    const now = Date.now();
    const user = { _id: new ObjectId(), profileId: "climber", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);

    const older = {
      _id: new ObjectId(),
      name: "Older",
      normalizedName: "older",
      type: "gym",
      status: "pending",
      createdBy: user._id,
      createdAt: new Date(now - 60_000),
    };
    const newer = {
      _id: new ObjectId(),
      name: "Newer",
      normalizedName: "newer",
      type: "gym",
      status: "pending",
      createdBy: user._id,
      createdAt: new Date(now),
    };
    const approved = {
      _id: new ObjectId(),
      name: "Approved",
      normalizedName: "approved",
      type: "gym",
      status: "approved",
      createdBy: user._id,
      createdAt: new Date(now - 120_000),
    };
    const privateGym = {
      _id: new ObjectId(),
      name: "MyWall",
      normalizedName: "mywall",
      type: "private-gym",
      status: "pending",
      createdBy: user._id,
      createdAt: new Date(now - 30_000),
    };
    await db.collection("places").insertMany([older, newer, approved, privateGym] as any);

    const result = await getPendingPlaces();
    expect(result.map((r) => r.name)).toEqual(["Older", "Newer"]);
    expect(result[0]!.creator?.profileId).toBe("climber");
  });
});
```

- [ ] **Step 2: Run to verify failure**

```bash
cd apps/admin && pnpm test place-ops
```
Expected: FAIL — missing module.

- [ ] **Step 3: Create `apps/admin/src/lib/place-ops.ts`**

```ts
import type { ObjectId } from "mongodb";
import { getDb } from "@/lib/mongo";
import type { PlaceDoc, UserDoc } from "@/lib/db-types";

export type PendingPlaceView = PlaceDoc & {
  creator?: { profileId: string; profileImageUrl?: string | null } | null;
};

export async function getPendingPlaces(): Promise<PendingPlaceView[]> {
  const db = await getDb();
  const places = await db
    .collection<PlaceDoc>("places")
    .find({ type: "gym", status: "pending" })
    .sort({ createdAt: 1 })
    .toArray();
  if (places.length === 0) return [];
  const userIds = [...new Set(places.map((p) => p.createdBy.toString()))].map(
    (s) => places.find((p) => p.createdBy.toString() === s)!.createdBy,
  );
  const users = await db
    .collection<UserDoc>("users")
    .find({ _id: { $in: userIds } })
    .toArray();
  const byId = new Map<string, UserDoc>(users.map((u) => [u._id.toString(), u]));
  return places.map((p) => {
    const u = byId.get(p.createdBy.toString());
    return {
      ...p,
      creator: u ? { profileId: u.profileId, profileImageUrl: u.profileImageUrl ?? null } : null,
    };
  });
}
```

- [ ] **Step 4: Run**

```bash
cd apps/admin && pnpm test place-ops
```
Expected: 1 passed.

- [ ] **Step 5: Commit**

```bash
git add apps/admin/src/lib/place-ops.ts apps/admin/tests/lib/place-ops.test.ts
git commit -m "$(cat <<'EOF'
feat(admin): add getPendingPlaces (joins creator profile)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: `GET /api/places/pending` route handler

**Files:**
- Create: `apps/admin/src/app/api/places/pending/route.ts`

- [ ] **Step 1: Create route**

```ts
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { getPendingPlaces } from "@/lib/place-ops";

export async function GET() {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  const places = await getPendingPlaces();
  return NextResponse.json({ places });
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/admin/src/app/api/places/pending
git commit -m "$(cat <<'EOF'
feat(admin): expose GET /api/places/pending

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: `getPlaceDetail(id)` + `GET /api/places/:id`

**Files:**
- Modify: `apps/admin/src/lib/place-ops.ts`
- Modify: `apps/admin/tests/lib/place-ops.test.ts`
- Create: `apps/admin/src/app/api/places/[id]/route.ts`

- [ ] **Step 1: Append failing test to `apps/admin/tests/lib/place-ops.test.ts`**

```ts
import { getPlaceDetail } from "@/lib/place-ops";

describe("getPlaceDetail", () => {
  test("returns place + counts + nearby approved", async () => {
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "climber", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const source = {
      _id: new ObjectId(),
      name: "New Gym",
      normalizedName: "newgym",
      type: "gym",
      status: "pending",
      createdBy: user._id,
      createdAt: new Date(),
      location: { type: "Point", coordinates: [127.0276, 37.4981] },
    };
    const nearby = {
      _id: new ObjectId(),
      name: "Existing Gym",
      normalizedName: "existinggym",
      type: "gym",
      status: "approved",
      createdBy: user._id,
      createdAt: new Date(),
      location: { type: "Point", coordinates: [127.0275, 37.4983] },
    };
    await db.collection("places").insertMany([source, nearby] as any);
    await db.collection("places").createIndex({ location: "2dsphere" });

    const imageId = new ObjectId();
    await db.collection("images").insertOne({
      _id: imageId,
      url: "https://example/x.jpg",
      filename: "x.jpg",
      userId: user._id,
      placeId: source._id,
      isDeleted: false,
      uploadedAt: new Date(),
    } as any);
    await db.collection("routes").insertOne({
      _id: new ObjectId(),
      imageId,
      userId: user._id,
    } as any);
    await db.collection("activities").insertOne({
      _id: new ObjectId(),
      routeId: new ObjectId(),
      userId: user._id,
      routeSnapshot: { gradeType: "v", grade: "v3", placeId: source._id, placeName: "New Gym" },
    } as any);

    const detail = await getPlaceDetail(source._id);
    expect(detail).not.toBeNull();
    expect(detail!.place.name).toBe("New Gym");
    expect(detail!.counts).toEqual({ imageCount: 1, routeCount: 1, activityCount: 1 });
    expect(detail!.nearbyApproved).toHaveLength(1);
    expect(detail!.nearbyApproved[0]!.name).toBe("Existing Gym");
    expect(detail!.nearbyApproved[0]!.distanceMeters).toBeGreaterThanOrEqual(0);
  });

  test("returns null for unknown id", async () => {
    const detail = await getPlaceDetail(new ObjectId());
    expect(detail).toBeNull();
  });
});
```

- [ ] **Step 2: Run to fail**

```bash
cd apps/admin && pnpm test place-ops
```
Expected: import error.

- [ ] **Step 3: Extend `apps/admin/src/lib/place-ops.ts`** with helpers + `getPlaceDetail`

Append to file:

```ts
import type { ImageDoc, ActivityDoc } from "@/lib/db-types";

function haversineMeters(a: [number, number], b: [number, number]): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const R = 6371008.8;
  const [lng1, lat1] = a;
  const [lng2, lat2] = b;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const x =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}

export type PlaceDetail = {
  place: PlaceDoc;
  creator: { profileId: string; profileImageUrl?: string | null } | null;
  counts: { imageCount: number; routeCount: number; activityCount: number };
  nearbyApproved: Array<PlaceDoc & { distanceMeters: number }>;
};

const NEARBY_RADIUS_METERS = 200;

export async function getPlaceDetail(id: ObjectId): Promise<PlaceDetail | null> {
  const db = await getDb();
  const place = await db.collection<PlaceDoc>("places").findOne({ _id: id });
  if (!place) return null;

  const user = await db.collection<UserDoc>("users").findOne({ _id: place.createdBy });

  const images = await db
    .collection<ImageDoc>("images")
    .find({ placeId: id }, { projection: { _id: 1 } })
    .toArray();
  const imageIds = images.map((i) => i._id);
  const routeCount = imageIds.length
    ? await db.collection("routes").countDocuments({ imageId: { $in: imageIds } })
    : 0;
  const activityCount = await db
    .collection<ActivityDoc>("activities")
    .countDocuments({ "routeSnapshot.placeId": id });

  let nearbyApproved: Array<PlaceDoc & { distanceMeters: number }> = [];
  if (place.location) {
    const nearby = await db
      .collection<PlaceDoc>("places")
      .find({
        _id: { $ne: id },
        type: "gym",
        status: "approved",
        location: {
          $nearSphere: {
            $geometry: { type: "Point", coordinates: place.location.coordinates },
            $maxDistance: NEARBY_RADIUS_METERS,
          },
        },
      })
      .limit(10)
      .toArray();
    nearbyApproved = nearby.map((n) => ({
      ...n,
      distanceMeters: n.location
        ? Math.round(haversineMeters(place.location!.coordinates, n.location.coordinates))
        : -1,
    }));
  }

  return {
    place,
    creator: user ? { profileId: user.profileId, profileImageUrl: user.profileImageUrl ?? null } : null,
    counts: { imageCount: images.length, routeCount, activityCount },
    nearbyApproved,
  };
}
```

- [ ] **Step 4: Run tests**

```bash
cd apps/admin && pnpm test place-ops
```
Expected: all passed.

- [ ] **Step 5: Create `apps/admin/src/app/api/places/[id]/route.ts`**

```ts
import { ObjectId } from "mongodb";
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { getPlaceDetail } from "@/lib/place-ops";

export async function GET(_req: Request, { params }: { params: { id: string } }) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  if (!ObjectId.isValid(params.id)) {
    return NextResponse.json({ error: "invalid id" }, { status: 422 });
  }
  const detail = await getPlaceDetail(new ObjectId(params.id));
  if (!detail) return NextResponse.json({ error: "not found" }, { status: 404 });
  return NextResponse.json(detail);
}
```

- [ ] **Step 6: Commit**

```bash
git add apps/admin/src/lib/place-ops.ts apps/admin/tests/lib/place-ops.test.ts apps/admin/src/app/api/places/[id]/route.ts
git commit -m "$(cat <<'EOF'
feat(admin): add getPlaceDetail + GET /api/places/:id

Returns place + creator profile + image/route/activity counts + nearby
(200m) approved gyms for merge-candidate hinting in the detail panel.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 18: `getMergeCandidates` + `GET /api/places/merge-candidates`

**Files:**
- Modify: `apps/admin/src/lib/place-ops.ts`
- Modify: `apps/admin/tests/lib/place-ops.test.ts`
- Create: `apps/admin/src/app/api/places/merge-candidates/route.ts`
- Modify: `apps/admin/src/lib/zod-schemas.ts` (create file)

- [ ] **Step 1: Append failing tests to `apps/admin/tests/lib/place-ops.test.ts`**

```ts
import { getMergeCandidates } from "@/lib/place-ops";

describe("getMergeCandidates", () => {
  test("nearby 1km returns approved gyms sorted by distance, excludes pending/merged/rejected/private", async () => {
    const db = client.db(DB);
    await db.collection("places").createIndex({ location: "2dsphere" });
    const mkPlace = (
      name: string,
      coords: [number, number],
      over: Partial<PlaceDoc> = {},
    ): PlaceDoc =>
      ({
        _id: new ObjectId(),
        name,
        normalizedName: name.toLowerCase(),
        type: "gym",
        status: "approved",
        location: { type: "Point", coordinates: coords },
        createdBy: new ObjectId(),
        createdAt: new Date(),
        ...over,
      }) as PlaceDoc;
    const approved = mkPlace("A", [127.0275, 37.4983]);
    const farAway = mkPlace("Far", [128.0, 37.0]);
    const pending = mkPlace("P", [127.028, 37.498], { status: "pending" });
    const privateGym = mkPlace("PG", [127.028, 37.498], { type: "private-gym" });
    await db.collection("places").insertMany([approved, farAway, pending, privateGym] as any);

    const results = await getMergeCandidates({ lat: 37.4981, lng: 127.0276 });
    const names = results.map((r) => r.name);
    expect(names).toContain("A");
    expect(names).not.toContain("Far");
    expect(names).not.toContain("P");
    expect(names).not.toContain("PG");
    expect(results[0]!.distanceMeters).toBeDefined();
  });

  test("name search returns approved gyms by normalizedName regex", async () => {
    const db = client.db(DB);
    await db.collection("places").insertMany([
      {
        _id: new ObjectId(),
        name: "강남 클라이밍 파크",
        normalizedName: "강남클라이밍파크",
        type: "gym",
        status: "approved",
        createdBy: new ObjectId(),
        createdAt: new Date(),
      },
      {
        _id: new ObjectId(),
        name: "Seoul Bouldering",
        normalizedName: "seoulbouldering",
        type: "gym",
        status: "approved",
        createdBy: new ObjectId(),
        createdAt: new Date(),
      },
    ] as any);

    const results = await getMergeCandidates({ lat: 0, lng: 0, q: "클라이밍" });
    expect(results.map((r) => r.name)).toEqual(["강남 클라이밍 파크"]);
  });
});
```

- [ ] **Step 2: Create `apps/admin/src/lib/zod-schemas.ts`**

```ts
import { z } from "zod";

export const ObjectIdString = z.string().regex(/^[a-f0-9]{24}$/i, "invalid object id");

export const MergeCandidatesQuery = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  q: z.string().min(1).max(100).optional(),
});

export const FailBody = z.object({
  reason: z.string().min(1).max(500).optional(),
});

export const RejectBody = z.object({
  reason: z.string().min(1).max(500).optional(),
});

export const MergeBody = z.object({
  targetPlaceId: ObjectIdString,
});
```

- [ ] **Step 3: Append `getMergeCandidates` to `apps/admin/src/lib/place-ops.ts`**

```ts
export async function getMergeCandidates(args: {
  lat: number;
  lng: number;
  q?: string;
}): Promise<Array<PlaceDoc & { distanceMeters?: number; imageCount: number; routeCount: number }>> {
  const db = await getDb();
  let docs: PlaceDoc[];
  if (args.q && args.q.trim()) {
    const escaped = args.q.trim().replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    docs = await db
      .collection<PlaceDoc>("places")
      .find({
        type: "gym",
        status: "approved",
        normalizedName: { $regex: escaped, $options: "i" },
      })
      .limit(20)
      .toArray();
  } else {
    docs = await db
      .collection<PlaceDoc>("places")
      .find({
        type: "gym",
        status: "approved",
        location: {
          $nearSphere: {
            $geometry: { type: "Point", coordinates: [args.lng, args.lat] },
            $maxDistance: 1000,
          },
        },
      })
      .limit(20)
      .toArray();
  }

  const ids = docs.map((d) => d._id);
  const imageAgg = await db
    .collection<ImageDoc>("images")
    .aggregate<{ _id: ObjectId; count: number }>([
      { $match: { placeId: { $in: ids } } },
      { $group: { _id: "$placeId", count: { $sum: 1 } } },
    ])
    .toArray();
  const imageCountByPlace = new Map(imageAgg.map((a) => [a._id.toString(), a.count]));
  const allImageIds = await db
    .collection<ImageDoc>("images")
    .find({ placeId: { $in: ids } }, { projection: { _id: 1, placeId: 1 } })
    .toArray();
  const imageIdToPlace = new Map(allImageIds.map((i) => [i._id.toString(), i.placeId!.toString()]));
  const routeAgg = await db
    .collection("routes")
    .aggregate<{ _id: ObjectId; count: number }>([
      { $match: { imageId: { $in: allImageIds.map((i) => i._id) } } },
      { $group: { _id: "$imageId", count: { $sum: 1 } } },
    ])
    .toArray();
  const routeCountByPlace = new Map<string, number>();
  for (const r of routeAgg) {
    const placeIdStr = imageIdToPlace.get(r._id.toString());
    if (!placeIdStr) continue;
    routeCountByPlace.set(placeIdStr, (routeCountByPlace.get(placeIdStr) ?? 0) + r.count);
  }

  return docs.map((d) => {
    const key = d._id.toString();
    const distanceMeters = d.location
      ? Math.round(haversineMeters([args.lng, args.lat], d.location.coordinates))
      : undefined;
    return {
      ...d,
      distanceMeters,
      imageCount: imageCountByPlace.get(key) ?? 0,
      routeCount: routeCountByPlace.get(key) ?? 0,
    };
  });
}
```

- [ ] **Step 4: Run tests**

```bash
cd apps/admin && pnpm test place-ops
```
Expected: all passed.

- [ ] **Step 5: Create `apps/admin/src/app/api/places/merge-candidates/route.ts`**

```ts
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { getMergeCandidates } from "@/lib/place-ops";
import { MergeCandidatesQuery } from "@/lib/zod-schemas";

export async function GET(req: Request) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  const url = new URL(req.url);
  const parsed = MergeCandidatesQuery.safeParse({
    lat: url.searchParams.get("lat"),
    lng: url.searchParams.get("lng"),
    q: url.searchParams.get("q") ?? undefined,
  });
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid query", details: parsed.error.flatten() }, { status: 422 });
  }
  const candidates = await getMergeCandidates(parsed.data);
  return NextResponse.json({ candidates });
}
```

- [ ] **Step 6: Commit**

```bash
git add apps/admin/src/lib/place-ops.ts apps/admin/src/lib/zod-schemas.ts apps/admin/tests/lib/place-ops.test.ts apps/admin/src/app/api/places/merge-candidates
git commit -m "$(cat <<'EOF'
feat(admin): add getMergeCandidates + GET /api/places/merge-candidates

1km $nearSphere by default, normalizedName regex when q is supplied.
Enriches each candidate with distance, image count, and route count.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 6 — Place mutation actions (PASS / FAIL / MERGE)

### Task 19: `passPlace` + route

**Files:**
- Modify: `apps/admin/src/lib/place-ops.ts`
- Modify: `apps/admin/tests/lib/place-ops.test.ts`
- Create: `apps/admin/src/app/api/places/[id]/pass/route.ts`

- [ ] **Step 1: Append failing tests to `apps/admin/tests/lib/place-ops.test.ts`**

```ts
import { passPlace } from "@/lib/place-ops";
import { vi } from "vitest";

vi.mock("@/lib/notifications", () => ({
  notify: vi.fn(async () => {}),
}));
import { notify } from "@/lib/notifications";

describe("passPlace", () => {
  test("pending → approved, emits place_review_passed", async () => {
    vi.mocked(notify).mockClear();
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "c", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(),
      name: "P",
      normalizedName: "p",
      type: "gym",
      status: "pending",
      createdBy: user._id,
      createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);

    await passPlace(place._id);

    const updated = await db.collection("places").findOne({ _id: place._id });
    expect(updated!.status).toBe("approved");
    expect(notify).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: user._id,
        type: "place_review_passed",
        params: expect.objectContaining({ place_name: "P" }),
      }),
    );
  });

  test("throws ConflictError when place is already approved", async () => {
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "c", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(),
      name: "P",
      normalizedName: "p",
      type: "gym",
      status: "approved",
      createdBy: user._id,
      createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);

    await expect(passPlace(place._id)).rejects.toMatchObject({ code: "CONFLICT" });
  });
});
```

- [ ] **Step 2: Extend `apps/admin/src/lib/place-ops.ts`**

Add at top of file (after existing imports):
```ts
import { notify } from "@/lib/notifications";

export class AdminOpError extends Error {
  constructor(
    public readonly code: "CONFLICT" | "BAD_REQUEST" | "NOT_FOUND",
    message: string,
  ) {
    super(message);
  }
}
```

Append:
```ts
export async function passPlace(id: ObjectId): Promise<void> {
  const db = await getDb();
  const result = await db
    .collection<PlaceDoc>("places")
    .findOneAndUpdate(
      { _id: id, status: "pending", type: "gym" },
      { $set: { status: "approved" } },
      { returnDocument: "before" },
    );
  if (!result) throw new AdminOpError("CONFLICT", "place is not pending");
  await notify({
    userId: result.createdBy,
    type: "place_review_passed",
    params: { place_name: result.name },
    link: `/places/${id.toString()}`,
  });
}
```

- [ ] **Step 3: Run tests**

```bash
cd apps/admin && pnpm test place-ops
```
Expected: all passed.

- [ ] **Step 4: Create `apps/admin/src/app/api/places/[id]/pass/route.ts`**

```ts
import { ObjectId } from "mongodb";
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { passPlace, AdminOpError } from "@/lib/place-ops";

export async function POST(_req: Request, { params }: { params: { id: string } }) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  if (!ObjectId.isValid(params.id)) {
    return NextResponse.json({ error: "invalid id" }, { status: 422 });
  }
  try {
    await passPlace(new ObjectId(params.id));
    console.log("[admin] pass", { actor: auth.admin.email, placeId: params.id });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminOpError && err.code === "CONFLICT") {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    throw err;
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add apps/admin/src/lib/place-ops.ts apps/admin/tests/lib/place-ops.test.ts apps/admin/src/app/api/places/[id]/pass
git commit -m "$(cat <<'EOF'
feat(admin): add passPlace + POST /api/places/:id/pass

Conditional status update (pending→approved) + notify.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 20: `failPlace` + route

**Files:**
- Modify: `apps/admin/src/lib/place-ops.ts`
- Modify: `apps/admin/tests/lib/place-ops.test.ts`
- Create: `apps/admin/src/app/api/places/[id]/fail/route.ts`

- [ ] **Step 1: Append failing tests**

```ts
import { failPlace } from "@/lib/place-ops";

describe("failPlace", () => {
  test("pending → rejected, stores reason when provided, notifies with reason_suffix", async () => {
    vi.mocked(notify).mockClear();
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "c", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(), name: "P", normalizedName: "p",
      type: "gym", status: "pending", createdBy: user._id, createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);

    await failPlace(place._id, "중복 등록");

    const updated = await db.collection("places").findOne({ _id: place._id });
    expect(updated!.status).toBe("rejected");
    expect(updated!.rejectedReason).toBe("중복 등록");
    expect(notify).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: user._id,
        type: "place_review_failed",
        params: { place_name: "P", reason_suffix: " 사유: 중복 등록" },
      }),
    );
  });

  test("omits reason_suffix when no reason provided, does not set rejectedReason", async () => {
    vi.mocked(notify).mockClear();
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "c", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(), name: "Q", normalizedName: "q",
      type: "gym", status: "pending", createdBy: user._id, createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);

    await failPlace(place._id);

    const updated = await db.collection("places").findOne({ _id: place._id });
    expect(updated!.rejectedReason ?? null).toBeNull();
    expect(notify).toHaveBeenCalledWith(
      expect.objectContaining({
        params: { place_name: "Q", reason_suffix: "" },
      }),
    );
  });

  test("conflict when not pending", async () => {
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "c", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(), name: "R", normalizedName: "r",
      type: "gym", status: "approved", createdBy: user._id, createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);
    await expect(failPlace(place._id, "any")).rejects.toMatchObject({ code: "CONFLICT" });
  });
});
```

- [ ] **Step 2: Append `failPlace` to `place-ops.ts`**

```ts
export async function failPlace(id: ObjectId, reason?: string): Promise<void> {
  const db = await getDb();
  const set: Record<string, unknown> = { status: "rejected" };
  if (reason) set.rejectedReason = reason;
  const result = await db
    .collection<PlaceDoc>("places")
    .findOneAndUpdate(
      { _id: id, status: "pending", type: "gym" },
      { $set: set },
      { returnDocument: "before" },
    );
  if (!result) throw new AdminOpError("CONFLICT", "place is not pending");
  await notify({
    userId: result.createdBy,
    type: "place_review_failed",
    params: {
      place_name: result.name,
      reason_suffix: reason ? ` 사유: ${reason}` : "",
    },
    link: `/places/${id.toString()}`,
  });
}
```

- [ ] **Step 3: Run**

```bash
cd apps/admin && pnpm test place-ops
```
Expected: all passed.

- [ ] **Step 4: Create `apps/admin/src/app/api/places/[id]/fail/route.ts`**

```ts
import { ObjectId } from "mongodb";
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { failPlace, AdminOpError } from "@/lib/place-ops";
import { FailBody } from "@/lib/zod-schemas";

export async function POST(req: Request, { params }: { params: { id: string } }) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  if (!ObjectId.isValid(params.id)) {
    return NextResponse.json({ error: "invalid id" }, { status: 422 });
  }
  const body = await req.json().catch(() => ({}));
  const parsed = FailBody.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid body", details: parsed.error.flatten() }, { status: 422 });
  }
  try {
    await failPlace(new ObjectId(params.id), parsed.data.reason);
    console.log("[admin] fail", { actor: auth.admin.email, placeId: params.id, reason: parsed.data.reason ?? null });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminOpError && err.code === "CONFLICT") {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    throw err;
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add apps/admin/src/lib/place-ops.ts apps/admin/tests/lib/place-ops.test.ts apps/admin/src/app/api/places/[id]/fail
git commit -m "$(cat <<'EOF'
feat(admin): add failPlace + POST /api/places/:id/fail

Optional reason persisted to Place.rejectedReason and surfaced in the
notification via reason_suffix.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 21: `mergePlace` with transaction + route

**Files:**
- Modify: `apps/admin/src/lib/place-ops.ts`
- Modify: `apps/admin/tests/lib/place-ops.test.ts`
- Create: `apps/admin/src/app/api/places/[id]/merge/route.ts`

- [ ] **Step 1: Append failing tests**

```ts
import { mergePlace } from "@/lib/place-ops";

describe("mergePlace", () => {
  async function seedMergeScenario() {
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "c", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const source = {
      _id: new ObjectId(), name: "Src", normalizedName: "src",
      type: "gym", status: "pending", createdBy: user._id, createdAt: new Date(),
    };
    const target = {
      _id: new ObjectId(), name: "Tgt", normalizedName: "tgt",
      type: "gym", status: "approved", createdBy: user._id, createdAt: new Date(),
    };
    await db.collection("places").insertMany([source, target] as any);
    const imageId = new ObjectId();
    await db.collection("images").insertOne({
      _id: imageId, url: "u", filename: "f", userId: user._id,
      placeId: source._id, isDeleted: false, uploadedAt: new Date(),
    } as any);
    await db.collection("activities").insertOne({
      _id: new ObjectId(), routeId: new ObjectId(), userId: user._id,
      routeSnapshot: { gradeType: "v", grade: "v3", placeId: source._id, placeName: "Src" },
    } as any);
    return { source, target, user, imageId };
  }

  test("happy path: re-parents images + activity snapshots, marks source merged, notifies", async () => {
    vi.mocked(notify).mockClear();
    const { source, target, user, imageId } = await seedMergeScenario();

    await mergePlace(source._id, target._id);

    const db = client.db(DB);
    const updatedSource = await db.collection("places").findOne({ _id: source._id });
    expect(updatedSource!.status).toBe("merged");
    expect(updatedSource!.mergedIntoPlaceId!.equals(target._id)).toBe(true);

    const img = await db.collection("images").findOne({ _id: imageId });
    expect(img!.placeId!.equals(target._id)).toBe(true);

    const act = await db.collection("activities").findOne({});
    expect(act!.routeSnapshot.placeId.equals(target._id)).toBe(true);
    expect(act!.routeSnapshot.placeName).toBe("Tgt");

    expect(notify).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: user._id,
        type: "place_merged",
        params: { place_name: "Src", target_name: "Tgt" },
      }),
    );
  });

  test("400 when source == target", async () => {
    const { source } = await seedMergeScenario();
    await expect(mergePlace(source._id, source._id)).rejects.toMatchObject({ code: "BAD_REQUEST" });
  });

  test("409 when source not pending", async () => {
    const { target } = await seedMergeScenario();
    const db = client.db(DB);
    const staleSource = {
      _id: new ObjectId(), name: "S2", normalizedName: "s2",
      type: "gym", status: "approved", createdBy: new ObjectId(), createdAt: new Date(),
    };
    await db.collection("places").insertOne(staleSource as any);
    await expect(mergePlace(staleSource._id, target._id)).rejects.toMatchObject({ code: "CONFLICT" });
  });

  test("400 when target not approved gym", async () => {
    const { source } = await seedMergeScenario();
    const db = client.db(DB);
    const badTarget = {
      _id: new ObjectId(), name: "T2", normalizedName: "t2",
      type: "gym", status: "pending", createdBy: new ObjectId(), createdAt: new Date(),
    };
    await db.collection("places").insertOne(badTarget as any);
    await expect(mergePlace(source._id, badTarget._id)).rejects.toMatchObject({ code: "BAD_REQUEST" });
  });

  test("400 when target is private-gym", async () => {
    const { source } = await seedMergeScenario();
    const db = client.db(DB);
    const badTarget = {
      _id: new ObjectId(), name: "T3", normalizedName: "t3",
      type: "private-gym", status: "approved", createdBy: new ObjectId(), createdAt: new Date(),
    };
    await db.collection("places").insertOne(badTarget as any);
    await expect(mergePlace(source._id, badTarget._id)).rejects.toMatchObject({ code: "BAD_REQUEST" });
  });
});
```

- [ ] **Step 2: Append `mergePlace` to `place-ops.ts`**

```ts
import { getMongoClient } from "@/lib/mongo";

export async function mergePlace(sourceId: ObjectId, targetId: ObjectId): Promise<void> {
  if (sourceId.equals(targetId)) {
    throw new AdminOpError("BAD_REQUEST", "source and target are the same");
  }
  const client = await getMongoClient();
  const db = client.db(process.env.MONGODB_DB);
  const session = client.startSession();
  let sourceName = "";
  let targetName = "";
  let createdBy: ObjectId | null = null;
  try {
    await session.withTransaction(async () => {
      const src = await db
        .collection<PlaceDoc>("places")
        .findOne({ _id: sourceId, type: "gym", status: "pending" }, { session });
      if (!src) throw new AdminOpError("CONFLICT", "source place is not pending");
      const tgt = await db
        .collection<PlaceDoc>("places")
        .findOne({ _id: targetId, type: "gym", status: "approved" }, { session });
      if (!tgt) throw new AdminOpError("BAD_REQUEST", "target must be an approved gym");

      sourceName = src.name;
      targetName = tgt.name;
      createdBy = src.createdBy;

      await db
        .collection<ImageDoc>("images")
        .updateMany({ placeId: sourceId }, { $set: { placeId: targetId } }, { session });
      await db
        .collection<ActivityDoc>("activities")
        .updateMany(
          { "routeSnapshot.placeId": sourceId },
          { $set: { "routeSnapshot.placeId": targetId, "routeSnapshot.placeName": tgt.name } },
          { session },
        );
      const updateResult = await db
        .collection<PlaceDoc>("places")
        .updateOne(
          { _id: sourceId, status: "pending" },
          { $set: { status: "merged", mergedIntoPlaceId: targetId } },
          { session },
        );
      if (updateResult.modifiedCount === 0) {
        throw new AdminOpError("CONFLICT", "source place is not pending");
      }
    });
  } finally {
    await session.endSession();
  }

  if (!createdBy) return;
  await notify({
    userId: createdBy,
    type: "place_merged",
    params: { place_name: sourceName, target_name: targetName },
    link: `/places/${targetId.toString()}`,
  });
}
```

- [ ] **Step 3: Run**

```bash
cd apps/admin && pnpm test place-ops
```
Expected: all passed.

- [ ] **Step 4: Create `apps/admin/src/app/api/places/[id]/merge/route.ts`**

```ts
import { ObjectId } from "mongodb";
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { mergePlace, AdminOpError } from "@/lib/place-ops";
import { MergeBody } from "@/lib/zod-schemas";

export async function POST(req: Request, { params }: { params: { id: string } }) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  if (!ObjectId.isValid(params.id)) {
    return NextResponse.json({ error: "invalid id" }, { status: 422 });
  }
  const body = await req.json().catch(() => ({}));
  const parsed = MergeBody.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid body", details: parsed.error.flatten() }, { status: 422 });
  }
  try {
    await mergePlace(new ObjectId(params.id), new ObjectId(parsed.data.targetPlaceId));
    console.log("[admin] merge", {
      actor: auth.admin.email,
      sourceId: params.id,
      targetId: parsed.data.targetPlaceId,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminOpError) {
      const statusCode = err.code === "BAD_REQUEST" ? 400 : 409;
      return NextResponse.json({ error: err.message }, { status: statusCode });
    }
    throw err;
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add apps/admin/src/lib/place-ops.ts apps/admin/tests/lib/place-ops.test.ts apps/admin/src/app/api/places/[id]/merge
git commit -m "$(cat <<'EOF'
feat(admin): add mergePlace + POST /api/places/:id/merge

Transactional re-parenting of images and activity snapshots to the
target gym, then marks the source place merged with mergedIntoPlaceId.
Notifies the source creator via place_merged.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 7 — Suggestions: list, detail, APPROVE, REJECT

### Task 22: `suggestion-ops.ts` — listing + detail

**Files:**
- Create: `apps/admin/src/lib/suggestion-ops.ts`
- Create: `apps/admin/tests/lib/suggestion-ops.test.ts`
- Create: `apps/admin/src/app/api/suggestions/pending/route.ts`
- Create: `apps/admin/src/app/api/suggestions/[id]/route.ts`

- [ ] **Step 1: Create failing test `apps/admin/tests/lib/suggestion-ops.test.ts`**

```ts
import { MongoClient, ObjectId } from "mongodb";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { getPendingSuggestions, getSuggestionDetail } from "@/lib/suggestion-ops";

vi.mock("@/lib/notifications", () => ({ notify: vi.fn(async () => {}) }));

const DB = "besetter_test";
let client: MongoClient;

beforeEach(async () => {
  client = new MongoClient(process.env.MONGODB_URI!);
  await client.connect();
  const db = client.db(DB);
  await Promise.all([
    db.collection("placeSuggestions").deleteMany({}),
    db.collection("places").deleteMany({}),
    db.collection("users").deleteMany({}),
  ]);
});
afterEach(async () => { await client.close(); });

describe("getPendingSuggestions", () => {
  test("returns pending only, attaches place snapshot and requester profile", async () => {
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "suggester", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(), name: "Existing", normalizedName: "existing",
      type: "gym", status: "approved", createdBy: new ObjectId(), createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);
    const pending = {
      _id: new ObjectId(),
      placeId: place._id,
      requestedBy: user._id,
      status: "pending",
      changes: { name: "Existing Updated" },
      createdAt: new Date(),
    };
    const reviewed = { ...pending, _id: new ObjectId(), status: "approved", reviewedAt: new Date() };
    await db.collection("placeSuggestions").insertMany([pending, reviewed] as any);

    const result = await getPendingSuggestions();
    expect(result).toHaveLength(1);
    expect(result[0]!.place.name).toBe("Existing");
    expect(result[0]!.requester?.profileId).toBe("suggester");
    expect(result[0]!.changes.name).toBe("Existing Updated");
  });
});

describe("getSuggestionDetail", () => {
  test("returns null for unknown id", async () => {
    const d = await getSuggestionDetail(new ObjectId());
    expect(d).toBeNull();
  });
});
```

- [ ] **Step 2: Run to fail**

```bash
cd apps/admin && pnpm test suggestion-ops
```
Expected: missing module.

- [ ] **Step 3: Create `apps/admin/src/lib/suggestion-ops.ts`**

```ts
import type { ObjectId } from "mongodb";
import { getDb, getMongoClient } from "@/lib/mongo";
import type {
  PlaceDoc,
  PlaceSuggestionDoc,
  UserDoc,
} from "@/lib/db-types";
import { notify } from "@/lib/notifications";
import { normalizeName } from "@/lib/normalize";
import { AdminOpError } from "@/lib/place-ops";

export type SuggestionListItem = PlaceSuggestionDoc & {
  place: Pick<PlaceDoc, "_id" | "name" | "normalizedName" | "status" | "type" | "coverImageUrl">;
  requester: { profileId: string; profileImageUrl?: string | null } | null;
};

export async function getPendingSuggestions(): Promise<SuggestionListItem[]> {
  const db = await getDb();
  const pending = await db
    .collection<PlaceSuggestionDoc>("placeSuggestions")
    .find({ status: "pending" })
    .sort({ createdAt: 1 })
    .toArray();
  if (pending.length === 0) return [];
  const placeIds = pending.map((s) => s.placeId);
  const userIds = pending.map((s) => s.requestedBy);
  const [places, users] = await Promise.all([
    db.collection<PlaceDoc>("places").find({ _id: { $in: placeIds } }).toArray(),
    db.collection<UserDoc>("users").find({ _id: { $in: userIds } }).toArray(),
  ]);
  const placeById = new Map(places.map((p) => [p._id.toString(), p]));
  const userById = new Map(users.map((u) => [u._id.toString(), u]));
  return pending
    .map((s) => {
      const p = placeById.get(s.placeId.toString());
      if (!p) return null;
      const u = userById.get(s.requestedBy.toString());
      return {
        ...s,
        place: {
          _id: p._id,
          name: p.name,
          normalizedName: p.normalizedName,
          status: p.status,
          type: p.type,
          coverImageUrl: p.coverImageUrl ?? null,
        },
        requester: u
          ? { profileId: u.profileId, profileImageUrl: u.profileImageUrl ?? null }
          : null,
      } satisfies SuggestionListItem;
    })
    .filter((x): x is SuggestionListItem => x !== null);
}

export type SuggestionDetail = SuggestionListItem & {
  currentPlace: PlaceDoc;
};

export async function getSuggestionDetail(id: ObjectId): Promise<SuggestionDetail | null> {
  const db = await getDb();
  const s = await db.collection<PlaceSuggestionDoc>("placeSuggestions").findOne({ _id: id });
  if (!s) return null;
  const place = await db.collection<PlaceDoc>("places").findOne({ _id: s.placeId });
  if (!place) return null;
  const user = await db.collection<UserDoc>("users").findOne({ _id: s.requestedBy });
  return {
    ...s,
    place: {
      _id: place._id,
      name: place.name,
      normalizedName: place.normalizedName,
      status: place.status,
      type: place.type,
      coverImageUrl: place.coverImageUrl ?? null,
    },
    requester: user
      ? { profileId: user.profileId, profileImageUrl: user.profileImageUrl ?? null }
      : null,
    currentPlace: place,
  };
}
```

- [ ] **Step 4: Run**

```bash
cd apps/admin && pnpm test suggestion-ops
```
Expected: tests passed.

- [ ] **Step 5: Create `apps/admin/src/app/api/suggestions/pending/route.ts`**

```ts
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { getPendingSuggestions } from "@/lib/suggestion-ops";

export async function GET() {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  const suggestions = await getPendingSuggestions();
  return NextResponse.json({ suggestions });
}
```

- [ ] **Step 6: Create `apps/admin/src/app/api/suggestions/[id]/route.ts`**

```ts
import { ObjectId } from "mongodb";
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { getSuggestionDetail } from "@/lib/suggestion-ops";

export async function GET(_req: Request, { params }: { params: { id: string } }) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  if (!ObjectId.isValid(params.id)) {
    return NextResponse.json({ error: "invalid id" }, { status: 422 });
  }
  const detail = await getSuggestionDetail(new ObjectId(params.id));
  if (!detail) return NextResponse.json({ error: "not found" }, { status: 404 });
  return NextResponse.json(detail);
}
```

- [ ] **Step 7: Commit**

```bash
git add apps/admin/src/lib/suggestion-ops.ts apps/admin/tests/lib/suggestion-ops.test.ts apps/admin/src/app/api/suggestions
git commit -m "$(cat <<'EOF'
feat(admin): add suggestion-ops listing/detail + GET routes

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 23: `approveSuggestion` + route

**Files:**
- Modify: `apps/admin/src/lib/suggestion-ops.ts`
- Modify: `apps/admin/tests/lib/suggestion-ops.test.ts`
- Create: `apps/admin/src/app/api/suggestions/[id]/approve/route.ts`

- [ ] **Step 1: Append failing tests**

```ts
import { approveSuggestion } from "@/lib/suggestion-ops";
import { notify } from "@/lib/notifications";

describe("approveSuggestion", () => {
  async function seed(changes: Record<string, unknown>) {
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "s", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(), name: "Old", normalizedName: "old",
      type: "gym", status: "approved", createdBy: new ObjectId(), createdAt: new Date(),
      location: { type: "Point", coordinates: [127, 37] },
    };
    await db.collection("places").insertOne(place as any);
    const suggestion = {
      _id: new ObjectId(), placeId: place._id, requestedBy: user._id,
      status: "pending", changes, createdAt: new Date(),
    };
    await db.collection("placeSuggestions").insertOne(suggestion as any);
    return { place, suggestion, user };
  }

  test("name change updates name + normalizedName", async () => {
    vi.mocked(notify).mockClear();
    const { place, suggestion } = await seed({ name: "New Name" });
    await approveSuggestion(suggestion._id);
    const db = client.db(DB);
    const updated = await db.collection("places").findOne({ _id: place._id });
    expect(updated!.name).toBe("New Name");
    expect(updated!.normalizedName).toBe("newname");
    const s = await db.collection("placeSuggestions").findOne({ _id: suggestion._id });
    expect(s!.status).toBe("approved");
    expect(s!.reviewedAt).toBeInstanceOf(Date);
  });

  test("location change updates coordinates", async () => {
    const { place, suggestion } = await seed({ latitude: 37.5, longitude: 127.1 });
    await approveSuggestion(suggestion._id);
    const db = client.db(DB);
    const updated = await db.collection("places").findOne({ _id: place._id });
    expect(updated!.location.coordinates).toEqual([127.1, 37.5]);
  });

  test("cover change updates coverImageUrl", async () => {
    const { place, suggestion } = await seed({ coverImageUrl: "https://example/new.jpg" });
    await approveSuggestion(suggestion._id);
    const db = client.db(DB);
    const updated = await db.collection("places").findOne({ _id: place._id });
    expect(updated!.coverImageUrl).toBe("https://example/new.jpg");
  });

  test("conflict when suggestion not pending", async () => {
    const { suggestion } = await seed({ name: "X" });
    const db = client.db(DB);
    await db.collection("placeSuggestions").updateOne(
      { _id: suggestion._id },
      { $set: { status: "approved" } },
    );
    await expect(approveSuggestion(suggestion._id)).rejects.toMatchObject({ code: "CONFLICT" });
  });

  test("conflict when target place not approved", async () => {
    const { place, suggestion } = await seed({ name: "X" });
    const db = client.db(DB);
    await db.collection("places").updateOne(
      { _id: place._id },
      { $set: { status: "rejected" } },
    );
    await expect(approveSuggestion(suggestion._id)).rejects.toMatchObject({ code: "CONFLICT" });
  });

  test("bad_request when all changes are null", async () => {
    const { suggestion } = await seed({});
    await expect(approveSuggestion(suggestion._id)).rejects.toMatchObject({ code: "BAD_REQUEST" });
  });

  test("notifies requester with place_suggestion_approved", async () => {
    vi.mocked(notify).mockClear();
    const { user, suggestion } = await seed({ name: "Y" });
    await approveSuggestion(suggestion._id);
    expect(notify).toHaveBeenCalledWith(
      expect.objectContaining({ userId: user._id, type: "place_suggestion_approved" }),
    );
  });
});
```

- [ ] **Step 2: Append `approveSuggestion` to `suggestion-ops.ts`**

```ts
export async function approveSuggestion(suggestionId: ObjectId): Promise<void> {
  const client = await getMongoClient();
  const db = client.db(process.env.MONGODB_DB);
  const session = client.startSession();
  let createdPlaceName = "";
  let requestedBy: ObjectId | null = null;
  try {
    await session.withTransaction(async () => {
      const s = await db
        .collection<PlaceSuggestionDoc>("placeSuggestions")
        .findOne({ _id: suggestionId, status: "pending" }, { session });
      if (!s) throw new AdminOpError("CONFLICT", "suggestion is not pending");
      const place = await db
        .collection<PlaceDoc>("places")
        .findOne({ _id: s.placeId, status: "approved" }, { session });
      if (!place) throw new AdminOpError("CONFLICT", "target place is not approved");

      const changes = s.changes ?? {};
      const set: Record<string, unknown> = {};
      if (changes.name != null) {
        set.name = changes.name;
        set.normalizedName = normalizeName(changes.name);
      }
      if (changes.latitude != null && changes.longitude != null) {
        set.location = {
          type: "Point",
          coordinates: [changes.longitude, changes.latitude],
        };
      }
      if (changes.coverImageUrl != null) {
        set.coverImageUrl = changes.coverImageUrl;
      }
      if (Object.keys(set).length === 0) {
        throw new AdminOpError("BAD_REQUEST", "suggestion has no changes");
      }
      await db.collection<PlaceDoc>("places").updateOne({ _id: place._id }, { $set: set }, { session });
      await db.collection<PlaceSuggestionDoc>("placeSuggestions").updateOne(
        { _id: suggestionId, status: "pending" },
        { $set: { status: "approved", reviewedAt: new Date() } },
        { session },
      );
      createdPlaceName = (set.name as string | undefined) ?? place.name;
      requestedBy = s.requestedBy;
    });
  } finally {
    await session.endSession();
  }

  if (!requestedBy) return;
  await notify({
    userId: requestedBy,
    type: "place_suggestion_approved",
    params: { place_name: createdPlaceName },
    link: null,
  });
}
```

- [ ] **Step 3: Run**

```bash
cd apps/admin && pnpm test suggestion-ops
```
Expected: all passed.

- [ ] **Step 4: Create `apps/admin/src/app/api/suggestions/[id]/approve/route.ts`**

```ts
import { ObjectId } from "mongodb";
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { approveSuggestion } from "@/lib/suggestion-ops";
import { AdminOpError } from "@/lib/place-ops";

export async function POST(_req: Request, { params }: { params: { id: string } }) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  if (!ObjectId.isValid(params.id)) {
    return NextResponse.json({ error: "invalid id" }, { status: 422 });
  }
  try {
    await approveSuggestion(new ObjectId(params.id));
    console.log("[admin] suggestion.approve", { actor: auth.admin.email, suggestionId: params.id });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminOpError) {
      const statusCode = err.code === "BAD_REQUEST" ? 400 : 409;
      return NextResponse.json({ error: err.message }, { status: statusCode });
    }
    throw err;
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add apps/admin/src/lib/suggestion-ops.ts apps/admin/tests/lib/suggestion-ops.test.ts apps/admin/src/app/api/suggestions/[id]/approve
git commit -m "$(cat <<'EOF'
feat(admin): add approveSuggestion + POST /api/suggestions/:id/approve

Applies non-null changes to the target place transactionally and
marks the suggestion approved.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 24: `rejectSuggestion` + route

**Files:**
- Modify: `apps/admin/src/lib/suggestion-ops.ts`
- Modify: `apps/admin/tests/lib/suggestion-ops.test.ts`
- Create: `apps/admin/src/app/api/suggestions/[id]/reject/route.ts`

- [ ] **Step 1: Append failing tests**

```ts
import { rejectSuggestion } from "@/lib/suggestion-ops";

describe("rejectSuggestion", () => {
  async function seedPending() {
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "s", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(), name: "P", normalizedName: "p",
      type: "gym", status: "approved", createdBy: new ObjectId(), createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);
    const suggestion = {
      _id: new ObjectId(), placeId: place._id, requestedBy: user._id,
      status: "pending", changes: { name: "Q" }, createdAt: new Date(),
    };
    await db.collection("placeSuggestions").insertOne(suggestion as any);
    return { place, suggestion, user };
  }

  test("marks rejected + sets reviewedAt + notifies with reason_suffix", async () => {
    vi.mocked(notify).mockClear();
    const { suggestion, user } = await seedPending();
    await rejectSuggestion(suggestion._id, "좌표 불일치");
    const db = client.db(DB);
    const s = await db.collection("placeSuggestions").findOne({ _id: suggestion._id });
    expect(s!.status).toBe("rejected");
    expect(s!.reviewedAt).toBeInstanceOf(Date);
    expect(notify).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: user._id,
        type: "place_suggestion_rejected",
        params: expect.objectContaining({ reason_suffix: " 사유: 좌표 불일치" }),
      }),
    );
  });

  test("no reason → empty reason_suffix", async () => {
    vi.mocked(notify).mockClear();
    const { suggestion } = await seedPending();
    await rejectSuggestion(suggestion._id);
    expect(notify).toHaveBeenCalledWith(
      expect.objectContaining({
        params: expect.objectContaining({ reason_suffix: "" }),
      }),
    );
  });

  test("conflict when already reviewed", async () => {
    const { suggestion } = await seedPending();
    const db = client.db(DB);
    await db.collection("placeSuggestions").updateOne(
      { _id: suggestion._id },
      { $set: { status: "approved" } },
    );
    await expect(rejectSuggestion(suggestion._id)).rejects.toMatchObject({ code: "CONFLICT" });
  });
});
```

- [ ] **Step 2: Append `rejectSuggestion` to `suggestion-ops.ts`**

```ts
export async function rejectSuggestion(
  suggestionId: ObjectId,
  reason?: string,
): Promise<void> {
  const db = await getDb();
  const result = await db
    .collection<PlaceSuggestionDoc>("placeSuggestions")
    .findOneAndUpdate(
      { _id: suggestionId, status: "pending" },
      { $set: { status: "rejected", reviewedAt: new Date() } },
      { returnDocument: "before" },
    );
  if (!result) throw new AdminOpError("CONFLICT", "suggestion is not pending");
  const place = await db.collection<PlaceDoc>("places").findOne({ _id: result.placeId });
  await notify({
    userId: result.requestedBy,
    type: "place_suggestion_rejected",
    params: {
      place_name: place?.name ?? "",
      reason_suffix: reason ? ` 사유: ${reason}` : "",
    },
    link: null,
  });
}
```

- [ ] **Step 3: Run**

```bash
cd apps/admin && pnpm test suggestion-ops
```
Expected: all passed.

- [ ] **Step 4: Create `apps/admin/src/app/api/suggestions/[id]/reject/route.ts`**

```ts
import { ObjectId } from "mongodb";
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { rejectSuggestion } from "@/lib/suggestion-ops";
import { AdminOpError } from "@/lib/place-ops";
import { RejectBody } from "@/lib/zod-schemas";

export async function POST(req: Request, { params }: { params: { id: string } }) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  if (!ObjectId.isValid(params.id)) {
    return NextResponse.json({ error: "invalid id" }, { status: 422 });
  }
  const body = await req.json().catch(() => ({}));
  const parsed = RejectBody.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid body", details: parsed.error.flatten() }, { status: 422 });
  }
  try {
    await rejectSuggestion(new ObjectId(params.id), parsed.data.reason);
    console.log("[admin] suggestion.reject", {
      actor: auth.admin.email,
      suggestionId: params.id,
      reason: parsed.data.reason ?? null,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminOpError) {
      const statusCode = err.code === "BAD_REQUEST" ? 400 : 409;
      return NextResponse.json({ error: err.message }, { status: statusCode });
    }
    throw err;
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add apps/admin/src/lib/suggestion-ops.ts apps/admin/tests/lib/suggestion-ops.test.ts apps/admin/src/app/api/suggestions/[id]/reject
git commit -m "$(cat <<'EOF'
feat(admin): add rejectSuggestion + POST /api/suggestions/:id/reject

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 8 — UI: sidebar, places page, merge dialog

### Task 25: Sidebar with pending counts

**Files:**
- Modify: `apps/admin/src/components/sidebar.tsx`
- Create: `apps/admin/src/app/api/counts/route.ts` (aggregator for sidebar badges)

- [ ] **Step 1: Create `apps/admin/src/app/api/counts/route.ts`**

```ts
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { getDb } from "@/lib/mongo";

export async function GET() {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  const db = await getDb();
  const [pendingPlaces, pendingSuggestions] = await Promise.all([
    db.collection("places").countDocuments({ type: "gym", status: "pending" }),
    db.collection("placeSuggestions").countDocuments({ status: "pending" }),
  ]);
  return NextResponse.json({ pendingPlaces, pendingSuggestions });
}
```

- [ ] **Step 2: Replace `apps/admin/src/components/sidebar.tsx`**

```tsx
"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

type Counts = { pendingPlaces: number; pendingSuggestions: number };

export function Sidebar({ email }: { email: string }) {
  const pathname = usePathname();
  const [counts, setCounts] = useState<Counts>({ pendingPlaces: 0, pendingSuggestions: 0 });

  useEffect(() => {
    fetch("/api/counts")
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => data && setCounts(data))
      .catch(() => {});
  }, [pathname]);

  const item = (href: string, label: string, count: number) => {
    const active = pathname?.startsWith(href);
    return (
      <Link
        href={href}
        style={{
          display: "block",
          padding: "8px 16px",
          background: active ? "rgba(100,150,255,0.13)" : "transparent",
          borderLeft: active ? "3px solid #6495ff" : "3px solid transparent",
          color: active ? "#fff" : "#b0b6c6",
          textDecoration: "none",
        }}
      >
        {label}
        <span
          style={{
            float: "right",
            background: "#3a4256",
            color: "#cfd4e0",
            borderRadius: 10,
            padding: "1px 7px",
            fontSize: 11,
          }}
        >
          {count}
        </span>
      </Link>
    );
  };

  return (
    <aside
      style={{
        width: 210,
        background: "#151821",
        borderRight: "1px solid #262b38",
        padding: "16px 0",
        color: "#c5c9d4",
      }}
    >
      <div style={{ padding: "0 16px 14px", borderBottom: "1px solid #262b38", marginBottom: 10 }}>
        <div style={{ fontWeight: 600, color: "#fff" }}>besetter admin</div>
        <div style={{ fontSize: 11, color: "#8b93a7", marginTop: 3 }}>{email}</div>
      </div>
      <div style={{ fontSize: 10, letterSpacing: "0.1em", color: "#6b7388", padding: "8px 16px 6px" }}>
        장소
      </div>
      {item("/places", "장소 검수", counts.pendingPlaces)}
      {item("/suggestions", "수정 제안", counts.pendingSuggestions)}
    </aside>
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add apps/admin/src/components/sidebar.tsx apps/admin/src/app/api/counts
git commit -m "$(cat <<'EOF'
feat(admin): sidebar with pending place/suggestion counts

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 26: Places page — queue list + detail panel + action buttons

**Files:**
- Create: `apps/admin/src/components/queue-list.tsx`
- Create: `apps/admin/src/components/place-detail.tsx`
- Create: `apps/admin/src/app/places/page.tsx`

- [ ] **Step 1: Create `apps/admin/src/components/queue-list.tsx`**

```tsx
"use client";
import type { ReactNode } from "react";

export function QueueList({
  title,
  items,
  selectedId,
  onSelect,
  renderItem,
}: {
  title: string;
  items: Array<{ id: string }>;
  selectedId: string | null;
  onSelect: (id: string) => void;
  renderItem: (item: { id: string }) => ReactNode;
}) {
  return (
    <div style={{ width: 320, borderRight: "1px solid #262b38", background: "#12151d", overflow: "auto" }}>
      <div style={{ padding: "12px 14px", borderBottom: "1px solid #262b38", color: "#fff", fontWeight: 600 }}>
        {title}
      </div>
      {items.length === 0 ? (
        <div style={{ padding: "24px 14px", color: "#6b7388", fontSize: 12, textAlign: "center" }}>대기 중인 항목이 없습니다</div>
      ) : (
        items.map((it) => {
          const active = selectedId === it.id;
          return (
            <button
              key={it.id}
              onClick={() => onSelect(it.id)}
              style={{
                display: "block",
                width: "100%",
                textAlign: "left",
                padding: "10px 14px",
                background: active ? "#1a1f2b" : "transparent",
                borderLeft: active ? "3px solid #6495ff" : "3px solid transparent",
                borderTop: "1px solid #1f2432",
                color: active ? "#fff" : "#c5c9d4",
                cursor: "pointer",
                font: "inherit",
              }}
            >
              {renderItem(it)}
            </button>
          );
        })
      )}
    </div>
  );
}
```

- [ ] **Step 2: Create `apps/admin/src/components/place-detail.tsx`**

```tsx
"use client";
import { useState } from "react";

type Detail = {
  place: {
    _id: string;
    name: string;
    status: string;
    type: string;
    coverImageUrl?: string | null;
    location?: { coordinates: [number, number] } | null;
    createdAt: string;
  };
  creator: { profileId: string; profileImageUrl?: string | null } | null;
  counts: { imageCount: number; routeCount: number; activityCount: number };
  nearbyApproved: Array<{ _id: string; name: string; distanceMeters: number }>;
};

export function PlaceDetail({
  detail,
  onPass,
  onFail,
  onOpenMerge,
}: {
  detail: Detail;
  onPass: () => void;
  onFail: (reason: string) => void;
  onOpenMerge: () => void;
}) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);

  const act = async (fn: () => Promise<void>) => {
    setBusy(true);
    try { await fn(); } finally { setBusy(false); }
  };

  return (
    <div style={{ flex: 1, background: "#0f1117", color: "#dde1ea", padding: 18, overflow: "auto" }}>
      <div style={{ display: "flex", gap: 16 }}>
        <div
          style={{
            width: 200,
            height: 140,
            background: "#262b38",
            borderRadius: 6,
            overflow: "hidden",
          }}
        >
          {detail.place.coverImageUrl ? (
            <img src={detail.place.coverImageUrl} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
          ) : null}
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 20, fontWeight: 600 }}>{detail.place.name}</div>
          <div style={{ fontSize: 12, color: "#8b93a7", marginTop: 4 }}>
            status: <b style={{ color: "#ffb86b" }}>{detail.place.status}</b> · type: {detail.place.type}
          </div>
          <div style={{ fontSize: 12, color: "#c5c9d4", marginTop: 10 }}>
            {detail.place.location
              ? `좌표 ${detail.place.location.coordinates[1].toFixed(4)}, ${detail.place.location.coordinates[0].toFixed(4)}`
              : "좌표 없음"}
            {detail.creator ? ` · 등록자 @${detail.creator.profileId}` : null}
          </div>
          <div style={{ fontSize: 12, color: "#c5c9d4", marginTop: 4 }}>
            매달린 데이터: 이미지 {detail.counts.imageCount} · 루트 {detail.counts.routeCount} · 활동 {detail.counts.activityCount}
          </div>
        </div>
      </div>

      <div style={{ marginTop: 18, border: "1px solid #262b38", borderRadius: 6, overflow: "hidden" }}>
        <div style={{ padding: "10px 14px", background: "#151821", fontSize: 12, color: "#c5c9d4" }}>
          반경 200m 내 approved 장소
        </div>
        {detail.nearbyApproved.length === 0 ? (
          <div style={{ padding: 12, color: "#6b7388", fontSize: 12 }}>해당 없음</div>
        ) : (
          detail.nearbyApproved.map((n) => (
            <div
              key={n._id}
              style={{
                padding: "8px 14px",
                borderTop: "1px solid #262b38",
                fontSize: 12,
                display: "flex",
                justifyContent: "space-between",
              }}
            >
              <span>
                <b>{n.name}</b> <span style={{ color: "#8b93a7" }}>· {n.distanceMeters}m</span>
              </span>
            </div>
          ))
        )}
      </div>

      <div style={{ marginTop: 14, display: "flex", gap: 10, alignItems: "flex-start" }}>
        <button
          disabled={busy}
          onClick={() => act(async () => onPass())}
          style={btnStyle("#3aa76d", "#fff")}
        >
          PASS
        </button>
        <button
          disabled={busy}
          onClick={() => act(async () => onFail(reason.trim() || ""))}
          style={btnStyle("#d04848", "#fff")}
        >
          FAIL
        </button>
        <button
          disabled={busy}
          onClick={() => act(async () => onOpenMerge())}
          style={btnStyle("#ffb86b", "#1a1308")}
        >
          MERGE
        </button>
        <input
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="FAIL 사유 (선택)"
          style={{
            flex: 1,
            background: "#1d2130",
            color: "#c5c9d4",
            border: "1px solid #2c3244",
            borderRadius: 5,
            padding: "9px 10px",
            fontSize: 12,
          }}
        />
      </div>
    </div>
  );
}

function btnStyle(bg: string, fg: string): React.CSSProperties {
  return {
    background: bg,
    color: fg,
    border: 0,
    borderRadius: 5,
    padding: "9px 18px",
    fontWeight: 600,
    cursor: "pointer",
  };
}
```

- [ ] **Step 3: Create `apps/admin/src/app/places/page.tsx`**

```tsx
"use client";
import { useCallback, useEffect, useState } from "react";
import { QueueList } from "@/components/queue-list";
import { PlaceDetail } from "@/components/place-detail";
import { MergeDialog } from "@/components/merge-dialog";

type PendingPlace = {
  _id: string;
  name: string;
  createdAt: string;
  creator: { profileId: string } | null;
};

export default function PlacesPage() {
  const [items, setItems] = useState<PendingPlace[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<any>(null);
  const [mergeOpen, setMergeOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refreshList = useCallback(async () => {
    const res = await fetch("/api/places/pending");
    if (!res.ok) return;
    const data = await res.json();
    setItems(data.places);
  }, []);

  useEffect(() => { refreshList(); }, [refreshList]);

  useEffect(() => {
    if (!selectedId) { setDetail(null); return; }
    fetch(`/api/places/${selectedId}`)
      .then((r) => (r.ok ? r.json() : null))
      .then(setDetail)
      .catch(() => setDetail(null));
  }, [selectedId]);

  async function runAction(path: string, body: unknown = {}) {
    setError(null);
    const res = await fetch(path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      if (res.status === 409) setError("이미 다른 운영자가 처리했습니다. 목록을 새로고침합니다.");
      else setError(`오류: ${res.status}`);
    }
    await refreshList();
    setSelectedId(null);
    setMergeOpen(false);
  }

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <QueueList
        title="신규 gym 큐"
        items={items.map((p) => ({ id: p._id, ...p })) as any}
        selectedId={selectedId}
        onSelect={setSelectedId}
        renderItem={(raw) => {
          const p = raw as unknown as PendingPlace;
          return (
            <>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "#8b93a7" }}>
                <span>{new Date(p.createdAt).toLocaleString()}</span>
                <span>by @{p.creator?.profileId ?? "?"}</span>
              </div>
              <div style={{ marginTop: 4, fontWeight: 600 }}>{p.name}</div>
            </>
          );
        }}
      />
      {detail ? (
        <PlaceDetail
          detail={detail}
          onPass={() => runAction(`/api/places/${detail.place._id}/pass`)}
          onFail={(reason) => runAction(`/api/places/${detail.place._id}/fail`, reason ? { reason } : {})}
          onOpenMerge={() => setMergeOpen(true)}
        />
      ) : (
        <div style={{ flex: 1, padding: 24, color: "#6b7388" }}>큐에서 항목을 선택하세요.</div>
      )}
      {mergeOpen && detail ? (
        <MergeDialog
          source={detail.place}
          counts={detail.counts}
          onClose={() => setMergeOpen(false)}
          onConfirm={(targetPlaceId) =>
            runAction(`/api/places/${detail.place._id}/merge`, { targetPlaceId })
          }
        />
      ) : null}
      {error ? (
        <div
          style={{
            position: "fixed",
            bottom: 20,
            right: 20,
            background: "#2b1d1d",
            border: "1px solid #d04848",
            borderRadius: 6,
            padding: "10px 14px",
            color: "#ffb3b3",
          }}
        >
          {error}
        </div>
      ) : null}
    </div>
  );
}
```

- [ ] **Step 4: Commit**

```bash
git add apps/admin/src/components/queue-list.tsx apps/admin/src/components/place-detail.tsx apps/admin/src/app/places/page.tsx
git commit -m "$(cat <<'EOF'
feat(admin): places review page wiring PASS/FAIL/MERGE entry points

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 27: Merge dialog

**Files:**
- Create: `apps/admin/src/components/merge-dialog.tsx`

- [ ] **Step 1: Create**

```tsx
"use client";
import { useEffect, useState } from "react";

type Candidate = {
  _id: string;
  name: string;
  location?: { coordinates: [number, number] } | null;
  distanceMeters?: number;
  imageCount: number;
  routeCount: number;
};

export function MergeDialog({
  source,
  counts,
  onClose,
  onConfirm,
}: {
  source: { _id: string; name: string; location?: { coordinates: [number, number] } | null };
  counts: { imageCount: number; routeCount: number; activityCount: number };
  onClose: () => void;
  onConfirm: (targetPlaceId: string) => void;
}) {
  const [q, setQ] = useState("");
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [selected, setSelected] = useState<string | null>(null);

  useEffect(() => {
    const lat = source.location?.coordinates[1] ?? 0;
    const lng = source.location?.coordinates[0] ?? 0;
    const url = new URL("/api/places/merge-candidates", window.location.origin);
    url.searchParams.set("lat", String(lat));
    url.searchParams.set("lng", String(lng));
    if (q.trim()) url.searchParams.set("q", q.trim());
    fetch(url)
      .then((r) => (r.ok ? r.json() : { candidates: [] }))
      .then((d) => setCandidates(d.candidates ?? []))
      .catch(() => setCandidates([]));
  }, [q, source.location]);

  return (
    <div
      role="dialog"
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(0,0,0,0.55)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: 40,
      }}
    >
      <div style={{ width: 720, background: "#0f1117", border: "1px solid #262b38", borderRadius: 8 }}>
        <div style={{ padding: "14px 18px", borderBottom: "1px solid #262b38", color: "#fff", fontWeight: 600 }}>
          MERGE 타깃 선택
        </div>
        <div style={{ padding: 18, color: "#dde1ea" }}>
          <div style={{ background: "#151821", border: "1px solid #262b38", borderRadius: 6, padding: "12px 14px" }}>
            <div style={{ fontSize: 11, color: "#8b93a7" }}>병합 대상(source)</div>
            <div style={{ fontWeight: 600 }}>{source.name}</div>
            <div style={{ fontSize: 11, color: "#ffb86b", marginTop: 4 }}>
              ⚠ 이미지 {counts.imageCount} · 루트 {counts.routeCount} · 활동 {counts.activityCount} 이관됨
            </div>
          </div>

          <div style={{ margin: "12px 0" }}>
            <input
              placeholder="이름으로 검색 (예: 강남 클라이밍)"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              style={{
                width: "100%",
                background: "#1d2130",
                color: "#c5c9d4",
                border: "1px solid #2c3244",
                borderRadius: 5,
                padding: "9px 10px",
                fontSize: 12,
              }}
            />
          </div>

          <div style={{ border: "1px solid #262b38", borderRadius: 6, overflow: "hidden" }}>
            {candidates.length === 0 ? (
              <div style={{ padding: 24, color: "#8b93a7", fontSize: 12, textAlign: "center" }}>
                1km 반경 내 approved 장소가 없습니다
              </div>
            ) : (
              candidates.map((c) => {
                const active = selected === c._id;
                return (
                  <button
                    key={c._id}
                    onClick={() => setSelected(c._id)}
                    style={{
                      display: "block",
                      width: "100%",
                      textAlign: "left",
                      padding: "10px 14px",
                      background: active ? "#1a1f2b" : "transparent",
                      borderTop: "1px solid #262b38",
                      borderLeft: active ? "3px solid #6495ff" : "3px solid transparent",
                      color: active ? "#fff" : "#c5c9d4",
                      cursor: "pointer",
                      font: "inherit",
                    }}
                  >
                    <div style={{ fontWeight: 600 }}>{c.name}</div>
                    <div style={{ fontSize: 11, color: "#8b93a7", marginTop: 3 }}>
                      이미지 {c.imageCount} · 루트 {c.routeCount}
                      {c.distanceMeters != null ? ` · ${c.distanceMeters}m` : ""}
                    </div>
                  </button>
                );
              })
            )}
          </div>

          <div style={{ marginTop: 18, display: "flex", gap: 10, justifyContent: "flex-end" }}>
            <button onClick={onClose} style={{ background: "#2c3244", color: "#c5c9d4", border: 0, borderRadius: 5, padding: "9px 16px", cursor: "pointer" }}>
              취소
            </button>
            <button
              disabled={!selected}
              onClick={() => selected && onConfirm(selected)}
              style={{
                background: selected ? "#ffb86b" : "#3a4256",
                color: "#1a1308",
                border: 0,
                borderRadius: 5,
                padding: "9px 18px",
                fontWeight: 600,
                cursor: selected ? "pointer" : "not-allowed",
              }}
            >
              선택 장소로 MERGE
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/admin/src/components/merge-dialog.tsx
git commit -m "$(cat <<'EOF'
feat(admin): add MergeDialog component

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 28: Suggestions page with diff view

**Files:**
- Create: `apps/admin/src/components/suggestion-diff.tsx`
- Create: `apps/admin/src/app/suggestions/page.tsx`

- [ ] **Step 1: Create `apps/admin/src/components/suggestion-diff.tsx`**

```tsx
"use client";
import { useState } from "react";

type Detail = {
  _id: string;
  requester: { profileId: string } | null;
  createdAt: string;
  changes: { name?: string | null; latitude?: number | null; longitude?: number | null; coverImageUrl?: string | null };
  currentPlace: {
    name: string;
    location?: { coordinates: [number, number] } | null;
    coverImageUrl?: string | null;
  };
};

export function SuggestionDiff({
  detail,
  onApprove,
  onReject,
}: {
  detail: Detail;
  onApprove: () => void;
  onReject: (reason: string) => void;
}) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const act = async (fn: () => Promise<void>) => { setBusy(true); try { await fn(); } finally { setBusy(false); } };

  const nameChanged = detail.changes.name != null;
  const locChanged = detail.changes.latitude != null && detail.changes.longitude != null;
  const coverChanged = detail.changes.coverImageUrl != null;

  return (
    <div style={{ flex: 1, background: "#0f1117", color: "#dde1ea", padding: 18, overflow: "auto" }}>
      <div style={{ fontSize: 20, fontWeight: 600 }}>{detail.currentPlace.name}</div>
      <div style={{ fontSize: 12, color: "#8b93a7", marginTop: 3 }}>
        제안자 @{detail.requester?.profileId ?? "?"} · {new Date(detail.createdAt).toLocaleString()}
      </div>

      <DiffCard label="NAME" changed={nameChanged}>
        <Side which="current">{detail.currentPlace.name}</Side>
        <Side which="proposed">{detail.changes.name ?? "—"}</Side>
      </DiffCard>

      <DiffCard label="LOCATION" changed={locChanged}>
        <Side which="current">
          {detail.currentPlace.location
            ? `${detail.currentPlace.location.coordinates[1]}, ${detail.currentPlace.location.coordinates[0]}`
            : "—"}
        </Side>
        <Side which="proposed">
          {locChanged ? `${detail.changes.latitude}, ${detail.changes.longitude}` : "—"}
        </Side>
      </DiffCard>

      <DiffCard label="COVER IMAGE" changed={coverChanged}>
        <Side which="current">
          {detail.currentPlace.coverImageUrl ? (
            <img src={detail.currentPlace.coverImageUrl} alt="" style={{ width: "100%", maxHeight: 140, objectFit: "cover", borderRadius: 4 }} />
          ) : "—"}
        </Side>
        <Side which="proposed">
          {coverChanged && detail.changes.coverImageUrl ? (
            <img src={detail.changes.coverImageUrl} alt="" style={{ width: "100%", maxHeight: 140, objectFit: "cover", borderRadius: 4 }} />
          ) : "—"}
        </Side>
      </DiffCard>

      <div style={{ marginTop: 16, display: "flex", gap: 10 }}>
        <button disabled={busy} onClick={() => act(async () => onApprove())} style={btn("#3aa76d", "#fff")}>APPROVE</button>
        <button disabled={busy} onClick={() => act(async () => onReject(reason.trim()))} style={btn("#d04848", "#fff")}>REJECT</button>
        <input
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="REJECT 사유 (선택)"
          style={{ flex: 1, background: "#1d2130", color: "#c5c9d4", border: "1px solid #2c3244", borderRadius: 5, padding: "9px 10px", fontSize: 12 }}
        />
      </div>
    </div>
  );
}

function btn(bg: string, fg: string): React.CSSProperties {
  return { background: bg, color: fg, border: 0, borderRadius: 5, padding: "9px 18px", fontWeight: 600, cursor: "pointer" };
}

function DiffCard({ label, changed, children }: { label: string; changed: boolean; children: React.ReactNode }) {
  if (!changed) {
    return (
      <div style={{ marginTop: 10, border: "1px dashed #262b38", borderRadius: 6, padding: "8px 12px", color: "#6b7388", fontSize: 11 }}>
        {label} — 제안 없음
      </div>
    );
  }
  return (
    <div style={{ marginTop: 10, border: "1px solid #262b38", borderRadius: 6, overflow: "hidden" }}>
      <div style={{ padding: "8px 12px", background: "#151821", fontSize: 11, color: "#8b93a7", letterSpacing: "0.05em" }}>{label}</div>
      <div style={{ display: "flex" }}>{children}</div>
    </div>
  );
}

function Side({ which, children }: { which: "current" | "proposed"; children: React.ReactNode }) {
  const bg = which === "current" ? "#1a1417" : "#141a17";
  const border = which === "current" ? "#d04848" : "#3aa76d";
  const fg = which === "current" ? "#d08a8a" : "#8ad0a0";
  return (
    <div style={{ flex: 1, padding: 12, background: bg, borderLeft: `3px solid ${border}`, borderRight: which === "current" ? "1px solid #262b38" : undefined }}>
      <div style={{ fontSize: 10, color: fg, marginBottom: 4 }}>{which === "current" ? "CURRENT" : "PROPOSED"}</div>
      <div style={{ color: "#fff" }}>{children}</div>
    </div>
  );
}
```

- [ ] **Step 2: Create `apps/admin/src/app/suggestions/page.tsx`**

```tsx
"use client";
import { useCallback, useEffect, useState } from "react";
import { QueueList } from "@/components/queue-list";
import { SuggestionDiff } from "@/components/suggestion-diff";

type Item = {
  _id: string;
  createdAt: string;
  place: { name: string };
  requester: { profileId: string } | null;
  changes: { name?: string | null; latitude?: number | null; coverImageUrl?: string | null };
};

export default function SuggestionsPage() {
  const [items, setItems] = useState<Item[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    const r = await fetch("/api/suggestions/pending");
    if (!r.ok) return;
    const d = await r.json();
    setItems(d.suggestions);
  }, []);
  useEffect(() => { refresh(); }, [refresh]);

  useEffect(() => {
    if (!selectedId) { setDetail(null); return; }
    fetch(`/api/suggestions/${selectedId}`).then((r) => (r.ok ? r.json() : null)).then(setDetail);
  }, [selectedId]);

  async function runAction(path: string, body: unknown = {}) {
    setError(null);
    const res = await fetch(path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      if (res.status === 409) setError("이미 다른 운영자가 처리했습니다.");
      else setError(`오류: ${res.status}`);
    }
    await refresh();
    setSelectedId(null);
  }

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <QueueList
        title="수정 제안 큐"
        items={items.map((s) => ({ id: s._id, ...s })) as any}
        selectedId={selectedId}
        onSelect={setSelectedId}
        renderItem={(raw) => {
          const s = raw as unknown as Item;
          const fields = [
            s.changes.name != null && "이름",
            s.changes.latitude != null && "좌표",
            s.changes.coverImageUrl != null && "커버",
          ].filter(Boolean);
          return (
            <>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "#8b93a7" }}>
                <span>{new Date(s.createdAt).toLocaleString()}</span>
                <span>by @{s.requester?.profileId ?? "?"}</span>
              </div>
              <div style={{ marginTop: 4, fontWeight: 600 }}>{s.place.name}</div>
              <div style={{ marginTop: 3, fontSize: 11, color: "#6bb4ff" }}>
                제안: {fields.join(", ") || "—"}
              </div>
            </>
          );
        }}
      />
      {detail ? (
        <SuggestionDiff
          detail={detail}
          onApprove={() => runAction(`/api/suggestions/${detail._id}/approve`)}
          onReject={(reason) => runAction(`/api/suggestions/${detail._id}/reject`, reason ? { reason } : {})}
        />
      ) : (
        <div style={{ flex: 1, padding: 24, color: "#6b7388" }}>큐에서 항목을 선택하세요.</div>
      )}
      {error ? (
        <div style={{ position: "fixed", bottom: 20, right: 20, background: "#2b1d1d", border: "1px solid #d04848", borderRadius: 6, padding: "10px 14px", color: "#ffb3b3" }}>
          {error}
        </div>
      ) : null}
    </div>
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add apps/admin/src/components/suggestion-diff.tsx apps/admin/src/app/suggestions/page.tsx
git commit -m "$(cat <<'EOF'
feat(admin): suggestions review page with diff + APPROVE/REJECT

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 9 — Manual end-to-end smoke (no automated UI tests)

### Task 29: Local manual smoke and README update

**Files:**
- Create: `apps/admin/README.md`

- [ ] **Step 1: Create `apps/admin/README.md`**

```markdown
# besetter admin

Local-only Next.js app for operators to review pending gyms and place suggestions.

## Setup

1. `cp .env.local.example .env.local` and fill in credentials.
2. Ensure MongoDB is running as a replica set (required for MERGE transactions):
   ```bash
   docker run --rm -p 27017:27017 mongo:7 --replSet rs0
   # in another shell:
   docker exec -it <container> mongosh --eval 'rs.initiate()'
   ```
3. `pnpm install`

## Dev loop

```bash
pnpm dev     # http://localhost:3000
pnpm test    # vitest
```

## Auth

Google OAuth restricted to `@olivebagel.com` domain + `ADMIN_EMAIL_ALLOWLIST` env.

## FCM push

Push dispatch is off by default (`ADMIN_FCM_ENABLED=false`). Set to `true` to
actually send to device tokens. Without it, notifications are still inserted
into MongoDB so mobile will see them on next fetch; only push fan-out is
skipped.

## Notification templates

When adding/editing a template, update BOTH:
- `services/api/app/services/notification_templates.py`
- `apps/admin/src/lib/notification-templates.ts`
```

- [ ] **Step 2: Manual smoke — run these by hand, ticking each:**

- [ ] `pnpm dev` in `apps/admin` starts the server without error
- [ ] Visiting `http://localhost:3000` unauthenticated redirects to `/signin`
- [ ] Signing in with a non-olivebagel.com account is rejected
- [ ] Signing in with a non-allowlisted olivebagel.com account is rejected
- [ ] Signing in with an allowlisted account lands on `/places` with the sidebar
- [ ] Sidebar shows pending counts that match the DB
- [ ] Clicking a queue item loads the detail panel with counts and nearby list
- [ ] `PASS` removes the item from the queue and flips the place to `approved` in the DB
- [ ] `FAIL` with reason stores `rejectedReason` on the place
- [ ] `MERGE` opens the dialog, 1km list shows target, name search filters the list
- [ ] Confirming MERGE marks source `merged`, re-parents images + activity snapshots, and inserts a notification
- [ ] On the suggestions page, diff cards show current vs proposed
- [ ] `APPROVE` on a name-only suggestion updates place's `name` + `normalizedName`
- [ ] `REJECT` marks the suggestion rejected and inserts a notification

- [ ] **Step 3: Commit README**

```bash
git add apps/admin/README.md
git commit -m "$(cat <<'EOF'
docs(admin): add README for setup, dev loop, and template sync rule

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review (run by the plan author; fix inline as needed)

**Spec coverage:**
- [x] apps/admin scaffold with Next.js App Router — Task 1–2
- [x] Google OAuth hd=olivebagel.com + allowlist — Task 7–9
- [x] MongoDB direct driver + singleton — Task 3
- [x] TS types mirroring camelCase collections — Task 4
- [x] Firebase Admin SDK push, dev gate — Task 13
- [x] Two review views (places / suggestions) — Task 26, 28
- [x] 5 new notification templates — both sides — Task 11, 12
- [x] `Place.rejected_reason` — Task 10
- [x] getPendingPlaces — Task 15
- [x] getPlaceDetail with counts + nearby — Task 17
- [x] getMergeCandidates (1km + name search) — Task 18
- [x] PASS — Task 19
- [x] FAIL (reason) — Task 20
- [x] MERGE (transaction) — Task 21
- [x] Suggestion list/detail — Task 22
- [x] Suggestion approve (per-field) — Task 23
- [x] Suggestion reject — Task 24
- [x] Sidebar with counts — Task 25
- [x] Input validation with zod — Task 18, 20, 21, 24
- [x] Dev safety via ADMIN_FCM_ENABLED — Task 13
- [x] Operator audit log to stdout — embedded in each route (Task 19–24)

**Placeholder scan:** none.

**Type consistency:** `AdminOpError` is defined in `place-ops.ts` Task 19 and reused in `suggestion-ops.ts` Task 22/23/24 — cross-file import is explicit. `AdminNotificationType` in `notifications.ts` Task 14 matches `NotificationType` union added in `db-types.ts` Task 4.

**Gaps checked:** spec's "Place 모델 확장 (FastAPI/TS)" handled by Task 10 (Python) + Task 4 (TS). Spec's "검색 노출 차단" is a no-op (already enforced by existing API filters); no task needed.
