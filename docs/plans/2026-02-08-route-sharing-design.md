# Route 공유하기 기능 설계

## 개요

Universal Link를 통해 루트를 공유하고, 앱 미설치 시 스토어로 리다이렉트하는 기능.

## 전체 흐름

```
[사용자 A: 공유하기]
루트 카드/상세화면 → 공유 버튼 탭 → 시스템 공유 시트
                    → https://api.besetter.app/share/routes/{routeId} 링크 복사/전송

[사용자 B: 링크 클릭]
링크 클릭 → 앱 설치됨?
         ├─ Yes → 앱 실행 → 로그인됨?
         │                 ├─ Yes → 루트 상세 화면
         │                 └─ No  → 로그인 화면 → 루트 상세 화면
         └─ No  → 브라우저 열림 → HTML 페이지
                               → iOS: App Store / Android: Play Store 리다이렉트
```

## Backend 변경사항

### Visibility Enum 추가

```python
class Visibility(str, Enum):
    PUBLIC = "public"
    PRIVATE = "private"
    UNLISTED = "unlisted"  # URL을 알면 접근 가능
```

### 공유 엔드포인트 (`GET /share/routes/{routeId}`)

- **응답**: HTML 페이지
  - OG 태그 포함 (카카오톡, iMessage 미리보기용)
  - JavaScript로 앱스토어/플레이스토어 리다이렉트
- **권한 체크**:
  - `PUBLIC` 또는 `UNLISTED` → 접근 허용
  - `PRIVATE` → "비공개 루트입니다" 페이지

### OG 태그

```html
<meta property="og:title" content="{루트 제목} | Besetter" />
<meta property="og:description" content="{난이도} · {암장명}" />
<meta property="og:image" content="{루트 이미지 URL}" />
```

## Universal Link 설정

### iOS - Apple App Site Association

API 서버에서 `/.well-known/apple-app-site-association` 제공:

```json
{
  "applinks": {
    "apps": [],
    "details": [{
      "appID": "{TeamID}.{BundleID}",
      "paths": ["/share/routes/*"]
    }]
  }
}
```

### Android - Asset Links

API 서버에서 `/.well-known/assetlinks.json` 제공:

```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "{패키지명}",
    "sha256_cert_fingerprints": ["{인증서 핑거프린트}"]
  }
}]
```

### 앱 설정

- iOS `Info.plist`: Associated Domains 추가
- Android `AndroidManifest.xml`: intent-filter 추가 (autoVerify=true)

## Flutter 앱 변경사항

### 딥링크 핸들링

```
링크 수신 → URL 파싱 (/share/routes/{routeId})
         → 로그인 체크
         ├─ 로그인됨 → 루트 상세 화면으로 이동
         └─ 미로그인 → 로그인 화면 (완료 후 루트 상세 화면)
```

### 공유 버튼 UI

| 위치 | 구현 |
|------|------|
| 루트 카드 | 메뉴 버튼 좌측에 `IconButton(Icons.share)` |
| 루트 상세 AppBar | 우측에 `IconButton(Icons.share)` |

### 공유 기능

```dart
Share.share('https://api.besetter.app/share/routes/$routeId');
```

- `share_plus` 패키지 사용
- 시스템 공유 시트 표시

## 예외 처리

| 상황 | 처리 |
|------|------|
| 존재하지 않는 routeId | 404 페이지 (웹) / 에러 다이얼로그 (앱) |
| PRIVATE 루트 접근 | "비공개 루트입니다" 페이지/메시지 |
| 삭제된 루트 (is_deleted=true) | 404 페이지 / "삭제된 루트입니다" |
| 네트워크 오류 | 재시도 안내 |
| 딥링크 파싱 실패 | 홈 화면으로 이동 |

## 변경 파일 목록

### Backend (services/api)

| 파일 | 변경 내용 |
|------|-----------|
| `app/models/route.py` | Visibility enum에 UNLISTED 추가 |
| `app/routers/share.py` | 신규 - 공유 엔드포인트 |
| `app/main.py` | share 라우터 등록 |
| `app/templates/share_route.html` | 신규 - OG 태그 + 스토어 리다이렉트 HTML |
| `app/routers/well_known.py` | 신규 - AASA, assetlinks.json 제공 |

### Flutter (apps/mobile)

| 파일 | 변경 내용 |
|------|-----------|
| `pubspec.yaml` | share_plus 패키지 추가 |
| `lib/main.dart` | 딥링크 리스너 설정 |
| `lib/services/deep_link_service.dart` | 신규 - 딥링크 파싱 및 라우팅 |
| `lib/widgets/route_card.dart` | 공유 버튼 추가 |
| `lib/pages/route_detail.dart` | AppBar에 공유 버튼 추가 |
| `ios/Runner/Runner.entitlements` | Associated Domains 추가 |
| `android/app/src/main/AndroidManifest.xml` | intent-filter 추가 |
