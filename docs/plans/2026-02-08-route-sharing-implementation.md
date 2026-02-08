# Route 공유하기 기능 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Universal Link를 통해 루트를 공유하고, 앱 미설치 시 스토어로 리다이렉트하는 기능 구현

**Architecture:** Backend에서 `/share/routes/{routeId}` 엔드포인트가 HTML을 반환하고, iOS/Android Universal Link 설정을 통해 앱이 설치되어 있으면 앱에서 열림. Flutter 앱에서 딥링크를 수신하여 로그인 체크 후 루트 상세 화면으로 이동.

**Tech Stack:** FastAPI (Jinja2 templates), Flutter (app_links, share_plus), Universal Links (AASA, assetlinks.json)

**API Base URL:** `https://besetter-api-371038003203.asia-northeast3.run.app`

---

## Task 1: Backend - Visibility Enum에 UNLISTED 추가

**Files:**
- Modify: `services/api/app/models/route.py:17-19`

**Step 1: Visibility Enum 수정**

`services/api/app/models/route.py` 파일의 17-19번 라인을 다음과 같이 수정:

```python
class Visibility(str, Enum):
    PUBLIC = "public"
    PRIVATE = "private"
    UNLISTED = "unlisted"
```

**Step 2: 커밋**

```bash
cd /Users/htjo/besetter
git add services/api/app/models/route.py
git commit -m "feat(api): add UNLISTED visibility option for route sharing"
```

---

## Task 2: Backend - Jinja2 템플릿 설정

**Files:**
- Modify: `services/api/pyproject.toml`
- Create: `services/api/app/templates/share_route.html`
- Create: `services/api/app/templates/share_error.html`

**Step 1: Jinja2 의존성 추가**

`services/api/pyproject.toml`의 dependencies에 추가:

```toml
"jinja2>=3.1.0",
```

**Step 2: 공유 페이지 HTML 템플릿 생성**

`services/api/app/templates/share_route.html`:

```html
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ title }} | Besetter</title>

    <!-- Open Graph -->
    <meta property="og:type" content="website">
    <meta property="og:title" content="{{ title }} | Besetter">
    <meta property="og:description" content="{{ description }}">
    <meta property="og:image" content="{{ image_url }}">
    <meta property="og:url" content="{{ share_url }}">

    <!-- Twitter Card -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="{{ title }} | Besetter">
    <meta name="twitter:description" content="{{ description }}">
    <meta name="twitter:image" content="{{ image_url }}">

    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            text-align: center;
            padding: 20px;
            box-sizing: border-box;
        }
        .container {
            max-width: 400px;
        }
        h1 {
            font-size: 24px;
            margin-bottom: 16px;
        }
        p {
            font-size: 16px;
            opacity: 0.9;
            margin-bottom: 24px;
        }
        .spinner {
            width: 40px;
            height: 40px;
            border: 3px solid rgba(255,255,255,0.3);
            border-top-color: white;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin: 0 auto 24px;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        .store-buttons {
            display: flex;
            flex-direction: column;
            gap: 12px;
        }
        .store-button {
            display: inline-block;
            padding: 12px 24px;
            background: white;
            color: #333;
            text-decoration: none;
            border-radius: 8px;
            font-weight: 600;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="spinner"></div>
        <h1>Besetter로 이동 중...</h1>
        <p>앱이 설치되어 있지 않다면 아래 버튼을 눌러주세요.</p>
        <div class="store-buttons">
            <a href="{{ app_store_url }}" class="store-button">App Store에서 다운로드</a>
            <a href="{{ play_store_url }}" class="store-button">Google Play에서 다운로드</a>
        </div>
    </div>

    <script>
        // 딥링크 시도 (fallback)
        const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
        const isAndroid = /Android/.test(navigator.userAgent);

        setTimeout(() => {
            if (isIOS) {
                window.location.href = "{{ app_store_url }}";
            } else if (isAndroid) {
                window.location.href = "{{ play_store_url }}";
            }
        }, 2500);
    </script>
</body>
</html>
```

**Step 3: 에러 페이지 HTML 템플릿 생성**

`services/api/app/templates/share_error.html`:

```html
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ title }} | Besetter</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            margin: 0;
            background: #f5f5f5;
            color: #333;
            text-align: center;
            padding: 20px;
            box-sizing: border-box;
        }
        .container {
            max-width: 400px;
        }
        .icon {
            font-size: 64px;
            margin-bottom: 16px;
        }
        h1 {
            font-size: 24px;
            margin-bottom: 16px;
        }
        p {
            font-size: 16px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">{{ icon }}</div>
        <h1>{{ title }}</h1>
        <p>{{ message }}</p>
    </div>
</body>
</html>
```

**Step 4: 커밋**

```bash
cd /Users/htjo/besetter
git add services/api/pyproject.toml services/api/app/templates/
git commit -m "feat(api): add Jinja2 templates for route sharing"
```

---

## Task 3: Backend - Share 라우터 생성

**Files:**
- Create: `services/api/app/routers/share.py`
- Modify: `services/api/app/main.py:4,44`

**Step 1: Share 라우터 생성**

`services/api/app/routers/share.py`:

```python
from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from beanie.odm.fields import PydanticObjectId
from bson.errors import InvalidId

from app.models.route import Route, Visibility

router = APIRouter(prefix="/share", tags=["share"])

templates = Jinja2Templates(directory="app/templates")

APP_STORE_URL = "https://apps.apple.com/app/besetter/id123456789"  # TODO: 실제 App Store URL로 교체
PLAY_STORE_URL = "https://play.google.com/store/apps/details?id=com.olivebagel.besetter"


@router.get("/routes/{route_id}", response_class=HTMLResponse)
async def share_route(request: Request, route_id: str):
    """공유 링크로 접근 시 OG 태그가 포함된 HTML 페이지 반환"""

    # ObjectId 유효성 검사
    try:
        object_id = PydanticObjectId(route_id)
    except (InvalidId, ValueError):
        return templates.TemplateResponse(
            "share_error.html",
            {
                "request": request,
                "icon": "🔍",
                "title": "루트를 찾을 수 없습니다",
                "message": "요청하신 루트가 존재하지 않습니다.",
            },
            status_code=404,
        )

    # 루트 조회
    route = await Route.get(object_id)

    # 루트가 없거나 삭제된 경우
    if route is None or route.is_deleted:
        return templates.TemplateResponse(
            "share_error.html",
            {
                "request": request,
                "icon": "🔍",
                "title": "루트를 찾을 수 없습니다",
                "message": "요청하신 루트가 존재하지 않거나 삭제되었습니다.",
            },
            status_code=404,
        )

    # 비공개 루트인 경우
    if route.visibility == Visibility.PRIVATE:
        return templates.TemplateResponse(
            "share_error.html",
            {
                "request": request,
                "icon": "🔒",
                "title": "비공개 루트입니다",
                "message": "이 루트는 비공개로 설정되어 있습니다.",
            },
            status_code=403,
        )

    # 제목 생성 (grade + type)
    route_type_kr = "볼더링" if route.type.value == "bouldering" else "지구력"
    title = f"{route.grade} {route_type_kr}"
    if route.title:
        title = route.title

    # 설명 생성
    description_parts = [route.grade]
    if route.gym_name:
        description_parts.append(route.gym_name)
    description = " · ".join(description_parts)

    share_url = str(request.url)

    return templates.TemplateResponse(
        "share_route.html",
        {
            "request": request,
            "title": title,
            "description": description,
            "image_url": str(route.image_url),
            "share_url": share_url,
            "app_store_url": APP_STORE_URL,
            "play_store_url": PLAY_STORE_URL,
        },
    )
```

**Step 2: main.py에 라우터 등록**

`services/api/app/main.py` 수정:

4번 라인에 import 추가:
```python
from app.routers import authentications, hold_polygons, share
```

44번 라인 (routes.router 다음)에 추가:
```python
app.include_router(share.router)
```

**Step 3: 커밋**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/share.py services/api/app/main.py
git commit -m "feat(api): add share router for route sharing with OG tags"
```

---

## Task 4: Backend - Well-Known 파일 엔드포인트

**Files:**
- Create: `services/api/app/routers/well_known.py`
- Modify: `services/api/app/main.py:4,45`

**Step 1: Well-Known 라우터 생성**

`services/api/app/routers/well_known.py`:

```python
from fastapi import APIRouter
from fastapi.responses import JSONResponse

router = APIRouter(prefix="/.well-known", tags=["well-known"])

