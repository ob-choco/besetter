# Home.dart 리팩터링 설계

## 개요

`apps/mobile/lib/pages/home.dart`가 약 1,000줄의 God Class로 되어 있어 리팩터링이 필요함. 상태 관리를 Provider에서 Riverpod으로 전환하고, UI 컴포넌트를 분리하여 유지보수성을 개선함.

## 결정 사항

| 항목 | 결정 |
|-----|------|
| 상태 관리 | Riverpod (Provider에서 전환) |
| Provider 정의 방식 | 코드 생성 (`@riverpod` 어노테이션) |
| Repository 레이어 | 추가하지 않음 (Provider에서 직접 API 호출) |
| 위젯 분리 | 기능별 파일 분리 (`widgets/home/`) |
| 마이그레이션 전략 | 전체 일괄 전환 |
| Hooks | 사용 (`hooks_riverpod` + `flutter_hooks`) |

## 의존성 변경

### 추가
```yaml
dependencies:
  flutter_riverpod: ^2.4.9
  hooks_riverpod: ^2.4.9
  flutter_hooks: ^0.20.4

dev_dependencies:
  riverpod_generator: ^2.3.9
  build_runner: ^2.4.8
  riverpod_annotation: ^2.3.3
```

### 제거
```yaml
dependencies:
  provider: ^6.x.x
```

## 프로젝트 구조

```
lib/
├── main.dart                    # ProviderScope로 앱 래핑
├── providers/
│   ├── auth_provider.dart       # AuthState → authProvider
│   ├── auth_provider.g.dart     # 생성됨
│   ├── image_provider.dart      # ImageProvider → imagesProvider
│   ├── image_provider.g.dart    # 생성됨
│   ├── route_provider.dart      # RouteProvider → routesProvider
│   └── route_provider.g.dart    # 생성됨
├── pages/
│   └── home.dart                # HookConsumerWidget으로 변경
└── widgets/
    └── home/
        ├── image_carousel.dart
        ├── image_card.dart
        ├── route_list.dart
        ├── route_card.dart
        └── edit_mode_dialog.dart
```

## Provider 구조

### routes_provider.dart

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'routes_provider.g.dart';

@freezed
class RoutesState with _$RoutesState {
  const factory RoutesState({
    required List<RouteData> routes,
    String? nextToken,
  }) = _RoutesState;
}

@riverpod
class Routes extends _$Routes {
  @override
  Future<RoutesState> build() async {
    return _fetchInitial();
  }

  Future<RoutesState> _fetchInitial() async {
    final response = await AuthorizedHttpClient.get('/routes?sort=createdAt:desc&limit=4');
    // 파싱 로직...
    return RoutesState(routes: routes, nextToken: nextToken);
  }

  Future<void> fetchMore() async {
    final current = state.valueOrNull;
    if (current == null || current.nextToken == null) return;
    // 추가 로딩 로직...
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  Future<bool> deleteRoute(String id) async {
    // 삭제 후 refresh 호출
  }
}

@riverpod
Future<int> routesTotalCount(RoutesTotalCountRef ref) async {
  final response = await AuthorizedHttpClient.get('/routes/count');
  return jsonDecode(response.body)['totalCount'];
}
```

### images_provider.dart

```dart
@riverpod
class Images extends _$Images {
  @override
  Future<List<ImageData>> build() async {
    return _fetchImages();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  Future<PolygonData?> createImage(File image) async {
    // 업로드 후 refresh 호출
  }
}
```

### auth_provider.dart

기존 `AuthState` 로직을 `@riverpod class Auth`로 전환.

## 위젯 분리 구조

### widgets/home/image_carousel.dart

```dart
class ImageCarousel extends HookConsumerWidget {
  // PageController는 usePageController()로 관리
  // imagesProvider를 watch하여 데이터 표시
  // 빈 상태 → WelcomeSection 표시
  // 데이터 있음 → PageView + DotsIndicator
}
```

### widgets/home/image_card.dart

```dart
class ImageCard extends ConsumerWidget {
  final ImageData image;
  final VoidCallback onTap;
  // 단일 이미지 카드 UI
  // 탭 시 EditModeDialog 표시는 상위에서 처리
}
```

### widgets/home/edit_mode_dialog.dart

```dart
class EditModeDialog extends ConsumerWidget {
  final ImageData image;
  // Wall Edit / Bouldering / Endurance 버튼 3개
  // 각 버튼 탭 시 polygon 데이터 fetch → 네비게이션
  // 로딩 상태는 AsyncValue로 처리
}
```

### widgets/home/route_card.dart

```dart
class RouteCard extends ConsumerWidget {
  final RouteData route;
  // 루트 카드 UI + 메뉴 (수정/삭제)
  // 삭제 시 routesProvider.deleteRoute() 호출
}
```

### widgets/home/route_list.dart

```dart
class RouteList extends HookConsumerWidget {
  // ScrollController는 useScrollController()로 관리
  // 스크롤 80% 도달 시 routesProvider.fetchMore() 호출
  // SliverList로 렌더링
}
```

### pages/home.dart (리팩터링 후)

```dart
class HomePage extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(...),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: HoldEditorButton(...)),
          SliverToBoxAdapter(child: ImageCarousel()),
          SliverToBoxAdapter(child: _buildRouteHeader(ref)),
          RouteList(),  // SliverList 반환
        ],
      ),
    );
  }
}
```

## 로딩/에러 처리

### AsyncValue 패턴 활용

```dart
class HomePage extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routesAsync = ref.watch(routesProvider);

    return routesAsync.when(
      loading: () => CircularProgressIndicator(),
      error: (e, st) => ErrorWidget(e),
      data: (state) => _buildContent(state),
    );
  }
}
```

### 개별 액션 로딩

```dart
// 삭제, polygon fetch 등
final isDeleting = useState(false);
```

### 기타

- `GuideBubble`: 기존 로직 유지, `useEffect`로 초기화
- `Confetti`: 기존 다이얼로그 로직 유지

## 제거되는 코드

| 항목 | 이유 |
|-----|------|
| `_routes`, `_routesNextToken`, `_isLoadingMore` | Provider로 이동 |
| `_fetchNextRoutes()`, `_fetchTotalCount()` | Provider로 이동 |
| `_showLoadingOverlay()`, `_hideLoadingOverlay()` | AsyncValue로 대체 |
| `navigateAndRefresh()` | `ref.invalidate()` 패턴으로 대체 |

## 예상 결과

- home.dart: ~1,000줄 → ~150줄
- 위젯 재사용성 향상
- 테스트 용이성 개선
- 상태 관리 일관성 확보

## 마이그레이션 순서

| 단계 | 작업 | 파일 |
|-----|------|------|
| 1 | 패키지 추가 및 build_runner 설정 | `pubspec.yaml` |
| 2 | main.dart에 ProviderScope 래핑 | `main.dart` |
| 3 | auth_provider.dart 전환 | `providers/` |
| 4 | images_provider.dart 전환 | `providers/` |
| 5 | routes_provider.dart 전환 | `providers/` |
| 6 | home 위젯들 분리 생성 | `widgets/home/` |
| 7 | home.dart 리팩터링 | `pages/home.dart` |
| 8 | 기존 provider 파일 제거 | `providers/` (구버전) |
| 9 | 다른 페이지들 Consumer 전환 | 나머지 pages |

## 검증

- 각 단계 후 `flutter build` 및 앱 실행 확인
- 기존 기능 동작 여부 테스트
