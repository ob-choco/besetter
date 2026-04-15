# 장소 수정 제안 알림 시스템 설계

**Goal.** 유저가 장소 정보 수정 제안을 제출했을 때 "감사" 알림을 받아 MY 탭에서 볼 수 있게 하고, GNB MY 아이콘과 MY 페이지 AppBar에 미확인 배지를 노출한다.

**Scope in.**
- `notifications` 컬렉션과 `User.unreadNotificationCount` 필드 추가.
- 목록 조회 / 읽음 처리 / `/users/me` 확장 API.
- `POST /places/suggestions` 성공 시 제안자에게 감사 알림 1건 생성 트리거.
- 모바일: GNB MY 탭 아이콘 배지, MY AppBar 종 아이콘, 별도 `NotificationsPage`.

**Scope out (명시적).**
- 운영진 제안 반영 툴, "반영됨" 알림 트리거. 운영 툴이 생길 때 같은 인프라에 트리거만 추가하면 됨.
- 푸시 알림 (FCM/APNS), 앱 외부 notification.
- 알림 탭 시 딥링크 라우팅. `link` 필드는 저장만 한다.
- 장소 등록자(created_by)에게 제안 도착 알림. 요구 아님.

---

## 1. 아키텍처 개요

```
[ POST /places/suggestions ]
        │
        ├─ Place.suggestions insert
        ├─ Notification insert (userId = requester)
        └─ User $inc unreadNotificationCount +1
                                │
                                ▼
[ GET /users/me ] ── userProfileProvider (keepAlive)
                                │
                ┌───────────────┼──────────────────┐
                ▼               ▼                  ▼
       [GNB MY icon badge]  [MY AppBar bell]  [NotificationsPage]
                                                    │
                                                    ├─ GET /notifications (cursor)
                                                    └─ POST /notifications/mark-read
                                                            │
                                                            ├─ Notification update_many ($set readAt=now)
                                                            └─ User $inc -markedCount
```

**핵심 원칙.**
- `User.unreadNotificationCount`는 **오직 `$inc`로만 갱신**. `$set: 0`은 금지 (동시 생성 경쟁에서 카운트 소실).
- 읽음 처리는 **실제로 mark된 개수만큼만 decrement**. `before` 커트오프 이후 도착한 알림은 건드리지 않음 → 배지가 "페이지 진입 이후 새로 도착한 알림 수"를 정확히 반영.
- 렌더된 최종 문자열을 알림 문서에 **스냅샷**으로 저장. 장소명이 나중에 바뀌어도 알림 문구는 당시 이름 유지.

---

## 2. 데이터 모델

### 2.1 `notifications` 컬렉션 (신규)

```python
class Notification(Document):
    user_id: PydanticObjectId
    type: str                                    # "place_suggestion_ack"
    title: str
    body: str
    link: Optional[str] = None                   # "/places/{place_id}" (저장만)
    read_at: Optional[datetime] = None
    created_at: datetime

    class Settings:
        name = "notifications"
        indexes = [
            IndexModel([("userId", ASCENDING), ("createdAt", DESCENDING)]),
        ]
        keep_nulls = True
```

- 복합 인덱스 `(userId ↓, createdAt ↓)` 하나로 목록 조회와 읽음 처리 쿼리 모두 커버. 별도 `readAt` 인덱스는 YAGNI.
- `link`는 nullable. 미래 타입(시스템 공지 등)은 없을 수 있음.
- `type`은 문자열 enum 대신 자유 문자열. 최초 값 `"place_suggestion_ack"`.

### 2.2 `User` 문서 필드 추가

```python
class User(Document):
    # ... 기존 필드 유지
    unread_notification_count: int = Field(default=0)
```

- 기존 유저 문서에 필드가 없어도 Pydantic default 0으로 읽힘.
- `$inc` 연산은 MongoDB가 누락 필드를 0으로 간주 후 증가 → 별도 백필 불필요.
- 응답 직렬화 시 `max(0, count)`로 클램프 (음수 드리프트 안전장치).

