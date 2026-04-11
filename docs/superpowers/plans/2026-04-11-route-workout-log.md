# Route Workout Log Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a workout log panel to the Route Viewer that shows the user's activity history and stats for that route, with a "completed only" filter toggle, cursor-based pagination, and activity deletion.

**Architecture:** Two new API endpoints (GET my-stats, GET my-activities) in the existing activities router. One new Flutter widget (WorkoutLogPanel) placed in the Route Viewer between the ActivityPanel and route info section. The activity list uses cursor-based pagination (10 per page) with scrollable container (3.5 items visible height).

**Tech Stack:** FastAPI + Beanie (MongoDB) for API, Flutter + StatefulWidget for mobile UI, Pydantic v2 with camelCase aliases.

---

## File Structure

**API (services/api/):**
- Modify: `app/models/activity.py` — extend Activity index to include `startedAt`
- Modify: `app/routers/activities.py` — add GET my-stats and GET my-activities endpoints
- Create: `tests/routers/test_activity_list.py` — tests for new endpoints

**Mobile (apps/mobile/):**
- Modify: `lib/services/activity_service.dart` — add `getMyStats()` and `getMyActivities()` methods
- Create: `lib/widgets/viewers/workout_log_panel.dart` — the workout log widget
- Modify: `lib/pages/viewers/route_viewer.dart` — insert WorkoutLogPanel
- Modify: `lib/l10n/app_ko.arb` — add Korean translations
- Modify: `lib/l10n/app_en.arb` — add English translations
- Modify: `lib/l10n/app_ja.arb` — add Japanese translations
- Modify: `lib/l10n/app_es.arb` — add Spanish translations

---

### Task 1: Extend Activity Index

**Files:**
- Modify: `services/api/app/models/activity.py:58-61`

- [ ] **Step 1: Update the index definition**

In `services/api/app/models/activity.py`, change the second index from `(routeId, userId)` to `(routeId, userId, startedAt)`:

```python
# In class Activity.Settings.indexes, change:
IndexModel([("routeId", ASCENDING), ("userId", ASCENDING)]),
# to:
IndexModel([("routeId", ASCENDING), ("userId", ASCENDING), ("startedAt", ASCENDING)]),
```

- [ ] **Step 2: Run existing tests to verify no breakage**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/ -v`
Expected: All existing tests PASS

- [ ] **Step 3: Commit**

```bash
git add services/api/app/models/activity.py
git commit -m "feat(api): extend activity index with startedAt for list query"
```

---

### Task 2: Add GET my-stats API Endpoint

**Files:**
- Modify: `services/api/app/routers/activities.py`
- Create: `tests/routers/test_activity_list.py`

- [ ] **Step 1: Write the test for my-stats response schema**

Create `services/api/tests/routers/test_activity_list.py`:

```python
from app.routers.activities import MyStatsResponse


def test_my_stats_response_schema():
    """MyStatsResponse should serialize with camelCase aliases."""
    stats = MyStatsResponse(
        total_count=5,
        total_duration=1234.56,
        completed_count=3,
        completed_duration=987.65,
        verified_completed_count=2,
        verified_completed_duration=600.12,
    )
    dumped = stats.model_dump(by_alias=True)
    assert dumped["totalCount"] == 5
    assert dumped["completedDuration"] == 987.65
    assert dumped["verifiedCompletedCount"] == 2
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/routers/test_activity_list.py -v`
Expected: FAIL with `ImportError: cannot import name 'MyStatsResponse'`

- [ ] **Step 3: Add MyStatsResponse and the endpoint**

In `services/api/app/routers/activities.py`, add the response model and endpoint:

```python
# Add response model after existing ActivityResponse class:

class MyStatsResponse(BaseModel):
    model_config = model_config

    total_count: int = 0
    total_duration: float = 0
    completed_count: int = 0
    completed_duration: float = 0
    verified_completed_count: int = 0
    verified_completed_duration: float = 0


# Add endpoint after existing delete_activity endpoint:

@router.get("/{route_id}/my-stats", response_model=MyStatsResponse)
async def get_my_stats(
    route_id: str,
    current_user: User = Depends(get_current_user),
):
    stats = await UserRouteStats.find_one(
        UserRouteStats.user_id == current_user.id,
        UserRouteStats.route_id == ObjectId(route_id),
    )
    if not stats:
        return MyStatsResponse()

    return MyStatsResponse(
        total_count=stats.total_count,
        total_duration=stats.total_duration,
        completed_count=stats.completed_count,
        completed_duration=stats.completed_duration,
        verified_completed_count=stats.verified_completed_count,
        verified_completed_duration=stats.verified_completed_duration,
    )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/routers/test_activity_list.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/activities.py tests/routers/test_activity_list.py
