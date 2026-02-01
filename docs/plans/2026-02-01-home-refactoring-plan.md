# Home.dart Riverpod 리팩터링 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Provider에서 Riverpod으로 전환하고 home.dart God Class를 분리하여 유지보수성 개선

**Architecture:** hooks_riverpod + riverpod_generator를 사용한 코드 생성 기반 상태 관리. 기존 ChangeNotifier Provider들을 AsyncNotifier로 전환하고, home.dart의 UI 컴포넌트를 widgets/home/ 폴더로 분리.

**Tech Stack:** Flutter, hooks_riverpod, flutter_hooks, riverpod_annotation, riverpod_generator, build_runner

---

## Task 1: 패키지 의존성 추가

**Files:**
- Modify: `apps/mobile/pubspec.yaml:40-41` (provider 제거)
- Modify: `apps/mobile/pubspec.yaml:69` (dev_dependencies에 추가)

**Step 1: pubspec.yaml 수정**

`apps/mobile/pubspec.yaml`에서 provider 제거하고 Riverpod 패키지 추가:

```yaml
dependencies:
  # provider: ^6.0.0  # 이 줄 제거
  flutter_riverpod: ^2.4.9
  hooks_riverpod: ^2.4.9
  flutter_hooks: ^0.20.4
  riverpod_annotation: ^2.3.3

dev_dependencies:
  riverpod_generator: ^2.3.9
  build_runner: ^2.4.8
```

**Step 2: 패키지 설치 확인**

Run: `cd apps/mobile && flutter pub get`
Expected: 패키지 다운로드 성공, 에러 없음

**Step 3: 커밋**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock
git commit -m "chore: replace provider with riverpod packages"
```

---

## Task 2: main.dart에 ProviderScope 래핑

**Files:**
- Modify: `apps/mobile/lib/main.dart`

**Step 1: import 변경**

```dart
// 제거
import 'package:provider/provider.dart';
import 'providers/image_state.dart' as image_provider;
import 'providers/route_state.dart';

// 추가
import 'package:hooks_riverpod/hooks_riverpod.dart';
```

**Step 2: runApp 수정**

기존:
```dart
runApp(
  MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (context) => AuthState()),
      ChangeNotifierProvider(create: (context) => image_provider.ImageProvider()),
      ChangeNotifierProvider(create: (context) => RouteProvider()),
    ],
    child: const MyApp(),
  ),
);
```

변경:
```dart
runApp(
  const ProviderScope(
    child: MyApp(),
  ),
);
```

**Step 3: MyApp을 ConsumerWidget으로 변경 (임시)**

MainMenuPage에서 authState를 사용하므로, 일단 빌드가 되도록 임시 처리:

```dart
class MainMenuPage extends ConsumerWidget {
  const MainMenuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: authProvider 전환 후 수정
    // 임시로 항상 LoginPage 표시
    return const LoginPage();
  }
}
```

**Step 4: 빌드 확인**

Run: `cd apps/mobile && flutter build apk --debug`
Expected: 빌드 성공 (일부 Provider 사용 코드에서 경고 가능)

**Step 5: 커밋**

```bash
git add apps/mobile/lib/main.dart
git commit -m "refactor: wrap app with ProviderScope"
```

---

## Task 3: AuthProvider 전환

**Files:**
- Create: `apps/mobile/lib/providers/auth_provider.dart`
- Modify: `apps/mobile/lib/providers/auth_state.dart` (나중에 삭제 예정)

**Step 1: auth_provider.dart 생성**

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'auth_provider.g.dart';

class AuthState {
  final bool isLoggedIn;
  final bool isInitialized;
  final String? userDisplayName;
  final String? accessToken;

  const AuthState({
    this.isLoggedIn = false,
    this.isInitialized = false,
    this.userDisplayName,
    this.accessToken,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    bool? isInitialized,
    String? userDisplayName,
    String? accessToken,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isInitialized: isInitialized ?? this.isInitialized,
      userDisplayName: userDisplayName ?? this.userDisplayName,
      accessToken: accessToken ?? this.accessToken,
    );
  }
}

@Riverpod(keepAlive: true)
class Auth extends _$Auth {
  @override
  Future<AuthState> build() async {
    return _loadAuthState();
  }

  Future<AuthState> _loadAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    return AuthState(
      isLoggedIn: prefs.getBool('isLoggedIn') ?? false,
      isInitialized: true,
      userDisplayName: prefs.getString('userDisplayName'),
      accessToken: prefs.getString('accessToken'),
    );
  }

  Future<void> _saveAuthState(AuthState authState) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', authState.isLoggedIn);
    await prefs.setString('userDisplayName', authState.userDisplayName ?? '');
    await prefs.setString('accessToken', authState.accessToken ?? '');
  }

  Future<void> login(String displayName, String accessToken) async {
    final newState = AuthState(
      isLoggedIn: true,
      isInitialized: true,
      userDisplayName: displayName,
      accessToken: accessToken,
    );
    await _saveAuthState(newState);
    state = AsyncData(newState);
  }

  Future<void> logout() async {
    final newState = const AuthState(
      isLoggedIn: false,
      isInitialized: true,
      userDisplayName: null,
      accessToken: null,
    );
    await _saveAuthState(newState);
    state = AsyncData(newState);
  }
}
```

