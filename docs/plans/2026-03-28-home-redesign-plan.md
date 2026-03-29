# Home 화면 개편 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home 화면을 Figma 디자인에 맞춰 벽 사진 캐로셀 + Take Wall Photo + BottomNavigationBar 구조로 개편한다.

**Architecture:** `MainTabPage`를 새로 만들어 BottomNavigationBar(Home/Routes/Menu)를 관리하고, Home 화면은 `WallImageCarousel` + `Take Wall Photo` 버튼으로 재구성한다. 기존 `HoldEditorButton`의 팝업 메뉴 로직과 `EditModeDialog`의 라우팅 로직을 재사용한다.

**Tech Stack:** Flutter, carousel_slider, hooks_riverpod, flutter_hooks

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `pubspec.yaml` | Modify | carousel_slider 패키지 추가 |
| `lib/pages/main_tab.dart` | Create | BottomNavigationBar + IndexedStack 탭 컨테이너 |
| `lib/widgets/home/wall_image_carousel.dart` | Create | carousel_slider 기반 벽 사진 캐로셀 |
| `lib/widgets/home/wall_card.dart` | Create | 개별 벽 카드 (이미지 + 오버레이 정보 + 버튼) |
| `lib/pages/home.dart` | Modify | 레이아웃 개편 (캐로셀 + Take Wall Photo) |
| `lib/main.dart` | Modify | MainMenuPage에서 HomePage 대신 MainTabPage 사용 |

---

### Task 1: carousel_slider 패키지 추가

**Files:**
- Modify: `apps/mobile/pubspec.yaml`

- [ ] **Step 1: pubspec.yaml에 carousel_slider 추가**

`apps/mobile/pubspec.yaml`의 dependencies 섹션에 추가 (cupertino_icons 아래):

```yaml
  carousel_slider: ^5.0.0
```

- [ ] **Step 2: 패키지 설치**

Run: `cd apps/mobile && flutter pub get`
Expected: 정상 완료

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock
git commit -m "feat(mobile): add carousel_slider package"
```

---

### Task 2: WallCard 위젯 생성

**Files:**
- Create: `apps/mobile/lib/widgets/home/wall_card.dart`

- [ ] **Step 1: wall_card.dart 작성**

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/image_data.dart';
import '../../models/polygon_data.dart';
import '../../services/http_client.dart';
import '../../pages/editors/route_editor_page.dart';
import '../../pages/editors/spray_wall_editor_page.dart';

class WallCard extends ConsumerStatefulWidget {
  final ImageData image;

  const WallCard({super.key, required this.image});

  @override
  ConsumerState<WallCard> createState() => _WallCardState();
}

class _WallCardState extends ConsumerState<WallCard> {
  bool _isLoading = false;

  Future<PolygonData?> _fetchPolygonData() async {
    if (_isLoading) return null;
    setState(() => _isLoading = true);
    try {
      final response = await AuthorizedHttpClient.get(
        '/hold-polygons/${widget.image.holdPolygonId}',
      );
      if (response.statusCode == 200) {
        return PolygonData.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load data')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    return null;
  }

  Future<void> _onCreateRoute() async {
    final polygonData = await _fetchPolygonData();
    if (polygonData == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _CreateRouteDialog(
        image: widget.image,
        polygonData: polygonData,
      ),
    );
  }

  Future<void> _onEditWall() async {
    final polygonData = await _fetchPolygonData();
    if (polygonData == null || !mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SprayWallEditorPage(
          image: widget.image,
          polygonData: polygonData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy').format(widget.image.uploadedAt);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: DecorationImage(
          image: NetworkImage(widget.image.url),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          // 하단 그라데이션 오버레이
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
          ),
          // 하단 정보 + 버튼
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recent Wall Photos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                if (widget.image.gymName != null)
                  Text(
                    'Gym Name: ${widget.image.gymName}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                if (widget.image.wallName != null)
                  Text(
                    'Wall: ${widget.image.wallName}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                Text(
                  'Date: $dateStr',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _ActionButton(
                      label: 'Edit Wall',
                      onTap: _onEditWall,
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      label: 'Create Route',
                      icon: Icons.arrow_outward,
                      onTap: _onCreateRoute,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 로딩 오버레이
          if (_isLoading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 4),
              Icon(icon, color: Colors.white, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateRouteDialog extends StatelessWidget {
  final ImageData image;
  final PolygonData polygonData;

  const _CreateRouteDialog({
    required this.image,
    required this.polygonData,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Create Route',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ModeButton(
                  label: 'BOULDERING',
                  icon: 'assets/icons/bouldering_button.svg',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RouteEditorPage(
                          image: image,
                          polygonData: polygonData,
                          initialMode: RouteEditModeType.bouldering,
                        ),
                      ),
                    );
                  },
                ),
                _ModeButton(
                  label: 'ENDURANCE',
                  icon: 'assets/icons/endurance_button.svg',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RouteEditorPage(
                          image: image,
                          polygonData: polygonData,
                          initialMode: RouteEditModeType.endurance,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = (MediaQuery.of(context).size.width * 0.2).clamp(60.0, 100.0);
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
            child: Image.asset(icon, width: size * 0.6, height: size * 0.6,
              errorBuilder: (_, __, ___) => Icon(Icons.terrain, size: size * 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 정적 분석**

Run: `cd apps/mobile && flutter analyze`
Expected: 에러 없음

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/home/wall_card.dart
git commit -m "feat(mobile): add WallCard widget for home carousel"
```

