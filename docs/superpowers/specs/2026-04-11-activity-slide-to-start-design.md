# Activity Slide-to-Start & Timer UI + API Simplification Design Spec

## Overview

Route Viewer 화면에 "등반 시작" 슬라이더와 타이머 패널을 추가한다. 동시에 Activity API를 단순화하여 PATCH 엔드포인트와 "started" 상태를 제거하고, POST에서 최종 결과만 저장하도록 변경한다.

---

## 1. API 변경사항

### 1.1 ActivityStatus 변경

`started` 상태를 제거한다. 타이머는 순수 클라이언트 로직이며 서버에는 최종 결과만 전송한다.

```python
class ActivityStatus(str, Enum):
    COMPLETED = "completed"
    ATTEMPTED = "attempted"
```

### 1.2 POST /routes/{routeId}/activity (수정)

클라이언트가 시작/종료 시간을 모두 전송한다. 서버는 최종 결과만 저장한다.

**Request Body:**
```json
{
  "latitude": 37.5665,
  "longitude": 126.9780,
  "status": "completed",
  "startedAt": "2026-04-11T14:00:00Z",
  "endedAt": "2026-04-11T14:02:34Z"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| latitude | float | Yes | 현재 위치 위도 |
| longitude | float | Yes | 현재 위치 경도 |
| status | string | Yes | "completed" 또는 "attempted" |
| startedAt | datetime | Yes | 등반 시작 시간 (클라이언트 기록) |
| endedAt | datetime | Yes | 등반 종료 시간 (클라이언트 기록) |

**변경점:**
- `status` 필수 (기본값 없음, "started" 제거)
- `startedAt` 필수 (클라이언트가 전송)
- `endedAt` 필수 (항상 종료된 상태로 저장)
- `duration` = `endedAt - startedAt` (서버에서 계산)

**제거되는 로직:**
- auto-cancel: 서버에 "started" 상태가 없으므로 불필요
- `AUTO_CANCEL_MAX_DURATION_S` 상수 제거

**Response 201:** 기존과 동일한 ActivityResponse.

### 1.3 PATCH 엔드포인트 제거

`PATCH /routes/{routeId}/activity/{activityId}` 를 완전히 제거한다. 클라이언트에서 최종 결과를 POST로 한번에 전송하므로 상태 업데이트가 불필요하다.

### 1.4 DELETE /routes/{routeId}/activity/{activityId} (유지)

변경 없음. 기존대로 hard delete + stats 감소.

### 1.5 Stats 갱신 매트릭스 (수정)

"started" 행이 제거되고, PATCH 행이 제거된다.

| 이벤트 | total_count | total_duration | completed_count | completed_duration | verified_completed_count | verified_completed_duration |
|---|---|---|---|---|---|---|
| POST (completed, verified) | +1 | +dur | +1 | +dur | +1 | +dur |
| POST (completed, unverified) | +1 | +dur | +1 | +dur | — | — |
| POST (attempted) | +1 | +dur | — | — | — | — |
| DELETE (was completed, verified) | -1 | -dur | -1 | -dur | -1 | -dur |
| DELETE (was completed, unverified) | -1 | -dur | -1 | -dur | — | — |
| DELETE (was attempted) | -1 | -dur | — | — | — | — |

### 1.6 인덱스 변경

`(routeId, userId, status)` 인덱스에서 `status` 제거 가능. auto-cancel 쿼리가 없으므로 `(routeId, userId)` 만으로 충분.
`(userId, startedAt)` 인덱스는 캘린더 조회용이므로 유지.

---

## 2. 모바일 UI

### 2.1 위치

Route Viewer (`route_viewer.dart`)의 홀드 목록과 루트 상세 정보 사이에 배치한다.

```
Column:
├── Image Viewer (BoulderingRouteImageViewer / EnduranceRouteImageViewer)
├── Hold List (BoulderingRouteHolds / EnduranceRouteHolds)
├── *** Slide-to-Start / Timer Panel (NEW) ***
├── Divider
└── Route Info (grade, gym, wall, expiry, description)
```

### 2.2 상태 전환 (3 States)

```
[Slider] ──swipe right──→ [Timer Panel] ──완등/미완등──→ [Confirmation] ──2초 or 확인──→ [Slider]
                                │
                                └──↻ 리셋──→ [Timer Panel] (타이머 초기화)
