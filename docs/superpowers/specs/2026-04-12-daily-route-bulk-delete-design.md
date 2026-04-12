# Daily Route Bulk Delete + Activity-Timezone Refactor Design

**Date:** 2026-04-12
**Status:** Draft

## Goal

두 가지를 같이 해결한다.

1. **Bulk delete:** 일일 운동 기록 카드에서 특정 루트의 하루치 액티비티를 한 번에 삭제할 수 있게 한다. 카드 우상단 오버플로 메뉴 → 확인 다이얼로그 → 삭제.
2. **Activity-timezone refactor:** `GET /my/daily-routes`, `GET /my/monthly-summary`, `GET /my/last-activity-date`가 현재는 caller-supplied 쿼리 `timezone`을 기준으로 그룹핑하는데, 각 활동에 이미 저장된 `Activity.timezone` 필드를 기준으로 그룹핑하도록 바꾼다. GET과 신규 DELETE가 완전히 같은 "하루" 정의를 공유하게 한다.

## Context

- `Activity` 모델에 `timezone: Optional[str]`(IANA TZ) 필드가 있지만, 집계 엔드포인트에서는 아직 읽지 않는다. 대신 쿼리 파라미터의 timezone으로 UTC 경계를 계산해서 `startedAt`으로 필터한다.
- 이 방식은 여행자 케이스에서 어긋난다. 활동을 했던 그 순간의 local date가 아니라 "지금 보고 있는 tz로 재해석한 date"로 그룹핑된다.
- Legacy row(timezone 필드가 비어 있는 활동)는 없는 것으로 확인됨.
- 기존 단일 삭제 `DELETE /{route_id}/activity/{activity_id}`는 그대로 유지하고 새 bulk 엔드포인트를 추가한다.
- Mobile `MyPage`는 HookConsumerWidget에 로컬 state로 달력/선택 날/daily routes payload/캐시를 들고 있다. 삭제 후 상태 갱신도 이 로컬 state 위에서 이루어진다.

## Policy Decisions

| # | 결정 | 내용 |
|---|---|---|
| 1 | 삭제 트리거 UI | 카드 우상단 ⋮ 오버플로 메뉴 → "삭제하기" 항목 |
| 2 | 확인 다이얼로그 | "해당 루트의 액티비티가 모두 삭제 됩니다. 삭제하시겠습니까?" / 취소 + 삭제 |
| 3 | API 모양 | `DELETE /my/daily-routes/{routeId}?date=YYYY-MM-DD` — GET /my/daily-routes의 역연산 |
| 4 | 응답 | `204 No Content` (멱등 — 매칭 0개여도 204) |
| 5 | Timezone 기준 | 세 GET + 신규 DELETE 모두 각 활동의 저장된 `timezone` 필드 기준으로 local date 계산 |
| 6 | 쿼리 `timezone` 파라미터 | 세 GET 모두에서 **제거**. 클라이언트 호출부도 정리 |
| 7 | 삭제 후 UI 갱신 | 로컬 state만 갱신 (daily-routes 재호출 없음) |
| 8 | 빈 날 이동 우선순위 | (a) 같은 달 이전 날 중 가장 가까운 → (b) 같은 달 이후 날 중 가장 가까운 → (c) `/last-activity-date` → (d) 빈 화면 |
| 9 | 집계 pre-filter | `(userId, startedAt)` 인덱스를 태우기 위해 UTC ±14h superset window로 선필터 |

## Out of Scope

- 개별 액티비티 삭제 (기존 단일 DELETE 유지)
- Undo/복원 (hard delete)
- 날짜 범위 삭제 (1일 단위만)
- MongoDB 트랜잭션으로 활동 삭제 + 스탯 감산 원자화 (drift는 로그로 수용)

## Architecture

### Backend (`services/api`)

