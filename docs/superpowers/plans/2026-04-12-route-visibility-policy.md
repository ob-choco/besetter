# Route Visibility Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route의 PUBLIC/PRIVATE visibility 정책을 동작시킨다 — 편집기에 토글 UI, 비공개 루트의 상세 진입 차단, 활동 카드에 상태 배지.

**Architecture:** 백엔드 `GET /routes/{id}`는 소유자가 아니면 PUBLIC만 통과하고 PRIVATE은 `403 {reason:"private"}`, `?withActivityCheck=true`이면 소유자 응답에 `hasOtherUserActivities` 플래그 포함. `GET /my/daily-routes`는 $lookup으로 각 루트의 `routeVisibility`/`isDeleted`를 동봉. 모바일 편집기는 Switch로 visibility를 로컬 state로 관리하다가 저장 버튼에서 bundled PATCH, 일간 카드는 상태에 따라 배지 렌더, 카드 탭에서 받은 403/404를 토스트+`Navigator.pop`으로 처리.

**Tech Stack:** FastAPI + Beanie ODM (MongoDB) + Pytest (backend), Flutter + Riverpod (mobile), 기존 `AuthorizedHttpClient` HTTP 헬퍼, 기존 `RouteData` 모델 확장.

---

## File Structure

**Backend (`services/api`)**

| 파일 | 변경 내용 |
|---|---|
| `app/routers/routes.py` | `_can_access_route` 헬퍼 추가, `RouteDetailView.has_other_user_activities` 필드 추가, `GET /routes/{id}` 핸들러 확장 (비소유자 PUBLIC 통과, PRIVATE 403, `?withActivityCheck=true`로 활동 존재 여부 계산) |
| `app/routers/my.py` | `DailyRouteItem.route_visibility`, `DailyRouteItem.is_deleted` 필드 추가, `get_daily_routes` 파이프라인에 `routes` 컬렉션 `$lookup` 단계 추가 |
| `tests/routers/test_routes.py` (신규) | `_can_access_route` 정책 단위 테스트, `RouteDetailView`/`GetRouteForbidden` 스키마 테스트 |
| `tests/routers/test_my.py` | `DailyRouteItem` 스키마에 새 필드 노출 테스트 추가 |

**Mobile (`apps/mobile`)**

| 파일 | 변경 내용 |
|---|---|
| `lib/models/route_data.dart` | `visibility`, `hasOtherUserActivities` 필드 추가 (`fromJson`/`toJson`) |
| `lib/pages/editors/route_editor_page.dart` | `_visibility`/`_hasOtherUserActivities` state, Switch UI 한 줄, `_loadExistingRoute`에 `?withActivityCheck=true` 쿼리 추가, PUBLIC→PRIVATE 시 확인 다이얼로그, `_saveRoute` 바디에 `visibility` 포함 |
| `lib/pages/my_page.dart` | `_DailyRouteCard`에 visibility/deleted 상태 표시용 한 줄 배지, `_navigateToRoute`에서 403/404 분기 |
| `lib/main.dart` | 딥링크의 `_navigateToRoute`에서 403/404 분기 |

---

## Task 1: Backend — Route access control helper

**Files:**
- Modify: `services/api/app/routers/routes.py`
- Create: `services/api/tests/routers/test_routes.py`

- [ ] **Step 1: Create failing tests for `_can_access_route`**

Create `services/api/tests/routers/test_routes.py`:

```python
from types import SimpleNamespace

from bson import ObjectId

from app.models.route import Visibility
from app.routers.routes import _can_access_route


def _make_route(owner_id: ObjectId, visibility: Visibility) -> SimpleNamespace:
    return SimpleNamespace(user_id=owner_id, visibility=visibility)


def _make_user(user_id: ObjectId) -> SimpleNamespace:
    return SimpleNamespace(id=user_id)


def test_owner_can_access_public_route():
    uid = ObjectId()
    assert _can_access_route(_make_route(uid, Visibility.PUBLIC), _make_user(uid)) is True


def test_owner_can_access_private_route():
    uid = ObjectId()
    assert _can_access_route(_make_route(uid, Visibility.PRIVATE), _make_user(uid)) is True


def test_non_owner_can_access_public_route():
    owner = ObjectId()
    viewer = ObjectId()
    assert _can_access_route(_make_route(owner, Visibility.PUBLIC), _make_user(viewer)) is True


def test_non_owner_cannot_access_private_route():
    owner = ObjectId()
    viewer = ObjectId()
    assert _can_access_route(_make_route(owner, Visibility.PRIVATE), _make_user(viewer)) is False


def test_non_owner_can_access_unlisted_route():
    """UNLISTED is only blocked from discovery, not from direct access (matches share.py)."""
    owner = ObjectId()
    viewer = ObjectId()
    assert _can_access_route(_make_route(owner, Visibility.UNLISTED), _make_user(viewer)) is True
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/htjo/besetter/services/api && pytest tests/routers/test_routes.py -v
```

Expected: `ImportError` or `AttributeError` on `_can_access_route` — function not yet defined.

- [ ] **Step 3: Implement `_can_access_route` helper**

In `services/api/app/routers/routes.py`, add the helper function near the top of the file (after imports, before the first `@router.*` decorator). The function takes a `Route`-like object and a `User`-like object and returns a bool:

```python
def _can_access_route(route, user) -> bool:
    """Return True if `user` may access `route`.

    Owner: always allowed (any visibility).
    Non-owner: allowed unless visibility is explicitly PRIVATE.
    UNLISTED is treated like PUBLIC for direct access (matches share.py).
    """
    if route.user_id == user.id:
        return True
    return route.visibility != Visibility.PRIVATE
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/htjo/besetter/services/api && pytest tests/routers/test_routes.py -v
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/routes.py services/api/tests/routers/test_routes.py
git commit -m "feat(api): add route access control helper"
```

---

## Task 2: Backend — `RouteDetailView.hasOtherUserActivities` field

**Files:**
- Modify: `services/api/app/routers/routes.py:66-73` (RouteDetailView)
- Modify: `services/api/tests/routers/test_routes.py` (append)

- [ ] **Step 1: Write failing schema test**

Append to `services/api/tests/routers/test_routes.py`:

```python
from app.routers.routes import RouteDetailView  # noqa: E402  (import near top is fine)


def test_route_detail_view_has_optional_activity_flag():
    """RouteDetailView must expose `hasOtherUserActivities` as optional camelCase field."""
    fields = RouteDetailView.model_fields
    assert "has_other_user_activities" in fields
    # Optional → default None, not required
    assert fields["has_other_user_activities"].is_required() is False


def test_route_detail_view_serializes_activity_flag_camel_case():
    """When set, the flag must serialize as `hasOtherUserActivities`."""
    view = RouteDetailView.model_construct(
        has_other_user_activities=True,
    )
    dumped = view.model_dump(by_alias=True, exclude_none=True)
    assert dumped.get("hasOtherUserActivities") is True
```

(Move the `from app.routers.routes import RouteDetailView` import to the top of the file alongside `_can_access_route`.)

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/htjo/besetter/services/api && pytest tests/routers/test_routes.py::test_route_detail_view_has_optional_activity_flag -v
```

Expected: AssertionError — `has_other_user_activities` not in `model_fields`.

- [ ] **Step 3: Add field to `RouteDetailView`**

In `services/api/app/routers/routes.py`, update the `RouteDetailView` class (around line 66-73) to add the new optional field:

```python
class RouteDetailView(Route):
    model_config = model_config

    place: Optional[PlaceView] = Field(None, description="장소 정보")
    wall_name: Optional[str] = Field(None, description="벽 이름")
    wall_expiration_date: Optional[datetime] = Field(None, description="벽 만료 일자")

    polygons: List[HoldPolygonData]

    has_other_user_activities: Optional[bool] = Field(
        None,
        description="다른 사용자가 이 루트로 활동 기록을 남겼는지 (소유자 + withActivityCheck=true 때만 채움)",
    )
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/htjo/besetter/services/api && pytest tests/routers/test_routes.py -v
```

Expected: all tests pass (including the two new schema tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/routes.py services/api/tests/routers/test_routes.py
git commit -m "feat(api): add RouteDetailView.hasOtherUserActivities field"
```

