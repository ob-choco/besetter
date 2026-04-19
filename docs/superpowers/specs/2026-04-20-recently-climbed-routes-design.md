# 최근 운동한 루트 (Recently Climbed Routes) 설계

## 개요

홈 화면에 "최근 운동한 루트" 섹션을 신설하여, 사용자가 최근 활동을 기록한 루트 상위 9개를 노출한다. 다른 사용자가 만든 루트도 운동할 수 있으므로, 카드에 루트 작성자(오너)의 프로필을 함께 표시한다. 동일한 오너 표시 원칙을 MY 페이지의 일일 활동 카드에도 적용한다.

## 목표 및 범위

**목표**
- 홈 화면에서 사용자가 최근 운동한 루트 9개를 바로 확인하고 이어서 운동을 재개할 수 있도록 한다.
- 타 사용자 루트의 작성자 정보를 투명하게 드러낸다.

**범위 안**
1. API 신설: `GET /my/recently-climbed-routes?limit=9`
2. API 확장: `GET /my/daily-routes` 응답에 오너 정보 추가
3. 선결: `UserRouteStats.lastActivityAt` 갱신 로직 구현 (현재 미구현 상태)
4. MongoDB 컴파운드 인덱스 추가: `(userId: 1, lastActivityAt: -1)`
5. 모바일: 홈 섹션, MY 일일 카드 오너 배지, `MainTab` 탭 인덱스 provider 승격
6. 신규 공유 컴포넌트: `OwnerView` (API), `OwnerBadge` (모바일)

**범위 밖**
- 타 사용자 프로필 페이지 (현재 앱에 미존재, 오너 썸네일은 표시 전용)
- 홈 섹션의 페이지네이션/인피니트 스크롤
- 전용 "전체 운동한 루트" 페이지 (기존 MY 탭이 이 역할을 대체)
- **기존 데이터 `lastActivityAt` 백필** (사용자 지시에 따라 제외 — 신규 활동부터 채워진다)

## 아키텍처 개요

```
모바일 홈                 →  GET /my/recently-climbed-routes?limit=9
                             └→ UserRouteStats (정렬/필터)
                                  ↓ routeId
                                Route + Image + Place + User(오너)
                                  ↓
                                OwnerView 포함 응답

모바일 MY                →  GET /my/daily-routes?date=...
                             └→ Activity 집계 + Route $lookup(+userId) + User(오너)
                                  ↓
                                OwnerView 포함 응답
```

**데이터 일관성:** `lastActivityAt`은 현재 갱신 경로가 없음. 본 스펙에서 `user_stats.py`의 `on_activity_created` / `on_activity_deleted`에 갱신 로직을 추가한다.

## API 설계

### 1. `GET /my/recently-climbed-routes`

**위치:** `services/api/app/routers/my.py`

**쿼리 파라미터**
| 이름 | 타입 | 기본 | 범위 | 설명 |
|---|---|---|---|---|
| `limit` | int | 9 | 1–20 | 반환할 루트 수 |

**응답 모델** (신규 `RecentRouteView`)

기존 `RouteServiceView`(`services/api/app/routers/routes.py`)에 `owner`, `isDeleted` 필드를 추가한 형태.

```python
class OwnerView(BaseModel):
    model_config = model_config

    user_id: PydanticObjectId
    profile_id: Optional[str] = None
    profile_image_url: Optional[str] = None
    is_deleted: bool = False


class RecentRouteView(BaseModel):
    model_config = model_config

    id: ObjectId
    type: RouteType
    title: Optional[str] = None
    visibility: Visibility
    is_deleted: bool = False

    grade_type: str
    grade: str
    grade_color: Optional[str] = None

    image_url: str
    overlay_image_url: Optional[str] = None

    place: Optional[PlaceView] = None
    wall_name: Optional[str] = None
    wall_expiration_date: Optional[datetime] = None

    owner: OwnerView

    my_total_count: int
    my_completed_count: int
    my_last_activity_at: datetime

    created_at: datetime
    updated_at: Optional[datetime] = None


class RecentRoutesResponse(BaseModel):
    model_config = model_config
    data: List[RecentRouteView]
```

**쿼리 로직** (`/my/recently-climbed-routes` 엔드포인트 본문)