# iOS App 정보 - TODO: 실제 값으로 교체
IOS_TEAM_ID = "XXXXXXXXXX"  # Apple Developer Team ID
IOS_BUNDLE_ID = "com.olivebagel.besetter"

# Android App 정보 - TODO: 실제 값으로 교체
ANDROID_PACKAGE_NAME = "com.olivebagel.besetter"
ANDROID_SHA256_FINGERPRINTS = [
    "XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX"
]


@router.get("/apple-app-site-association")
async def apple_app_site_association():
    """iOS Universal Links를 위한 AASA 파일"""
    return JSONResponse(
        content={
            "applinks": {
                "apps": [],
                "details": [
                    {
                        "appID": f"{IOS_TEAM_ID}.{IOS_BUNDLE_ID}",
                        "paths": ["/share/routes/*"],
                    }
                ],
            }
        },
        media_type="application/json",
    )


@router.get("/assetlinks.json")
async def asset_links():
    """Android App Links를 위한 assetlinks.json 파일"""
    return JSONResponse(
        content=[
            {
                "relation": ["delegate_permission/common.handle_all_urls"],
                "target": {
                    "namespace": "android_app",
                    "package_name": ANDROID_PACKAGE_NAME,
                    "sha256_cert_fingerprints": ANDROID_SHA256_FINGERPRINTS,
                },
            }
        ],
        media_type="application/json",
    )
```

**Step 2: main.py에 라우터 등록**

`services/api/app/main.py` 수정:

4번 라인의 import 수정:
```python
from app.routers import authentications, hold_polygons, share, well_known
```

45번 라인 (share.router 다음)에 추가:
```python
app.include_router(well_known.router)
```

**Step 3: 커밋**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/well_known.py services/api/app/main.py
git commit -m "feat(api): add well-known endpoints for Universal Links"
```

---

## Task 5: Flutter - share_plus 및 app_links 패키지 추가

**Files:**
- Modify: `apps/mobile/pubspec.yaml:70`

**Step 1: 패키지 추가**

`apps/mobile/pubspec.yaml`의 70번 라인 (webview_flutter 다음)에 추가:

```yaml
  share_plus: ^10.0.0
  app_links: ^6.3.0
```

**Step 2: 패키지 설치**

```bash
cd /Users/htjo/besetter/apps/mobile
flutter pub get
```

**Step 3: 커밋**

```bash
cd /Users/htjo/besetter
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock
git commit -m "feat(mobile): add share_plus and app_links packages"
```

---

## Task 6: Flutter - Deep Link Service 생성

**Files:**
- Create: `apps/mobile/lib/services/deep_link_service.dart`

**Step 1: DeepLinkService 생성**

`apps/mobile/lib/services/deep_link_service.dart`:

```dart
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// 딥링크 대기 중인 route ID (로그인 후 처리용)
  String? pendingRouteId;

  /// 딥링크 리스너 초기화
  void init({required Function(String routeId) onRouteLink}) {
    // 앱이 이미 실행 중일 때 딥링크 수신
    _subscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri, onRouteLink);
    });

    // 앱이 딥링크로 시작된 경우
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleUri(uri, onRouteLink);
      }
    });
  }

  void _handleUri(Uri uri, Function(String routeId) onRouteLink) {
    // /share/routes/{routeId} 형식 파싱
    final pathSegments = uri.pathSegments;
    if (pathSegments.length >= 3 &&
        pathSegments[0] == 'share' &&
        pathSegments[1] == 'routes') {
      final routeId = pathSegments[2];
      onRouteLink(routeId);
    }
  }

  /// 대기 중인 딥링크 소비
  String? consumePendingRouteId() {
    final routeId = pendingRouteId;
    pendingRouteId = null;
    return routeId;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
```

**Step 2: 커밋**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/services/deep_link_service.dart
git commit -m "feat(mobile): add DeepLinkService for handling shared route links"
```

---

## Task 7: Flutter - main.dart에 딥링크 핸들러 통합

**Files:**
- Modify: `apps/mobile/lib/main.dart`

**Step 1: DeepLinkService import 및 초기화**

`apps/mobile/lib/main.dart` 수정:

8번 라인에 import 추가:
```dart
import 'services/deep_link_service.dart';
```

26번 라인 `void main()` 함수 내부, `runApp()` 전에 추가:
```dart
  DeepLinkService().init(
    onRouteLink: (routeId) {
      // 로그인 상태 확인 후 처리는 MainMenuPage에서 수행
      DeepLinkService().pendingRouteId = routeId;
    },
  );