| 파일 | 변경 |
|---|---|
| `app/routers/my.py` | 헬퍼 `_day_utc_superset`, `_month_utc_superset` 추가. `_day_utc_range` / `_month_utc_range` 는 `last-activity-date`가 쓰지 않게 되면 제거 |
| `app/routers/my.py` | `get_daily_routes` 파이프라인: UTC superset pre-filter → `$addFields localDate` → `$match localDate == date` 로 교체. 쿼리 `timezone` 파라미터 제거 |
| `app/routers/my.py` | `get_monthly_summary` 파이프라인: UTC superset pre-filter → `$addFields localYearMonth/localDay` (각 활동 `$timezone` 참조) → `$match` → `$group by localDay`. 쿼리 `timezone` 파라미터 제거 |
| `app/routers/my.py` | `get_last_activity_date`: 가장 최근 활동의 `timezone` 필드로 local date 계산. 쿼리 `timezone` 파라미터 제거 |
| `app/routers/my.py` | 신규 엔드포인트 `DELETE /my/daily-routes/{routeId}?date=YYYY-MM-DD` |
| `app/routers/activities.py` | 신규 헬퍼 `_merge_incs(list[dict]) -> dict` 공개(또는 my.py에서 import 가능한 위치). 단일 DELETE 로직과 재사용 가능한 구조 |
| `tests/routers/test_my.py` | `_day_utc_superset` / `_month_utc_superset` 유닛 테스트 추가. 기존 스키마 테스트는 그대로 통과해야 함 |
| `tests/routers/test_activities.py` (신규 또는 기존) | `_merge_incs` 유닛 테스트 |

### Mobile (`apps/mobile`)

| 파일 | 변경 |
|---|---|
| `lib/services/activity_service.dart` | `deleteDailyRouteGroup(routeId, date)` 신규. `getDailyRoutes`, `getMonthlySummary`, `getLastActivityDate`의 `timezone` 파라미터 제거 |
| `lib/services/http_client.dart` | `AuthorizedHttpClient.delete(path)` 메서드가 없으면 추가 |
| `lib/pages/my_page.dart` | `_DailyRouteCard`에 우상단 ⋮ `PopupMenuButton` 추가, `onDeleteConfirmed` 콜백 prop 추가 |
| `lib/pages/my_page.dart` | `MyPage` 빌드 로직에 `handleRouteGroupDelete(routeId)` 추가. 로컬 state 갱신 + 캐시 무효화 + 빈 날 처리 + last-activity-date 재조회 |
| `lib/pages/my_page.dart` | `loadDailyRoutes`, `loadMonthlySummary`, 초기 로드에서 `timezone` 인자 제거. `timezone` hook state 자체 제거 |

## API Contracts

### `DELETE /my/daily-routes/{route_id}`

**Path/Query:**
- `route_id: str` (path) — ObjectId 문자열
- `date: str` (query, required) — `YYYY-MM-DD` 정규식 패턴

**Responses:**
- `204 No Content` — 매칭 활동을 전부 삭제 (0개여도 204; 멱등)
- `400 Bad Request` — `date` 형식 오류 / `route_id` 형식 오류
- `401 Unauthorized` — 기존 auth 의존성

**인증:** `get_current_user`. 쿼리 조건에 `user_id == current_user.id` 포함 — 타인 루트 넘어오면 매칭 0개로 처리되어 자연스럽게 204.

### `GET /my/daily-routes`

- **변경 전:** `?date=YYYY-MM-DD&timezone=Asia/Seoul`
- **변경 후:** `?date=YYYY-MM-DD`
- 응답 모양은 동일. 그룹핑 기준만 각 활동의 `timezone` 필드로 이동.

### `GET /my/monthly-summary`

- **변경 전:** `?year=2026&month=4&timezone=Asia/Seoul`
- **변경 후:** `?year=2026&month=4`
- 응답 모양 동일. 활동 `timezone` 기준으로 "이 year/month에 속하는" 활동만 집계.

### `GET /my/last-activity-date`