1. `UserRouteStats`에서 `user_id == current_user.id AND last_activity_at != null`, 정렬 `last_activity_at desc, _id desc`, `limit` 만큼 조회.
2. 조회된 `route_id` 목록으로 `Route` 일괄 조회 (소프트 삭제 포함 — `is_deleted` 필터링하지 않음, 툼스톤으로 응답에 포함).
3. `Route.image_id` 목록으로 `Image` 일괄 조회 → `place_id` 수집.
4. `Place` 일괄 조회.
5. `Route.user_id` 목록으로 `User` 일괄 조회 (탈퇴 회원 포함 — `is_deleted` 필터링하지 않음).
6. 각 루트별로 `RecentRouteView` 구성:
   - `image_url` / `overlay_image_url`: **public GCS 호스트** — `app.core.gcs.to_public_url`(또는 `get_public_url(extract_blob_path_from_url(raw))`)을 사용. signed URL 생성 생략. `routers/places.py:87`의 `cover_image_url=to_public_url(place.cover_image_url)` 패턴과 동일.
   - `owner`: 해당 사용자가 `is_deleted=True`이면 `OwnerView(user_id=..., profile_id=None, profile_image_url=None, is_deleted=True)`, 아니면 모든 필드 채움.
   - `visibility`와 `is_deleted`는 Route doc 값 그대로.
   - Route doc이 존재하지 않거나(데이터 무결성 파손) 이미지 doc 조회에 실패하면 해당 행은 스킵.
7. 접근 제어: **생략.** `UserRouteStats`에 기록이 있다는 것은 본인이 과거 운동한 이력이 있다는 뜻이므로, 해당 루트의 visibility/isDeleted 상태와 무관하게 응답에 포함한다 (툼스톤 카드로 렌더링됨). `/my/daily-routes`의 기존 동작과 일치.

**정렬은 고정**: `last_activity_at desc, _id desc`. `sort` 파라미터 없음.

### 2. `GET /my/daily-routes` 응답 확장

**위치:** `services/api/app/routers/my.py` 내 기존 `get_daily_routes` 핸들러 수정.

**`DailyRouteItem`에 `owner: OwnerView` 필드 추가**

```python
class DailyRouteItem(BaseModel):
    # 기존 필드들...
    owner: OwnerView  # 신규
```

**파이프라인 변경**

기존 `$lookup`은 `routes` 컬렉션에서 `visibility`, `isDeleted`만 projection 했다. 여기에 `user_id` projection을 추가한다.

```python
{"$lookup": {
    "from": "routes",
    "localField": "_id",
    "foreignField": "_id",
    "as": "route",
    "pipeline": [
        {"$project": {"visibility": 1, "isDeleted": 1, "userId": 1}},
    ],
}},
{"$set": {
    "routeVisibility": {"$ifNull": [{"$first": "$route.visibility"}, "public"]},
    "isDeleted": {"$ifNull": [{"$first": "$route.isDeleted"}, False]},
    "ownerUserId": {"$first": "$route.userId"},
}},
```

Aggregate 결과 수신 후, 고유한 `ownerUserId` 목록을 추려 `User` 일괄 조회, 응답에 `owner` 필드를 채운다. `ownerUserId`가 없거나(`Route` 자체가 사라진 극단적 케이스) User를 찾지 못한 경우 `owner.is_deleted=True`로 처리.

### 3. 공통 `OwnerView` 위치

`services/api/app/models/user.py` 또는 `app/routers/__init__.py` 등 공용 모듈에 정의하여 `routes.py`·`my.py`에서 공유. 새 파일 `app/models/views/owner.py`에 두는 방안도 있으나, 기존 코드베이스는 라우터 모듈 안에 View를 선언하는 관습이 더 강하므로, **`app/models/user.py`에 `OwnerView`를 추가**한다 (User 모델 곁).

### 4. `UserRouteStats.lastActivityAt` 갱신 로직

**현재 상태:** `_apply_user_route_stats_delta` (`app/services/user_stats.py:75`)는 `$setOnInsert: {"lastActivityAt": None}`으로 초기화만 하고 이후 절대 갱신하지 않는다. 기존 테스트 `tests/services/test_user_stats.py:206`이 "항상 null"을 단언한다.

**변경 방향**

