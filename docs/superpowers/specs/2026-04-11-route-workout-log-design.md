# Route Workout Log Panel Design

## Overview

Route Viewer 화면에 사용자의 운동 기록 패널을 추가한다. UserRouteStats 통계와 Activity 리스트를 보여주며, "완등만" 필터 토글로 완등 기록만/전체 기록을 전환한다.

**Figma 참고:** `node-id=2053-2206`

## UI 구조

### 위치

Route Viewer에서 Activity Panel (slide-to-start) 바로 아래, Route 정보 섹션 위에 배치.

```
이미지 뷰어
홀드 목록
Activity Panel (slide-to-start)
━━━ Workout Log Panel (NEW) ━━━
구분선
Route 정보 (그레이드, 짐, 섹터 등)
```

### 레이아웃

```
┌─────────────────────────────────────────┐
│ WORKOUT LOG                    [완등만] │
│ Total: 3 sessions | Avg. Duration: 05:32│
├─────────────────────────────────────────┤
│ ┌─ 스크롤 영역 (3.5건 높이) ──────────┐ │
│ │ OCTOBER 25, 2023                    │ │
│ │                                     │ │
│ │ 14:20  [✓ ON-SITE]       완등  🗑   │ │
│ │ Duration: 00:45:12                  │ │
│ │                                     │ │
│ │ 09:15                    완등  🗑   │ │
│ │ Duration: 00:38:40                  │ │
│ │                                     │ │
│ │ 08:30  [✓ ON-SITE]             🗑   │ │
│ │ Duration: 00:12:05                  │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 헤더

- **타이틀**: "WORKOUT LOG"
- **통계 요약**: `Total: N sessions | Avg. Duration: HH:MM:SS`
  - "완등만" 활성 시: `completedCount`, `completedDuration / completedCount`
  - "완등만" 비활성 시: `totalCount`, `totalDuration / totalCount`
- **"완등만" 필터 토글 버튼**:
  - 기본: 활성화 (완등 기록만 표시)
  - 누르면 비활성화 (전체 기록 표시)
  - 다시 누르면 활성화

### Activity 항목

- **시작 시간**: `HH:mm` 포맷 (로케일 기반)
- **ON-SITE 뱃지**: `[✓ ON-SITE]` — 녹색 원 체크 아이콘 + 텍스트
  - `locationVerified == true && status == completed` 일 때만 표시
- **완등 라벨**: `status == completed` 일 때만 표시
- **미완등 항목**: 라벨 없음, ON-SITE 뱃지도 없음 (전체보기 모드에서만 노출)
- **삭제 버튼**: 휴지통 아이콘, 탭 시 해당 활동 삭제

### 날짜 그룹

- Activity를 날짜별로 그룹핑
- 날짜 포맷: 로케일에 따른 날짜 표시 (예: "OCTOBER 25, 2023", "2023년 10월 25일")

### 리스트 동작

- **고정 높이**: 3.5건이 보이는 높이의 컨테이너
- **내부 스크롤**: 컨테이너 내에서 스크롤
- **페이지네이션**: 10개씩 커서 기반, 스크롤 하단 도달 시 추가 로드
- **정렬**: `startedAt` DESC (최신순)

### 빈 상태

운동 기록이 없을 때 간단한 메시지 표시.

### 삭제 동작

- 기존 `DELETE /routes/{route_id}/activity/{activity_id}` 엔드포인트 사용
- 삭제 후 리스트 리프레시 + 헤더 통계 갱신

## API

### 새 엔드포인트 1: Stats

```
GET /routes/{route_id}/my-stats
```

- 한 번만 호출하여 헤더 통계에 사용
- 클라이언트에서 필터 상태에 따라 completed/total 값을 선택해 표시

**응답:**

```json
{
  "totalCount": 5,
  "totalDuration": 1234.56,
  "completedCount": 3,
  "completedDuration": 987.65,
  "verifiedCompletedCount": 2,
  "verifiedCompletedDuration": 600.12
}
```

### 새 엔드포인트 2: Activity 리스트

```
GET /routes/{route_id}/my-activities?status=completed&limit=10&cursor=<activity_id>
```

**쿼리 파라미터:**
- `status` (optional): `completed` — 완등만 필터. 생략 시 전체 반환
- `limit` (optional): 페이지 크기. 기본값 10
- `cursor` (optional): 마지막 activity ID. 커서 기반 페이지네이션

**응답:**

```json
{
  "activities": [
    {
      "id": "...",
      "status": "completed",
      "locationVerified": true,
      "startedAt": "2023-10-25T14:20:00Z",
      "endedAt": "2023-10-25T15:05:12Z",
      "duration": 2712.00,
      "createdAt": "..."
    }
  ],
  "nextCursor": "activity_id_or_null"
}
```

- `nextCursor`가 null이면 더 이상 데이터 없음
- 필터 토글 시 리스트만 다시 호출 (stats 재호출 불필요)

### 기존 엔드포인트 재활용

- `DELETE /routes/{route_id}/activity/{activity_id}` — 삭제 후 stats + 리스트 리프레시

## 인덱스

기존 인덱스 `(routeId, userId)`를 `(routeId, userId, startedAt)`로 확장한다.

**변경:**

```python
# 변경 전
IndexModel([("routeId", ASCENDING), ("userId", ASCENDING)])

# 변경 후
IndexModel([("routeId", ASCENDING), ("userId", ASCENDING), ("startedAt", ASCENDING)])
```

**이유:**
- 기존 `(routeId, userId)` 쿼리도 prefix로 여전히 커버
- 새 리스트 쿼리에서 필터 + 정렬 + 커서 페이지네이션을 인덱스만으로 처리
- MongoDB 역방향 스캔으로 ASC 인덱스에서 DESC 정렬 지원
- `status` 필터는 결과 수가 적으므로 인메모리로 충분

## Stats 갱신 방식

기존 `$inc` 기반 증분 방식 유지:
- Activity 생성 시 `sign=1`로 Route.activityStats + UserRouteStats 증가
- Activity 삭제 시 `sign=-1`로 감소
- Aggregation 불필요

## 다국어 (i18n)

새로 추가할 번역 키:
- `workoutLog`: "WORKOUT LOG" / "운동 기록" / "ワークアウトログ" / "REGISTRO DE EJERCICIO"
- `totalSessions`: "Total: {count} sessions"
- `avgDuration`: "Avg. Duration: {duration}"
- `completedOnly`: "완등만" / "Completed Only" / "完登のみ" / "Solo completados"
- `onSite`: "ON-SITE"
- `noWorkoutRecords`: "No workout records yet" / "운동 기록이 없습니다" / ...
