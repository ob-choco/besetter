# Route List Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Routes 탭에 Figma 디자인 기반 루트 목록 페이지를 구현하고, API에 type 필터를 추가한다.

**Architecture:** API에 type query parameter를 추가하여 서버사이드 필터링 지원. Flutter에서 RoutesProvider를 type 필터 지원으로 확장하고, RouteCard를 Figma 디자인으로 전면 개편하며, Routes 탭 placeholder를 실제 페이지로 교체한다.

**Tech Stack:** FastAPI + Beanie (API), Flutter + hooks_riverpod + cached_network_image + timeago (Mobile)

---

### Task 1: API — GET /routes에 type 필터 추가

**Files:**
- Modify: `services/api/app/routers/routes.py:194-202`

- [ ] **Step 1: get_routes에 type 파라미터 추가**

`services/api/app/routers/routes.py`의 `get_routes` 함수 시그니처에 `type` 파라미터를 추가하고, MongoDB 쿼리에 필터 조건을 추가한다.

```python
@router.get("", response_model=RouteListResponse)
async def get_routes(
    current_user: User = Depends(get_current_user),
    sort: str = Query("createdAt:desc", description="정렬 기준 (예: createdAt:desc)"),
    limit: int = Query(10, ge=1, le=100),
    next: Optional[str] = None,
    type: Optional[RouteType] = Query(None, description="루트 타입 필터 (bouldering, endurance)"),
):
    # 쿼리 빌더 초기화
    query = Route.find(Route.user_id == current_user.id, Route.is_deleted != True)

    # 타입 필터
    if type:
        query = query.find(Route.type == type)
```

- [ ] **Step 2: 서버 임포트 확인 및 테스트**

Run: `cd /Users/htjo/besetter/services/api && python -c "from app.routers.routes import router; print('OK')"`

- [ ] **Step 3: Commit**

```bash
git add services/api/app/routers/routes.py
git commit -m "feat(api): add type filter to GET /routes endpoint"
```

---

### Task 2: Flutter — RouteData 모델에 overlay 필드 추가

**Files:**
- Modify: `apps/mobile/lib/models/route_data.dart`

- [ ] **Step 1: overlayImageUrl, overlayProcessing 필드 추가**

`RouteData` 클래스에 두 필드를 추가한다.

클래스 필드 추가 (wallExpirationDate 뒤):
```dart
  final String? overlayImageUrl;
  final bool overlayProcessing;
```

생성자에 추가:
```dart
    this.overlayImageUrl,
    this.overlayProcessing = false,
```

fromJson에 추가:
```dart
      overlayImageUrl: json['overlayImageUrl'],
      overlayProcessing: json['overlayProcessing'] ?? false,
```

toJson에 추가:
```dart
        'overlayImageUrl': overlayImageUrl,
        'overlayProcessing': overlayProcessing,
```

- [ ] **Step 2: static analysis 확인**

Run: `cd apps/mobile && flutter analyze`

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/models/route_data.dart
git commit -m "feat(mobile): add overlay fields to RouteData model"
```

---

### Task 3: Flutter — timeago 패키지 추가

**Files:**
- Modify: `apps/mobile/pubspec.yaml`

- [ ] **Step 1: pubspec.yaml에 timeago 추가**

dependencies 섹션에 추가:
```yaml
  timeago: ^3.7.0
```

- [ ] **Step 2: 패키지 설치**

Run: `cd apps/mobile && flutter pub get`

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock
git commit -m "feat(mobile): add timeago package for relative timestamps"
```

---

### Task 4: Flutter — RoutesProvider에 type 필터 지원 추가

**Files:**
- Modify: `apps/mobile/lib/providers/routes_provider.dart`

- [ ] **Step 1: provider를 family로 변경하여 type 파라미터 지원**

현재 `@riverpod class Routes`를 type 파라미터를 받도록 수정한다. Riverpod의 family 패턴을 사용한다.

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/route_data.dart';
import '../models/paginated_response.dart';
import '../services/http_client.dart';

part 'routes_provider.g.dart';