**Step 2: 코드 생성 실행**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `auth_provider.g.dart` 파일 생성

**Step 3: 커밋**

```bash
git add apps/mobile/lib/providers/auth_provider.dart apps/mobile/lib/providers/auth_provider.g.dart
git commit -m "feat: add riverpod auth provider"
```

---

## Task 4: main.dart MainMenuPage 수정

**Files:**
- Modify: `apps/mobile/lib/main.dart`

**Step 1: import 추가**

```dart
import 'providers/auth_provider.dart';
```

**Step 2: MainMenuPage 수정**

```dart
class MainMenuPage extends ConsumerWidget {
  const MainMenuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authProvider);

    return authAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        body: Center(child: Text('Error: $e')),
      ),
      data: (authState) {
        if (!authState.isInitialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return UpgradeAlert(
          child: authState.isLoggedIn ? const HomePage() : const LoginPage(),
        );
      },
    );
  }
}
```

**Step 3: 빌드 확인**

Run: `cd apps/mobile && flutter build apk --debug`
Expected: 빌드 성공

**Step 4: 커밋**

```bash
git add apps/mobile/lib/main.dart
git commit -m "refactor: use authProvider in MainMenuPage"
```

---

## Task 5: http_client.dart 전환

**Files:**
- Modify: `apps/mobile/lib/services/http_client.dart`
- Modify: `apps/mobile/lib/main.dart` (container 추가)

**Step 1: main.dart에 전역 container 추가**

```dart
// main.dart 상단에 추가
late ProviderContainer container;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ... Firebase, LineSDK 초기화 ...

  container = ProviderContainer();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );
}
```

**Step 2: http_client.dart 수정**

```dart
// import 변경
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/auth_provider.dart';
import '../main.dart' show container;

// _refreshTokens 메서드 내 로그아웃 처리 변경
// 기존: await context.read<AuthState>().logout();
// 변경:
await container.read(authProvider.notifier).logout();

// _executeRequest 메서드 내 로그아웃 처리도 동일하게 변경
```

**Step 3: 빌드 확인**

Run: `cd apps/mobile && flutter build apk --debug`
Expected: 빌드 성공

**Step 4: 커밋**

```bash
git add apps/mobile/lib/main.dart apps/mobile/lib/services/http_client.dart
git commit -m "refactor: use riverpod container in http_client"
```

---

## Task 6: login.dart 전환

**Files:**
- Modify: `apps/mobile/lib/login.dart`

**Step 1: import 변경**

```dart
// 제거
import 'package:provider/provider.dart';
import 'providers/auth_state.dart';

// 추가
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'providers/auth_provider.dart';
```

**Step 2: LoginPage를 ConsumerWidget으로 변경**