---

## Task 3: Backend — `GET /routes/{id}` authorization + `withActivityCheck`

**Files:**
- Modify: `services/api/app/routers/routes.py:373-389` (get_route handler)

This task has no unit test — existing test style is pure schema/helper, and the endpoint requires DB. The access helper from Task 1 already covers the policy logic.

- [ ] **Step 1: Add `Query` import if missing**

In `services/api/app/routers/routes.py`, ensure `Query` is imported from fastapi:

```python
from fastapi import APIRouter, Depends, HTTPException, Query, status
```

(Check the existing import line and add `Query` if not there.)

- [ ] **Step 2: Replace `get_route` handler**

Replace the existing `get_route` function (around lines 373-389) with:

```python
@router.get("/{route_id}", response_model=RouteDetailView)
async def get_route(
    route_id: str,
    with_activity_check: bool = Query(False, alias="withActivityCheck"),
    current_user: User = Depends(get_current_user),
):
    route = await Route.find_one(
        Route.id == ObjectId(route_id),
        Route.is_deleted != True,
    )
    if not route:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Route not found")

    if not _can_access_route(route, current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"reason": "private"},
        )

    blob_path = extract_blob_path_from_url(route.image_url)
    if blob_path:
        route.image_url = HttpUrl(generate_signed_url(blob_path))
    if route.overlay_image_url:
        overlay_blob_path = extract_blob_path_from_url(route.overlay_image_url)
        if overlay_blob_path:
            route.overlay_image_url = HttpUrl(generate_signed_url(overlay_blob_path))

    detail = await _enrich_route_with_hold_polygon_data(route)

    is_owner = route.user_id == current_user.id
    if is_owner and with_activity_check:
        has_other = (
            await Activity.find(
                Activity.route_id == route.id,
                Activity.user_id != current_user.id,
            )
            .limit(1)
            .count()
        ) > 0
        detail.has_other_user_activities = has_other

    return detail
```

- [ ] **Step 3: Ensure `Activity` is imported**

At the top of `services/api/app/routers/routes.py`, confirm `Activity` is imported from `app.models.activity`. If not, add:

```python
from app.models.activity import Activity
```

- [ ] **Step 4: Run full test suite to check nothing broke**

```bash
cd /Users/htjo/besetter/services/api && pytest tests/ -v
```

Expected: no regressions. All previously passing tests still pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/routes.py
git commit -m "feat(api): extend GET /routes/{id} with visibility + withActivityCheck"
```

---

## Task 4: Backend — `DailyRouteItem` new fields

**Files:**
- Modify: `services/api/app/routers/my.py:88-103` (DailyRouteItem)
- Modify: `services/api/tests/routers/test_my.py:95-128` (daily routes schema test)

- [ ] **Step 1: Write failing test**

Update `test_daily_routes_response_schema` in `services/api/tests/routers/test_my.py`. Replace the existing `route_item = DailyRouteItem(...)` block and assertions with:

```python
def test_daily_routes_response_schema():
    """DailyRoutesResponse should serialize with camelCase aliases."""
    snapshot = RouteSnapshot(
        title="Morning Light",
        grade_type="v_grade",
        grade="V4",
        grade_color="#4CAF50",
        place_name="Urban Apex Gym",
    )
    route_item = DailyRouteItem(
        route_id="507f1f77bcf86cd799439011",
        route_snapshot=snapshot,
        route_visibility="public",
        is_deleted=False,
        total_count=3,
        completed_count=2,
        attempted_count=1,
        total_duration=845.50,
    )
    summary = DailySummary(
        total_count=3,
        completed_count=2,
        attempted_count=1,
        total_duration=845.50,
        route_count=1,
    )
    resp = DailyRoutesResponse(summary=summary, routes=[route_item])
    dumped = resp.model_dump(by_alias=True)

    assert dumped["summary"]["totalCount"] == 3
    assert dumped["summary"]["routeCount"] == 1
    assert len(dumped["routes"]) == 1
    assert dumped["routes"][0]["routeId"] == "507f1f77bcf86cd799439011"
    assert dumped["routes"][0]["routeSnapshot"]["gradeType"] == "v_grade"
    assert dumped["routes"][0]["routeVisibility"] == "public"
    assert dumped["routes"][0]["isDeleted"] is False
    assert dumped["routes"][0]["completedCount"] == 2
    assert dumped["routes"][0]["totalDuration"] == 845.50
