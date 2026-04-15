# 장소 수정 제안 알림 시스템 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 유저가 장소 정보 수정 제안을 제출하면 감사 알림을 받아 MY 탭에서 확인할 수 있는 알림 시스템을 구축한다.

**Architecture:** 새 `notifications` 컬렉션과 `User.unreadNotificationCount` 필드를 추가하고, `POST /places/suggestions` 성공 시 제안자에게 알림 1건을 생성한다. 모바일은 GNB MY 아이콘 배지 + 별도 `NotificationsPage`로 노출. 카운터는 `$inc`만 사용하고 읽음 처리는 실제로 mark된 개수만 decrement해 동시성을 보장한다.

**Tech Stack:** FastAPI + Beanie ODM + MongoDB, Flutter (hooks_riverpod, StatefulWidget), Riverpod `keepAlive` provider.

**Spec:** `docs/superpowers/specs/2026-04-15-place-suggestion-notifications-design.md`

---

## File Structure

**Backend (`services/api/`)**
- Create: `app/models/notification.py` — `Notification` Beanie Document
- Modify: `app/models/user.py` — `unread_notification_count: int = 0` 필드 추가
- Modify: `app/main.py` — document_models에 Notification 등록
- Create: `app/routers/notifications.py` — `GET /notifications`, `POST /notifications/mark-read`
- Modify: `app/main.py` — notifications router include
- Modify: `app/routers/users.py` — `UserProfileResponse`에 `unread_notification_count` 추가, 클램프
- Modify: `app/routers/places.py` — `create_place_suggestion` 후처리에서 알림 생성 + 카운터 증가
- Create: `tests/routers/test_notifications.py` — 알림 핸들러 단위 테스트

**Mobile (`apps/mobile/`)**
- Modify: `lib/providers/user_provider.dart` — `UserState.unreadNotificationCount`
- Create: `lib/models/notification_data.dart` — `NotificationData` 모델
- Create: `lib/services/notification_service.dart` — `list`, `markRead`
- Create: `lib/pages/notifications_page.dart` — 알림 리스트 화면
- Modify: `lib/pages/main_tab.dart` — GNB MY 아이콘 `Badge.count`
- Modify: `lib/pages/my_page.dart` — AppBar 왼쪽 종 아이콘 + 배지, 탭 시 `NotificationsPage` 푸시
- Modify: `lib/widgets/editors/place_selection_sheet.dart` — `ConsumerStatefulWidget` 전환 + `onCompleted`에서 `ref.invalidate(userProfileProvider)`

---

## Task 1: Backend — Notification 모델 + User 필드 추가

**Files:**
- Create: `services/api/app/models/notification.py`
- Modify: `services/api/app/models/user.py`
- Modify: `services/api/app/main.py`

- [ ] **Step 1: Create `app/models/notification.py`**

```python
from datetime import datetime
from typing import Optional

from beanie import Document
from beanie.odm.fields import PydanticObjectId
from pydantic import Field
from pymongo import ASCENDING, DESCENDING, IndexModel

from . import model_config


class Notification(Document):
    model_config = model_config

    user_id: PydanticObjectId = Field(..., description="알림 수신자")
    type: str = Field(..., description="알림 타입 (place_suggestion_ack 등)")
    title: str = Field(..., description="알림 제목")
    body: str = Field(..., description="알림 본문 (렌더 완료된 스냅샷)")
    link: Optional[str] = Field(None, description="연결 경로. 저장만 하고 동작은 없음")
    read_at: Optional[datetime] = Field(None, description="읽은 시간")
    created_at: datetime = Field(..., description="생성 시간")

    class Settings:
        name = "notifications"
        indexes = [
            IndexModel([("userId", ASCENDING), ("createdAt", DESCENDING)]),
        ]
        keep_nulls = True
```

- [ ] **Step 2: Add `unread_notification_count` to `User` model**

Modify `services/api/app/models/user.py` — add field to `class User(Document)`:

```python
class User(Document):
    model_config = model_config

    name: Optional[str] = None
    email: Optional[str] = None
    profile_image_url: Optional[str] = None
    bio: Optional[str] = None
    unread_notification_count: int = 0

    refresh_token: Optional[str] = None
    # ... 이하 기존 필드 유지
```

- [ ] **Step 3: Register Notification in `app/main.py` document_models**

Find the line that initializes `init_beanie(... document_models=[...])` and add `Notification` import + entry:

```python
from app.models.notification import Notification as NotificationModel
# ...
await init_beanie(
    database=db,
    document_models=[
        OpenIdNonceModel,
        UserModel,
        HoldPolygonModel,
        ImageModel,
        RouteModel,
        PlaceModel,
        PlaceSuggestionModel,
        ActivityModel,
        UserRouteStatsModel,
        NotificationModel,
    ],
)
```

- [ ] **Step 4: Verify imports compile**

Run:
```bash
cd /Users/htjo/besetter/services/api && python -c "from app.models.notification import Notification; from app.models.user import User; print('ok')"
```
Expected: `ok`

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter && git add services/api/app/models/notification.py services/api/app/models/user.py services/api/app/main.py
git commit -m "$(cat <<'EOF'
feat(api): add Notification model and User.unread_notification_count

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Backend — `/notifications` 라우터 (list + mark-read)

**Files:**
- Create: `services/api/app/routers/notifications.py`
- Modify: `services/api/app/main.py`
- Test: `services/api/tests/routers/test_notifications.py`

- [ ] **Step 1: Write failing unit test for `list_notifications` serialization**

Create `services/api/tests/routers/test_notifications.py`:

```python
from datetime import datetime, timezone
from beanie.odm.fields import PydanticObjectId

from app.routers.notifications import notification_to_view


def test_notification_to_view_maps_all_fields():
    from app.models.notification import Notification

    now = datetime(2026, 4, 15, 12, 0, 0, tzinfo=timezone.utc)
    notif = Notification(
        id=PydanticObjectId("64b000000000000000000001"),
        user_id=PydanticObjectId("64b000000000000000000002"),
        type="place_suggestion_ack",
        title="정보 수정 제안이 접수되었습니다",
        body="클라이밍파크 강남점에 대한 소중한 제보 감사합니다 🙌 운영진이 확인하고 반영할게요.",
        link="/places/64b000000000000000000003",
        read_at=None,
        created_at=now,
    )
    view = notification_to_view(notif)
    assert view.id == notif.id
    assert view.type == "place_suggestion_ack"
    assert view.title == "정보 수정 제안이 접수되었습니다"
    assert view.body.startswith("클라이밍파크 강남점")
    assert view.link == "/places/64b000000000000000000003"
    assert view.read_at is None
    assert view.created_at == now
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/htjo/besetter/services/api && pytest tests/routers/test_notifications.py -v
```
Expected: FAIL with `ModuleNotFoundError: app.routers.notifications` or similar.

- [ ] **Step 3: Create `app/routers/notifications.py`**

```python
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from beanie.odm.fields import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.dependencies import get_current_user
from app.models import model_config
from app.models.notification import Notification
from app.models.user import User

router = APIRouter(prefix="/notifications", tags=["notifications"])

_CLOCK_SKEW = timedelta(seconds=5)


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------


class NotificationView(BaseModel):
    model_config = model_config

    id: PydanticObjectId
    type: str
    title: str
    body: str
    link: Optional[str] = None
    read_at: Optional[datetime] = None
    created_at: datetime


class NotificationListResponse(BaseModel):
    model_config = model_config

    items: List[NotificationView]
    next_cursor: Optional[datetime] = None


class MarkReadRequest(BaseModel):
    model_config = model_config

    before: datetime


class MarkReadResponse(BaseModel):
    model_config = model_config

    marked_count: int
    unread_notification_count: int


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def notification_to_view(notif: Notification) -> NotificationView:
    return NotificationView(
        id=notif.id,
        type=notif.type,
        title=notif.title,
        body=notif.body,
        link=notif.link,
        read_at=notif.read_at,
        created_at=notif.created_at,
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("", response_model=NotificationListResponse)
async def list_notifications(
    before: Optional[datetime] = Query(None, description="이 시각 이전 알림만"),
    limit: int = Query(20, ge=1, le=50),
    current_user: User = Depends(get_current_user),
):
    query_filter: dict = {"userId": current_user.id}
    if before is not None:
        query_filter["createdAt"] = {"$lt": before}

    items = (
        await Notification.find(query_filter)
        .sort(-Notification.created_at)
        .limit(limit)
        .to_list()
    )

    next_cursor = items[-1].created_at if len(items) == limit else None
    return NotificationListResponse(
        items=[notification_to_view(n) for n in items],
        next_cursor=next_cursor,
    )


@router.post("/mark-read", response_model=MarkReadResponse)
async def mark_notifications_read(
    payload: MarkReadRequest,
    current_user: User = Depends(get_current_user),
):
    now = datetime.now(tz=timezone.utc)
    if payload.before > now + _CLOCK_SKEW:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="before must be <= now",
        )

    notif_coll = Notification.get_motor_collection()
    result = await notif_coll.update_many(
        {
            "userId": current_user.id,
            "readAt": None,
            "createdAt": {"$lte": payload.before},
        },
        {"$set": {"readAt": now}},
    )
    marked = result.modified_count

    if marked:
        await User.get_motor_collection().update_one(
            {"_id": current_user.id},
            {"$inc": {"unreadNotificationCount": -marked}},
        )

    fresh = await User.get(current_user.id)
    count = fresh.unread_notification_count if fresh else 0
    return MarkReadResponse(
        marked_count=marked,
        unread_notification_count=max(0, count),
    )
```

