# Private Gym Tab & Edit Pane Extraction Design

**Date:** 2026-04-13

## Goal

사용자가 등록한 private 암장을 거리/검색과 무관하게 항상 별도 탭으로 노출하고, private 암장 편집을 즉시 반영 플로우로 완성한다. 아울러 점점 커지는 `place_selection_sheet.dart`에서 suggest/edit 패널을 별도 파일로 추출해 가독성을 확보한다.

## Background

현재 `PlaceSelectionSheet`는 `_loadNearbyPlaces()`로 근처 암장(gym + private-gym 혼합)을 불러오고, 이름 검색 시 `instantSearch()`로 대체한다. Private 암장은 결과 리스트 안에서 배경색/뱃지로 구분될 뿐, 거리가 멀면 아예 보이지 않는다. 사용자는 자기 소유 private 암장(홈월, 친구네 창고 등)을 언제든 빠르게 고르고 싶어 한다.

또한 private 암장 편집은 코드상 이미 존재(`_isGymSuggest == false` 경로, `PlaceService.updatePlace` 호출)하지만, 이미지 수정 UI가 gym 경로에만 노출돼 있어 사실상 이름/위치만 고칠 수 있다. `place_selection_sheet.dart`는 이미 1,205줄로 커져 있어 추가 기능을 넣을 때 파일 크기 문제도 함께 정리할 필요가 있다.

## Scope

### In Scope

1. **백엔드 엔드포인트 추가**: `GET /places/my-private` — 현재 유저가 소유한 모든 private 암장 반환 (페이징 없음)
2. **기존 엔드포인트 동작 변경**:
   - `GET /places/nearby`: `type == "private-gym"` 결과 제외
   - `GET /places/instant-search`: `type == "private-gym"` 결과 제외
3. **Flutter 탭 UI**:
   - `[근처 암장]` / `[내 프라이빗]` 두 탭, 기본은 `[근처 암장]`
   - 탭 전환 시 해당 탭의 리스트만 표시
   - 검색창에 입력 시 탭을 숨기고 gym 검색 결과를 단일 리스트로 표시 (검색어를 지우면 이전 탭으로 복귀)
   - `[내 프라이빗]` 탭이 비어 있을 때: "등록된 프라이빗 암장이 없습니다" 텍스트만 표시 (별도 CTA 없음 — 하단의 기존 "새 암장 등록하기" 버튼을 그대로 사용)
4. **Private 암장 이미지 수정 지원**: suggest/edit 패널에서 private 경로에도 이미지 섹션을 노출하고, 선택한 이미지를 `PlaceService.updatePlace`로 즉시 반영
5. **suggest/edit 패널 추출**: `_buildSuggestMode()`와 관련 헬퍼/상태를 `place_edit_pane.dart` (파일명 제안: `apps/mobile/lib/widgets/editors/place_edit_pane.dart`)로 이동. 새 파일은 "gym에는 제안, private에는 즉시 수정" 두 케이스 모두 처리.

### Out of Scope

- Private 암장 삭제 플로우
- Private 암장 목록의 페이징/정렬
- 내 모든 암장을 조회하는 새로운 상위 화면 (현재는 place selection sheet 내부에서만 사용)
- 프라이빗 암장을 다른 유저에게 공유하는 기능
- 기존에 nearby/instant-search가 private을 포함하던 동작에 의존하는 외부 호출부 조사 (내부 사용처는 place selection sheet 하나로 한정)

## Architecture

```
┌─────────────────────────────────────────┐
│  place_selection_sheet.dart              │
│  ┌───────────────────────────────────┐  │
│  │ Select Mode                       │  │
│  │  ├─ 검색창                         │  │
│  │  ├─ 탭: [근처] / [내 프라이빗]      │  │
│  │  └─ 리스트 (_buildPlaceItem)       │  │
│  ├───────────────────────────────────┤  │
│  │ Register Mode (기존)               │  │
│  └───────────────────────────────────┘  │
│                                         │
│  place_edit_pane.dart (NEW)             │
│  ┌───────────────────────────────────┐  │
│  │ Suggest/Edit Pane (추출된 위젯)    │  │
│  │  - gym: createSuggestion           │  │
│  │  - private-gym: updatePlace        │  │
│  │  - 이름/위치/이미지 모두 지원       │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────┐
│  PlaceService (Flutter)                  │
│  + getMyPrivatePlaces()                  │
│  (nearby/instantSearch 는 서버 변경으로   │
│   private 자동 제외됨 — 클라이언트 변경   │
│   없음)                                  │
└─────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────┐
│  services/api/app/routers/places.py      │
│  + GET /places/my-private                │
│  * GET /places/nearby (private 제외)     │
│  * GET /places/instant-search (private 제외) │
└─────────────────────────────────────────┘
```

## Detailed Design

### Backend

#### `GET /places/my-private`

**파라미터:** 없음 (인증만)

**응답:** `List[PlaceView]` — 거리는 `null` (기준점이 없음)

**쿼리:**