```

Also append a new test for the private/deleted case:

```python
def test_daily_route_item_private_and_deleted_flags():
    snapshot = RouteSnapshot(grade_type="v_grade", grade="V2")
    item = DailyRouteItem(
        route_id="507f1f77bcf86cd799439012",
        route_snapshot=snapshot,
        route_visibility="private",
        is_deleted=True,
        total_count=1,
        completed_count=0,
        attempted_count=1,
        total_duration=12.0,
    )
    dumped = item.model_dump(by_alias=True)
    assert dumped["routeVisibility"] == "private"
    assert dumped["isDeleted"] is True
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/htjo/besetter/services/api && pytest tests/routers/test_my.py::test_daily_routes_response_schema tests/routers/test_my.py::test_daily_route_item_private_and_deleted_flags -v
```

Expected: `ValidationError` — `DailyRouteItem` does not yet accept `route_visibility` / `is_deleted`.

- [ ] **Step 3: Add fields to `DailyRouteItem`**

In `services/api/app/routers/my.py`, update the `DailyRouteItem` class (around lines 88-96). Add `Visibility` import at the top if missing:

```python
from app.models.route import Visibility
```

Then update the class:

```python
class DailyRouteItem(BaseModel):
    model_config = model_config

    route_id: str
    route_snapshot: RouteSnapshot
    route_visibility: Visibility = Visibility.PUBLIC
    is_deleted: bool = False
    total_count: int
    completed_count: int
    attempted_count: int
    total_duration: float
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/htjo/besetter/services/api && pytest tests/routers/test_my.py -v
```

Expected: all tests in `test_my.py` pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/my.py services/api/tests/routers/test_my.py
git commit -m "feat(api): add routeVisibility and isDeleted to DailyRouteItem"
```

---

## Task 5: Backend — `get_daily_routes` pipeline with $lookup

**Files:**
- Modify: `services/api/app/routers/my.py:158-217` (get_daily_routes)

This task has no unit test — the aggregation pipeline change needs a real DB. The schema-level change is already covered by Task 4 tests.

- [ ] **Step 1: Add `$lookup` and projection stages to the pipeline**

In `services/api/app/routers/my.py`, update the `get_daily_routes` handler. Replace the `pipeline = [...]` assignment with:

```python
    pipeline = [
        {"$match": {
            "userId": current_user.id,
            "startedAt": {"$gte": start_utc, "$lt": end_utc},
        }},
        {"$group": {
            "_id": "$routeId",
            "routeSnapshot": {"$first": "$routeSnapshot"},
            "totalCount": {"$sum": 1},
            "completedCount": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
            "attemptedCount": {"$sum": {"$cond": [{"$eq": ["$status", "attempted"]}, 1, 0]}},
            "totalDuration": {"$sum": "$duration"},
        }},
        {"$lookup": {
            "from": "routes",
            "localField": "_id",
            "foreignField": "_id",
            "as": "route",
            "pipeline": [
                {"$project": {"visibility": 1, "isDeleted": 1}},
            ],
        }},
        {"$set": {
            "routeVisibility": {
                "$ifNull": [{"$first": "$route.visibility"}, "public"],
            },
            "isDeleted": {
                "$ifNull": [{"$first": "$route.isDeleted"}, False],
            },
        }},
        {"$unset": "route"},
        {"$group": {
            "_id": None,
            "routes": {"$push": "$$ROOT"},
            "totalCount": {"$sum": "$totalCount"},
            "completedCount": {"$sum": "$completedCount"},
            "attemptedCount": {"$sum": "$attemptedCount"},
            "totalDuration": {"$sum": "$totalDuration"},
            "routeCount": {"$sum": 1},
        }},
    ]
```