```

**Step 2: MainMenuPage에서 딥링크 처리**

`apps/mobile/lib/main.dart`의 `MainMenuPage` 클래스를 다음으로 교체:

```dart
class MainMenuPage extends ConsumerStatefulWidget {
  const MainMenuPage({super.key});

  @override
  ConsumerState<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends ConsumerState<MainMenuPage> {
  @override
  void initState() {
    super.initState();
    // 딥링크 초기화
    DeepLinkService().init(
      onRouteLink: (routeId) {
        _handleRouteLink(routeId);
      },
    );
    // 앱 시작 시 대기 중인 딥링크 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingRouteId = DeepLinkService().consumePendingRouteId();
      if (pendingRouteId != null) {
        _handleRouteLink(pendingRouteId);
      }
    });
  }

  void _handleRouteLink(String routeId) {
    final authAsync = ref.read(authProvider);
    authAsync.whenData((authState) {
      if (authState.isLoggedIn) {
        _navigateToRoute(routeId);
      } else {
        // 로그인 필요 - pendingRouteId 저장 후 로그인 화면으로
        DeepLinkService().pendingRouteId = routeId;
        Navigator.of(context).pushNamed('/login');
      }
    });
  }

  Future<void> _navigateToRoute(String routeId) async {
    // RouteViewer로 직접 이동
    final response = await AuthorizedHttpClient.get('/routes/$routeId');
    if (response.statusCode == 200) {
      final routeData = RouteData.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RouteViewer(routeData: routeData),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('루트를 불러올 수 없습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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

        // 로그인 완료 후 대기 중인 딥링크 처리
        if (authState.isLoggedIn) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final pendingRouteId = DeepLinkService().consumePendingRouteId();
            if (pendingRouteId != null) {
              _navigateToRoute(pendingRouteId);
            }
          });
        }

        return UpgradeAlert(
          child: authState.isLoggedIn ? const HomePage() : const LoginPage(),
        );
      },
    );
  }
}
```

상단에 필요한 import 추가:
```dart
import 'dart:convert';
import 'models/route_data.dart';
import 'pages/viewers/route_viewer.dart';
```

**Step 3: 정적 분석 실행**

```bash
cd /Users/htjo/besetter/apps/mobile
flutter analyze
```

**Step 4: 커밋**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/main.dart
git commit -m "feat(mobile): integrate deep link handling in MainMenuPage"
```

---

## Task 8: Flutter - RouteCard에 공유 버튼 추가

**Files:**
- Modify: `apps/mobile/lib/widgets/home/route_card.dart:171-211`

**Step 1: share_plus import 추가**

`apps/mobile/lib/widgets/home/route_card.dart` 상단에 추가:
```dart
import 'package:share_plus/share_plus.dart';
```

**Step 2: 공유 함수 추가**

`_RouteCardState` 클래스 내부, `_handleDelete` 함수 다음에 추가:

```dart
  void _handleShare() {
    const baseUrl = 'https://besetter-api-371038003203.asia-northeast3.run.app';
    final shareUrl = '$baseUrl/share/routes/${widget.route.id}';
    Share.share(shareUrl);
  }
```

**Step 3: 공유 버튼 UI 추가**

171-211번 라인의 `Row` 위젯을 다음으로 교체:

```dart
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.share, size: 20),
                              onPressed: _handleShare,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.more_vert, size: 20),
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
```

**Step 4: 정적 분석 실행**

```bash
cd /Users/htjo/besetter/apps/mobile
flutter analyze
```

**Step 5: 커밋**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/widgets/home/route_card.dart
git commit -m "feat(mobile): add share button to RouteCard"
```

---

## Task 9: Flutter - RouteViewer AppBar에 공유 버튼 추가

**Files:**
- Modify: `apps/mobile/lib/pages/viewers/route_viewer.dart:192-206`

**Step 1: share_plus import 추가**

`apps/mobile/lib/pages/viewers/route_viewer.dart` 상단에 추가:
```dart
import 'package:share_plus/share_plus.dart';
```

**Step 2: 공유 함수 추가**

`_RouteViewerState` 클래스 내부, `_getSelectedOrder` 함수 다음에 추가:

```dart
  void _handleShare() {
    const baseUrl = 'https://besetter-api-371038003203.asia-northeast3.run.app';
    final shareUrl = '$baseUrl/share/routes/${widget.routeData.id}';
    Share.share(shareUrl);
  }