```python
candidates = await Place.find(
    Place.type == "private-gym",
    Place.created_by == current_user.id,
).sort(-Place.created_at).to_list()
```

정렬은 최신 등록 순(내림차순). `created_at`으로 정렬하여 유저가 방금 만든 것이 위로 올라오도록 한다.

#### `GET /places/nearby` 수정

기존 쿼리 필터에 `"type": "gym"` 추가:

```python
query_filter = {
    "type": "gym",
    "location": {
        "$nearSphere": { ... }
    }
}
```

기존에 있던 Python-side `if place.type == "private-gym" and str(place.created_by) != str(current_user.id): continue` 는 삭제(더 이상 private을 반환하지 않으므로 불필요).

#### `GET /places/instant-search` 수정

쿼리에 타입 필터 추가:

```python
candidates = await Place.find(
    {
        "type": "gym",
        "normalizedName": {"$regex": re.escape(normalized_query), "$options": "i"},
    }
).limit(20).to_list()
```

Private 필터링 루프 제거.

### Flutter

#### `PlaceService.getMyPrivatePlaces()`

새 메서드를 추가한다. 기존 `getNearbyPlaces`와 동일한 응답 구조(`List<PlaceData>`)를 반환.

```dart
static Future<List<PlaceData>> getMyPrivatePlaces() async {
  final response = await ApiClient.get('/places/my-private');
  final list = response.data as List;
  return list.map((e) => PlaceData.fromJson(e)).toList();
}
```

#### `PlaceSelectionSheet` 상태 추가

```dart
enum _SelectTab { nearby, private }

_SelectTab _activeTab = _SelectTab.nearby;
List<PlaceData> _nearbyPlaces = [];    // 기존 _places를 분리
List<PlaceData> _privatePlaces = [];
List<PlaceData> _searchResults = [];   // 검색 모드 전용
bool _loadingNearby = false;
bool _loadingPrivate = false;
bool _loadingSearch = false;
```

기존 `_places`, `_isLoading`, `_isSearchMode`는 위 필드로 대체한다. 렌더링 시 검색 모드 우선, 그 다음 활성 탭.

#### 로딩 전략

- 시트 진입 시 `_loadNearbyPlaces()` + `_loadMyPrivatePlaces()` 를 병렬로 호출 (두 탭 모두 클릭 즉시 결과가 보이도록)
- 두 로드는 독립 — 한쪽이 실패해도 다른쪽 표시
- 빈 상태 처리:
  - 근처 탭: 기존 "근처에 등록된 암장이 없습니다"
  - 프라이빗 탭: "등록된 프라이빗 암장이 없습니다"

#### 탭 바

검색창 아래(기존 위치) + 리스트 위에 탭 바. 검색어가 비어 있을 때만 탭 표시, 검색어가 있을 때는 탭 숨김 + 단일 리스트(gym 검색 결과).

```
Material Tabs 스타일 참고:
┌─────────────────────────┐
│ 📍 근처 암장  │ 🔒 내 프라이빗 │
│ ━━━━━━━━━━━  │              │
└─────────────────────────┘
```

활성 탭은 앱의 primary color (`Color(0xFF6750A4)`) 언더라인과 볼드 텍스트, 비활성 탭은 회색.

#### 검색 동작

- 검색어 입력 → 1초 디바운스 후 `instantSearch` 호출 → `_searchResults` 업데이트
- 검색 모드에서는 탭을 숨기고 단일 리스트 표시 (결과가 0개면 "검색 결과가 없습니다")
- 검색어를 지우면 탭 UI로 복귀하고 마지막 활성 탭 유지

#### `_buildPlaceItem` 재사용

기존 렌더러는 유지하되 `isPrivate` 분기(`🔒` 접두어, `FFF8E1` 배경, 오렌지 뱃지)는 그대로 사용. private 탭에서는 거리가 `null`이므로 거리 라인을 생략.

### Edit Pane 추출 (`place_edit_pane.dart`)

**목표:** `place_selection_sheet.dart`의 ~400줄(820~1149) 분리.

**새 위젯:**

```dart
class PlaceEditPane extends StatefulWidget {
  final PlaceData place;
  final VoidCallback onBack;
  final ValueChanged<PlaceEditResult> onCompleted;

  const PlaceEditPane({
    super.key,
    required this.place,
    required this.onBack,
    required this.onCompleted,
  });
}

class PlaceEditResult {
  final PlaceData? updatedPlace; // private 즉시 반영 시
  final bool suggestionSubmitted; // gym 제안 완료 시
  const PlaceEditResult({this.updatedPlace, this.suggestionSubmitted = false});
}
```

**상태 내부화:** 현재 시트 State에 있는 `_suggestNameController`, `_suggestNewPosition`, `_suggestMapController`, `_suggestImage`, `_isSubmitting` 을 `PlaceEditPane`의 State로 이동.

**분기 로직:** 내부에서 `widget.place.type == 'gym'` 으로 분기. `_isGymSuggest`에 해당하는 로컬 게터 유지.