1. `_apply_user_route_stats_delta` 시그니처에 `last_activity_at: Optional[datetime]` 파라미터 추가.
2. `$setOnInsert: {"lastActivityAt": None}`을 제거한다.
3. `last_activity_at`이 주어지면 `$max: {"lastActivityAt": last_activity_at}` 연산을 추가한다 (시간이 뒤처진 activity가 나중에 기록돼도 값이 후퇴하지 않음).
4. `on_activity_created`에서는 `activity.started_at`을 전달한다.
5. `on_activity_deleted`:
   - 먼저 `$inc` 버킷 감산을 수행 (기존과 동일).
   - 삭제한 `activity.started_at`이 현재 `lastActivityAt`과 일치하는 경우에만 재계산이 필요.
   - 재계산 방식: `Activity.find(user_id=..., route_id=...).sort([("startedAt", -1)]).first_or_none()`으로 남은 activity 중 `started_at` 최대값을 찾아 `$set`. 없으면 `$set: {"lastActivityAt": None}`. 단, 기존 로직이 "버킷이 모두 0이면 UserRouteStats doc 자체를 삭제"하므로, 삭제 경로와 겹치는 경우에는 재계산을 건너뛴다.
   - 구현 순서: `_apply_user_route_stats_delta(deltas, last_activity_at=None)` → 버킷 모두 0이면 `delete_one` → 그렇지 않고 `activity.started_at == stats.last_activity_at`이었다면 재계산.

**주의**: `on_activity_deleted`는 이미 "`delete_one` 또는 activity 삭제 전후의 레이스"를 처리 중. 재계산 쿼리는 `await activity.delete()` **이후** 실행해야 정확. 현재 `on_activity_deleted`는 호출 순서를 불명하게 두고 있으니, 호출부(`activities.py:280`)의 순서를 명시적으로 "hook 먼저, delete 나중"으로 변경하면 문제. 대신 hook 내부에서 `still_present` 체크를 참고해 분기한다. 구체적으로:
- `still_present == True` (hook이 delete 이전에 불림): 남은 activity 조회 시 자기 자신을 제외해야 하므로 `Activity.id != activity.id` 필터 추가.
- `still_present == False` (hook이 delete 이후에 불림): 추가 필터 불필요.

### 5. MongoDB 인덱스

`services/api/app/models/activity.py`의 `UserRouteStats.Settings.indexes`에 추가:

```python
IndexModel(
    [("userId", ASCENDING), ("lastActivityAt", DESCENDING)],
    name="userId_1_lastActivityAt_-1",
),
```

`lastActivityAt`은 신규 갱신 로직 이후 모든 문서에 값이 존재한다 (첫 activity 시점에 바로 set). Partial filter 없이 일반 컴파운드 인덱스로 충분.

**주의:** 기존 문서 중 `lastActivityAt`이 null인 레코드(갱신 로직 배포 이전의 데이터)는 backfill하지 않는다. 다음 activity가 들어올 때 `$max`로 자연스럽게 채워진다. 그 시점까지 이들 레코드는 홈 섹션에 나타나지 않지만, MY 탭의 캘린더/일별 리스트에는 이미 노출되고 있으므로 사용자가 재진입하면 복구 가능.

## 모바일 UI 설계

### 1. 홈 화면 레이아웃 (`lib/pages/home.dart`)

기존 순서: 인사말 → `HoldEditorButton` → "최근 벽 사진" 헤더 → `WallImageCarousel`

**추가:** `WallImageCarousel` 뒤에

- 섹션 헤더 (`Padding` + `Row`)
  - 좌측 컬럼: 타이틀 "최근 운동한 루트" (fontSize 20, fontWeight w800, letterSpacing -0.4, color `#0F1A2E`) + 서브라벨 "활동 기록 기준" (fontSize 13, color `Colors.grey[500]`)
  - 우측: `TextButton` "기록 전체" (color `#1E4BD8`, fontSize 14, fontWeight w700) → 탭 시 MainTab 인덱스 2로 전환
- 콘텐츠: `RecentClimbedRoutesSection` 위젯 — provider 구독하여 카드 리스트 / 빈 상태 / 로딩 / 에러 분기

### 2. `RecentClimbedRoutesSection` 위젯 (신규)

**파일:** `lib/widgets/home/recent_climbed_routes_section.dart`

`recentClimbedRoutesProvider`의 `AsyncValue<List<RouteData>>`를 구독. 상태별 렌더:

- **로딩:** `SizedBox(height: ..., child: Center(CircularProgressIndicator))`
- **에러:** "최근 운동한 루트를 불러오지 못했어요" + 재시도 버튼
- **빈 데이터:** 빈 상태 카드 (아래 참조)
- **데이터:** `Column`에 `RecentClimbedRouteCard` 최대 9개 (간격 10px, 수평 패딩 24px, routes_page.dart의 SliverPadding과 동일)

### 3. `RecentClimbedRouteCard` 위젯 (신규)

**파일:** `lib/widgets/home/recent_climbed_route_card.dart`

**원칙:** 기존 `RouteListItem` (`lib/widgets/home/route_list_item.dart`)과 **동일한 레이아웃**. 변경점은 두 가지:

1. **우상단 액션:** `PopupMenuButton<String>`(3-dot 메뉴) **제거**, 공유 `InkWell` 버튼만 유지. `Positioned(top:4, right:4)` 고정.
2. **오너 배지 1줄 추가:** place · wall 줄 아래에 `OwnerBadge` 위젯 배치. 본인 루트이면 숨김.

**나머지 구조 전부 동일:**
- `Material` + `InkWell` 래핑
- `LayoutBuilder`로 썸네일 크기 `constraints.maxWidth / 2.618`
- 좌측 썸네일 (grade chip), 우측 Expanded Column
- 오버라인 `{TYPE} · {gradeType}`
- 타이틀 (`route.title ?? route.grade`)
- place · wall 줄
- 하단 `✓ 완등 · 시도` + 우측 정렬 시간 (`timeago.format(lastAt)`)
- 로딩 오버레이

**탭 동작:** `RouteListItem._openViewer`와 동일한 로직 재사용 — `/routes/{id}` 로드 후 `RouteViewer` 이동. 403/404/기타 오류 시 snackbar (`_DailyRouteCard._navigateToRoute` 패턴 참고).

**툼스톤 처리:**
- `route.isDeleted == true` 또는 (`route.visibility == 'private'` && `route.owner.userId != currentUserId`): 카드에 회색 오버레이 + 배지 아이콘/텍스트 표시. 탭 시 snackbar만, 뷰어 이동 없음.
- 기존 `_DailyRouteCard`의 `isBlocked` / `blockedIcon` / `blockedText` 분기 로직 참고.

### 4. `OwnerBadge` 위젯 (신규, 공유 컴포넌트)

**파일:** `lib/widgets/common/owner_badge.dart`

```dart
class OwnerBadge extends StatelessWidget {
  final OwnerInfo owner;
  const OwnerBadge({super.key, required this.owner});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 1. 탈퇴 회원: 회색 인물 아이콘 + l10n.deletedUser
    // 2. 프로필 이미지 있음: CachedNetworkImage 원형(20x20)
    // 3. 프로필 이미지 없음: 파스텔 배경 원 + profile_id 첫 글자 이니셜
    // 텍스트: "@{profileId}" (탈퇴 시 l10n.deletedUser)
  }
}
```

- 원형 아바타 20-24px
- 아바타 우측 6px 간격 후 `@{profileId}` 텍스트 (fontSize 12, color `Colors.grey[600]`)
- 탈퇴 회원: 아바타는 `Icons.person_off_outlined` 회색, 텍스트 `l10n.deletedUser`

**l10n 키 추가:** `deletedUser` ("탈퇴한 회원" / "Deleted user" / "退会済み" / "Usuario eliminado")

### 5. 빈 상태 카드

홈 섹션이 빈 배열을 받으면:

```
┌───────────────────────────────────────────┐
│       🧗  아직 운동한 루트가 없어요         │
│         루트를 골라 첫 운동을 시작해보세요   │
│                                           │
│              [ 루트 보러 가기 → ]           │
└───────────────────────────────────────────┘
```

- 배경 흰색, 라운드 18, 수직 패딩 32
- CTA 탭 → `MainTab` 인덱스 1 (routes) 전환
- l10n 키 신규: `noClimbedRoutesYet`, `startFirstWorkoutHint`, `viewRoutes`

### 6. MY 페이지 `_DailyRouteCard` 확장

**파일:** `lib/pages/my_page.dart`의 `_DailyRouteCard` 위젯 수정