git commit -m "feat(api): add GET my-stats endpoint for route workout log"
```

---

### Task 3: Add GET my-activities API Endpoint with Cursor Pagination

**Files:**
- Modify: `services/api/app/routers/activities.py`
- Modify: `tests/routers/test_activity_list.py`

- [ ] **Step 1: Write tests for the list response schema and cursor helpers**

Append to `services/api/tests/routers/test_activity_list.py`:

```python
from datetime import datetime, timezone
from app.routers.activities import (
    MyActivitiesResponse,
    ActivityListItem,
    _encode_activity_cursor,
    _decode_activity_cursor,
)


def test_activity_list_item_schema():
    """ActivityListItem should serialize with camelCase aliases."""
    item = ActivityListItem(
        id="507f1f77bcf86cd799439011",
        status="completed",
        location_verified=True,
        started_at=datetime(2023, 10, 25, 14, 20, 0, tzinfo=timezone.utc),
        ended_at=datetime(2023, 10, 25, 15, 5, 12, tzinfo=timezone.utc),
        duration=2712.0,
        created_at=datetime(2023, 10, 25, 14, 20, 0, tzinfo=timezone.utc),
    )
    dumped = item.model_dump(by_alias=True)
    assert dumped["locationVerified"] is True
    assert dumped["startedAt"] == datetime(2023, 10, 25, 14, 20, 0, tzinfo=timezone.utc)
    assert "started_at" not in dumped


def test_my_activities_response_schema():
    """MyActivitiesResponse should have activities list and nextCursor."""
    resp = MyActivitiesResponse(activities=[], next_cursor=None)
    dumped = resp.model_dump(by_alias=True)
    assert dumped["activities"] == []
    assert dumped["nextCursor"] is None


def test_encode_decode_activity_cursor():
    """Cursor encode/decode should round-trip correctly."""
    cursor = _encode_activity_cursor("2023-10-25T14:20:00+00:00", "507f1f77bcf86cd799439011")
    started_at_str, last_id = _decode_activity_cursor(cursor)
    assert started_at_str == "2023-10-25T14:20:00+00:00"
    assert last_id == "507f1f77bcf86cd799439011"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/routers/test_activity_list.py -v`
Expected: FAIL with `ImportError`

- [ ] **Step 3: Add response models, cursor helpers, and the endpoint**

In `services/api/app/routers/activities.py`, add at the top with existing imports:

```python
import base64
from typing import Optional, List
```

Add response models after `MyStatsResponse`:

```python
class ActivityListItem(BaseModel):
    model_config = model_config

    id: str
    status: ActivityStatus
    location_verified: bool
    started_at: datetime
    ended_at: datetime
    duration: float
    created_at: datetime


class MyActivitiesResponse(BaseModel):
    model_config = model_config

    activities: List[ActivityListItem]
    next_cursor: Optional[str] = None
```

Add cursor helpers before the endpoints section:

```python
def _encode_activity_cursor(started_at_iso: str, last_id: str) -> str:
    cursor_str = f"{started_at_iso}|{last_id}"
    return base64.b64encode(cursor_str.encode()).decode()


def _decode_activity_cursor(cursor: str) -> tuple[str, str]:
    decoded = base64.b64decode(cursor.encode()).decode()
    started_at_str, last_id = decoded.split("|")
    return started_at_str, last_id