```dart
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  // ... 기존 상수들 유지 ...

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 기존 build 내용 유지
  }

  // 각 로그인 핸들러에서:
  // 기존: final authState = context.read<AuthState>();
  // 변경: final authNotifier = ref.read(authProvider.notifier);

  // 기존: authState.login(displayName, accessToken);
  // 변경: await authNotifier.login(displayName, accessToken);
}
```

**Step 3: 각 로그인 메서드 수정**

`_handleAppleLogin`, `_handleGoogleLogin`, `_handleLineLogin`, `_handleKakaoLoginResult` 메서드에서:

```dart
// 기존
final authState = context.read<AuthState>();
authState.login('', data['accessToken']);

// 변경
await ref.read(authProvider.notifier).login('', data['accessToken']);
```

**Step 4: 빌드 확인**

Run: `cd apps/mobile && flutter build apk --debug`
Expected: 빌드 성공

**Step 5: 커밋**

```bash
git add apps/mobile/lib/login.dart
git commit -m "refactor: use riverpod in login page"
```

---

## Task 7: setting.dart 전환

**Files:**
- Modify: `apps/mobile/lib/pages/setting.dart`

**Step 1: import 변경**

```dart
// 제거
import 'package:provider/provider.dart';
import '../providers/auth_state.dart';

// 추가
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/auth_provider.dart';
```

**Step 2: SettingsPage를 ConsumerWidget으로 변경**

```dart
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  // ...

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 로그아웃 부분:
    // 기존: await context.read<AuthState>().logout();
    // 변경: await ref.read(authProvider.notifier).logout();
  }
}
```

**Step 3: 빌드 확인**

Run: `cd apps/mobile && flutter build apk --debug`
Expected: 빌드 성공

**Step 4: 커밋**

```bash
git add apps/mobile/lib/pages/setting.dart
git commit -m "refactor: use riverpod in settings page"
```

---

## Task 8: terms_page.dart 전환

**Files:**
- Modify: `apps/mobile/lib/pages/terms_page.dart`

**Step 1: import 변경**

```dart
// 제거
import 'package:provider/provider.dart';
import '../providers/auth_state.dart';

// 추가
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/auth_provider.dart';
```

**Step 2: TermsPage를 ConsumerStatefulWidget으로 변경**

```dart
class TermsPage extends ConsumerStatefulWidget {
  // ... 기존 필드들 유지 ...

  @override
  ConsumerState<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends ConsumerState<TermsPage> {
  // _handleSignUp 내에서:
  // 기존: final authState = context.read<AuthState>();
  //       await authState.login('', data['accessToken']);
  // 변경: await ref.read(authProvider.notifier).login('', data['accessToken']);
}
```

**Step 3: 빌드 확인**

Run: `cd apps/mobile && flutter build apk --debug`
Expected: 빌드 성공

**Step 4: 커밋**

```bash
git add apps/mobile/lib/pages/terms_page.dart
git commit -m "refactor: use riverpod in terms page"
```

---

## Task 9: ImagesProvider 전환

**Files:**
- Create: `apps/mobile/lib/providers/images_provider.dart`

**Step 1: images_provider.dart 생성**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/image_data.dart';
import '../models/paginated_response.dart';
import '../models/polygon_data.dart';
import '../services/http_client.dart';

part 'images_provider.g.dart';

@riverpod
class Images extends _$Images {
  @override
  Future<List<ImageData>> build() async {
    return _fetchImages();
  }