- 기존 `placeName` Text 아래, `if (isBlocked)` 툼스톤 라벨 아래에 `OwnerBadge(owner: ...)` 추가
- 본인 소유면 숨김
- 백엔드 응답에 `owner` 필드가 포함됐으므로 `route['owner']`로 접근

### 7. `MainTab` 탭 인덱스 Provider 승격

**파일:** `lib/pages/main_tab.dart`

현재 `final currentIndex = useState(0);` 를 Riverpod state provider로 승격.

**신규 파일:** `lib/providers/main_tab_provider.dart`

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'main_tab_provider.g.dart';

@riverpod
class MainTabIndex extends _$MainTabIndex {
  @override
  int build() => 0;
  void set(int index) => state = index;
}
```

`MainTabPage` 수정:
- `currentIndex.value` → `ref.watch(mainTabIndexProvider)`
- `onTap` → `ref.read(mainTabIndexProvider.notifier).set(index)`
- 기존 `myPageRefreshSignal` useState·`activityDirtyProvider` 체크 로직은 그대로 유지

홈의 "기록 전체" 탭: `ref.read(mainTabIndexProvider.notifier).set(2)`. 빈 상태 CTA "루트 보러 가기": `set(1)`.

### 8. `RouteData` / 모델 확장

**파일:** `lib/models/route_data.dart`

`OwnerInfo` 신규 클래스 + `RouteData`에 `owner`, `isDeleted` 필드 추가.

```dart
class OwnerInfo {
  final String userId;
  final String? profileId;
  final String? profileImageUrl;
  final bool isDeleted;

  const OwnerInfo({
    required this.userId,
    this.profileId,
    this.profileImageUrl,
    this.isDeleted = false,
  });