```

Add the endpoint after `get_my_stats`:

```python
@router.get("/{route_id}/my-activities", response_model=MyActivitiesResponse)
async def get_my_activities(
    route_id: str,
    current_user: User = Depends(get_current_user),
    status: Optional[ActivityStatus] = None,
    limit: int = 10,
    cursor: Optional[str] = None,
):
    query_filters = [
        Activity.route_id == ObjectId(route_id),
        Activity.user_id == current_user.id,
    ]

    if status:
        query_filters.append(Activity.status == status)

    if cursor:
        started_at_str, last_id = _decode_activity_cursor(cursor)
        cursor_started_at = datetime.fromisoformat(started_at_str)
        cursor_id = ObjectId(last_id)
        # startedAt DESC, _id DESC: get items before cursor
        from beanie.odm.operators.find.comparison import LT
        from beanie.odm.operators.find.logical import Or, And
        from beanie.odm.operators.find.comparison import Eq

        query_filters.append(
            Or(
                LT(Activity.started_at, cursor_started_at),
                And(
                    Eq(Activity.started_at, cursor_started_at),
                    LT(Activity.id, cursor_id),
                ),
            )
        )

    activities = (
        await Activity.find(*query_filters)
        .sort([("started_at", -1), ("_id", -1)])
        .limit(limit + 1)
        .to_list()
    )

    has_next = len(activities) > limit
    next_cursor = None

    if has_next:
        activities = activities[:limit]
        last = activities[-1]
        next_cursor = _encode_activity_cursor(
            last.started_at.isoformat(), str(last.id)
        )

    return MyActivitiesResponse(
        activities=[
            ActivityListItem(
                id=str(a.id),
                status=a.status,
                location_verified=a.location_verified,
                started_at=a.started_at,
                ended_at=a.ended_at,
                duration=a.duration,
                created_at=a.created_at,
            )
            for a in activities
        ],
        next_cursor=next_cursor,
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/routers/test_activity_list.py -v`
Expected: All PASS

- [ ] **Step 5: Run all tests to verify no breakage**

Run: `cd /Users/htjo/besetter/services/api && python -m pytest tests/ -v`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add services/api/app/routers/activities.py tests/routers/test_activity_list.py
git commit -m "feat(api): add GET my-activities endpoint with cursor pagination"
```

---

### Task 4: Add i18n Strings for All Locales

**Files:**
- Modify: `apps/mobile/lib/l10n/app_ko.arb`
- Modify: `apps/mobile/lib/l10n/app_en.arb`
- Modify: `apps/mobile/lib/l10n/app_ja.arb`
- Modify: `apps/mobile/lib/l10n/app_es.arb`

- [ ] **Step 1: Add new translation keys to all 4 ARB files**

Add the following keys before the closing `}` in each file.

**app_ko.arb:**
```json
  "workoutLog": "운동 기록",
  "totalSessionsCount": "총 {count}회",
  "@totalSessionsCount": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "avgDurationLabel": "평균 {duration}",
  "@avgDurationLabel": {
    "placeholders": {
      "duration": {"type": "String"}
    }
  },
  "completedOnly": "완등만",
  "onSite": "ON-SITE",
  "noWorkoutRecords": "운동 기록이 없습니다",
  "deleteActivityConfirm": "이 기록을 삭제하시겠습니까?",
  "activityDeleted": "기록이 삭제되었습니다",
  "failedDeleteActivity": "기록 삭제에 실패했습니다"
```

**app_en.arb:**
```json
  "workoutLog": "WORKOUT LOG",
  "totalSessionsCount": "Total: {count} sessions",
  "@totalSessionsCount": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "avgDurationLabel": "Avg. Duration: {duration}",
  "@avgDurationLabel": {
    "placeholders": {
      "duration": {"type": "String"}
    }
  },
  "completedOnly": "Completed Only",
  "onSite": "ON-SITE",
  "noWorkoutRecords": "No workout records yet",
  "deleteActivityConfirm": "Delete this record?",
  "activityDeleted": "Record deleted",
  "failedDeleteActivity": "Failed to delete record"
```

**app_ja.arb:**
```json
  "workoutLog": "ワークアウトログ",
  "totalSessionsCount": "合計 {count}回",
  "@totalSessionsCount": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "avgDurationLabel": "平均 {duration}",
  "@avgDurationLabel": {
    "placeholders": {
      "duration": {"type": "String"}
    }
  },
  "completedOnly": "完登のみ",
  "onSite": "ON-SITE",
  "noWorkoutRecords": "ワークアウト記録がありません",
  "deleteActivityConfirm": "この記録を削除しますか？",
  "activityDeleted": "記録が削除されました",
  "failedDeleteActivity": "記録の削除に失敗しました"
```

**app_es.arb:**
```json
  "workoutLog": "REGISTRO DE EJERCICIO",
  "totalSessionsCount": "Total: {count} sesiones",
  "@totalSessionsCount": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "avgDurationLabel": "Duración promedio: {duration}",
  "@avgDurationLabel": {
    "placeholders": {
      "duration": {"type": "String"}
    }
  },
  "completedOnly": "Solo completados",
  "onSite": "ON-SITE",
  "noWorkoutRecords": "Aún no hay registros de ejercicio",
  "deleteActivityConfirm": "¿Eliminar este registro?",
  "activityDeleted": "Registro eliminado",
  "failedDeleteActivity": "No se pudo eliminar el registro"
```

- [ ] **Step 2: Run Flutter analyze**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/l10n/app_ko.arb apps/mobile/lib/l10n/app_en.arb apps/mobile/lib/l10n/app_ja.arb apps/mobile/lib/l10n/app_es.arb
git commit -m "feat(mobile): add i18n strings for workout log panel"
```

---

### Task 5: Add Flutter Service Methods for Stats and Activities

**Files:**
- Modify: `apps/mobile/lib/services/activity_service.dart`

- [ ] **Step 1: Add getMyStats method**

In `apps/mobile/lib/services/activity_service.dart`, add after the `deleteActivity` method:

```dart
  /// Get the current user's stats for a specific route.
  static Future<Map<String, dynamic>> getMyStats({
    required String routeId,
  }) async {
    final response = await AuthorizedHttpClient.get(
      '/routes/$routeId/my-stats',
    );

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load stats. Status: ${response.statusCode}');
    }
  }