  Future<List<ImageData>> _fetchImages() async {
    final queryParams = {
      'sort': 'uploadedAt:desc',
      'limit': '9',
    };
    final uri = Uri.parse('/images').replace(queryParameters: queryParams);
    final response = await AuthorizedHttpClient.get(uri.toString());

    if (response.statusCode == 200) {
      final result = PaginatedResponse.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
        (json) => ImageData.fromJson(json),
      );
      return result.data;
    } else {
      throw Exception('Failed to load images. Status code: ${response.statusCode}');
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<PolygonData?> createImage(File image) async {
    state = const AsyncLoading();

    try {
      final response = await AuthorizedHttpClient.multipartPost(
        '/hold-polygons',
        image.path,
      );

      if (response.statusCode == 201) {
        final responseBody = jsonDecode(response.body);
        final polygonData = PolygonData.fromJson(responseBody);

        await refresh();
        return polygonData;
      } else {
        throw Exception('Failed to create image. Status: ${response.statusCode}');
      }
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return null;
    }
  }
}
```

**Step 2: 코드 생성 실행**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `images_provider.g.dart` 파일 생성

**Step 3: 커밋**

```bash
git add apps/mobile/lib/providers/images_provider.dart apps/mobile/lib/providers/images_provider.g.dart
git commit -m "feat: add riverpod images provider"
```

---

## Task 10: RoutesProvider 전환

**Files:**
- Create: `apps/mobile/lib/providers/routes_provider.dart`

**Step 1: routes_provider.dart 생성**

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
  Future<RoutesState> build() async {
    return _fetchInitial();
  }

  Future<RoutesState> _fetchInitial() async {
    final queryParams = {
      'sort': 'createdAt:desc',
      'limit': '4',
    };
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
      final queryParams = {
        'sort': 'createdAt:desc',
        'limit': '4',
        'next': current.nextToken!,
      };
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

**Step 2: 코드 생성 실행**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `routes_provider.g.dart` 파일 생성

**Step 3: 커밋**

```bash
git add apps/mobile/lib/providers/routes_provider.dart apps/mobile/lib/providers/routes_provider.g.dart
git commit -m "feat: add riverpod routes provider"
```

---

## Task 11: widgets/home 폴더 생성 및 image_card.dart

**Files:**
- Create: `apps/mobile/lib/widgets/home/image_card.dart`

**Step 1: 디렉토리 생성**

Run: `mkdir -p apps/mobile/lib/widgets/home`

**Step 2: image_card.dart 생성**

```dart
import 'package:flutter/material.dart';
import '../../models/image_data.dart';
import '../authorized_network_image.dart';

class ImageCard extends StatelessWidget {
  final ImageData image;
  final VoidCallback onTap;