  factory OwnerInfo.fromJson(Map<String, dynamic> json) => OwnerInfo(
    userId: json['userId'] as String,
    profileId: json['profileId'] as String?,
    profileImageUrl: json['profileImageUrl'] as String?,
    isDeleted: json['isDeleted'] as bool? ?? false,
  );
}
```

`RouteData.fromJson`에서 `owner` 키가 있으면 파싱 (없으면 null — 기존 `/routes` 응답 호환).

`isDeleted`도 선택적 필드로 추가 (없으면 false — 기존 응답 호환).

### 9. Provider

**파일:** `lib/providers/recent_climbed_routes_provider.dart`

```dart
@riverpod
Future<List<RouteData>> recentClimbedRoutes(RecentClimbedRoutesRef ref) async {
  final response = await AuthorizedHttpClient.get('/my/recently-climbed-routes?limit=9');
  if (response.statusCode == 200) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return (decoded['data'] as List)
      .map((e) => RouteData.fromJson(e as Map<String, dynamic>))
      .toList();
  }
  throw Exception('Failed to load recently climbed routes');
}
```

**무효화 타이밍:** 활동 저장/삭제 후. 현재 `activityDirtyProvider`가 MY 탭 진입 시 체크용으로 사용되지만, 홈은 항상 렌더됨(IndexedStack). 따라서 `create_activity` / `delete_activity` 완료 직후 명시적 `ref.invalidate(recentClimbedRoutesProvider)`를 호출한다 (기존 `routesProvider` invalidate 호출과 동일 자리).

## 로컬라이제이션 변경

**`lib/l10n/app_{ko,en,ja,es}.arb`에 신규 키 추가**

| 키 | ko | en | ja | es |
|---|---|---|---|---|
| `recentlyClimbedRoutesTitle` | "최근 운동한 루트" | "Recently climbed" | "最近の活動" | "Rutas recientes" |
| `recentlyClimbedRoutesSubtitle` | "활동 기록 기준" | "By activity log" | "活動記録順" | "Por registro" |
| `viewAllRecords` | "기록 전체" | "All records" | "すべての記録" | "Todos" |
| `deletedUser` | "탈퇴한 회원" | "Deleted user" | "退会済みユーザー" | "Usuario eliminado" |
| `noClimbedRoutesYet` | "아직 운동한 루트가 없어요" | "No climbs logged yet" | "まだ活動記録がありません" | "Aún no hay actividad" |
| `startFirstWorkoutHint` | "루트를 골라 첫 운동을 시작해보세요" | "Pick a route to start your first workout" | "ルートを選んで運動を始めましょう" | "Elige una ruta y empieza" |
| `viewRoutes` | "루트 보러 가기" | "Browse routes" | "ルートを見る" | "Ver rutas" |

## 에러 처리

**API**
- `/my/recently-climbed-routes`: 인증 실패 시 401 (기존 `/my/*` 공통 동작). DB 조회 실패 시 500. 데이터 무결성 파손(Route doc 없음)은 해당 row 스킵하고 정상 200 응답 유지.
- `/my/daily-routes`: 오너 조인 실패 시 해당 row의 `owner.is_deleted=true`로 대체, 전체 응답은 200 유지.

**모바일**
- `recentClimbedRoutesProvider` 에러: 섹션 내 에러 UI + 재시도 버튼. 다른 홈 요소에는 영향 없음.
- 카드 탭 시 루트 로드 실패: 기존 `_navigateToRoute` snackbar 패턴 (403 private, 404 deleted, 기타 unavailable).

## 테스트

### API 유닛 테스트

**`tests/services/test_user_stats.py`**
- `on_activity_created` 후 `stats.last_activity_at == activity.started_at` 단언 (기존 `is None` 단언 교체)
- 늦게 들어온 activity(`started_at`이 기존 값보다 과거)의 `$max` 동작 검증
- `on_activity_deleted` 후, 삭제된 activity가 `lastActivityAt`과 일치했던 경우 재계산 값 검증
- 모든 activity가 삭제되어 stats doc이 제거되는 기존 케이스 유지

**`tests/models/test_activity.py`**
- `tests/models/test_activity.py:88`의 `assert stats.last_activity_at is None` 제거 또는 "아직 activity 없는 초기 상태" 문맥으로 좁힘

**신규 `tests/routers/test_my_recently_climbed_routes.py`**
- 기본 조회: 9개 정렬 순서 검증
- `limit` 파라미터 경계(1, 20, 초과) 검증
- 타 사용자 루트 포함 시 `owner` 필드 채워짐 검증
- 삭제된 루트 → `is_deleted=true` 응답 검증
- 비공개 루트 (타인) → `visibility=private` 응답 검증
- 탈퇴한 오너 → `owner.is_deleted=true` 검증
- public GCS URL 포맷 검증 (`storage.googleapis.com/...`)
- `lastActivityAt`이 null인 stats doc은 제외 검증

**`tests/routers/test_my.py`** (또는 daily-routes 테스트 파일)
- `/my/daily-routes` 응답에 `owner` 필드 포함 검증
- 본인/타인/탈퇴 오너 각 케이스 검증

### 모바일 검증

**정적 분석**
- `cd apps/mobile && flutter analyze` — 0 issues 유지

**코드 생성**
- `dart run build_runner build --delete-conflicting-outputs` — 신규 `recentClimbedRoutesProvider`, `mainTabIndexProvider`의 `.g.dart` 생성

**수동 검증 포인트** (시뮬레이터)
- 홈 섹션 최대 9개 카드 렌더링
- 오너 배지: 본인 숨김, 타인 표시, 탈퇴 회원 대체 라벨
- 삭제된 루트 툼스톤
- 비공개 루트 툼스톤 (탭 시 snackbar)
- 빈 상태 카드 CTA → routes 탭 전환
- "기록 전체" 링크 → MY 탭 전환, 자동으로 최근 활동 날짜 선택됨
- 활동 기록 후 홈 재진입 시 카드 최신화

## 구현 순서 제안

1. **선결**: `user_stats.py`의 `lastActivityAt` 갱신 로직 + 테스트 업데이트
2. MongoDB 인덱스 추가 (모델 indexes 배열)
3. `OwnerView` Pydantic 모델 + `GET /my/recently-climbed-routes` 엔드포인트 + 테스트
4. `/my/daily-routes` 응답 확장 + 테스트
5. 모바일 `RouteData.owner`/`isDeleted` + `OwnerInfo`
6. `mainTabIndexProvider` 승격
7. `OwnerBadge` 공유 컴포넌트 + l10n
8. `RecentClimbedRouteCard` + `RecentClimbedRoutesSection` + `recentClimbedRoutesProvider`
9. 홈 화면에 섹션 삽입
10. MY `_DailyRouteCard`에 `OwnerBadge` 적용
11. 활동 저장/삭제 경로에 `recentClimbedRoutesProvider` invalidate 연결
12. 시뮬레이터 QA

## 열린 질문

없음 — 브레인스토밍 과정에서 모두 해소됨.
