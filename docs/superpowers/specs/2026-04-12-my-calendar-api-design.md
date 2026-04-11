# MY Page Calendar API Integration Design

## Goal

MY 페이지의 월간 캘린더와 일별 운동 루트 리스트를 실제 API와 연동한다. 현재 mock 데이터로 구현된 캘린더와 최근 운동 섹션을 3개의 API endpoint로 교체한다.

## Architecture

3개의 독립적인 API endpoint로 구성:
1. **last-activity-date** — 초기 캘린더 월/일 결정
2. **monthly-summary** — 캘린더 dot 표시용 활동 날짜 목록
3. **daily-routes** — 선택된 날짜의 루트별 집계 데이터

기존 `(userId, startedAt)` 인덱스가 모든 쿼리를 커버하므로 인덱스 변경 없음. 타임존 기반 로컬 날짜 aggregation을 위해 Activity 모델에 `timezone` 필드 추가.

## Tech Stack

- API: FastAPI + Beanie (MongoDB ODM) + MongoDB Aggregation Pipeline
- Mobile: Flutter (HookConsumerWidget, flutter_timezone 패키지)
- Timezone: IANA timezone strings (e.g., "Asia/Seoul")

---

## 1. Activity 모델 변경

### 1.1 timezone 필드 추가

`Activity` 모델에 `timezone: str` 필드를 추가한다.

```python
class Activity(Document):
    ...
    timezone: str  # IANA timezone, e.g. "Asia/Seoul"
```

`CreateActivityRequest`에도 `timezone: str` 필드를 추가한다.

```python
class CreateActivityRequest(BaseModel):
    ...
    timezone: str
```

기존 Activity 문서에는 `timezone` 필드가 없으므로 `Optional[str]`로 선언하되, API에서는 필수로 받는다. 기존 데이터에 대해서는 fallback으로 `"Asia/Seoul"`을 사용한다 (현재 유저 기반).

---

## 2. API Endpoints

모든 endpoint는 `/my` prefix를 사용한다. 새로운 router 파일 `app/routers/my.py`에 구현한다.

### 2.1 GET /my/last-activity-date

현재 유저의 가장 최근 Activity의 startedAt을 로컬 날짜로 반환한다.

**Query Parameters:**
- `timezone: str` (required) — IANA timezone, e.g. "Asia/Seoul"

**Response:**
```json
{ "lastActivityDate": "2026-04-10" }
```
활동이 없으면:
```json
{ "lastActivityDate": null }
```

**구현:**
- `Activity.find(userId=current_user.id).sort(-startedAt).limit(1)`
- `startedAt`을 전달받은 timezone으로 변환하여 날짜 문자열(YYYY-MM-DD) 반환
- 인덱스: `(userId, startedAt)` 역방향 스캔

### 2.2 GET /my/monthly-summary

해당 월에 운동한 날짜 번호 리스트를 반환한다.

**Query Parameters:**
- `year: int` (required)
- `month: int` (required, 1-12)
- `timezone: str` (required)

**Response:**
```json
{ "activeDates": [1, 5, 9, 10, 12] }
```

**구현:**
MongoDB Aggregation Pipeline:
```python
[
    {"$match": {
        "userId": current_user_id,
        "startedAt": {"$gte": month_start_utc, "$lt": month_end_utc}
    }},
    {"$group": {
        "_id": {"$dayOfMonth": {"date": "$startedAt", "timezone": timezone}}
    }},
    {"$sort": {"_id": 1}}
]
```

- `month_start_utc` / `month_end_utc`는 전달받은 timezone 기준 월초/월말을 UTC로 변환한 값
- 인덱스: `(userId, startedAt)` range scan

### 2.3 GET /my/daily-routes

선택된 날짜의 Activity를 routeId별로 그룹핑하여 반환한다.

**Query Parameters:**
- `date: str` (required, "YYYY-MM-DD")
- `timezone: str` (required)

**Response:**
```json
{
    "routes": [
        {
            "routeId": "507f1f77bcf86cd799439011",
            "routeSnapshot": {
                "title": "Morning Light",
                "gradeType": "v_grade",
                "grade": "V4",
                "gradeColor": "#4CAF50",
                "placeId": "...",
                "placeName": "Urban Apex Gym",
                "imageUrl": "https://...",
                "overlayImageUrl": "https://..."
            },
            "totalCount": 3,
            "completedCount": 2,
            "attemptedCount": 1,
            "totalDuration": 845.50
        }
    ]
}
```

