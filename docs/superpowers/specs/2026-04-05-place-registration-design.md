# Place Registration & Selection Feature Design

유저가 생성하는 클라이밍 암장(Place) 데이터베이스. 스프레이월 에디터에서 벽 사진의 EXIF GPS를 기반으로 근처 암장을 추천하고, 없으면 신규 등록할 수 있다.

## Background

- Google Places API 대신 자체 Place DB를 구축하여 비용 $0 달성
- 한 유저가 암장을 등록하면 다음 유저는 선택만 하면 됨 (플라이휠)
- 위치기반서비스사업 신고 예정 (GPS 좌표 서버 전송)

## Data Model

### Place Collection

```
collection: places
{
  _id:        ObjectId
  name:       String          // "더클라임 강남점"
  type:       String          // "gym" | "private-gym"
  latitude:   Number          // 37.516523
  longitude:  Number          // 127.019823
  createdBy:  ObjectId (ref)  // 최초 등록 userId
  createdAt:  Date
}

index: 2dsphere on { latitude, longitude }
```

### Type Visibility Rules

- `gym`: 모든 유저의 nearby 검색에 노출. 커뮤니티 공유 자산.
- `private-gym`: `createdBy` 본인에게만 노출. 다른 유저 검색 결과에 미포함. 개인 연습 공간용.

### Image Data 변경

기존 `gymName: String` 필드를 `placeId: ObjectId (ref)` 로 교체. 벽 위치(`wallName`), 만기일(`wallExpirationDate`)은 기존 유지.

## API Design

### GET /places/nearby

근처 암장 목록 조회. 사진 EXIF GPS 또는 기기 위치 기반.

```
Query Parameters:
  latitude:  number (required)
  longitude: number (required)
  radius:    number (optional, default: 100, unit: meters)

Response: 200
[
  {
    id:        string
    name:      string
    type:      "gym" | "private-gym"
    latitude:  number
    longitude: number
    distance:  number (meters)
    createdBy: string
  }
]
```

**서버 필터 로직:**
- `type=gym` → 모든 유저에게 반환
- `type=private-gym` → 요청자의 userId === createdBy 일 때만 반환

### POST /places

새 암장(Place) 등록.

```
Body:
  name:      string (required)
  latitude:  number (required)
  longitude: number (required)
  type:      "gym" | "private-gym" (optional, default: "gym")

Response: 201
{
  id:        string
  name:      string
  type:      "gym" | "private-gym"
  latitude:  number
  longitude: number
  createdBy: string  // 서버에서 인증된 userId 자동 설정
}
```

## User Flow

### 진입점

스프레이월 에디터 → "클라이밍 암장 정보" ListTile 탭

### Flow

```
[암장 정보 탭]
  → 사진 EXIF에서 GPS 추출
  → GET /places/nearby 호출
  → [암장 선택 바텀시트]
      ├─ 근처 암장 있음 → 리스트에서 탭하여 선택 → placeId 연결 → 시트 닫힘
      └─ 근처 암장 없음 또는 해당 없음
          → "새 암장 등록하기" 탭
          → [새 암장 등록 시트]
              - 암장 이름 입력 (필수)
              - OSM 지도에 EXIF GPS 핀 표시 (탭하여 이동 가능)
              - 개인 암장 토글 (OFF=gym, ON=private-gym)
              → "등록하기" 탭
              → POST /places 호출
              → placeId 연결 → 시트 닫힘
```

### EXIF GPS 없는 경우

1. 기기 현재 위치로 fallback (`geolocator` 패키지)
2. 위치 권한도 없으면 → 지도 없이 이름만 입력 + 좌표 수동 설정 안내

### 선택 완료 후

에디터 화면의 "클라이밍 암장 정보" subtitle에 선택된 암장 이름 + ✓ 표시.
다시 탭하면 바텀시트 재오픈 (변경 가능).

## Screen Specs

### ② 암장 선택 바텀시트

- `showModalBottomSheet` with `isScrollControlled: true`
- 상단: 드래그 핸들 + "암장 선택" 타이틀
- 근처 암장 섹션: "📍 근처 암장" 라벨 + 리스트
  - 각 아이템: 암장 이름 + 거리(m) + type 배지
  - `gym`: 기본 배경 (#F7F8FA)
  - `private-gym`: 노란 배경 (#FFF8E1) + 🔒 + "나만 보임" + orange 배지
- 하단: 점선 테두리 "새 암장 등록하기" 버튼

### ③ 새 암장 등록 시트

- 암장 이름: TextField (필수, autofocus)
- 지도: `flutter_map` + OpenStreetMap 타일
  - 초기 위치: EXIF GPS 좌표
  - 핀: 빨간색 마커, 지도 탭으로 위치 이동
  - 우측 하단: "© OpenStreetMap" 귀속 표시 (필수)
- 개인 암장 토글: Switch widget
  - OFF (기본): type=gym, 설명 "나만 볼 수 있는 암장"
  - ON: type=private-gym
- 하단: "등록하기" FilledButton

## Tech Stack

| 구성 요소 | 패키지 | 비용 |
|-----------|--------|------|
| 지도 | `flutter_map` + OpenStreetMap 타일 | $0 |
| 좌표 유틸 | `latlong2` | $0 |
| EXIF 추출 | `exif` (또는 `native_exif`) | $0 |
| 위치 fallback | `geolocator` (EXIF 없을 때) | $0 |

## Edge Cases

1. **DB 비어있음 (첫 사용자)**: nearby 결과 0건 → "새 암장 등록" 버튼이 눈에 띄게 표시
2. **중복 등록**: 동일 이름 + 반경 100m 내 기존 암장 있으면 → "혹시 이 암장인가요?" 확인 (POST /places 서버에서 체크)
3. **EXIF GPS 없음**: 기기 위치 fallback → 위치 권한 없으면 좌표 0,0 + 안내 문구
4. **private-gym 등록 후**: 해당 유저만 nearby에서 조회 가능. 다른 유저는 해당 place 미노출.

## Legal

- 위치기반서비스사업 신고 예정 (GPS 좌표 서버 전송 → 개인위치정보 해당)
- 소상공인/1인 창조기업은 사업 개시 후 1개월 내 신고 가능
- 개인위치정보 수집·이용 동의 필요 (위치정보법 제15조)

## Out of Scope (v1)

- 암장 상세 페이지
- 암장 수정/삭제
- 암장 사진 등록
- 텍스트 검색 (이름으로 검색)
- 암장 리뷰/평점