---

## 3. API 엔드포인트

### 3.1 `GET /notifications`

내 알림 목록 (최신순, 커서 페이지네이션).

**Query**
- `before: Optional[datetime]` — ISO8601. 이 시각 이전 `createdAt`만.
- `limit: int = 20` — 1~50 범위.

**Response 200**
```json
{
  "items": [
    {
      "id": "...",
      "type": "place_suggestion_ack",
      "title": "정보 수정 제안이 접수되었습니다",
      "body": "클라이밍파크 강남점에 대한 소중한 제보 감사합니다 🙌 운영진이 확인하고 반영할게요.",
      "link": "/places/<place_id>",
      "readAt": null,
      "createdAt": "2026-04-15T12:34:56Z"
    }
  ],
  "nextCursor": "2026-04-14T09:10:11Z"
}
```

- `nextCursor`는 마지막 아이템의 `createdAt`. 더 없으면 `null`.
- 에러: `limit` 범위 외 → 422.

### 3.2 `POST /notifications/mark-read`

페이지 진입 시각을 기준으로 그 이전 미확인 알림을 일괄 읽음 처리.

**Body**
```json
{ "before": "2026-04-15T12:34:56Z" }
```

**Response 200**
```json
{ "markedCount": 3, "unreadNotificationCount": 0 }
```

**의사코드**
```python
now = datetime.now(tz=timezone.utc)

if before > now + SMALL_SKEW:
    raise HTTPException(422, "before must be <= now")

coll = Notification.get_motor_collection()
result = await coll.update_many(
    {
        "userId": current_user.id,
        "readAt": None,
        "createdAt": {"$lte": before},
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
return {
    "markedCount": marked,
    "unreadNotificationCount": max(0, fresh.unread_notification_count),
}
```

**순서 엄수.** 알림 `update_many` → 유저 `$inc -N`. 반대 순서면 생성 경쟁에서 카운트 소실.

**중복 호출 안전.** `readAt: null` 필터 덕분에 두 번째 호출은 0건 매치 → `-0` 감소. 결과 멱등.

### 3.3 `GET /users/me` 확장

응답에 필드 추가:

```json
{
  "...": "...",
  "unreadNotificationCount": 0
}
```

`max(0, user.unread_notification_count)` 클램프. 기존 필드 변경 없음.

### 3.4 `POST /places/suggestions` 후처리 추가

제안 저장 성공 직후, 함수 리턴 직전:

```python
try:
    place_name_snapshot = place.name
    notif = Notification(
        user_id=current_user.id,
        type="place_suggestion_ack",
        title="정보 수정 제안이 접수되었습니다",
        body=f"{place_name_snapshot}에 대한 소중한 제보 감사합니다 🙌 운영진이 확인하고 반영할게요.",
        link=f"/places/{place.id}",
        created_at=datetime.now(tz=timezone.utc),
    )
    await notif.save()
    await User.get_motor_collection().update_one(
        {"_id": current_user.id},
        {"$inc": {"unreadNotificationCount": 1}},
    )
except Exception as exc:  # best-effort
    logger.warning("notification creation failed: %s", exc)
```

- 순서: 알림 insert → 유저 `$inc +1`. 반대면 "카운트는 올랐는데 항목이 안 보임"이라는 잠깐의 부정합이 발생.
- 알림 생성 실패는 제안 생성 자체를 롤백하지 않음. 로그만 남김.

---

## 4. 모바일 클라이언트

### 4.1 파일 구성