**이미지 섹션 노출 변경:** 기존에는 gym 경로에만 이미지 섹션이 있었음. 추출 후에는 **gym/private 모두** 이미지 섹션을 노출한다. 이미지 선택 로직은 양쪽 동일하나 제출 경로가 다르다:

- gym: `PlaceService.createSuggestion(imagePath: ...)`
- private-gym: `PlaceService.updatePlace(imagePath: ...)` — `updatePlace`에 `imagePath` 파라미터 추가 필요

#### `PlaceService.updatePlace` 시그니처 확장

현재 `updatePlace`는 `AuthorizedHttpClient.put`으로 JSON body를 전송한다 (place_service.dart:74-92). 호출부는 `place_selection_sheet.dart:273` 한 곳뿐이다. 이미지 지원을 위해 `updatePlace`가 `String? imagePath`를 받아 multipart PUT으로 전환한다. `AuthorizedHttpClient.multipartRequest`는 이미 `method: 'PUT'`을 지원하므로(http_client.dart:178-210) 그걸 사용한다.

```dart
static Future<PlaceData> updatePlace(
  String placeId, {
  String? name,
  double? latitude,
  double? longitude,
  String? imagePath,
}) async {
  final fields = <String, String>{
    if (name != null) 'name': name,
    if (latitude != null) 'latitude': latitude.toString(),
    if (longitude != null) 'longitude': longitude.toString(),
  };
  final response = await AuthorizedHttpClient.multipartRequest(
    '/places/$placeId',
    imagePath,
    fieldName: 'image',
    fields: fields,
    method: 'PUT',
  );
  if (response.statusCode == 200) {
    return PlaceData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }
  throw Exception('Failed to update place. Status: ${response.statusCode}');
}
```

백엔드의 `PUT /places/{place_id}` 역시 이미지 업로드를 지원해야 한다 — 현재 구현은 `UpdatePlaceRequest` BaseModel(JSON)로 이름/좌표만 받는다. `POST /places`와 동일한 multipart 방식으로 변경한다. 호출부가 모바일 `updatePlace` 하나뿐이므로 클라이언트와 동시 배포하면 JSON body 뒷호환은 필요 없다.

#### 백엔드 `PUT /places/{place_id}` 수정

`UpdatePlaceRequest` 대신 multipart form 파라미터로 변경 (create 엔드포인트와 동일한 패턴):

```python
@router.put("/{place_id}", response_model=PlaceView)
async def update_place(
    place_id: str,
    name: Optional[str] = Form(None),
    latitude: Optional[float] = Form(None),
    longitude: Optional[float] = Form(None),
    image: Optional[UploadFile] = File(None),
    current_user: User = Depends(get_current_user),
):
    ...
    if image is not None and image.filename:
        file_ext = os.path.splitext(image.filename)[1].lower()
        if file_ext not in (".jpg", ".jpeg", ".png"):
            raise HTTPException(...)
        content = await image.read()
        place.cover_image_url = _upload_place_image(content, file_ext)
    ...
```

기존 이미지 교체 시 GCS의 이전 blob은 남겨둔다(삭제 플로우는 out of scope).

## Data Model

**변경 없음.** `Place` 문서 스키마는 그대로 유지.

## Error Handling

- `getMyPrivatePlaces` 실패: private 탭 빈 상태로 표시 + SnackBar로 에러 알림
- `updatePlace` 이미지 업로드 실패: 기존과 동일하게 "요청에 실패했습니다. 다시 시도해주세요."
- `PUT /places/{place_id}` 권한: 기존과 동일 (`created_by != current_user` 이거나 `type != private-gym` 이면 403)

## Testing Strategy

### Backend (`services/api`)

- `GET /places/my-private` — 다른 유저의 private은 필터되는지, gym은 제외되는지, `created_at` 내림차순인지
- `GET /places/nearby` — private 제외 확인
- `GET /places/instant-search` — private 제외 확인
- `PUT /places/{id}` — 이미지 multipart 업로드 동작, 권한 검사 유지

### Frontend (`apps/mobile`)

- `flutter analyze` 통과
- 기존 위젯 테스트가 있다면 갱신 (place_selection_sheet에 테스트가 있는지 확인 필요)

## Migration / Rollout

- 백엔드 API 호환성: `GET /places/nearby` 응답에서 private이 빠지는 것이 유일한 breaking change. 내부 사용처는 place selection sheet 뿐이라 클라이언트 업데이트와 동시에 배포 가능. 구버전 클라이언트는 private이 nearby에 없어도 치명적이지 않음(버튼으로 검색/등록은 가능).
- `PUT /places/{id}` JSON body → multipart 전환: 호출부가 모바일 `PlaceService.updatePlace` 하나뿐(grep 확인 완료)이라 클라이언트와 동시 배포하면 뒷호환 불필요. 구버전 클라이언트는 private 수정 시 422를 받게 되나 기능 자체가 기존에도 불완전했으므로 수용 가능한 리그레션.
- 앱 강제 업데이트(`minAppVersion`)를 함께 올릴지 여부는 배포 시점에 판단(본 spec 범위 외).