- [ ] **Step 2: Update the `DailyRouteItem` construction to read new fields**

In the same handler, update the list comprehension at the bottom that builds `routes`:

```python
    routes = [
        DailyRouteItem(
            route_id=str(r["_id"]),
            route_snapshot=RouteSnapshot(**r["routeSnapshot"]),
            route_visibility=r.get("routeVisibility", "public"),
            is_deleted=r.get("isDeleted", False),
            total_count=r["totalCount"],
            completed_count=r["completedCount"],
            attempted_count=r["attemptedCount"],
            total_duration=r["totalDuration"],
        )
        for r in doc["routes"]
    ]
```

- [ ] **Step 3: Run full backend test suite**

```bash
cd /Users/htjo/besetter/services/api && pytest tests/ -v
```

Expected: no regressions.

- [ ] **Step 4: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/my.py
git commit -m "feat(api): attach routeVisibility and isDeleted to daily-routes"
```

---

## Task 6: Mobile — `RouteData` model new fields

**Files:**
- Modify: `apps/mobile/lib/models/route_data.dart`

- [ ] **Step 1: Add fields to `RouteData` class**

Open `apps/mobile/lib/models/route_data.dart`. Add two new fields to the field list and the constructor:

```dart
  final String visibility;
  final bool? hasOtherUserActivities;
```

Update the constructor parameter list to include:

```dart
    this.visibility = 'public',
    this.hasOtherUserActivities,
```

- [ ] **Step 2: Update `fromJson`**

In the `fromJson` factory method, add:

```dart
      visibility: json['visibility'] as String? ?? 'public',
      hasOtherUserActivities: json['hasOtherUserActivities'] as bool?,
```

- [ ] **Step 3: Update `toJson`**

In the `toJson` method, add to the returned map:

```dart
        'visibility': visibility,
        'hasOtherUserActivities': hasOtherUserActivities,
```

- [ ] **Step 4: Run analyzer**

```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/models/route_data.dart
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/models/route_data.dart
git commit -m "feat(mobile): add visibility and hasOtherUserActivities to RouteData"
```

---

## Task 7: Mobile — Visibility Switch UI in route editor

**Files:**
- Modify: `apps/mobile/lib/pages/editors/route_editor_page.dart`

- [ ] **Step 1: Add state variables**

In `_RouteEditorPageState` in `route_editor_page.dart`, add state variables alongside `_title`/`_description` (around line 85):

```dart
  String _visibility = 'public';
  bool _hasOtherUserActivities = false;
```

- [ ] **Step 2: Wire Switch into the build method**

In the `build()` method, locate the `Column` that contains `RouteInformationInput` (around line 780-843). Insert a new `Padding` widget directly AFTER the `RouteInformationInput(...)` and BEFORE the `Padding` holding the save button:

```dart
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5E8EC)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _visibility == 'public' ? '공개' : '비공개',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF2C2F30)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _visibility == 'public'
                                    ? '다른 사람도 이 루트를 볼 수 있어요.'
                                    : '다른 사람은 상세를 볼 수 없어요.',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF8A8F94)),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _visibility == 'public',
                          onChanged: (next) => _onVisibilityChanged(next),
                        ),
                      ],
                    ),
                  ),
                ),