| 상태 | 경로 | 책임 |
|------|------|------|
| 수정 | `lib/providers/user_provider.dart` | `UserState`에 `unreadNotificationCount` 추가 |
| 생성 | `lib/models/notification_data.dart` | `NotificationData` 모델 + `fromJson` |
| 생성 | `lib/services/notification_service.dart` | `list(before)`, `markRead(before)` |
| 생성 | `lib/pages/notifications_page.dart` | 알림 리스트 화면 |
| 수정 | `lib/pages/main_tab.dart` | GNB MY 아이콘 배지 |
| 수정 | `lib/pages/my_page.dart` | AppBar 왼쪽 종 아이콘 + 배지, 탭 → 푸시 |
| 수정 | `lib/widgets/editors/place_selection_sheet.dart` | `ConsumerStatefulWidget`로 전환 + 제안 성공 후 `ref.invalidate(userProfileProvider)` |

### 4.2 `UserState` 확장

```dart
class UserState {
  // ... 기존 필드
  final int unreadNotificationCount;   // default 0
}
```

`fromJson`에서 `json['unreadNotificationCount'] as int? ?? 0`.

### 4.3 `NotificationData`

```dart
class NotificationData {
  final String id;
  final String type;
  final String title;
  final String body;
  final String? link;
  final DateTime? readAt;
  final DateTime createdAt;
}
```

순수 데이터 클래스 + `fromJson`.

### 4.4 `NotificationService`

```dart
class NotificationService {
  static Future<({List<NotificationData> items, DateTime? nextCursor})> list({
    DateTime? before,
    int limit = 20,
  });

  /// 반환: 서버가 내려준 갱신된 unreadNotificationCount
  static Future<int> markRead(DateTime before);
}
```

### 4.5 `NotificationsPage` (StatefulWidget)

진입 로직:
1. `final enteredAt = DateTime.now().toUtc();` 기록.
2. 첫 페이지 `list(before: null)` 호출.
3. 목록 렌더 완료 후 `markRead(enteredAt)` 호출.
4. `markRead` 응답의 `unreadNotificationCount`로 `userProfileProvider` 상태 덮어쓰기 (`copyWith`).

리스트:
- `ListView.builder` + 하단 스크롤 근접 감지로 `nextCursor` 요청.
- 로딩 푸터 스피너.
- 빈 상태: "아직 받은 알림이 없어요".

아이템 UI:
- 좌측 고정 아이콘 (지금은 타입 하나뿐이라 고정).
- 제목, 본문 2줄 클램프, 상대 시간 ("방금 전 / N분 전 / N시간 전 / N일 전 / YYYY.MM.DD").
- 진입 시 찍은 `enteredAt`보다 이후 도착한 항목만 UI 미확인 스타일 (배경색 + 좌측 파란 점). 나머지는 "방금 읽음 처리됨"으로 표시.

탭 동작: 없음. 코드에 `// TODO: link 라우팅` 주석만.

### 4.6 GNB MY 아이콘 배지 (`main_tab.dart`)