- [ ] **Step 4: Run the serializer test to verify it passes**

Run:
```bash
cd /Users/htjo/besetter/services/api && pytest tests/routers/test_notifications.py::test_notification_to_view_maps_all_fields -v
```
Expected: PASS.

- [ ] **Step 5: Register router in `app/main.py`**

Find where other routers are included (e.g., `app.include_router(places.router)`) and add:

```python
from app.routers import notifications
# ...
app.include_router(notifications.router)
```

- [ ] **Step 6: Verify app imports**

Run:
```bash
cd /Users/htjo/besetter/services/api && python -c "from app.routers.notifications import router; print(len(router.routes))"
```
Expected: `2` (list + mark-read).

- [ ] **Step 7: Commit**

```bash
cd /Users/htjo/besetter && git add services/api/app/routers/notifications.py services/api/app/main.py services/api/tests/routers/test_notifications.py
git commit -m "$(cat <<'EOF'
feat(api): add GET /notifications and POST /notifications/mark-read

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Backend — `/users/me` 응답에 unreadNotificationCount 추가

**Files:**
- Modify: `services/api/app/routers/users.py`

- [ ] **Step 1: Add field to `UserProfileResponse`**

In `services/api/app/routers/users.py`, update the class:

```python
class UserProfileResponse(BaseModel):
    model_config = model_config

    id: str = Field(alias="id")
    name: Optional[str] = None
    email: Optional[str] = None
    bio: Optional[str] = None
    profile_image_url: Optional[str] = None
    unread_notification_count: int = 0
```

- [ ] **Step 2: Populate field in `_build_profile_response` with clamp**

Update the helper:

```python
def _build_profile_response(user: User) -> UserProfileResponse:
    signed_url = None
    if user.profile_image_url:
        blob_path = extract_blob_path_from_url(user.profile_image_url)
        if blob_path:
            signed_url = generate_signed_url(blob_path)
        else:
            signed_url = user.profile_image_url

    return UserProfileResponse(
        id=str(user.id),
        name=user.name,
        email=user.email,
        bio=user.bio,
        profile_image_url=signed_url,
        unread_notification_count=max(0, user.unread_notification_count),
    )
```

- [ ] **Step 3: Verify imports still compile**

Run:
```bash
cd /Users/htjo/besetter/services/api && python -c "from app.routers.users import UserProfileResponse; r = UserProfileResponse(id='x'); print(r.unread_notification_count)"
```
Expected: `0`.

- [ ] **Step 4: Commit**

```bash
cd /Users/htjo/besetter && git add services/api/app/routers/users.py
git commit -m "$(cat <<'EOF'
feat(api): expose unreadNotificationCount from /users/me

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Backend — `POST /places/suggestions` 후처리 (알림 + 카운터)

**Files:**
- Modify: `services/api/app/routers/places.py`

- [ ] **Step 1: Add imports**

At the top of `services/api/app/routers/places.py`, add:

```python
import logging

from app.models.notification import Notification

logger = logging.getLogger(__name__)
```

(skip any import that already exists)

- [ ] **Step 2: Add notification creation after suggestion.save()**

Find the end of `create_place_suggestion` — the block that returns `PlaceSuggestionView`. Insert this code between `created = await suggestion.save()` and the `return ...`:

```python
    # Best-effort: notify the requester with a thank-you message.
    try:
        place_name_snapshot = place.name
        notif = Notification(
            user_id=current_user.id,
            type="place_suggestion_ack",
            title="정보 수정 제안이 접수되었습니다",
            body=(
                f"{place_name_snapshot}에 대한 소중한 제보 감사합니다 🙌 "
                "운영진이 확인하고 반영할게요."
            ),
            link=f"/places/{place.id}",
            created_at=datetime.now(tz=timezone.utc),
        )
        await notif.save()
        await User.get_motor_collection().update_one(
            {"_id": current_user.id},
            {"$inc": {"unreadNotificationCount": 1}},
        )
    except Exception as exc:  # best-effort; do not block suggestion creation
        logger.warning("notification creation failed for place %s: %s", place.id, exc)
```