  const ImageCard({
    super.key,
    required this.image,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: onTap,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AuthorizedNetworkImage(
                  imageUrl: image.url,
                  fit: BoxFit.cover,
                ),
                if (image.wallName != null &&
                    image.wallName!.isNotEmpty &&
                    image.gymName != null &&
                    image.gymName!.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      color: Colors.black54,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            image.wallName!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            image.gymName!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

**Step 3: 커밋**

```bash
git add apps/mobile/lib/widgets/home/image_card.dart
git commit -m "feat: add ImageCard widget"
```

---

## Task 12: edit_mode_dialog.dart 생성

**Files:**
- Create: `apps/mobile/lib/widgets/home/edit_mode_dialog.dart`

**Step 1: edit_mode_dialog.dart 생성**

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/image_data.dart';
import '../../models/polygon_data.dart';
import '../../services/http_client.dart';
import '../../pages/editors/route_editor_page.dart';
import '../../pages/editors/spray_wall_editor_page.dart';

class EditModeDialog extends ConsumerStatefulWidget {
  final ImageData image;

  const EditModeDialog({
    super.key,
    required this.image,
  });

  @override
  ConsumerState<EditModeDialog> createState() => _EditModeDialogState();
}

class _EditModeDialogState extends ConsumerState<EditModeDialog> {
  bool _isLoading = false;

  Future<void> _handleModeSelection(
    BuildContext context,
    Future<void> Function(PolygonData polygonData) onSuccess,
  ) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final response = await AuthorizedHttpClient.get(
        '/hold-polygons/${widget.image.holdPolygonId}',
      );
      if (response.statusCode == 200) {
        final polygonData = PolygonData.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
        if (!mounted) return;
        Navigator.pop(context);
        await onSuccess(polygonData);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = (screenWidth * 0.2).clamp(60.0, 100.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: screenWidth * 0.9,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildIconButton(
                      icon: 'assets/icons/wall_edit_button.svg',
                      label: 'WALL EDIT',
                      size: iconSize,
                      onTap: () => _handleModeSelection(
                        context,
                        (polygonData) async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SprayWallEditorPage(
                                image: widget.image,
                                polygonData: polygonData,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _buildIconButton(
                      icon: 'assets/icons/bouldering_button.svg',
                      label: 'BOULDERING',
                      size: iconSize,
                      onTap: () => _handleModeSelection(
                        context,
                        (polygonData) async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RouteEditorPage(
                                image: widget.image,
                                polygonData: polygonData,
                                initialMode: RouteEditModeType.bouldering,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _buildIconButton(
                      icon: 'assets/icons/endurance_button.svg',
                      label: 'ENDURANCE',
                      size: iconSize,
                      onTap: () => _handleModeSelection(
                        context,
                        (polygonData) async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RouteEditorPage(
                                image: widget.image,
                                polygonData: polygonData,
                                initialMode: RouteEditModeType.endurance,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required String icon,
    required String label,
    required VoidCallback onTap,
    required double size,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SvgPicture.asset(
              icon,
              width: size * 0.6,
              height: size * 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 2: 커밋**

```bash
git add apps/mobile/lib/widgets/home/edit_mode_dialog.dart
git commit -m "feat: add EditModeDialog widget"
```

---

## Task 13: image_carousel.dart 생성

**Files:**
- Create: `apps/mobile/lib/widgets/home/image_carousel.dart`

**Step 1: image_carousel.dart 생성**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:dots_indicator/dots_indicator.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/image_data.dart';
import '../../providers/images_provider.dart';
import 'image_card.dart';
import 'edit_mode_dialog.dart';

class ImageCarousel extends HookConsumerWidget {
  final VoidCallback? onInteraction;

  const ImageCarousel({
    super.key,
    this.onInteraction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagesAsync = ref.watch(imagesProvider);
    final pageController = usePageController();
    final currentPage = useState(0.0);

    useEffect(() {
      void listener() {
        currentPage.value = pageController.page ?? 0;
      }
      pageController.addListener(listener);
      return () => pageController.removeListener(listener);
    }, [pageController]);

    return imagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Text(AppLocalizations.of(context)!.errorOccurred),
      ),
      data: (images) {
        if (images.isEmpty) {
          return _buildWelcomeSection(context);
        }
        return _buildCarousel(
          context,
          images,
          pageController,
          currentPage.value,
          onInteraction,
        );
      },
    );
  }

  Widget _buildWelcomeSection(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context)!.setProblemAtGymNow,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(
          height: MediaQuery.of(context).size.width * 0.4,
        ),
      ],
    );
  }

  Widget _buildCarousel(
    BuildContext context,
    List<ImageData> images,
    PageController pageController,
    double currentPage,
    VoidCallback? onInteraction,
  ) {
    final int totalPages = (images.length / 3).ceil().clamp(0, 3);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context)!.setRouteWithRecentPhoto,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: MediaQuery.of(context).size.width * 0.4,
          child: PageView.builder(
            controller: pageController,
            itemCount: totalPages,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, pageIndex) {
              final startIndex = pageIndex * 3;
              final endIndex = (startIndex + 3).clamp(0, images.length);
              final pageImages = images.sublist(startIndex, endIndex);

              if (pageIndex == 2) {
                return _buildLastPage(context, pageImages, onInteraction);
              }

              return _buildPage(context, pageImages, onInteraction);
            },
          ),
        ),
        const SizedBox(height: 8),
        if (totalPages > 0)
          DotsIndicator(
            dotsCount: totalPages,
            position: currentPage.toInt().clamp(0, totalPages - 1),
            decorator: DotsDecorator(
              activeColor: Theme.of(context).primaryColor,
              size: const Size.square(6.0),
              activeSize: const Size.square(6.0),
              spacing: const EdgeInsets.all(4.0),
            ),
          ),
      ],
    );
  }

  Widget _buildPage(
    BuildContext context,
    List<ImageData> pageImages,
    VoidCallback? onInteraction,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          ...pageImages.map((image) => Expanded(
                child: ImageCard(
                  image: image,
                  onTap: () {
                    onInteraction?.call();
                    showDialog(
                      context: context,
                      barrierDismissible: true,
                      builder: (context) => EditModeDialog(image: image),
                    );
                  },
                ),
              )),
          ...List.generate(
            3 - pageImages.length,
            (_) => const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.0),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: SizedBox(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastPage(
    BuildContext context,
    List<ImageData> pageImages,
    VoidCallback? onInteraction,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          ...pageImages.take(2).map((image) => Expanded(
                child: ImageCard(
                  image: image,
                  onTap: () {
                    onInteraction?.call();
                    showDialog(
                      context: context,
                      barrierDismissible: true,
                      builder: (context) => EditModeDialog(image: image),
                    );
                  },
                ),
              )),
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/images'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Card(
                    child: Container(
                      color: Colors.grey[200],
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_circle_outline, size: 32),
                            const SizedBox(height: 4),
                            Text(
                              AppLocalizations.of(context)!.viewMore,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 2: 커밋**

```bash
git add apps/mobile/lib/widgets/home/image_carousel.dart
git commit -m "feat: add ImageCarousel widget"
```

---

## Task 14: route_card.dart 생성

**Files:**
- Create: `apps/mobile/lib/widgets/home/route_card.dart`

**Step 1: route_card.dart 생성**

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/route_data.dart';
import '../../services/http_client.dart';
import '../../providers/routes_provider.dart';
import '../../pages/viewers/route_viewer.dart';
import '../../pages/editors/route_editor_page.dart';
import '../authorized_network_image.dart';

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
    if (mounted) {
      setState(() => _isLoading = value);
    }
  }

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
          MaterialPageRoute(
            builder: (context) => RouteViewer(routeData: routeData),
          ),
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
      // 에디터에서 돌아온 후 새로고침
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
      final success = await ref.read(routesProvider.notifier).deleteRoute(widget.route.id);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.routeDeleted)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.failedDeleteRoute)),
        );
      }
    } finally {
      _setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;

    return Stack(
      children: [
        Card(
          elevation: 2,
          child: InkWell(
            onTap: _navigateToViewer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 60,
                          height: 60,
                          child: AuthorizedNetworkImage(
                            imageUrl: route.imageUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 60,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${route.grade} ${route.type == RouteType.bouldering ? AppLocalizations.of(context)!.bouldering : AppLocalizations.of(context)!.endurance}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.menu, size: 20),
                              itemBuilder: (context) => [
                                PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit),
                                      const SizedBox(width: 8),
                                      Text(AppLocalizations.of(context)!.doEdit),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete),
                                      const SizedBox(width: 8),
                                      Text(AppLocalizations.of(context)!.doDelete),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _handleEdit();
                                } else if (value == 'delete') {
                                  _handleDelete();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.grey[200],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (route.gymName != null && route.wallName != null)
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 16,
                                color: Colors.grey[700],
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${route.gymName} - ${route.wallName}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (route.gymName == null || route.wallName == null)
                        const Spacer(),
                      Text(
                        DateFormat.yMd(AppLocalizations.of(context)!.localeName)
                            .add_jm()
                            .format(route.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );
  }
}
```

**Step 2: 커밋**

```bash
git add apps/mobile/lib/widgets/home/route_card.dart
git commit -m "feat: add RouteCard widget"
```

---

## Task 15: route_list.dart 생성

**Files:**
- Create: `apps/mobile/lib/widgets/home/route_list.dart`

**Step 1: route_list.dart 생성**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../providers/routes_provider.dart';
import 'route_card.dart';

class RouteList extends HookConsumerWidget {
  final ScrollController? parentScrollController;
  final VoidCallback? onInteraction;

  const RouteList({
    super.key,
    this.parentScrollController,
    this.onInteraction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routesAsync = ref.watch(routesProvider);

    useEffect(() {
      void onScroll() {
        final controller = parentScrollController;
        if (controller == null) return;

        if (controller.position.pixels >= controller.position.maxScrollExtent * 0.8) {
          final state = routesAsync.valueOrNull;
          if (state != null && state.nextToken != null && !state.isLoadingMore) {
            ref.read(routesProvider.notifier).fetchMore();
          }
        }
      }

      parentScrollController?.addListener(onScroll);
      return () => parentScrollController?.removeListener(onScroll);
    }, [parentScrollController, routesAsync]);

    return routesAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => SliverToBoxAdapter(
        child: Center(child: Text('Error: $e')),
      ),
      data: (state) => SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == state.routes.length) {
              return (state.nextToken != null && state.isLoadingMore)
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: RouteCard(
                route: state.routes[index],
                onInteraction: onInteraction,
              ),
            );
          },
          childCount: state.routes.length +
              ((state.nextToken != null && state.isLoadingMore) ? 1 : 0),
        ),
      ),
    );
  }
}
```

**Step 2: 커밋**

```bash
git add apps/mobile/lib/widgets/home/route_list.dart
git commit -m "feat: add RouteList widget"
```

---

## Task 16: home.dart 리팩터링

**Files:**
- Modify: `apps/mobile/lib/pages/home.dart`

**Step 1: home.dart 전체 교체**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/routes_provider.dart';
import '../services/token_service.dart';
import '../widgets/hold_editor_button.dart';
import '../widgets/confetti.dart';
import '../widgets/guide_bubble.dart';
import '../widgets/home/image_carousel.dart';
import '../widgets/home/route_list.dart';
import './setting.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  static const String _hasShownConfettiKey = 'has_shown_confetti_';
  static const String _hasShownGuideKey = 'has_shown_guide';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollController = useScrollController();
    final editorButtonKey = useMemoized(() => GlobalKey());
    final guideBubble = useState<GuideBubble?>(null);
    final totalCountAsync = ref.watch(routesTotalCountProvider);

    // Guide bubble 초기화
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        guideBubble.value = GuideBubble(
          context: context,
          targetKey: editorButtonKey,
          message: AppLocalizations.of(context)!.uploadPhoto,
          autoDismissSeconds: 60,
          prefKey: _hasShownGuideKey,
        );
        guideBubble.value?.checkAndShow();
      });
      return () => guideBubble.value?.dispose();
    }, []);

    // Confetti 체크
    useEffect(() {
      _checkAndShowConfetti(context);
      return null;
    }, []);

    void handleInteraction() {
      guideBubble.value?.removeOverlay();
      guideBubble.value?.markAsShown();
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                icon: const Icon(Icons.menu),
                iconSize: 32,
                onPressed: () {
                  handleInteraction();
                  guideBubble.value?.removeOverlayImmediately();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsPage(),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Center(
                    child: HoldEditorButton(
                      buttonKey: editorButtonKey,
                      onTapDown: handleInteraction,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ImageCarousel(onInteraction: handleInteraction),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Text(
                        AppLocalizations.of(context)!.routeCard,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      totalCountAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (count) => Text(
                          ' $count',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              sliver: RouteList(
                parentScrollController: scrollController,
                onInteraction: handleInteraction,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkAndShowConfetti(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = await TokenService.getRefreshToken();

    if (refreshToken != null) {
      final hasShown = prefs.getBool('$_hasShownConfettiKey$refreshToken') ?? false;

      if (!hasShown) {
        prefs.setBool('$_hasShownConfettiKey$refreshToken', true);
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => const ConfettiDialogWidget(),
          );
        }
      }
    }
  }
}
```

**Step 2: 빌드 확인**

Run: `cd apps/mobile && flutter build apk --debug`
Expected: 빌드 성공

**Step 3: 커밋**

```bash
git add apps/mobile/lib/pages/home.dart
git commit -m "refactor: simplify home.dart with riverpod and extracted widgets"
```

---

## Task 17: image_preview_page.dart 전환

**Files:**
- Modify: `apps/mobile/lib/pages/image_preview_page.dart`

**Step 1: import 변경 및 Provider 사용 수정**

```dart
// 제거
import 'package:provider/provider.dart';
import '../providers/image_state.dart' as image_provider;

// 추가
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/images_provider.dart';
```

**Step 2: 위젯 전환**

Provider 사용하는 부분:
```dart
// 기존
final imageProvider = Provider.of<image_provider.ImageProvider>(context, listen: false);

// 변경: ConsumerStatefulWidget으로 변경하고
await ref.read(imagesProvider.notifier).refresh();
```

**Step 3: 빌드 확인**

Run: `cd apps/mobile && flutter build apk --debug`
Expected: 빌드 성공

**Step 4: 커밋**

```bash
git add apps/mobile/lib/pages/image_preview_page.dart
git commit -m "refactor: use riverpod in image preview page"
```

---

## Task 18: 기존 provider 파일 제거

**Files:**
- Delete: `apps/mobile/lib/providers/auth_state.dart`
- Delete: `apps/mobile/lib/providers/image_state.dart`
- Delete: `apps/mobile/lib/providers/route_state.dart`

**Step 1: 파일 삭제**

Run:
```bash
rm apps/mobile/lib/providers/auth_state.dart
rm apps/mobile/lib/providers/image_state.dart
rm apps/mobile/lib/providers/route_state.dart
```

**Step 2: 빌드 확인**

Run: `cd apps/mobile && flutter build apk --debug`
Expected: 빌드 성공 (모든 import가 새 provider로 전환되어 있어야 함)

**Step 3: 커밋**

```bash
git add -u apps/mobile/lib/providers/
git commit -m "chore: remove legacy provider files"
```

---

## Task 19: 최종 검증 및 pubspec에서 provider 제거 확인

**Files:**
- Verify: `apps/mobile/pubspec.yaml`

**Step 1: provider 패키지가 완전히 제거되었는지 확인**

pubspec.yaml에서 `provider:` 라인이 없는지 확인

**Step 2: 전체 빌드 테스트**

Run: `cd apps/mobile && flutter clean && flutter pub get && flutter build apk --debug`
Expected: 빌드 성공

**Step 3: 앱 실행 테스트**

Run: `cd apps/mobile && flutter run`
Expected: 앱이 정상적으로 실행되고 다음 기능 동작:
- 로그인/로그아웃
- 홈 화면 이미지 캐러셀 표시
- 루트 목록 표시 및 무한 스크롤
- 루트 삭제
- 설정 페이지 이동

**Step 4: 최종 커밋**

```bash
git add .
git commit -m "feat: complete riverpod migration and home.dart refactoring"
```

---

## 요약

| Task | 설명 | 예상 파일 변경 |
|------|------|--------------|
| 1 | 패키지 의존성 추가 | pubspec.yaml |
| 2 | ProviderScope 래핑 | main.dart |
| 3 | AuthProvider 전환 | auth_provider.dart (신규) |
| 4 | MainMenuPage 수정 | main.dart |
| 5 | http_client.dart 전환 | http_client.dart, main.dart |
| 6 | login.dart 전환 | login.dart |
| 7 | setting.dart 전환 | setting.dart |
| 8 | terms_page.dart 전환 | terms_page.dart |
| 9 | ImagesProvider 전환 | images_provider.dart (신규) |
| 10 | RoutesProvider 전환 | routes_provider.dart (신규) |
| 11 | ImageCard 위젯 | widgets/home/image_card.dart (신규) |
| 12 | EditModeDialog 위젯 | widgets/home/edit_mode_dialog.dart (신규) |
| 13 | ImageCarousel 위젯 | widgets/home/image_carousel.dart (신규) |
| 14 | RouteCard 위젯 | widgets/home/route_card.dart (신규) |
| 15 | RouteList 위젯 | widgets/home/route_list.dart (신규) |
| 16 | home.dart 리팩터링 | home.dart |
| 17 | image_preview_page.dart 전환 | image_preview_page.dart |
| 18 | 기존 provider 파일 제거 | 3개 파일 삭제 |
| 19 | 최종 검증 | - |

**예상 결과:**
- home.dart: ~1,000줄 → ~150줄
- 신규 위젯 5개 생성 (widgets/home/)
- 신규 provider 3개 생성
- 기존 provider 3개 삭제
- 전체 앱 Riverpod으로 통일