```

### 2.3 State 1: Slide-to-Start Bar

피그마 node `2053:2261` 참조.

- 파란 pill 배경 (`#0052D0`), border-radius 9999
- 왼쪽에 흰색 원형 핸들 (48x48, `>>` 아이콘)
- 중앙 텍스트: "등반 시작!" (white 70% opacity, 14px, uppercase, letter-spacing 1.4px)
- 그림자: `0px 10px 15px -3px rgba(0,0,0,0.1)`
- **동작:** 핸들을 오른쪽 끝까지 스와이프하면:
  1. 위치 인증 좌표 캡처 (GPS)
  2. 클라이언트 타이머 시작 (startedAt 기록)
  3. Timer Panel로 전환

### 2.4 State 2: Timer Panel

피그마 node `2053:2182` 참조.

- 흰색 카드, border 1px `#E6E8EA`, border-radius 16px
- 그림자: `0px 4px 20px rgba(0,0,0,0.08)`
- 상단: 녹색 점 (8px, `#22C55E`) + "DURATION" 라벨 (11px, bold, `#595C5D`)
- 타이머: `00:00:00` 형식 (36px, extra-bold, `#2C2F30`, letter-spacing -1.8px)
- 타이머는 1초 간격으로 실시간 업데이트
- 하단 버튼 그리드 (4-column, gap 12px):

| 버튼 | 크기 | 배경 | 동작 | API 호출 |
|------|------|------|------|---------|
| ↻ 리셋 | 1col | `#E6E8EA` | 타이머 초기화, 기록 없음 | 없음 |
| ✕ 미완등 | 1col | `#E6E8EA` | Activity 기록 | POST status=attempted |
| ✓ 완등 | 2col | `#0066FF` | Activity 기록 + confetti | POST status=completed |

### 2.5 State 3: Confirmation

완등/미완등 후 잠시 표시되는 확인 UI.

**완등 시:**
- 녹색 배경 카드 (`#F0FDF4`, border `#BBF7D0`)
- 체크 아이콘 (녹색 원)
- 메시지: "Sent!" (하드코딩)
  - TODO 주석: 추후 첫 완등이면 "Flash!" / "Onsight!", 이후 완등이면 "Sent!" / "Crushed it!" / "Allez!" 등 랜덤
- 소요 시간 표시 (예: "완등 · 2분 34초")
- 확인 버튼
- Confetti 애니메이션 (화면 전체)
- 2초 후 자동 dismiss (확인 버튼을 누르지 않으면)

**미완등 시:**
- 차분한 톤, confetti 없음
- 메시지: "기록되었습니다"
- 소요 시간 표시
- 확인 버튼
- 2초 후 자동 dismiss

### 2.6 위치 인증

기존 로직과 동일. 슬라이더를 스와이프하는 시점에 GPS 좌표를 캡처하여 POST 요청에 포함한다. 서버에서 Place 좌표와 비교하여 300m 이내이면 `locationVerified = true`.

### 2.7 에러 처리

- POST 실패 시: 토스트/스낵바로 에러 표시, 타이머 패널 유지 (재시도 가능)
- GPS 좌표 획득 실패 시: `latitude: 0, longitude: 0` 전송 → `locationVerified = false`

---

## 3. 파일 구조

### API (수정)
| 파일 | 변경 |
|---|---|
| `services/api/app/models/activity.py` | ActivityStatus에서 STARTED 제거 |
| `services/api/app/routers/activities.py` | PATCH 엔드포인트 제거, POST 단순화, auto-cancel 제거 |

### 모바일 (신규/수정)
| 파일 | 역할 |
|---|---|
| `apps/mobile/lib/widgets/viewers/slide_to_start.dart` | 슬라이드 바 위젯 |
| `apps/mobile/lib/widgets/viewers/activity_timer_panel.dart` | 타이머 패널 위젯 |
| `apps/mobile/lib/widgets/viewers/activity_confirmation.dart` | 확인 UI 위젯 |
| `apps/mobile/lib/services/activity_service.dart` | Activity POST/DELETE API 호출 |
| `apps/mobile/lib/pages/viewers/route_viewer.dart` | 위 위젯들 통합, 상태 관리 |

### 의존성
| 패키지 | 용도 |
|---|---|
| `confetti` (pub.dev) | 완등 시 confetti 애니메이션 |

---

## 4. Scope 외 (추후)

- 루트별 활동 기록 목록 조회 화면
- 첫 완등 여부에 따른 축하 메시지 분기 (Flash/Onsight vs Sent/Crushed)
- My Page 캘린더 실데이터 연동
- Route 상세 화면에서 activity_stats 표시