```

**Step 3: AppBar actions 수정**

192-206번 라인의 `appBar` 부분을 다음으로 교체:

```dart
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.viewRoute),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _handleShare,
            tooltip: '공유',
          ),
          if (widget.routeData.type == RouteType.endurance)
            IconButton(
              icon: Icon(_showHoldOrder ? Icons.visibility : Icons.visibility_off),
              onPressed: () {
                setState(() {
                  _showHoldOrder = !_showHoldOrder;
                });
              },
              tooltip: AppLocalizations.of(context)!.displayHoldOrder,
            ),
        ],
      ),
```

**Step 4: 정적 분석 실행**

```bash
cd /Users/htjo/besetter/apps/mobile
flutter analyze
```

**Step 5: 커밋**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/pages/viewers/route_viewer.dart
git commit -m "feat(mobile): add share button to RouteViewer AppBar"
```

---

## Task 10: iOS - Associated Domains 설정

**Files:**
- Modify: `apps/mobile/ios/Runner/Runner.entitlements:9-12`

**Step 1: Associated Domains 추가**

`apps/mobile/ios/Runner/Runner.entitlements`의 9-12번 라인을 다음으로 교체:

```xml
	<key>com.apple.developer.associated-domains</key>
	<array>
		<string>applinks:olivebagel.com</string>
		<string>applinks:besetter-api-371038003203.asia-northeast3.run.app</string>
	</array>
```

**Step 2: 커밋**

```bash
cd /Users/htjo/besetter
git add apps/mobile/ios/Runner/Runner.entitlements
git commit -m "feat(ios): add API domain to associated domains for Universal Links"
```

---

## Task 11: Android - App Links Intent Filter 추가

**Files:**
- Modify: `apps/mobile/android/app/src/main/AndroidManifest.xml:5-15`

**Step 1: MainActivity에 intent-filter 추가**

`apps/mobile/android/app/src/main/AndroidManifest.xml`의 MainActivity 내부 (14번 라인, 기존 intent-filter 닫힌 후)에 추가:

```xml
            <!-- Deep Link for route sharing -->
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data
                    android:scheme="https"
                    android:host="besetter-api-371038003203.asia-northeast3.run.app"
                    android:pathPrefix="/share/routes" />
            </intent-filter>
```

**Step 2: 커밋**

```bash
cd /Users/htjo/besetter
git add apps/mobile/android/app/src/main/AndroidManifest.xml
git commit -m "feat(android): add intent-filter for App Links route sharing"
```

---

## Task 12: 최종 검증

**Step 1: Flutter 정적 분석**

```bash
cd /Users/htjo/besetter/apps/mobile
flutter analyze
```

Expected: No issues found!

**Step 2: Backend 구문 검사**

```bash
cd /Users/htjo/besetter/services/api
python -m py_compile app/routers/share.py app/routers/well_known.py
```

Expected: No output (no syntax errors)

**Step 3: 커밋 히스토리 확인**

```bash
cd /Users/htjo/besetter
git log --oneline -12
```

---

## 구현 후 수동 테스트 체크리스트

- [ ] API 서버 배포 후 `/.well-known/apple-app-site-association` 접속 확인
- [ ] API 서버 배포 후 `/.well-known/assetlinks.json` 접속 확인
- [ ] API 서버 배포 후 `/share/routes/{validRouteId}` 접속 시 HTML 페이지 확인
- [ ] iOS 앱에서 공유 버튼 탭 시 시스템 공유 시트 표시 확인
- [ ] Android 앱에서 공유 버튼 탭 시 시스템 공유 시트 표시 확인
- [ ] 공유 링크 클릭 시 앱으로 이동 확인 (앱 설치된 경우)
- [ ] 공유 링크 클릭 시 스토어로 리다이렉트 확인 (앱 미설치 경우)
- [ ] 미로그인 상태에서 딥링크 진입 시 로그인 후 루트 화면 이동 확인