```

- [ ] **Step 3: Add stub toggle handler**

Add this method somewhere inside `_RouteEditorPageState` (e.g. just above `_saveRoute`). In this task it's a plain setter — Task 8 will add the confirmation dialog:

```dart
  void _onVisibilityChanged(bool goingPublic) {
    setState(() {
      _visibility = goingPublic ? 'public' : 'private';
    });
  }
```

- [ ] **Step 4: Include `visibility` in save payload**

In `_saveRoute()` (around line 400-410), update the `routeData` map to include visibility:

```dart
      final Map<String, dynamic> routeData = {
        'type': _currentModeType == RouteEditModeType.bouldering ? 'bouldering' : 'endurance',
        'imageId': _imageData!.id,
        'gradeType': _selectedGradeType!.value,
        'grade': _selectedGrade,
        'gradeScore': _gradeScore,
        'gradeColor': _selectedGradeColor?.value.toRadixString(16).padLeft(8, '0'),
        'title': _title,
        'description': _description,
        'visibility': _visibility,
      };
```

- [ ] **Step 5: Restore `_visibility` from loaded route on edit**

In `_loadExistingRoute()` (around line 548-562), inside the `setState` that copies fields from `routeData`, add:

```dart
        _visibility = routeData.visibility;
```

- [ ] **Step 6: Run analyzer**

```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/pages/editors/route_editor_page.dart
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/pages/editors/route_editor_page.dart
git commit -m "feat(mobile): add visibility Switch to route editor"
```

---

## Task 8: Mobile — PUBLIC→PRIVATE confirmation dialog + `withActivityCheck`

**Files:**
- Modify: `apps/mobile/lib/pages/editors/route_editor_page.dart`

- [ ] **Step 1: Call GET with `withActivityCheck=true` on edit load**

In `_loadExistingRoute()` (around line 508), replace the existing GET line:

```dart
      final response = await AuthorizedHttpClient.get('/routes/${widget.routeId}');
```

with:

```dart
      final response = await AuthorizedHttpClient.get('/routes/${widget.routeId}?withActivityCheck=true');
```

- [ ] **Step 2: Store the flag after load**

In the same `setState` block that copies `_visibility` (added in Task 7), also set:

```dart
        _hasOtherUserActivities = routeData.hasOtherUserActivities ?? false;
```

- [ ] **Step 3: Replace `_onVisibilityChanged` with dialog-aware version**

Replace the stub from Task 7:

```dart
  Future<void> _onVisibilityChanged(bool goingPublic) async {
    if (goingPublic) {
      setState(() => _visibility = 'public');
      return;
    }

    if (!_hasOtherUserActivities) {
      setState(() => _visibility = 'private');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('비공개로 전환할까요?'),
        content: const Text(
          '다른 사람의 활동 기록에도 🔒 표시로 바뀌고 상세 진입이 막혀요. 계속할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('비공개로 전환'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed == true) {
      setState(() => _visibility = 'private');
    }
    // confirmed == false/null → Switch stays on `public`; the widget rebuilds
    // from _visibility which we didn't change.
  }
```

- [ ] **Step 4: Run analyzer**

```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/pages/editors/route_editor_page.dart
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/pages/editors/route_editor_page.dart
git commit -m "feat(mobile): warn before switching route to private"
```

---

## Task 9: Mobile — Daily route card private/deleted badge

**Files:**
- Modify: `apps/mobile/lib/pages/my_page.dart`

- [ ] **Step 1: Read new fields in `_DailyRouteCard.build`**

In `apps/mobile/lib/pages/my_page.dart`, locate `_DailyRouteCard.build` (around line 772). Below the existing `final imageUrl = ...;` line, add:

```dart
    final routeVisibility = route['routeVisibility'] as String? ?? 'public';
    final isDeleted = route['isDeleted'] as bool? ?? false;
    final isBlocked = isDeleted || routeVisibility == 'private';
    final blockedIcon = isDeleted ? '🗑' : '🔒';
    final blockedText = isDeleted ? '삭제된 루트입니다.' : '비공개된 루트입니다.';
```

- [ ] **Step 2: Insert a badge row into the top Column**

In the same method, find the inner top `Column` that renders grade badge / title / placeName (around line 826-840). After the `Text(placeName, ...)` widget, add a conditional badge:

```dart
                          Text(placeName, style: const TextStyle(fontSize: 12, color: Color(0xFF595C5D))),
                          if (isBlocked) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(blockedIcon, style: const TextStyle(fontSize: 11)),
                                const SizedBox(width: 4),
                                Text(
                                  blockedText,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF8A8F94),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
```

- [ ] **Step 3: Run analyzer**

```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/pages/my_page.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/pages/my_page.dart
git commit -m "feat(mobile): show private/deleted badge on daily route card"
```

---

## Task 10: Mobile — Handle 403/404 on route fetch (toast + no nav)

**Files:**
- Modify: `apps/mobile/lib/pages/my_page.dart` (`_DailyRouteCard._navigateToRoute`)
- Modify: `apps/mobile/lib/main.dart` (deep-link `_navigateToRoute`)

- [ ] **Step 1: Replace `_navigateToRoute` in `_DailyRouteCard`**

In `apps/mobile/lib/pages/my_page.dart`, replace the method (around line 861-877) with:

```dart
  Future<void> _navigateToRoute(BuildContext context, String routeId) async {
    try {
      final response = await AuthorizedHttpClient.get('/routes/$routeId');
      if (!context.mounted) return;

      if (response.statusCode == 200) {
        final routeData = RouteData.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RouteViewer(routeData: routeData)),
        );
        onReturn?.call();
        return;
      }

      if (response.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🔒 비공개된 루트입니다')),
        );
        return;
      }

      if (response.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🗑 삭제된 루트입니다')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('루트를 불러올 수 없습니다.')),
      );
    } catch (_) {
      // silently fail (network etc.)
    }
  }