```

- [ ] **Step 2: Add getMyActivities method**

In the same file, add after `getMyStats`:

```dart
  /// Get the current user's activities for a specific route.
  ///
  /// [status] - Optional filter: "completed" for completed only, null for all.
  /// [limit] - Page size, default 10.
  /// [cursor] - Cursor for pagination, null for first page.
  static Future<Map<String, dynamic>> getMyActivities({
    required String routeId,
    String? status,
    int limit = 10,
    String? cursor,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      if (status != null) 'status': status,
      if (cursor != null) 'cursor': cursor,
    };
    final uri = Uri.parse('/routes/$routeId/my-activities')
        .replace(queryParameters: queryParams);

    final response = await AuthorizedHttpClient.get(uri.toString());

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load activities. Status: ${response.statusCode}');
    }
  }
```

- [ ] **Step 3: Run Flutter analyze**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze`
Expected: No issues

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/services/activity_service.dart
git commit -m "feat(mobile): add service methods for my-stats and my-activities"
```

---

### Task 6: Build WorkoutLogPanel Widget

**Files:**
- Create: `apps/mobile/lib/widgets/viewers/workout_log_panel.dart`

- [ ] **Step 1: Create the WorkoutLogPanel widget**

Create `apps/mobile/lib/widgets/viewers/workout_log_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../services/activity_service.dart';

class WorkoutLogPanel extends StatefulWidget {
  final String routeId;

  const WorkoutLogPanel({
    required this.routeId,
    Key? key,
  }) : super(key: key);

  @override
  State<WorkoutLogPanel> createState() => _WorkoutLogPanelState();
}

class _WorkoutLogPanelState extends State<WorkoutLogPanel> {
  // Stats (loaded once)
  Map<String, dynamic>? _stats;
  bool _statsLoading = true;

  // Activities list
  List<Map<String, dynamic>> _activities = [];
  bool _activitiesLoading = true;
  String? _nextCursor;
  bool _loadingMore = false;