- **변경 전:** `?timezone=Asia/Seoul`
- **변경 후:** 파라미터 없음
- 가장 최근 활동의 `started_at`을 그 활동의 `timezone`으로 변환해서 `YYYY-MM-DD` 반환.

## UTC Superset Windows

Timezone offset 범위는 `[UTC-12, UTC+14]`. 어떤 활동이든 그 활동의 local date가 `D`라면 `started_at`의 UTC 값은 `[D 00:00 UTC - 14h, (D+1) 00:00 UTC + 14h)` 안에 반드시 존재한다.

```python
def _day_utc_superset(date_str: str) -> tuple[datetime, datetime]:
    """UTC window guaranteed to contain every activity whose local date
    (in its own stored timezone) equals date_str. Padded ±14h to cover
    every possible IANA offset."""
    from datetime import timedelta
    year, month, day = map(int, date_str.split("-"))
    naive_day_start = datetime(year, month, day, tzinfo=timezone.utc)
    naive_day_end = naive_day_start + timedelta(days=1)
    return (
        naive_day_start - timedelta(hours=14),
        naive_day_end + timedelta(hours=14),
    )


def _month_utc_superset(year: int, month: int) -> tuple[datetime, datetime]:
    """UTC window guaranteed to contain every activity whose local year/month
    (in its own stored timezone) equals year/month. Padded ±14h."""
    from datetime import timedelta
    naive_month_start = datetime(year, month, 1, tzinfo=timezone.utc)
    if month == 12:
        naive_month_end = datetime(year + 1, 1, 1, tzinfo=timezone.utc)
    else:
        naive_month_end = datetime(year, month + 1, 1, tzinfo=timezone.utc)
    return (
        naive_month_start - timedelta(hours=14),
        naive_month_end + timedelta(hours=14),
    )
```

Superset window는 약 52시간(일 단위) 또는 `(한 달 + 28시간)`(월 단위). `(userId, startedAt)` 기존 복합 인덱스로 seek 가능.

## Aggregation Pipelines

### `get_daily_routes` (변경)

```python
utc_lo, utc_hi = _day_utc_superset(date)
pipeline = [
    {"$match": {
        "userId": current_user.id,
        "startedAt": {"$gte": utc_lo, "$lt": utc_hi},
    }},
    {"$addFields": {
        "localDate": {
            "$dateToString": {
                "format": "%Y-%m-%d",
                "date": "$startedAt",
                "timezone": {"$ifNull": ["$timezone", "UTC"]},
            }
        }
    }},
    {"$match": {"localDate": date}},
    {"$group": {
        "_id": "$routeId",
        "routeSnapshot": {"$first": "$routeSnapshot"},
        "totalCount": {"$sum": 1},
        "completedCount": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
        "attemptedCount": {"$sum": {"$cond": [{"$eq": ["$status", "attempted"]}, 1, 0]}},
        "totalDuration": {"$sum": "$duration"},
    }},
    # $lookup / $set / $unset / $group (global) — Route Visibility Policy 스펙과 동일
    ...
]
```

### `get_monthly_summary` (변경)

```python
utc_lo, utc_hi = _month_utc_superset(year, month)
year_month = f"{year:04d}-{month:02d}"
pipeline = [
    {"$match": {
        "userId": current_user.id,
        "startedAt": {"$gte": utc_lo, "$lt": utc_hi},
    }},
    {"$addFields": {
        "localYearMonth": {
            "$dateToString": {
                "format": "%Y-%m",
                "date": "$startedAt",
                "timezone": {"$ifNull": ["$timezone", "UTC"]},
            }
        },
        "localDay": {
            "$dayOfMonth": {
                "date": "$startedAt",
                "timezone": {"$ifNull": ["$timezone", "UTC"]},
            }
        },
    }},
    {"$match": {"localYearMonth": year_month}},
    {"$group": {"_id": "$localDay"}},
    {"$sort": {"_id": 1}},
]
```

### `get_last_activity_date` (변경)