- [ ] **Step 3: Verify imports compile**

Run:
```bash
cd /Users/htjo/besetter/services/api && python -c "from app.routers.places import create_place_suggestion; print('ok')"
```
Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
cd /Users/htjo/besetter && git add services/api/app/routers/places.py
git commit -m "$(cat <<'EOF'
feat(api): emit thank-you notification on place suggestion

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Mobile — `UserState.unreadNotificationCount` 확장

**Files:**
- Modify: `apps/mobile/lib/providers/user_provider.dart`

- [ ] **Step 1: Add field, constructor, copyWith, and fromJson parsing**

Replace `class UserState { ... }` with:

```dart
class UserState {
  final String id;
  final String? name;
  final String? email;
  final String? bio;
  final String? profileImageUrl;
  final int unreadNotificationCount;

  const UserState({
    required this.id,
    this.name,
    this.email,
    this.bio,
    this.profileImageUrl,
    this.unreadNotificationCount = 0,
  });

  UserState copyWith({
    String? id,
    String? name,
    String? email,
    String? bio,
    String? profileImageUrl,
    int? unreadNotificationCount,
  }) {
    return UserState(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      bio: bio ?? this.bio,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      unreadNotificationCount:
          unreadNotificationCount ?? this.unreadNotificationCount,
    );
  }

  factory UserState.fromJson(Map<String, dynamic> json) {
    return UserState(
      id: json['id'] as String,
      name: json['name'] as String?,
      email: json['email'] as String?,
      bio: json['bio'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      unreadNotificationCount:
          (json['unreadNotificationCount'] as int?) ?? 0,
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

Run:
```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze
```
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
cd /Users/htjo/besetter && git add apps/mobile/lib/providers/user_provider.dart
git commit -m "$(cat <<'EOF'
feat(mobile): add unreadNotificationCount to UserState

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Mobile — `NotificationData` 모델 + `NotificationService`

**Files:**
- Create: `apps/mobile/lib/models/notification_data.dart`
- Create: `apps/mobile/lib/services/notification_service.dart`

- [ ] **Step 1: Create `NotificationData` model**

Create `apps/mobile/lib/models/notification_data.dart`:

```dart
class NotificationData {
  final String id;
  final String type;
  final String title;
  final String body;
  final String? link;
  final DateTime? readAt;
  final DateTime createdAt;

  const NotificationData({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.link,
    required this.readAt,
    required this.createdAt,
  });

