# Activity Tracking Design Spec

## Overview

BESETTER 앱에 운동 기록(Activity) 기능을 추가한다. 사용자가 루트를 시도할 때 위치 인증과 함께 활동을 기록하고, 완등/미완등 상태를 관리한다. Route별 통계(전체 합산 + 유저별)를 실시간 집계하고, 월간 캘린더는 Activity 컬렉션에서 aggregation으로 조회한다.

---

## 1. Data Model

### 1.1 Activity Document (독립 컬렉션)

`services/api/app/models/activity.py`에 새 Document 생성.

```python
class ActivityStatus(str, Enum):
    STARTED = "started"
    COMPLETED = "completed"
    ATTEMPTED = "attempted"

class RouteSnapshot(BaseModel):
    title: Optional[str]
    grade_type: str
    grade: str
    grade_color: Optional[str]
    place_id: Optional[PydanticObjectId]
    place_name: Optional[str]
    image_url: Optional[str]        # route.image_url
    overlay_image_url: Optional[str] # route.overlay_image_url

class Activity(Document):
    route_id: PydanticObjectId
    user_id: PydanticObjectId
    status: ActivityStatus = ActivityStatus.STARTED
    location_verified: bool = False
    started_at: datetime
    ended_at: Optional[datetime] = None
    duration: Optional[int] = None  # 초 단위
    route_snapshot: RouteSnapshot
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Settings:
        name = "activities"
        indexes = [
            IndexModel([("userId", ASCENDING), ("startedAt", ASCENDING)]),
            IndexModel([("routeId", ASCENDING), ("userId", ASCENDING), ("status", ASCENDING)]),
        ]
```

- Hard delete (soft delete 없음, `is_deleted` 필드 없음)
- `duration` = `ended_at - started_at` (초 단위 정수)
- `route_snapshot`은 Activity 생성 시 Route에서 복사

### 1.2 Route 문서에 activity_stats embed (전체 합산)

기존 `Route` Document에 필드 추가:

```python
class ActivityStats(BaseModel):
    total_count: int = 0
    total_duration: int = 0           # 초 단위 합계
    completed_count: int = 0
    completed_duration: int = 0
    verified_completed_count: int = 0
    verified_completed_duration: int = 0

class Route(Document):
    # ... 기존 필드 ...
    activity_stats: ActivityStats = Field(default_factory=ActivityStats)
```

- 평균 duration은 조회 시 `total_duration / total_count`로 계산
- count + sum 패턴으로 증감 갱신 가능

### 1.3 UserRouteStats Document (유저별 per-route)

`services/api/app/models/activity.py`에 함께 정의.

```python
class UserRouteStats(Document):
    user_id: PydanticObjectId
    route_id: PydanticObjectId
    total_count: int = 0
    total_duration: int = 0
    completed_count: int = 0
    completed_duration: int = 0
    verified_completed_count: int = 0
    verified_completed_duration: int = 0
    last_activity_at: Optional[datetime] = None

    class Settings:
        name = "userRouteStats"
        indexes = [
            IndexModel(
                [("userId", ASCENDING), ("routeId", ASCENDING)],
                unique=True,
            ),
        ]
```

---

## 2. API Endpoints

### 2.1 POST /routes/{routeId}/activity

운동 기록을 생성한다.