```python
activity = (
    await Activity.find(Activity.user_id == current_user.id)
    .sort([("startedAt", -1)])
    .limit(1)
    .to_list()
)
if not activity:
    return LastActivityDateResponse()
a = activity[0]
tz_name = a.timezone or "UTC"
date_str = a.started_at.astimezone(ZoneInfo(tz_name)).strftime("%Y-%m-%d")
return LastActivityDateResponse(last_activity_date=date_str)
```

### DELETE 핸들러

```
1. date 정규식 검증 (Query pattern)
2. route_id ObjectId 변환
3. aggregation으로 매칭 활동 pull (UTC superset + localDate 재확인):
     pipeline = [
       {"$match": {"userId": uid, "routeId": rid,
                   "startedAt": {"$gte": utc_lo, "$lt": utc_hi}}},
       {"$addFields": {"localDate": {"$dateToString": {
           "format": "%Y-%m-%d", "date": "$startedAt",
           "timezone": {"$ifNull": ["$timezone", "UTC"]}}}}},
       {"$match": {"localDate": date}},
       {"$project": {"_id": 1, "status": 1, "locationVerified": 1, "duration": 1}},
     ]
4. matched == [] → return 204
5. 활동 ID 리스트 추출, cumulative inc 계산 (활동별 _build_stats_inc → _merge_incs)
6. pymongo delete_many({_id: {$in: ids}})  ← 먼저 hard delete
7. _update_route_stats(route_id, merged_inc)
8. _update_user_route_stats(current_user.id, route_id, merged_inc)
9. UserRouteStats 정리 (모든 카운트 <= 0 이면 문서 삭제) — 기존 단일 DELETE와 동일
10. return 204
```

**실행 순서:** 활동 삭제 먼저, 스탯 감산 나중. 중간 실패 시 drift 방향이 "stats가 약간 높게 잡힘"쪽이어서 다음 정상 활동으로 상쇄 가능.

## Helper: `_merge_incs`

```python
def _merge_incs(incs: list[dict]) -> dict:
    """Merge multiple $inc dicts by summing values of common keys."""
    merged: dict = {}
    for inc in incs:
        for key, value in inc.items():
            merged[key] = merged.get(key, 0) + value
    return merged
```

순수 함수. 유닛 테스트 가능.

## Mobile — UX Flow

### `_DailyRouteCard` 구조 변경

현재: 전체 카드가 `GestureDetector` → 탭 시 route_viewer 진입.

변경: 카드 콘텐츠 영역 상단 우측에 `PopupMenuButton<String>`(`icon: Icon(Icons.more_vert)`) 배치. `PopupMenuButton`은 자체 탭 영역을 소비하므로 바깥 `GestureDetector`의 route_viewer 진입과 충돌하지 않는다.

메뉴 항목:
- `PopupMenuItem(value: 'delete', child: Text('삭제하기', style: TextStyle(color: Colors.red)))`

선택 시:

```dart
final confirmed = await showDialog<bool>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('액티비티 삭제'),
    content: const Text('해당 루트의 액티비티가 모두 삭제 됩니다. 삭제하시겠습니까?'),
    actions: [
      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(true),
        child: const Text('삭제', style: TextStyle(color: Colors.red)),
      ),
    ],
  ),
);
if (confirmed == true) {
  onDeleteConfirmed?.call(routeId);
}
```

### `handleRouteGroupDelete` in `MyPage`