```

- [ ] **Step 2: Replace deep-link `_navigateToRoute` in `main.dart`**

In `apps/mobile/lib/main.dart`, replace the handler (around line 126-144) with:

```dart
  Future<void> _navigateToRoute(String routeId) async {
    final response = await AuthorizedHttpClient.get('/routes/$routeId');
    if (!mounted) return;

    if (response.statusCode == 200) {
      final routeData = RouteData.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RouteViewer(routeData: routeData),
        ),
      );
      return;
    }

    if (response.statusCode == 403) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🔒 비공개된 루트입니다')),
      );
      return;
    }

    if (response.statusCode == 404) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🗑 삭제된 루트입니다')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('루트를 불러올 수 없습니다.')),
    );
  }
```

- [ ] **Step 3: Run analyzer on both files**

```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze lib/pages/my_page.dart lib/main.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/pages/my_page.dart apps/mobile/lib/main.dart
git commit -m "feat(mobile): show toast for private/deleted routes on tap"
```

---

## Final verification

After all tasks are complete, run both test suites once more:

```bash
cd /Users/htjo/besetter/services/api && pytest tests/ -v
cd /Users/htjo/besetter/apps/mobile && flutter analyze
```

Both should pass with no regressions.

## Spec coverage check

| Spec item | Task |
|---|---|
| GET /routes/{id} owner/non-owner/private/403 | Task 1, 3 |
| `hasOtherUserActivities` flag in response | Task 2, 3 |
| `withActivityCheck` query param | Task 3 |
| `DailyRouteItem.routeVisibility` | Task 4, 5 |
| `DailyRouteItem.isDeleted` | Task 4, 5 |
| Route editor visibility Switch UI (create + edit) | Task 7 |
| Route editor loads with `withActivityCheck=true` | Task 8 |
| PUBLIC→PRIVATE confirmation dialog gated on `hasOtherUserActivities` | Task 8 |
| visibility saved via bundled PATCH on save button | Task 7 |
| Daily route card shows 🔒/🗑 badge | Task 9 |
| route_viewer-style 403/404 handling (toast + pop / no nav) | Task 10 |
| RouteData Dart model fields | Task 6 |
