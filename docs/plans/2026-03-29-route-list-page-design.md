# Route List Page Design

## Goal

Routes 탭에 Figma "루트 리스트" 디자인 기반의 루트 목록 페이지를 구현한다.

## Architecture

- **API**: GET /routes에 `type` query parameter를 추가하여 서버사이드 필터링 지원
- **Flutter**: Routes 탭 placeholder를 전용 페이지로 교체하고, RouteCard를 Figma 디자인에 맞게 전면 개편
- 기존 route_card.dart의 공유/편집/삭제 로직을 유지하면서 UI만 변경

## Tech Stack

- FastAPI (API 수정)
- Flutter + hooks_riverpod (모바일)
- cached_network_image (이미지 캐싱)
- timeago (상대 시간 표시)

---

## 변경 범위

### 1. API: GET /routes type 필터 추가

`services/api/app/routers/routes.py`의 `get_routes` 엔드포인트에 `type` query parameter 추가.

- 값: `bouldering` | `endurance` | 없음(전체)
- MongoDB 쿼리에 `Route.type == type` 조건 추가

### 2. Flutter: RouteData 모델 확장

`route_data.dart`에 필드 추가:
- `overlayImageUrl: String?` — 오버레이 이미지 URL
- `overlayProcessing: bool` — 오버레이 생성 중 여부

### 3. Flutter: RoutesProvider 수정

`routes_provider.dart`에 type 필터 지원:
- `fetchRoutes(type)` 호출 시 query parameter에 `type` 포함
- 필터 변경 시 리스트 리셋 + 새로 fetch

### 4. Flutter: RouteCard 위젯 전면 개편

Figma 디자인 기반 카드 레이아웃:
- 큰 오버레이 이미지 (overlayImageUrl 우선, fallback imageUrl), 둥근 모서리
- 이미지 좌상단: 난이도 뱃지 (gradeColor 배경 + grade 텍스트)
- `overlayProcessing == true`이면 이미지 위 "이미지 생성 중" 라벨
- 이미지 하단: 루트 제목 (볼드), 공유 아이콘 버튼, 더보기(...) 팝업 메뉴
- 위치 정보: gymName + wallName (있으면 "GymName • WallName" 형식)
- 상대 시간 (timeago 패키지)

액션 (기존 로직 유지):
- 카드 탭 → RouteViewer
- 공유 버튼 → share_plus
- 더보기 → 편집하기, 삭제하기

### 5. Flutter: Routes 탭 페이지

`main_tab.dart`의 Routes placeholder를 `RoutesPage`로 교체:
- "Your Routes" 헤더 (Routes 볼드 강조)
- 필터 칩: All / Bouldering / Endurance
- 무한 스크롤 루트 카드 리스트 (기존 cursor 기반 페이지네이션)
- pull-to-refresh 지원

---

## 디자인 참조

Figma: `https://www.figma.com/design/NcvQLkVoxRIsvZzYO8kteB/BESETTER?node-id=2019-559`