```dart
Future<void> handleRouteGroupDelete(BuildContext context, String routeId) async {
  final year = calendarYear.value;
  final month = calendarMonth.value;
  final day = selectedDay.value;
  if (day == null) return;
  final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  try {
    await ActivityService.deleteDailyRouteGroup(routeId: routeId, date: dateStr);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('삭제에 실패했어요. 잠시 후 다시 시도해주세요.')),
    );
    return;
  }

  final data = dailyRoutesData.value;
  if (data == null) return;
  final routes = List<Map<String, dynamic>>.from(data['routes'] ?? []);
  final removedIndex = routes.indexWhere((r) => r['routeId'] == routeId);
  if (removedIndex == -1) return;
  final removed = routes.removeAt(removedIndex);

  final newSummary = Map<String, dynamic>.from(data['summary'] as Map);
  newSummary['totalCount'] = (newSummary['totalCount'] as int) - ((removed['totalCount'] as int?) ?? 0);
  newSummary['completedCount'] = (newSummary['completedCount'] as int) - ((removed['completedCount'] as int?) ?? 0);
  newSummary['attemptedCount'] = (newSummary['attemptedCount'] as int) - ((removed['attemptedCount'] as int?) ?? 0);
  newSummary['totalDuration'] = (newSummary['totalDuration'] as num).toDouble() - ((removed['totalDuration'] as num?)?.toDouble() ?? 0.0);
  newSummary['routeCount'] = (newSummary['routeCount'] as int) - 1;

  dailyRoutesCache.value.remove(dateStr);
  final monthKey = '$year-${month.toString().padLeft(2, '0')}';
  monthlySummaryCache.value.remove(monthKey);

  if (routes.isNotEmpty) {
    dailyRoutesData.value = {'summary': newSummary, 'routes': routes};
    return;
  }

  // 이 날이 빈 날
  final updatedActiveDates = [...activeDates.value]..remove(day);
  activeDates.value = updatedActiveDates;
  dailyRoutesData.value = null;

  final previousDays = updatedActiveDates.where((d) => d < day).toList();
  if (previousDays.isNotEmpty) {
    final target = previousDays.reduce((a, b) => a > b ? a : b);
    selectedDay.value = target;
    await loadDailyRoutes(year, month, target);
    return;
  }

  final nextDays = updatedActiveDates.where((d) => d > day).toList();
  if (nextDays.isNotEmpty) {
    final target = nextDays.reduce((a, b) => a < b ? a : b);
    selectedDay.value = target;
    await loadDailyRoutes(year, month, target);
    return;
  }

  // 같은 달에 남은 날 없음 → last-activity-date
  final lastDate = await ActivityService.getLastActivityDate();
  if (!context.mounted) return;
  if (lastDate == null) {
    selectedDay.value = null;
    return;
  }
  final parts = lastDate.split('-').map(int.parse).toList();
  calendarYear.value = parts[0];
  calendarMonth.value = parts[1];
  selectedDay.value = parts[2];
  await Future.wait([
    loadMonthlySummary(parts[0], parts[1]),
    loadDailyRoutes(parts[0], parts[1], parts[2]),
  ]);
}
```

### `ActivityService` 변경

```dart
// 신규
static Future<void> deleteDailyRouteGroup({required String routeId, required String date}) async {
  final response = await AuthorizedHttpClient.delete('/my/daily-routes/$routeId?date=$date');
  if (response.statusCode != 204) {
    throw Exception('Delete failed: ${response.statusCode}');
  }
}

// 기존 메서드 시그니처 정리
static Future<Map<String, dynamic>> getDailyRoutes({required String date}) async { ... }
static Future<List<int>> getMonthlySummary({required int year, required int month}) async { ... }
static Future<String?> getLastActivityDate() async { ... }
```

`AuthorizedHttpClient.delete` 메서드가 없으면 기존 `get`/`patch` 패턴에 맞춰 추가.

## Edge Cases