**구현:**
MongoDB Aggregation Pipeline:
```python
[
    {"$match": {
        "userId": current_user_id,
        "startedAt": {"$gte": day_start_utc, "$lt": day_end_utc}
    }},
    {"$group": {
        "_id": "$routeId",
        "routeSnapshot": {"$first": "$routeSnapshot"},
        "totalCount": {"$sum": 1},
        "completedCount": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
        "attemptedCount": {"$sum": {"$cond": [{"$eq": ["$status", "attempted"]}, 1, 0]}},
        "totalDuration": {"$sum": "$duration"}
    }}
]
```

- `day_start_utc` / `day_end_utc`는 전달받은 timezone 기준 해당 날짜의 00:00:00~23:59:59를 UTC로 변환
- 인덱스: `(userId, startedAt)` range scan (하루 범위, 매우 좁음)

---

## 3. Flutter 변경

### 3.1 의존성 추가

`flutter_timezone` 패키지 추가 — 기기의 IANA timezone 문자열 획득용.

### 3.2 Service Layer

`ActivityService`에 3개 메서드 추가:

```dart
static Future<String?> getLastActivityDate({required String timezone})
static Future<List<int>> getMonthlySummary({required int year, required int month, required String timezone})
static Future<List<Map<String, dynamic>>> getDailyRoutes({required String date, required String timezone})
```

`createActivity()` 호출 시 `timezone` 파라미터 추가.

### 3.3 MY Page 캘린더 변경

**상태:**
- `year`, `month` — 현재 표시 중인 캘린더 월
- `selectedDay` — 선택된 날짜 (null 가능)
- `activeDates` — 현재 월의 활동 날짜 목록
- `dailyRoutes` — 선택된 날짜의 루트 그룹 리스트

**초기 로드 시퀀스:**
1. `getLastActivityDate()` 호출
2. 응답의 날짜로 year/month/selectedDay 설정 (null이면 현재 월, selectedDay=null)
3. `getMonthlySummary()` + `getDailyRoutes()` 병렬 호출
4. 캘린더 렌더링 + 루트 리스트 표시

**월 이동:**
- 좌(←): 이전 월로 이동, selectedDay 초기화
- 우(→): 다음 월로 이동, selectedDay 초기화
- 최소 월: 2026년 4월 (이전 불가)
- 최대 월: 현재 월 (이후 불가)
- 월 이동 시 `getMonthlySummary()` 호출 (현재 월이면 매번, 과거 월이면 캐시 확인)

**날짜 선택:**
- `activeDates`에 포함된 날짜만 탭 가능
- 오늘 이후 날짜 비활성화 (탭 불가 + 흐린 스타일)
- 선택 시 `getDailyRoutes()` 호출 (과거 날짜는 캐시 확인, 오늘은 매번 호출)

**캐시 구조:**
```dart
Map<String, List<int>> _monthlySummaryCache;     // "2026-04" → [1, 5, 9, 10]
Map<String, List<RouteGroup>> _dailyRoutesCache;  // "2026-04-10" → [...]
```

캐시 조건:
| 대상 | 조건 | 캐시 |
|------|------|------|
| 현재 월 monthly-summary | 현재 월 | 매번 호출 |
| 과거 월 monthly-summary | 과거 월 | 캐시 |
| 오늘 daily-routes | 오늘 날짜 | 매번 호출 |
| 과거 daily-routes | 과거 날짜 | 캐시 |

### 3.4 _RecentWorkout → _DailyRoutes 교체

기존 `_RecentWorkout` 위젯을 `_DailyRoutes`로 교체. 선택된 날짜의 루트 그룹 카드 리스트를 표시:
- 루트 이미지 (imageUrl)
- 난이도 뱃지 (grade + gradeColor)
- 루트 이름 (title)
- 장소 (placeName)
- 횟수: 완등 N / 미완등 N
- 총 소요시간

활동이 아예 없는 유저 (lastActivityDate == null): 캘린더는 현재 월 표시, 아래 루트 리스트는 빈 상태.

### 3.5 Activity 생성 시 timezone 전송

`ActivityPanel`의 `createActivity()` 호출부에서 `flutter_timezone`으로 얻은 timezone 문자열을 함께 전송.

---

## 4. 인덱스

기존 `(userId, startedAt)` 인덱스가 3개 endpoint 모두 커버. 변경 불필요.

- `last-activity-date`: userId prefix + startedAt 역방향 스캔
- `monthly-summary`: userId prefix + startedAt 범위 스캔 → in-memory group
- `daily-routes`: userId prefix + startedAt 범위 스캔 (하루, 매우 좁음) → in-memory group