```dart
BottomNavigationBarItem(
  icon: Consumer(
    builder: (context, ref, _) {
      final count = ref.watch(userProfileProvider).whenOrNull(
            data: (u) => u.unreadNotificationCount,
          ) ?? 0;
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

- `count == 0`이면 배지 완전히 숨김 (넛지 목적).
- `userProfileProvider`가 `keepAlive`라 앱 전역에서 동일한 값을 공유.

### 4.7 MY 페이지 AppBar 종 아이콘

- AppBar `leading` 위치(또는 현재 수동 배치된 상단 헤더의 왼쪽)에 종 아이콘 + 배지.
- 탭 시 `Navigator.push(MaterialPageRoute(builder: (_) => const NotificationsPage()))`.
- 뒤로 돌아오면 `markRead` 응답으로 provider가 이미 갱신돼 있어 배지는 0 표시.

### 4.8 `PlaceSelectionSheet` invalidate 경로

`PlaceSelectionSheet`를 `ConsumerStatefulWidget` + `ConsumerState`로 전환 (파일 내부 소규모 변경). 기존 `_goToEdit` 경로에서 `PlaceEditPane`에 넘기는 `onCompleted`:

```dart
PlaceEditPane(
  place: _editTarget!,
  onCompleted: () {
    ref.invalidate(userProfileProvider);
    setState(() { _mode = _SheetMode.select; ... });
  },
)
```

- gym 수정 제안 / private-gym 수정 공통 콜백.
- private-gym 수정은 알림을 생성하지 않지만 invalidate 비용은 `/users/me` 한 번 더 부르는 정도.
- `PlaceEditPane` 자체는 순수 유지 (책임 경계).

---

## 5. 에러 처리

### 5.1 서버

| 지점 | 케이스 | 처리 |
|------|--------|------|
| `POST /places/suggestions` 후처리 | 알림/카운터 실패 | try/except, 로그, 제안 응답 200 유지 (best-effort) |
| `POST /notifications/mark-read` | `before > now + skew` | 422 |
| `POST /notifications/mark-read` | 매치 0건 | 200, `{markedCount:0, unreadNotificationCount: 현재값}` |
| `POST /notifications/mark-read` | 유저 `$inc` 실패 | 로그 + 500. 다음 mark-read는 재매치 불가(readAt 필터). 응답 클램프로 UI 복구 |
| `GET /notifications` | `limit` 범위 외 | 422 |

### 5.2 클라이언트

| 지점 | 케이스 | 처리 |
|------|--------|------|
| `NotificationsPage` 초기 로드 | 실패 | 재시도 버튼 + 에러 텍스트 |
| 다음 페이지 로드 | 실패 | 푸터에 "다시 시도" |
| `markRead` | 실패 | silent (다음 진입 시 재시도). 배지는 `invalidate`로 대체 갱신 |
| `/users/me` | `unreadNotificationCount` 누락 | 기본 0 |

---

## 6. 테스트 계획

**백엔드 (`pytest`, 기존 테스트 구조 재사용)**

`test_notifications.py` (신규):
- 유저 A가 장소 X에 제안 생성 → notification 1건 + `user.unreadNotificationCount == 1`.
- `GET /notifications` 정렬/limit/before 커서 동작.
- `POST /notifications/mark-read before=T` → `markedCount`, `unreadNotificationCount` 정확.
- 동시 시나리오 시뮬레이션: mark-read 수행 직전에 새 알림 insert → 수행 후 counter가 1로 남는지.
- 다른 유저 알림 격리 (userId 필터 검증).
- `before > now` → 422.

`test_places_suggestions.py` (기존):
- "알림 생성 + 카운터 증가" assertion 1개 추가.

`/users/me`:
- `unread_notification_count` 필드가 누락된 유저 문서에서 0으로 내려오는지.

**모바일 (`flutter analyze`만)**

- 코드 생성(`build_runner`) 후 `flutter analyze` 0 error, 0 warning.
- UI 테스트 없음 (기존 방침 유지).

---

## 7. 마이그레이션

- **DB 마이그레이션 없음.** MongoDB + Beanie가 필드 추가 시 자동 처리.
- `notifications` 인덱스는 Beanie Settings가 기동 시 생성.
- 기존 `User` 문서의 `unread_notification_count` 누락은 Pydantic default 0 + `$inc`의 누락 필드 0 처리로 해결. 별도 백필 스크립트 불필요.
- 배포 순서: API 먼저 (`services/api/deploy.sh`) → 모바일. 모바일 구버전은 `/users/me`의 신규 필드를 무시하므로 하위 호환.

---

## 8. 작업 단위 (writing-plans 입력)

1. **백엔드: Notification 모델 + User 필드 추가** (모델/인덱스/config)
2. **백엔드: GET /notifications, POST /notifications/mark-read 엔드포인트**
3. **백엔드: /users/me 응답에 unreadNotificationCount 추가 + 클램프**
4. **백엔드: POST /places/suggestions 후처리 (알림 생성 + 카운터 +1)**
5. **모바일: UserState 필드 확장 + `PlaceSelectionSheet` ConsumerStatefulWidget 전환 + invalidate**
6. **모바일: NotificationData / NotificationService**
7. **모바일: NotificationsPage**
8. **모바일: MyPage AppBar 종 아이콘 + MainTab GNB 배지**