**Request Body:**
```json
{
  "latitude": 37.5665,
  "longitude": 126.9780,
  "status": "started",
  "endedAt": "2026-04-11T15:30:00Z"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| latitude | float | Yes | 현재 위치 위도 |
| longitude | float | Yes | 현재 위치 경도 |
| status | string | No | 기본값 "started". "completed" 또는 "attempted" 가능 |
| endedAt | datetime | Conditional | status가 "completed"/"attempted"일 때 필수 |

**처리 흐름:**

1. Route 존재 확인 (soft delete 포함 조회 불가)
2. Route → Image → place_id로 Place 조회 → location 좌표 획득
3. 요청 좌표와 Place 좌표 간 거리 계산 (Haversine) → 300m 이내면 `location_verified = true`
4. Place에 location이 없거나, Image에 place_id가 없으면 `location_verified = false`
5. 같은 route + 같은 user에 기존 "started" 상태 Activity가 있으면 → 자동으로 "attempted"로 변경 (ended_at = now, duration = min(now - started_at, 3600초). 1시간 초과 시 duration은 3600초로 캡핑)
6. 스냅샷 추출: Route에서 title, grade, grade_type, grade_color, image_url, overlay_image_url. Image(Route.image_id)에서 place_id → Place에서 place_name
7. Activity 문서 생성
8. status가 "completed"/"attempted"이면 duration 계산 (ended_at - started_at)
9. Route.activity_stats 갱신
10. UserRouteStats 갱신 (upsert)

**Response 201:**
```json
{
  "_id": "...",
  "routeId": "...",
  "status": "started",
  "locationVerified": true,
  "startedAt": "2026-04-11T14:00:00Z",
  "endedAt": null,
  "duration": null,
  "routeSnapshot": {
    "title": "Electric Drift",
    "gradeType": "v_scale",
    "grade": "V7",
    "gradeColor": "#FF5722",
    "placeId": "...",
    "placeName": "Urban Apex Gym",
    "imageUrl": "...(signed URL)",
    "overlayImageUrl": "...(signed URL)"
  },
  "createdAt": "2026-04-11T14:00:00Z"
}
```

### 2.2 PATCH /routes/{routeId}/activity/{activityId}

활동 상태를 종료(완등/미완등)로 변경한다.

**Request Body:**
```json
{
  "status": "completed",
  "endedAt": "2026-04-11T15:30:00Z"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| status | string | Yes | "completed" 또는 "attempted" |
| endedAt | datetime | Yes | 종료 시간 |

**처리 흐름:**

1. Activity 존재 확인 + 본인 소유 확인
2. 현재 status가 "started"인지 확인 (이미 종료된 건 수정 불가)
3. duration = endedAt - started_at (초)
4. Activity 업데이트 (status, ended_at, duration)
5. Route.activity_stats 갱신:
   - total_duration += duration
   - status가 "completed"면: completed_count += 1, completed_duration += duration
   - location_verified이고 "completed"면: verified_completed_count += 1, verified_completed_duration += duration
6. UserRouteStats 동일하게 갱신

**Response 200:** 업데이트된 Activity 객체.

### 2.3 DELETE /routes/{routeId}/activity/{activityId}

운동 기록을 삭제한다 (hard delete).

**처리 흐름:**

1. Activity 존재 확인 + 본인 소유 확인
2. 삭제 전 Activity의 status, duration, location_verified 확인
3. Route.activity_stats 감소 갱신:
   - total_count -= 1
   - status가 "completed"/"attempted"이면: total_duration -= duration
   - status가 "completed"면: completed_count -= 1, completed_duration -= duration
   - location_verified이고 "completed"면: verified_completed_count -= 1, verified_completed_duration -= duration
4. UserRouteStats 동일하게 감소 갱신
5. Activity 문서 삭제

**Response 204:** No content.

---

## 3. Stats 갱신 로직 상세

### 갱신 매트릭스

| 이벤트 | total_count | total_duration | completed_count | completed_duration | verified_completed_count | verified_completed_duration |
|---|---|---|---|---|---|---|
| POST (started) | +1 | — | — | — | — | — |
| POST (completed, verified) | +1 | +dur | +1 | +dur | +1 | +dur |
| POST (completed, unverified) | +1 | +dur | +1 | +dur | — | — |
| POST (attempted, verified) | +1 | +dur | — | — | — | — |
| POST (attempted, unverified) | +1 | +dur | — | — | — | — |
| PATCH → completed (verified) | — | +dur | +1 | +dur | +1 | +dur |
| PATCH → completed (unverified) | — | +dur | +1 | +dur | — | — |
| PATCH → attempted | — | +dur | — | — | — | — |
| DELETE (was started) | -1 | — | — | — | — | — |
| DELETE (was completed, verified) | -1 | -dur | -1 | -dur | -1 | -dur |
| DELETE (was completed, unverified) | -1 | -dur | -1 | -dur | — | — |
| DELETE (was attempted) | -1 | -dur | — | — | — | — |
| 자동취소 (started→attempted) | — | +dur* | — | — | — | — |

*자동취소 시 duration = min(now - started_at, 3600). 1시간 초과 시 3600초로 캡핑

Route.activity_stats와 UserRouteStats에 동일하게 적용.

---

## 4. 캘린더 데이터 조회

Activity 컬렉션에서 MongoDB aggregation으로 월별 운동 일수를 조회한다.

**Aggregation Pipeline:**
```python
[
    {"$match": {
        "userId": user_id,
        "startedAt": {"$gte": month_start, "$lt": month_end},
    }},
    {"$group": {
        "_id": {"$dayOfMonth": "$startedAt"},
        "count": {"$sum": 1},
    }},
]
```

결과: `[{_id: 1, count: 2}, {_id: 4, count: 1}, ...]` → 캘린더에서 운동한 날짜와 횟수를 표시.

인덱스 `(userId, startedAt)`가 이 쿼리를 커버.

### 4.2 일별 Activity 목록 조회

캘린더에서 날짜를 선택하면 해당 날짜의 Activity 목록을 조회하여 루트 리스트를 보여준다.

**Query:**
```python
Activity.find(
    Activity.user_id == user_id,
    Activity.started_at >= day_start,
    Activity.started_at < day_end,
).sort(-Activity.started_at)
```

결과의 `route_snapshot`에 title, grade, grade_color, place_name, image_url, overlay_image_url이 포함되어 있으므로 별도 Route join 없이 바로 카드 UI를 렌더링할 수 있다.

동일한 `(userId, startedAt)` 인덱스를 사용.

---

## 5. 위치 인증 로직

**Haversine 거리 계산:**

```python
from math import radians, sin, cos, sqrt, atan2

def haversine_distance(lat1, lon1, lat2, lon2) -> float:
    """두 좌표 간 거리를 미터 단위로 반환한다."""
    R = 6371000  # 지구 반지름 (미터)
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat/2)**2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon/2)**2
    return R * 2 * atan2(sqrt(a), sqrt(1-a))
```

- 인증 반경: **300m**
- Place에 location이 없으면: `location_verified = false` (에러 아님)
- 반경 밖이어도: Activity는 생성됨, `location_verified = false`로만 표시

---

## 6. User 삭제 시 처리

`DELETE /users/me` 엔드포인트에 Activity와 UserRouteStats hard delete 추가:

```python
# Activity hard delete
await Activity.find(Activity.user_id == current_user.id).delete()

# UserRouteStats hard delete
await UserRouteStats.find(UserRouteStats.user_id == current_user.id).delete()
```

기존 Route/Image/HoldPolygon soft delete 로직 다음에 추가.

Route.activity_stats는 전체 합산이므로 유저 삭제 시 재계산하지 않는다 (해당 유저의 기록도 전체 통계에 포함된 채로 유지).

---

## 7. 파일 구조

| 파일 | 역할 |
|---|---|
| `services/api/app/models/activity.py` | Activity, UserRouteStats, ActivityStats, RouteSnapshot 모델 |
| `services/api/app/routers/activities.py` | POST/PATCH/DELETE 엔드포인트 |
| `services/api/app/models/route.py` | Route에 activity_stats 필드 추가 |
| `services/api/app/routers/users.py` | 유저 삭제 시 Activity/UserRouteStats hard delete 추가 |
| `services/api/app/main.py` | activities 라우터 등록 |

---

## 8. Scope 외 (추후)

- 모바일 UI (Activity 생성/종료 화면)
- My Page 캘린더 실데이터 연동
- Route 상세 화면에서 activity_stats 표시
- 유저별 통계 조회 API (GET /users/me/stats)
- 활동 목록 조회 API (GET /routes/{routeId}/activities, GET /users/me/activities)