class RoutesState {
  final List<RouteData> routes;
  final String? nextToken;
  final bool isLoadingMore;

  const RoutesState({
    this.routes = const [],
    this.nextToken,
    this.isLoadingMore = false,
  });

  RoutesState copyWith({
    List<RouteData>? routes,
    String? nextToken,
    bool? isLoadingMore,
  }) {
    return RoutesState(
      routes: routes ?? this.routes,
      nextToken: nextToken,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

@riverpod
class Routes extends _$Routes {
  @override
  Future<RoutesState> build({String? type}) async {
    return _fetchInitial();
  }

  Future<RoutesState> _fetchInitial() async {
    final queryParams = <String, String>{
      'sort': 'createdAt:desc',
      'limit': '10',
    };
    if (type != null) {
      queryParams['type'] = type!;
    }
    final uri = Uri.parse('/routes').replace(queryParameters: queryParams);
    final response = await AuthorizedHttpClient.get(uri.toString());

    if (response.statusCode == 200) {
      final result = PaginatedResponse.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
        (json) => RouteData.fromJson(json),
      );
      return RoutesState(
        routes: result.data,
        nextToken: result.nextToken,
      );
    } else {
      throw Exception('Failed to load routes');
    }
  }

  Future<void> fetchMore() async {
    final current = state.valueOrNull;
    if (current == null || current.nextToken == null || current.isLoadingMore) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final queryParams = <String, String>{
        'sort': 'createdAt:desc',
        'limit': '10',
        'next': current.nextToken!,
      };
      if (type != null) {
        queryParams['type'] = type!;
      }
      final uri = Uri.parse('/routes').replace(queryParameters: queryParams);
      final response = await AuthorizedHttpClient.get(uri.toString());

      if (response.statusCode == 200) {
        final result = PaginatedResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
          (json) => RouteData.fromJson(json),
        );
        state = AsyncData(RoutesState(
          routes: [...current.routes, ...result.data],
          nextToken: result.nextToken,
          isLoadingMore: false,
        ));
      } else {
        state = AsyncData(current.copyWith(isLoadingMore: false));
        throw Exception('Failed to load more routes');
      }
    } catch (e) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
      rethrow;
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<bool> deleteRoute(String routeId) async {
    try {
      final response = await AuthorizedHttpClient.delete('/routes/$routeId');
      if (response.statusCode == 204) {
        await refresh();
        ref.invalidate(routesTotalCountProvider);
        return true;
      } else {
        throw Exception('Failed to delete route');
      }
    } catch (e) {
      debugPrint('Error deleting route: $e');
      return false;
    }
  }
}

@riverpod
Future<int> routesTotalCount(RoutesTotalCountRef ref) async {
  final response = await AuthorizedHttpClient.get('/routes/count');
  if (response.statusCode == 200) {
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['totalCount'] as int;
  }
  throw Exception('Failed to fetch total count');
}
```

주요 변경:
- `build()` → `build({String? type})` family 파라미터
- `_fetchInitial()`과 `fetchMore()`에서 `type`이 있으면 queryParams에 추가
- `limit`을 `'4'`에서 `'10'`으로 변경 (Routes 탭 전용 리스트이므로)

- [ ] **Step 2: build_runner로 코드 생성**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 3: 기존 provider 호출 부분 수정**

홈 화면의 route_list.dart 등에서 `routesProvider`를 `routesProvider()`로 변경해야 한다. 기존 호출을 검색하여 업데이트.

Run: `grep -rn "routesProvider" apps/mobile/lib/ --include="*.dart"` 로 사용처를 확인하고 모두 `routesProvider()` (type 없이) 로 변경.

- [ ] **Step 4: static analysis 확인**

Run: `cd apps/mobile && flutter analyze`

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/providers/routes_provider.dart apps/mobile/lib/providers/routes_provider.g.dart
git commit -m "feat(mobile): add type filter support to routes provider"
```

---

### Task 5: Flutter — RouteCard 위젯 전면 개편

**Files:**
- Modify: `apps/mobile/lib/widgets/home/route_card.dart`

- [ ] **Step 1: RouteCard를 Figma 디자인으로 재작성**

기존 로직(공유, 편집, 삭제, 뷰어 네비게이션)은 유지하면서 UI를 전면 교체한다.

```dart
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/route_data.dart';
import '../../services/http_client.dart';
import '../../providers/routes_provider.dart';
import '../../pages/viewers/route_viewer.dart';
import '../../pages/editors/route_editor_page.dart';

class RouteCard extends ConsumerStatefulWidget {
  final RouteData route;
  final VoidCallback? onInteraction;

  const RouteCard({
    super.key,
    required this.route,
    this.onInteraction,
  });

  @override
  ConsumerState<RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends ConsumerState<RouteCard> {
  bool _isLoading = false;

  void _setLoading(bool value) {
    if (mounted) setState(() => _isLoading = value);
  }

  // --- 기존 액션 메서드 (_navigateToViewer, _handleEdit, _handleDelete, _handleShare) 유지 ---

  Future<void> _navigateToViewer() async {
    widget.onInteraction?.call();
    _setLoading(true);
    try {
      final response = await AuthorizedHttpClient.get('/routes/${widget.route.id}');
      if (response.statusCode == 200) {
        final routeData = RouteData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => RouteViewer(routeData: routeData)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
      );
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _handleEdit() async {
    _setLoading(true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RouteEditorPage(
            routeId: widget.route.id,
            editType: EditType.edit,
            initialMode: widget.route.type == RouteType.bouldering
                ? RouteEditModeType.bouldering
                : RouteEditModeType.endurance,
          ),
        ),
      );
      ref.invalidate(routesProvider);
      ref.invalidate(routesTotalCountProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
      );
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deleteRoute),
        content: Text(AppLocalizations.of(context)!.confirmDeleteRoute),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _setLoading(true);
    try {
      final success = await ref.read(routesProvider().notifier).deleteRoute(widget.route.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success
            ? AppLocalizations.of(context)!.routeDeleted
            : AppLocalizations.of(context)!.failedDeleteRoute)),
      );
    } finally {
      _setLoading(false);
    }
  }

  void _handleShare() {
    const baseUrl = 'https://besetter-api-371038003203.asia-northeast3.run.app';
    final shareUrl = '$baseUrl/share/routes/${widget.route.id}';
    Share.share(shareUrl);
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final imageUrl = route.overlayImageUrl ?? route.imageUrl;
    final gradeColor = route.gradeColor != null
        ? Color(int.parse(route.gradeColor!.replaceFirst('#', '0xFF')))
        : Colors.blue;

    return GestureDetector(
      onTap: _navigateToViewer,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 오버레이 이미지
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 342 / 427.5,  // Figma 비율
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(color: Colors.grey[300]),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.broken_image, size: 48),
                          ),
                        ),
                      ),
                      // 난이도 뱃지
                      Positioned(
                        top: 18,
                        left: 24,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5.5),
                          decoration: BoxDecoration(
                            color: gradeColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            route.grade,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      // 오버레이 처리 중 라벨
                      if (route.overlayProcessing)
                        Positioned(
                          top: 18,
                          right: 24,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '이미지 생성 중',
                                  style: TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // 하단 정보
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 0, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 제목
                          Text(
                            route.title ?? route.grade,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          // 위치 정보
                          if (route.gymName != null || route.wallName != null)
                            Text(
                              [route.gymName, route.wallName].whereType<String>().join(' \u2022 '),
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 2),
                          // 상대 시간
                          Text(
                            timeago.format(route.createdAt),
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                    // 공유 + 더보기 버튼
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.share_outlined, size: 20),
                          onPressed: _handleShare,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz, size: 20),
                          padding: EdgeInsets.zero,
                          itemBuilder: (context) => [
                            PopupMenuItem<String>(
                              value: 'edit',
                              child: Row(
                                children: [
                                  const Icon(Icons.edit, size: 18),
                                  const SizedBox(width: 8),
                                  Text(AppLocalizations.of(context)!.doEdit),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(Icons.delete, size: 18),
                                  const SizedBox(width: 8),
                                  Text(AppLocalizations.of(context)!.doDelete),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'edit') _handleEdit();
                            if (value == 'delete') _handleDelete();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 로딩 오버레이
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black38,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: static analysis 확인**

Run: `cd apps/mobile && flutter analyze`

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/home/route_card.dart
git commit -m "feat(mobile): redesign RouteCard to match Figma design"
```

---

### Task 6: Flutter — Routes 탭 페이지 구현

**Files:**
- Create: `apps/mobile/lib/pages/routes_page.dart`
- Modify: `apps/mobile/lib/pages/main_tab.dart`

- [ ] **Step 1: RoutesPage 작성**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/routes_provider.dart';
import '../widgets/home/route_card.dart';

class RoutesPage extends HookConsumerWidget {
  const RoutesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFilter = useState<String?>(null); // null = All
    final routesAsync = ref.watch(routesProvider(type: selectedFilter.value));

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(routesProvider(type: selectedFilter.value).notifier).refresh(),
          child: CustomScrollView(
            slivers: [
              // 헤더: Your Routes
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 36, color: Colors.black),
                      children: [
                        TextSpan(text: 'Your\n'),
                        TextSpan(
                          text: 'Routes',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 필터 칩
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: selectedFilter.value == null,
                        onTap: () => selectedFilter.value = null,
                      ),
                      const SizedBox(width: 12),
                      _FilterChip(
                        label: 'Bouldering',
                        selected: selectedFilter.value == 'bouldering',
                        onTap: () => selectedFilter.value = 'bouldering',
                      ),
                      const SizedBox(width: 12),
                      _FilterChip(
                        label: 'Endurance',
                        selected: selectedFilter.value == 'endurance',
                        onTap: () => selectedFilter.value = 'endurance',
                      ),
                    ],
                  ),
                ),
              ),
              // 루트 리스트
              routesAsync.when(
                loading: () => const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, st) => SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Failed to load routes'),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => ref.invalidate(routesProvider(type: selectedFilter.value)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (routesState) {
                  if (routesState.routes.isEmpty) {
                    return const SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'No routes yet',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          // 무한 스크롤: 마지막 근처에서 추가 로드
                          if (index >= routesState.routes.length - 2 &&
                              routesState.nextToken != null &&
                              !routesState.isLoadingMore) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              ref.read(routesProvider(type: selectedFilter.value).notifier).fetchMore();
                            });
                          }

                          // 로딩 인디케이터 (마지막 아이템 다음)
                          if (index == routesState.routes.length) {
                            return routesState.isLoadingMore
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(child: CircularProgressIndicator()),
                                  )
                                : const SizedBox.shrink();
                          }

                          final route = routesState.routes[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              children: [
                                RouteCard(route: route),
                                if (index < routesState.routes.length - 1)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 16),
                                    child: Divider(height: 1),
                                  ),
                              ],
                            ),
                          );
                        },
                        childCount: routesState.routes.length + 1,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: selected ? null : Border.all(color: Colors.grey[300]!),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: main_tab.dart에서 placeholder를 RoutesPage로 교체**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'home.dart';
import 'routes_page.dart';
import 'setting.dart';

class MainTabPage extends HookConsumerWidget {
  const MainTabPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = useState(0);

    final pages = [
      const HomePage(),
      const RoutesPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: currentIndex.value,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex.value,
        onTap: (index) => currentIndex.value = index,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Routes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            label: 'Menu',
          ),
        ],
      ),
    );
  }
}
```

`_PlaceholderPage` 클래스 전체 삭제.

- [ ] **Step 3: 기존 routesProvider 호출부 전부 수정**

provider가 family로 바뀌었으므로 기존 `routesProvider` → `routesProvider()` 로 변경. `routesProvider.notifier` → `routesProvider().notifier`.

- [ ] **Step 4: build_runner로 코드 생성**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 5: static analysis 확인**

Run: `cd apps/mobile && flutter analyze`

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/pages/routes_page.dart apps/mobile/lib/pages/main_tab.dart apps/mobile/lib/providers/routes_provider.g.dart
git commit -m "feat(mobile): implement Routes tab page with filter chips and infinite scroll"
```