  // Filter
  bool _completedOnly = true;

  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadStats();
    _loadActivities();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 50 &&
        !_loadingMore &&
        _nextCursor != null) {
      _loadMoreActivities();
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await ActivityService.getMyStats(routeId: widget.routeId);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _statsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statsLoading = false;
      });
    }
  }

  Future<void> _loadActivities() async {
    setState(() {
      _activitiesLoading = true;
      _activities = [];
      _nextCursor = null;
    });

    try {
      final result = await ActivityService.getMyActivities(
        routeId: widget.routeId,
        status: _completedOnly ? 'completed' : null,
      );
      if (!mounted) return;
      setState(() {
        _activities = List<Map<String, dynamic>>.from(result['activities']);
        _nextCursor = result['nextCursor'] as String?;
        _activitiesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activitiesLoading = false;
      });
    }
  }

  Future<void> _loadMoreActivities() async {
    if (_loadingMore || _nextCursor == null) return;

    setState(() {
      _loadingMore = true;
    });

    try {
      final result = await ActivityService.getMyActivities(
        routeId: widget.routeId,
        status: _completedOnly ? 'completed' : null,
        cursor: _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        _activities.addAll(
          List<Map<String, dynamic>>.from(result['activities']),
        );
        _nextCursor = result['nextCursor'] as String?;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
      });
    }
  }

  void _toggleFilter() {
    setState(() {
      _completedOnly = !_completedOnly;
    });
    _loadActivities();
  }

  Future<void> _deleteActivity(String activityId) async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.deleteActivityConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ActivityService.deleteActivity(
        routeId: widget.routeId,
        activityId: activityId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.activityDeleted)),
      );
      // Refresh both stats and activities
      _loadStats();
      _loadActivities();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedDeleteActivity)),
      );
    }
  }

  String _formatAvgDuration(double totalDuration, int count) {
    if (count == 0) return '00:00:00';
    final avg = totalDuration / count;
    final hours = (avg / 3600).floor().toString().padLeft(2, '0');
    final minutes = ((avg % 3600) / 60).floor().toString().padLeft(2, '0');
    final seconds = (avg % 60).floor().toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatDuration(double durationSeconds) {
    final hours = (durationSeconds / 3600).floor().toString().padLeft(2, '0');
    final minutes = ((durationSeconds % 3600) / 60).floor().toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).floor().toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  /// Group activities by date, returning a list of (dateLabel, activities) pairs.
  List<MapEntry<String, List<Map<String, dynamic>>>> _groupByDate() {
    final locale = AppLocalizations.of(context)!.localeName;
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final activity in _activities) {
      final startedAt = DateTime.parse(activity['startedAt'] as String);
      final dateKey = DateFormat.yMMMMd(locale).format(startedAt.toLocal()).toUpperCase();
      grouped.putIfAbsent(dateKey, () => []).add(activity);
    }

    return grouped.entries.toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Don't show panel if stats are still loading or there are no activities at all
    if (_statsLoading) return const SizedBox.shrink();
    if (_stats != null && (_stats!['totalCount'] as int) == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6E8EA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(l10n),
            if (_activitiesLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_activities.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    l10n.noWorkoutRecords,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF595C5D),
                    ),
                  ),
                ),
              )
            else
              _buildActivityList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    // Select stats based on filter
    int count = 0;
    double duration = 0;
    if (_stats != null) {
      if (_completedOnly) {
        count = (_stats!['completedCount'] as num).toInt();
        duration = (_stats!['completedDuration'] as num).toDouble();
      } else {
        count = (_stats!['totalCount'] as num).toInt();
        duration = (_stats!['totalDuration'] as num).toDouble();
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.workoutLog,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF595C5D),
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _toggleFilter,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _completedOnly
                        ? const Color(0xFF0066FF)
                        : const Color(0xFFE6E8EA),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n.completedOnly,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _completedOnly ? Colors.white : const Color(0xFF595C5D),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.totalSessionsCount(count)} | ${l10n.avgDurationLabel(_formatAvgDuration(duration, count))}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF595C5D),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityList() {
    final groups = _groupByDate();

    // Build flat list of widgets for the scrollable area
    final List<Widget> items = [];
    for (final group in groups) {
      // Date header
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            group.key,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF22C55E),
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
      // Activity rows
      for (final activity in group.value) {
        items.add(_buildActivityRow(activity));
      }
    }

    // Loading indicator at bottom
    if (_loadingMore) {
      items.add(
        const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    // 3.5 items visible: each item ~72px height → container ~252px
    return SizedBox(
      height: 252,
      child: ListView(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        children: items,
      ),
    );
  }

  Widget _buildActivityRow(Map<String, dynamic> activity) {
    final startedAt = DateTime.parse(activity['startedAt'] as String).toLocal();
    final timeStr = DateFormat.Hm().format(startedAt);
    final duration = (activity['duration'] as num).toDouble();
    final isCompleted = activity['status'] == 'completed';
    final isVerified = activity['locationVerified'] == true;
    final activityId = activity['id'] as String;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time + duration column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2C2F30),
                      ),
                    ),
                    if (isVerified && isCompleted) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 12,
                              color: Color(0xFF22C55E),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              l10n.onSite,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Duration: ${_formatDuration(duration)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF595C5D),
                  ),
                ),
              ],
            ),
          ),
          // Completed label
          if (isCompleted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0066FF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l10n.completed,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0066FF),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Delete button
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: GestureDetector(
              onTap: () => _deleteActivity(activityId),
              child: const Icon(
                Icons.delete_outline,
                size: 20,
                color: Color(0xFF595C5D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run Flutter analyze**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/workout_log_panel.dart
git commit -m "feat(mobile): create WorkoutLogPanel widget"
```

---

### Task 7: Integrate WorkoutLogPanel into Route Viewer

**Files:**
- Modify: `apps/mobile/lib/pages/viewers/route_viewer.dart`

- [ ] **Step 1: Add import and insert the widget**

In `apps/mobile/lib/pages/viewers/route_viewer.dart`:

Add import at the top with the existing viewer imports:

```dart
import '../../widgets/viewers/workout_log_panel.dart';
```

Insert `WorkoutLogPanel` between the `ActivityPanel` widget and the divider `Container`. Find these lines (around line 313-318):

```dart
                  // Activity panel (slide-to-start / timer / confirmation)
                  ActivityPanel(routeId: widget.routeData.id),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    height: 1,
                    color: Colors.grey.shade300,
                  ),
```

Change to:

```dart
                  // Activity panel (slide-to-start / timer / confirmation)
                  ActivityPanel(routeId: widget.routeData.id),
                  // Workout log (stats + activity list)
                  WorkoutLogPanel(routeId: widget.routeData.id),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    height: 1,
                    color: Colors.grey.shade300,
                  ),
```

- [ ] **Step 2: Run Flutter analyze**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/pages/viewers/route_viewer.dart
git commit -m "feat(mobile): integrate WorkoutLogPanel into Route Viewer"
```

---

### Task 8: Refresh Workout Log After Activity Create/Delete

**Files:**
- Modify: `apps/mobile/lib/pages/viewers/route_viewer.dart`
- Modify: `apps/mobile/lib/widgets/viewers/activity_panel.dart`
- Modify: `apps/mobile/lib/widgets/viewers/workout_log_panel.dart`

The WorkoutLogPanel needs to refresh when a new activity is created (via ActivityPanel) or when an activity is deleted (from within WorkoutLogPanel itself — already handled in Task 6). For the create case, we need a way for ActivityPanel to notify WorkoutLogPanel.

- [ ] **Step 1: Add a GlobalKey-based refresh to WorkoutLogPanel**

In `apps/mobile/lib/widgets/viewers/workout_log_panel.dart`, add a public method to the State class:

```dart
class _WorkoutLogPanelState extends State<WorkoutLogPanel> {
  // ... existing code ...

  /// Called externally to refresh stats and activities (e.g., after new activity created).
  void refresh() {
    _loadStats();
    _loadActivities();
  }

  // ... rest of existing code ...
}
```

- [ ] **Step 2: Wire up refresh in Route Viewer**

In `apps/mobile/lib/pages/viewers/route_viewer.dart`:

Add a GlobalKey field in `_RouteViewerState`:

```dart
  final _workoutLogKey = GlobalKey<dynamic>();
```

Update the WorkoutLogPanel widget to use the key:

```dart
                  WorkoutLogPanel(
                    key: _workoutLogKey,
                    routeId: widget.routeData.id,
                  ),
```

- [ ] **Step 3: Add onActivityCreated callback to ActivityPanel**

In `apps/mobile/lib/widgets/viewers/activity_panel.dart`, add an optional callback:

```dart
class ActivityPanel extends StatefulWidget {
  final String routeId;
  final VoidCallback? onActivityCreated;

  const ActivityPanel({
    required this.routeId,
    this.onActivityCreated,
    Key? key,
  }) : super(key: key);
```

In `_onFinish` method, after `setState` and confetti, call the callback:

```dart
      // After setState block, add:
      widget.onActivityCreated?.call();
```

- [ ] **Step 4: Connect the callback in Route Viewer**

In `apps/mobile/lib/pages/viewers/route_viewer.dart`, update the ActivityPanel:

```dart
                  ActivityPanel(
                    routeId: widget.routeData.id,
                    onActivityCreated: () {
                      (_workoutLogKey.currentState as dynamic).refresh();
                    },
                  ),
```

- [ ] **Step 5: Run Flutter analyze**

Run: `cd /Users/htjo/besetter/apps/mobile && flutter analyze`
Expected: No issues

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/workout_log_panel.dart apps/mobile/lib/widgets/viewers/activity_panel.dart apps/mobile/lib/pages/viewers/route_viewer.dart
git commit -m "feat(mobile): refresh workout log after activity create"
```
