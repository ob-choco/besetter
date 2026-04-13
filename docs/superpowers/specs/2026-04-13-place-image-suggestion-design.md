# Place Image Suggestion — Design Spec

**Date:** 2026-04-13
**Status:** Draft
**Scope:** Mobile (`apps/mobile`) + API (`services/api`)

## Goal

사용자가 공용 암장(`gym` 타입)의 **대표 이미지**를 검수 제안할 수 있게 한다. 기존의 이름 · 위치 제안 흐름과 같은 시트(`place_selection_sheet.dart` Suggest 모드)에서 처리한다.

## Non-Goals

- 개인 암장(private) 대표 이미지 즉시 교체 — 이번 스코프 밖
- 기존 이미지 삭제 제안
- 여러 장 이미지 갤러리 제안

## Context

현재 `Suggest` 모드는 `gym` 타입 장소의 **이름**과 **위치**만 검수 제안으로 제출한다(`PlaceService.createSuggestion`, JSON body `/places/suggestions`). 서버의 `PlaceSuggestion` 모델에는 이미 `image_url` 필드가 존재하지만 클라이언트 · 엔드포인트 모두 이 필드를 사용하지 않는다.

같은 기회에, 의미가 불분명한 `Place.image_url` / `Place.thumbnail_url` 이중 필드 구조를 단순화한다. 서버는 이미 `/images/{blob}?type=<preset>` 동적 썸네일 엔드포인트(`routers/images.py:348`)를 제공하므로, 정적인 `thumbnail_url` 필드는 불필요하다.

## Data Model Changes

### Server (`services/api/app/models/place.py`, `routers/places.py`)

- `Place.image_url` → `Place.repr_image_url`
- `Place.thumbnail_url` **제거**
- `PlaceSuggestion.image_url` → `PlaceSuggestion.repr_image_url`
- `PlaceResponse`: `image_url` / `thumbnail_url` → `repr_image_url` (단일 필드)
- `_upload_place_image(content, ext) -> str` — 반환을 튜플에서 단일 URL로 변경, 200x200 `_thumb.jpg` 생성 코드 삭제
- `create_place` 엔드포인트를 새 시그니처에 맞게 수정

**DB 마이그레이션 없음.** 기존 도큐먼트에 대한 필드 리네임/드롭 스크립트는 실행하지 않는다.

### Mobile (`apps/mobile/lib/models/place_data.dart`)

- `PlaceData.thumbnailUrl` → `PlaceData.reprImageUrl`
- 모든 참조(`place_selection_sheet.dart`, 기타 리스트 카드 등)도 따라서 리네임

리스트 카드의 썸네일은 `reprImageUrl`에서 GCS blob path를 추출해 `{api_base}/images/{blob}?type=<preset>`로 조립한다. 프리셋 이름은 `services/api/app/services/thumbnail.py`의 `PRESETS`에서 확인하여 리스트용 작은 크기를 선택한다.

## UI & Interaction

### 위치

Suggest 모드 시트의 섹션 순서를 다음과 같이 변경:

1. **대표 이미지** (신규, 최상단 — `_isGymSuggest == true` 일 때만 노출)
2. 이름
3. 위치 (gym일 때만)

private 암장(`_isGymSuggest == false`)에서는 이미지 섹션 자체가 렌더되지 않는다.

### 상태 1 — 기존 이미지 있음 (`_suggestPlace.reprImageUrl != null`)

- 높이 120 정도의 원본 이미지 배경 (`CachedNetworkImage`)
- 우측 하단에 반투명 "📷 사진 변경" pill 오버레이
- 이미지 어디를 탭해도 피커 열림
- 새 이미지 선택 후에는 선택한 로컬 파일(`Image.file`)로 교체 표시, 우측 상단 `X` 버튼으로 원본 복귀(register 모드 패턴 재사용)

### 상태 2 — 이미지 없음 (`reprImageUrl == null`)

점선 테두리 CTA 카드 — 단순 placeholder가 아니라 적극적인 등록 유도:

- 중앙 정렬, padding 큼
- 카메라 아이콘
- 굵은 텍스트: "이 암장에 아직 사진이 없어요"
- 서브 텍스트: "첫 대표 사진을 등록해 주세요"
- 보라색(`_suggestAccentColor` `0xFF6750A4`) 버튼 "📷 사진 선택"
- 탭하면 피커 열림. 선택 후 모습은 상태 1의 "선택 후" 와 동일

### 상태 변수 (`_PlaceSelectionSheetState`)

```dart
File? _suggestImage;

Future<void> _pickSuggestImage() async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
  if (picked != null) {
    setState(() => _suggestImage = File(picked.path));
  }
}
```

### 제출 가능 판정

`_hasSuggestChanges` getter 확장:

```dart
bool get _hasSuggestChanges {
  final nameChanged = /* 기존 로직 */;
  return nameChanged || _suggestNewPosition != null || _suggestImage != null;
}
```

이름 · 위치 · 이미지 중 **아무거나 하나 이상** 변경하면 제출 가능.

### 제출 후 리셋

성공 시 기존 `_suggestNewPosition`, `_suggestNameController` 리셋 패턴과 함께 `_suggestImage = null`도 초기화.

## API Contract

### Client: `PlaceService.createSuggestion`

JSON → **multipart/form-data**로 전환. `createPlace`에서 이미 쓰는 `AuthorizedHttpClient.multipartPost` 헬퍼 재사용.

```dart
static Future<void> createSuggestion({
  required String placeId,
  String? name,
  double? latitude,
  double? longitude,
  String? imagePath,
}) async {
  final fields = <String, String>{
    'placeId': placeId,
    if (name != null) 'name': name,
    if (latitude != null) 'latitude': latitude.toString(),
    if (longitude != null) 'longitude': longitude.toString(),
  };
  final response = await AuthorizedHttpClient.multipartPost(
    '/places/suggestions',
    imagePath,
    fieldName: 'image',
    fields: fields,
  );
  if (response.statusCode != 201) {
    throw Exception('Failed to create suggestion. Status: ${response.statusCode}');
  }
}
```

### Server: `POST /places/suggestions`

기존 JSON body → `Form(...)` + `image: Optional[UploadFile] = File(None)` 형태로 변경.

- `image`가 제공되면 리팩터된 `_upload_place_image()`로 업로드 → 반환된 URL을 `PlaceSuggestion.repr_image_url`로 저장
- 이름 · 위치 · 이미지 중 **어떤 것도 제공되지 않으면** `400` 응답 (no-op 제안 방지)
- 응답 모델 `PlaceSuggestionView`는 기존대로 유지

## Testing

### Static (mobile)

```
cd apps/mobile && flutter analyze
```

에러 · 린트 없음.

### Unit (server)

`services/api/tests/` 의 기존 place 관련 pytest 스위트 통과:
- place CRUD (필드 리네임에 맞춰 테스트도 수정)
- suggestion 생성 (JSON → multipart 전환에 맞춰 수정)
- image-only 제안 / text-only 제안 / 혼합 제안 케이스

### Manual (cannot be verified by code)

실기기에서:
- 이미지 없는 암장에서 CTA 카드 노출 확인
- 이미지 있는 암장에서 오버레이 노출 확인
- 이미지만 선택하고 제출 → 성공 다이얼로그
- 이름 + 이미지 함께 제출 → 성공
- 리스트 카드 썸네일이 `/images/{blob}?type=<preset>`으로 정상 로드되는지 확인

## Scope & Files Touched

**Mobile**
- `apps/mobile/lib/services/place_service.dart`
- `apps/mobile/lib/models/place_data.dart`
- `apps/mobile/lib/widgets/editors/place_selection_sheet.dart`
- `thumbnailUrl` 참조가 있는 모든 파일 (grep으로 확인)

**Server**
- `services/api/app/models/place.py`
- `services/api/app/routers/places.py`
- 관련 pytest 테스트 파일

## Open Questions

없음.
