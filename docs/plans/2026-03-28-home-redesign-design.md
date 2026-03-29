# Home 화면 개편

## 개요

Figma 디자인에 맞춰 Home 화면을 개편한다. 기존 이미지 그리드 캐로셀 + 루트 리스트 구조를 벽 사진 카드 캐로셀 + Take Wall Photo 버튼 구조로 변경하고, BottomNavigationBar(Home, Routes, Menu)를 추가한다.

## 페이지 구조

```
Scaffold
├── body: Column
│   ├── "Your Climbing Walls" 타이틀
│   └── WallImageCarousel
│       ├── WallCard x N (최근 9건)
│       └── "더보기" 카드 (마지막)
├── bottomSheet: "Take Wall Photo" 버튼
└── bottomNavigationBar: Home / Routes / Menu
```

- 기존 AppBar의 Settings 메뉴 아이콘 제거. Settings 진입은 Menu 탭으로 이동.
- 기존 RouteList 섹션은 Home에서 제거 (향후 Routes 탭에서 구현).
- 기존 가이드 버블, 컨페티 등 UX 요소는 유지.

## BottomNavigationBar

| 탭 | 아이콘 | 화면 |
|----|--------|------|
| Home | Icons.home | Home 화면 (이번 구현 대상) |
| Routes | Icons.list | Placeholder (빈 화면) |
| Menu | Icons.menu | Settings 페이지 (기존 `SettingPage`) |

- `IndexedStack` + `BottomNavigationBar` 패턴으로 구현.
- 기존 `main.dart`의 라우팅 구조를 수정하여 탭 네비게이션을 최상위에 배치.

## WallImageCarousel

### 패키지

`carousel_slider` (https://pub.dev/packages/carousel_slider) 사용.
- `enlargeCenterPage: true` — 중앙 카드 확대, 좌우 카드 축소
- 기본 스냅 + 관성 스크롤로 자연스러운 캐로셀 느낌

### 데이터

기존 `imagesProvider` 그대로 사용. `GET /images?sort=uploadedAt:desc&limit=9` 응답의 `ImageData` 목록.

### 카드 구성 (WallCard)

Figma 디자인 기준:
- **벽 이미지**: 전체 배경, 라운드 처리
- **하단 오버레이** (그라데이션 어두운 배경):
  - "Recent Wall Photos" 라벨
  - 암장 이름 (`gymName`)
  - 벽 이름 (`wallName`) — 있는 경우에만 표시
  - 날짜 (`uploadedAt`)
- **우하단 버튼 2개**:
  - **"Create Route"** 버튼 → `EditModeDialog`에서 볼더링/지구력 선택 (Wall Edit 옵션 제외)
  - **"Edit Wall"** 버튼 → 바로 `SprayWallEditorPage`로 이동

### 더보기 카드

캐로셀 마지막 위치에 "더보기" 카드 배치. 탭 시 `/images` (ImageListPage)로 이동.

### 빈 상태

이미지가 0건일 때 빈 상태 UI 표시 ("아직 벽 사진이 없어요" + Take Wall Photo 유도).

## Take Wall Photo 버튼

- 화면 하단에 고정 배치 (bottomSheet 또는 Column 하단)
- 카메라 아이콘 + "Take Wall Photo" 텍스트
- 탭 시 기존 `HoldEditorButton`의 팝업 메뉴 동작과 동일:
  1. 사진 촬영 (카메라)
  2. 갤러리에서 선택
  3. 기존 벽 선택 (`/images`)
- 기존 `HoldEditorButton`의 이미지 검증 로직(해상도, 비율) 및 `ImagePreviewPage` 이동 로직 재사용.

## 파일 구조

| 파일 | Action | 역할 |
|------|--------|------|
| `lib/pages/home.dart` | Modify | 전체 Home 화면 레이아웃 개편 |
| `lib/pages/main_tab.dart` | Create | BottomNavigationBar + IndexedStack 탭 컨테이너 |
| `lib/widgets/home/wall_image_carousel.dart` | Create | 캐로셀 위젯 |
| `lib/widgets/home/wall_card.dart` | Create | 개별 벽 카드 위젯 |
| `lib/main.dart` | Modify | 라우팅 구조 수정 (MainTabPage를 인증 후 메인 화면으로) |

기존 `lib/widgets/home/image_carousel.dart`, `lib/widgets/home/image_card.dart`는 더 이상 Home에서 사용하지 않지만, 다른 곳에서 참조 가능하므로 삭제하지 않고 유지.