---

### Task 3: WallImageCarousel 위젯 생성

**Files:**
- Create: `apps/mobile/lib/widgets/home/wall_image_carousel.dart`

- [ ] **Step 1: wall_image_carousel.dart 작성**

```dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:carousel_slider/carousel_slider.dart';
import '../../providers/images_provider.dart';
import 'wall_card.dart';

class WallImageCarousel extends ConsumerWidget {
  const WallImageCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagesAsync = ref.watch(imagesProvider);

    return imagesAsync.when(
      loading: () => const SizedBox(
        height: 400,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => const SizedBox(
        height: 400,
        child: Center(child: Text('Error loading images')),
      ),
      data: (images) {
        if (images.isEmpty) {
          return _buildEmptyState(context);
        }

        // 이미지 카드 + 더보기 카드
        final itemCount = images.length + 1;

        return CarouselSlider.builder(
          itemCount: itemCount,
          itemBuilder: (context, index, realIndex) {
            if (index == images.length) {
              return _buildViewMoreCard(context);
            }
            return WallCard(image: images[index]);
          },
          options: CarouselOptions(
            height: 420,
            enlargeCenterPage: true,
            enlargeFactor: 0.2,
            viewportFraction: 0.85,
            enableInfiniteScroll: false,
            padEnds: true,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No wall photos yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Take a wall photo to get started!',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewMoreCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/images'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, size: 48, color: Colors.grey[600]),
              const SizedBox(height: 12),
              Text(
                'View More',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 정적 분석**

Run: `cd apps/mobile && flutter analyze`
Expected: 에러 없음

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/home/wall_image_carousel.dart
git commit -m "feat(mobile): add WallImageCarousel with carousel_slider"
```

---

### Task 4: MainTabPage 생성

**Files:**
- Create: `apps/mobile/lib/pages/main_tab.dart`

- [ ] **Step 1: main_tab.dart 작성**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'home.dart';
import 'setting.dart';

class MainTabPage extends HookConsumerWidget {
  const MainTabPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = useState(0);