- **매칭 0개:** 정상 동작. 서버 멱등 204, 클라이언트는 "지울 게 없음"이 성공 경로로 그대로 통과. 미래 날짜, 이미 다른 기기에서 지운 경우, 존재하지 않는 루트 모두 이 경로.
- **네트워크 실패:** 토스트 "삭제에 실패했어요..." + 로컬 state 건드리지 않음. 재시도 가능.
- **삭제 도중 스탯 감산 실패:** 활동은 이미 삭제됨 → stats가 drift(약간 높음). 로그 남김. 다음 정상 활동으로 상쇄.
- **타인 루트에 대한 DELETE:** `userId` 필터로 매칭 0개 → 204. 소유자 체크 불필요.
- **`Activity.timezone`이 null:** 사용자 확인으로 현재 DB에 없지만, 방어적으로 `$ifNull: ["$timezone", "UTC"]` 처리. 파이프라인이 터지지 않음.
- **여러 기기 동시 삭제:** 첫 번째가 끝난 뒤 두 번째는 매칭 0개 → 204.
- **Timezone 파라미터를 쓰는 기존 클라이언트가 남아있는 경우:** FastAPI는 모르는 쿼리 파라미터를 무시하므로 400 없음. 서버만 올라간 상태에서 구버전 클라이언트도 계속 동작.
- **Last-activity-date가 null인 상태로 전체 삭제 완료:** `selectedDay=null`, `dailyRoutesData=null`, 초기 상태와 동일한 빈 화면.
- **빈 날 점프 후 로드 실패:** 기존 `loadDailyRoutes` catch 블록이 `dailyRoutesData=null`로 처리. 삭제 flow 자체는 성공.

## Testing

### Backend 유닛 테스트

- `_day_utc_superset("2026-04-12")`
  - 하한 == `datetime(2026, 4, 11, 10, 0, 0, tzinfo=UTC)`
  - 상한 == `datetime(2026, 4, 13, 14, 0, 0, tzinfo=UTC)`
- `_day_utc_superset("2026-01-01")` — 연도 경계에서도 상하한이 깨지지 않는지
- `_month_utc_superset(2026, 4)`
  - 하한 == `datetime(2026, 3, 31, 10, 0, 0, tzinfo=UTC)`
  - 상한 == `datetime(2026, 5, 1, 14, 0, 0, tzinfo=UTC)`
- `_month_utc_superset(2026, 12)` — 연도 rollover
- `_merge_incs([])` → `{}`
- `_merge_incs([{"a": 1}, {"a": 2}, {"b": 3}])` → `{"a": 3, "b": 3}`
- 기존 `test_daily_routes_response_schema` / `test_monthly_summary_response_schema` / `test_last_activity_date_response_schema` 변경 없이 계속 통과

### Mobile

- `flutter analyze` — 변경 파일들에 새 issue 없어야 함
- 수동 테스트 시나리오:
  1. 같은 날 여러 루트 중 하나 삭제 → 그 카드만 제거, 다른 카드 유지, summary 감소
  2. 그 날의 마지막 루트 삭제 → 같은 달 이전 날 중 가까운 날로 이동
  3. 그 달에 이전 날 없음 + 이후 날 있음 → 이후 날 중 가까운 날로 이동
  4. 그 달에 남은 날 없음 → `/last-activity-date`가 반환한 날짜로 이동 (년/월 바뀜 가능)
  5. 전체 활동 삭제 후 → 빈 상태 + 달력만
  6. 동시에 두 번 같은 카드 삭제 (race) → 둘 다 성공 토스트 없이 종료, UI 정합

## Implementation Notes

- `_day_utc_superset` / `_month_utc_superset`는 완전히 timezone-agnostic이어서 `ZoneInfo`를 import할 필요 없음. `datetime` + `timedelta(hours=14)`만으로 충분.
- 기존 `_day_utc_range` / `_month_utc_range` 헬퍼는 이번 리팩터 이후 쓰는 곳이 없다. 구현 단계에서 삭제 여부를 확인하고 unused면 제거.
- DELETE 핸들러의 "활동 먼저 삭제 → 스탯 감산 나중" 순서는 의도적. 원자성이 깨질 때 drift 방향을 보수적으로 (stats가 약간 높게) 잡기 위함.
- `$ifNull: ["$timezone", "UTC"]` 는 defensive fallback. 현재 DB에는 null이 없다는 전제지만, 파이프라인이 null 필드에서 터지지 않도록 최소한의 안전장치.
- 구현 세부는 writing-plans 단계에서 구체화.