  factory NotificationData.fromJson(Map<String, dynamic> json) {
    return NotificationData(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      link: json['link'] as String?,
      readAt: json['readAt'] == null
          ? null
          : DateTime.parse(json['readAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
```

- [ ] **Step 2: Create `NotificationService`**

Create `apps/mobile/lib/services/notification_service.dart`:

```dart
import 'dart:convert';

import '../models/notification_data.dart';
import 'http_client.dart';

class NotificationListResult {
  final List<NotificationData> items;
  final DateTime? nextCursor;

  const NotificationListResult({required this.items, required this.nextCursor});
}

class NotificationService {
  static Future<NotificationListResult> list({
    DateTime? before,
    int limit = 20,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (before != null) {
      query['before'] = before.toUtc().toIso8601String();
    }
    final qs = query.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final path = qs.isEmpty ? '/notifications' : '/notifications?$qs';

    final response = await AuthorizedHttpClient.get(path);
    if (response.statusCode != 200) {
      throw Exception('Failed to load notifications: ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final items = (decoded['items'] as List<dynamic>)
        .map((e) => NotificationData.fromJson(e as Map<String, dynamic>))
        .toList();
    final nextCursorStr = decoded['nextCursor'] as String?;
    final nextCursor = nextCursorStr == null ? null : DateTime.parse(nextCursorStr);
    return NotificationListResult(items: items, nextCursor: nextCursor);
  }

  /// Returns the server's updated unreadNotificationCount.
  static Future<int> markRead(DateTime before) async {
    final body = jsonEncode({'before': before.toUtc().toIso8601String()});
    final response = await AuthorizedHttpClient.post(
      '/notifications/mark-read',
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to mark notifications read: ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return (decoded['unreadNotificationCount'] as int?) ?? 0;
  }
}
```

**Note for implementer:** Before committing, verify that `AuthorizedHttpClient.post` exists with a `body` parameter that sends JSON. If the existing helper uses different signature (e.g., positional body, named `jsonBody`), adapt this call to match. Check `apps/mobile/lib/services/http_client.dart` first.

- [ ] **Step 3: Run flutter analyze**

Run:
```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze
```
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
cd /Users/htjo/besetter && git add apps/mobile/lib/models/notification_data.dart apps/mobile/lib/services/notification_service.dart
git commit -m "$(cat <<'EOF'
feat(mobile): add NotificationData model and NotificationService

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Mobile — `NotificationsPage` 리스트 화면

**Files:**
- Create: `apps/mobile/lib/pages/notifications_page.dart`

- [ ] **Step 1: Create `NotificationsPage`**

Create `apps/mobile/lib/pages/notifications_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/notification_data.dart';
import '../providers/user_provider.dart';
import '../services/notification_service.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  final List<NotificationData> _items = [];
  late final DateTime _enteredAt;

  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  DateTime? _cursor;
  Object? _initialError;
  Object? _loadMoreError;

  @override
  void initState() {
    super.initState();
    _enteredAt = DateTime.now().toUtc();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _initialError = null;
    });
    try {
      final result = await NotificationService.list(limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _cursor = result.nextCursor;
        _hasMore = result.nextCursor != null;
        _initialLoading = false;
      });
      _markReadAfterLoad();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _initialError = e;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final result = await NotificationService.list(
        before: _cursor,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _cursor = result.nextCursor;
        _hasMore = result.nextCursor != null;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = e;
      });
    }
  }

  Future<void> _markReadAfterLoad() async {
    try {
      final newCount = await NotificationService.markRead(_enteredAt);
      if (!mounted) return;
      final current = ref.read(userProfileProvider).valueOrNull;
      if (current != null) {
        ref
            .read(userProfileProvider.notifier)
            .state = AsyncData(current.copyWith(unreadNotificationCount: newCount));
      }
    } catch (_) {
      // silent — next entry will retry
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  String _relativeTime(DateTime createdAt) {
    final now = DateTime.now();
    final diff = now.difference(createdAt.toLocal());
    if (diff.inSeconds < 60) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    final local = createdAt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y.$m.$d';
  }

  bool _isUnreadAfterEntry(NotificationData n) {
    // Items that arrived after we entered the page stay visually "unread".
    return n.readAt == null && n.createdAt.toUtc().isAfter(_enteredAt);
  }

  Widget _buildItem(NotificationData n) {
    final unread = _isUnreadAfterEntry(n);
    return Container(
      color: unread ? Theme.of(context).colorScheme.primary.withOpacity(0.06) : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.edit_note_outlined, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (unread)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        n.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  n.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _relativeTime(n.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_initialError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('알림을 불러오지 못했어요.'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadInitial,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('아직 받은 알림이 없어요'));
    }
    return ListView.separated(
      controller: _scrollController,
      itemCount: _items.length + (_hasMore || _loadMoreError != null ? 1 : 0),
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: Theme.of(context).dividerColor.withOpacity(0.5),
      ),
      itemBuilder: (context, index) {
        if (index < _items.length) {
          return _buildItem(_items[index]);
        }
        if (_loadMoreError != null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: TextButton(
                onPressed: _loadMore,
                child: const Text('다시 시도'),
              ),
            ),
          );
        }
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('알림')),
      body: _buildBody(),
    );
  }
}
```

**Note for implementer:**
- `ref.read(userProfileProvider.notifier).state = AsyncData(...)` requires that `UserProfile` from `user_provider.dart` allows direct `state` assignment. If the generated Notifier doesn't expose a setter, replace with `ref.invalidate(userProfileProvider)` as a fallback (causes a refetch instead of local update).
- Before finalizing, confirm the exact API of the existing notifier and pick the cleanest path.

- [ ] **Step 2: Run flutter analyze**

Run:
```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze
```
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
cd /Users/htjo/besetter && git add apps/mobile/lib/pages/notifications_page.dart
git commit -m "$(cat <<'EOF'
feat(mobile): add NotificationsPage with cursor pagination

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Mobile — GNB 배지 + MY AppBar 종 + PlaceSelectionSheet invalidate

**Files:**
- Modify: `apps/mobile/lib/pages/main_tab.dart`
- Modify: `apps/mobile/lib/pages/my_page.dart`
- Modify: `apps/mobile/lib/widgets/editors/place_selection_sheet.dart`

- [ ] **Step 1: GNB MY 아이콘에 `Badge.count` 적용**

In `apps/mobile/lib/pages/main_tab.dart`, replace the MY `BottomNavigationBarItem` (the one with `Icons.person`) with a Consumer-wrapped icon:

```dart
BottomNavigationBarItem(
  icon: Consumer(
    builder: (context, ref, _) {
      final count = ref.watch(userProfileProvider).whenOrNull(
                data: (u) => u.unreadNotificationCount,
              ) ??
          0;
      return Badge.count(
        count: count,
        isLabelVisible: count > 0,
        child: const Icon(Icons.person),
      );
    },
  ),
  label: AppLocalizations.of(context)!.navMy,
),
```

Also ensure the file imports:
```dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/user_provider.dart';
```
(add only if missing)

- [ ] **Step 2: Add bell icon with badge to MY page header**

In `apps/mobile/lib/pages/my_page.dart`, locate the top header area of the page (where the title or profile begins). Add a leading bell button. Since `MyPage` is a `HookConsumerWidget`, `ref` is available.

Add the import at the top if missing:
```dart
import 'notifications_page.dart';
```

Then, at the header area of the page body, insert this widget (adjust its parent Row/Stack based on existing layout — the exact spot is just below or inside the top AppBar-like area):

```dart
Consumer(
  builder: (context, ref, _) {
    final count = ref.watch(userProfileProvider).whenOrNull(
              data: (u) => u.unreadNotificationCount,
            ) ??
        0;
    return IconButton(
      icon: Badge.count(
        count: count,
        isLabelVisible: count > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsPage()),
        );
      },
    );
  },
),
```

**Note for implementer:** `my_page.dart` is 1086 lines with a custom header layout, not a standard `AppBar`. Read the top of the `build()` method (roughly the first 150 lines after state hooks) to find where the page title / profile row is assembled, and place the bell icon at the top-left of that row. If there is a pre-existing leading slot (e.g., in a `Row` with `MainAxisAlignment.spaceBetween`), put the bell there; otherwise wrap the current header in a `Row` with the bell on the left.

- [ ] **Step 3: Convert `PlaceSelectionSheet` to ConsumerStatefulWidget**

In `apps/mobile/lib/widgets/editors/place_selection_sheet.dart`:

1. Add import at top:
```dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../providers/user_provider.dart';
```

2. Change class declarations:
```dart
class PlaceSelectionSheet extends ConsumerStatefulWidget {
  // ... keep existing fields/constructor
  @override
  ConsumerState<PlaceSelectionSheet> createState() => _PlaceSelectionSheetState();
}

class _PlaceSelectionSheetState extends ConsumerState<PlaceSelectionSheet> {
  // ... keep existing state
}
```

- [ ] **Step 4: Invalidate provider in `PlaceEditPane.onCompleted`**

Find where `PlaceEditPane` is instantiated in `place_selection_sheet.dart` (inside the edit mode branch). Update the `onCompleted` callback:

```dart
PlaceEditPane(
  place: _editTarget!,
  onCompleted: () {
    ref.invalidate(userProfileProvider);
    setState(() {
      _mode = _SheetMode.select;
      _editTarget = null;
    });
  },
),
```

**Note for implementer:** Preserve any other state reset logic that was already in the existing `onCompleted`. Only add the `ref.invalidate(userProfileProvider)` call as the first line of the callback body, and keep the existing `setState` block intact. Do not remove fields that the existing callback touched.

- [ ] **Step 5: Run flutter analyze**

Run:
```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze
```
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
cd /Users/htjo/besetter && git add apps/mobile/lib/pages/main_tab.dart apps/mobile/lib/pages/my_page.dart apps/mobile/lib/widgets/editors/place_selection_sheet.dart
git commit -m "$(cat <<'EOF'
feat(mobile): notification badges on GNB and MY header

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Post-Implementation

- [ ] **Deploy API**

After all tasks pass, deploy the API so mobile can talk to the new endpoints:

```bash
cd /Users/htjo/besetter && ./services/api/deploy.sh
```

- [ ] **Verify on device**

1. Open the app, submit a suggestion on any gym from the place selection sheet.
2. Close the sheet — the GNB MY icon should now show a red `1` badge.
3. Tap MY → tap the bell icon → `NotificationsPage` opens and shows the thank-you message.
4. Go back — both badges should be cleared.
5. Pull to refresh or reopen the app to confirm the state persists.