    final pages = [
      const HomePage(),
      const _PlaceholderPage(title: 'Routes'),
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

class _PlaceholderPage extends StatelessWidget {
  final String title;

  const _PlaceholderPage({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          title,
          style: const TextStyle(fontSize: 24, color: Colors.grey),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 정적 분석**

Run: `cd apps/mobile && flutter analyze`
Expected: 에러 없음

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/pages/main_tab.dart
git commit -m "feat(mobile): add MainTabPage with BottomNavigationBar"
```

---

### Task 5: HomePage 개편

**Files:**
- Modify: `apps/mobile/lib/pages/home.dart`

- [ ] **Step 1: home.dart를 새 레이아웃으로 교체**

`apps/mobile/lib/pages/home.dart` 전체를 다음으로 교체:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/token_service.dart';
import '../widgets/confetti.dart';
import '../widgets/hold_editor_button.dart';
import '../widgets/home/wall_image_carousel.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  static const String _hasShownConfettiKey = 'has_shown_confetti_';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorButtonKey = useMemoized(() => GlobalKey());

    // Confetti 체크
    useEffect(() {
      _checkAndShowConfetti(context);
      return null;
    }, []);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Your Climbing Walls',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            const Expanded(
              child: WallImageCarousel(),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: HoldEditorButton(
                buttonKey: editorButtonKey,
                buttonLabel: 'Take Wall Photo',
                buttonIcon: Icons.camera_alt,
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

참고: `HoldEditorButton`에 `buttonLabel`과 `buttonIcon` 파라미터를 추가해야 한다 (Task 6에서 처리).

- [ ] **Step 2: 정적 분석 (Task 6 이후에 통과)**

분석은 Task 6 이후에 실행한다 (HoldEditorButton 수정 필요).

---

### Task 6: HoldEditorButton에 커스텀 라벨/아이콘 지원 추가

**Files:**
- Modify: `apps/mobile/lib/widgets/hold_editor_button.dart`

- [ ] **Step 1: HoldEditorButton에 optional 파라미터 추가**

`apps/mobile/lib/widgets/hold_editor_button.dart`의 `HoldEditorButton` 클래스를 수정:

기존:
```dart
class HoldEditorButton extends StatefulWidget {
  final GlobalKey buttonKey;
  final Function()? onTapDown;

  const HoldEditorButton({
    super.key,
    required this.buttonKey,
    this.onTapDown,
  });
```

변경:
```dart
class HoldEditorButton extends StatefulWidget {
  final GlobalKey buttonKey;
  final Function()? onTapDown;
  final String? buttonLabel;
  final IconData? buttonIcon;

  const HoldEditorButton({
    super.key,
    required this.buttonKey,
    this.onTapDown,
    this.buttonLabel,
    this.buttonIcon,
  });
```

`build` 메서드의 `child: Container(...)` 부분을 수정:

기존:
```dart
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF007AFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          AppLocalizations.of(context)!.setRoute,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
```

변경:
```dart
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF007AFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.buttonIcon != null) ...[
              Icon(widget.buttonIcon, color: Colors.white, size: 24),
              const SizedBox(width: 8),
            ],
            Text(
              widget.buttonLabel ?? AppLocalizations.of(context)!.setRoute,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
```

- [ ] **Step 2: 정적 분석**

Run: `cd apps/mobile && flutter analyze`
Expected: 에러 없음

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/hold_editor_button.dart apps/mobile/lib/pages/home.dart
git commit -m "feat(mobile): redesign home page with wall carousel and take photo button"
```

---

### Task 7: main.dart에서 MainTabPage 연결

**Files:**
- Modify: `apps/mobile/lib/main.dart`

- [ ] **Step 1: import 추가 및 MainMenuPage에서 MainTabPage 사용**

`apps/mobile/lib/main.dart`에서:

import 추가:
```dart
import 'pages/main_tab.dart';
```

`_MainMenuPageState.build` 메서드에서 `HomePage` → `MainTabPage` 교체:

기존 (174행):
```dart
        return UpgradeAlert(
          child: authState.isLoggedIn ? const HomePage() : const LoginPage(),
        );
```

변경:
```dart
        return UpgradeAlert(
          child: authState.isLoggedIn ? const MainTabPage() : const LoginPage(),
        );
```

- [ ] **Step 2: 정적 분석**

Run: `cd apps/mobile && flutter analyze`
Expected: 에러 없음

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/main.dart
git commit -m "feat(mobile): connect MainTabPage as authenticated home screen"
```

---

### Task 8: 통합 검증

- [ ] **Step 1: 전체 정적 분석**

Run: `cd apps/mobile && flutter analyze`
Expected: 에러 없음

- [ ] **Step 2: 사용하지 않는 import 확인**

`home.dart`에서 기존 사용하던 import 중 불필요한 것 제거 확인:
- `route_list.dart` → 제거됨
- `image_carousel.dart` → 제거됨
- `guide_bubble.dart` → 제거됨 (가이드 버블은 향후 캐로셀에 맞게 재도입 가능)
- `routes_provider.dart` → 제거됨
- `setting.dart` → 제거됨 (MainTabPage에서 import)

- [ ] **Step 3: 최종 Commit**

```bash
git add -A
git commit -m "feat(mobile): complete home page redesign with tab navigation"
```
