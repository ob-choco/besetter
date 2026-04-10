# My Page (Profile Screen) Design Spec

## Overview

BESETTER 앱의 3번째 탭을 기존 Settings(Menu)에서 My Page(Profile)로 교체한다. 프로필 조회/편집 기능은 실제 API와 연동하고, 월별 운동 달력과 최근 운동 섹션은 목업 데이터로 UI만 구현한다.

**Figma 참조**: `https://www.figma.com/design/NcvQLkVoxRIsvZzYO8kteB/BESETTER?node-id=2049-1024`

---

## 1. Backend

### 1.1 User Model 변경

`services/api/app/models/user.py`의 `User` Document에 필드 추가:

```python
bio: Optional[str] = None
```

MongoDB + Optional 필드이므로 별도 마이그레이션 불필요.

### 1.2 GET /users/me

인증된 유저의 프로필 정보를 반환한다.

**Response 200:**
```json
{
  "name": "Alex Rivers",
  "email": "alex@example.com",
  "bio": "Outdoor enthusiast. Bouldering since 2018.",
  "profileImageUrl": "https://storage.googleapis.com/besetter/profile_images/...(signed URL)"
}
```

- `profile_image_url`이 존재하면 `generate_signed_url()`로 signed URL 변환 후 반환
- 없으면 `profileImageUrl: null`
- camelCase 응답 (기존 API 컨벤션 따름)

### 1.3 PATCH /users/me

프로필 정보를 수정한다. multipart/form-data 요청.

**Request:**
| Field | Type | Required | Description |
|---|---|---|---|
| name | string | No | 변경할 이름 |
| bio | string | No | 변경할 자기소개 |
| profileImage | file | No | 변경할 프로필 이미지 |

**Response 200:** GET /users/me와 동일 형태.

**이미지 처리:**
- GCS 저장 경로: `profile_images/{user_id}_{timestamp}{ext}`
- 기존 프로필 이미지가 있으면 GCS에서 이전 이미지 삭제 후 교체
- 이미지 없이 name/bio만 수정도 가능

**사용 인프라:**
- 기존 `app/core/gcs.py`의 `bucket`, `generate_signed_url`, `extract_blob_path_from_url` 활용

---

## 2. Mobile — Tab 변경

### 2.1 MainTabPage 수정

`apps/mobile/lib/pages/main_tab.dart`:

- 3번째 탭 `SettingsPage` → `MyPage`로 교체
- 아이콘: `Icons.menu` → `Icons.person`
- 라벨: `navMenu` → `navMy`

### 2.2 i18n 추가

`l10n/app_en.arb`, `app_ko.arb`, `app_ja.arb`, `app_es.arb`에 `navMy` 키 추가.

---

## 3. Mobile — MyPage 화면

### 3.1 파일 구조

| 파일 | 역할 |
|---|---|
| `lib/pages/my_page.dart` | MyPage 화면 (HookConsumerWidget) |
| `lib/providers/user_provider.dart` | GET/PATCH /users/me 호출 및 상태 관리 |

### 3.2 UserProvider

`@riverpod` 어노테이션 사용 (기존 패턴).

**UserState:**
```dart
class UserState {
  final String? name;
  final String? email;
  final String? bio;
  final String? profileImageUrl;
}
```

**메서드:**
- `fetchProfile()`: GET /users/me → 상태 업데이트
- `updateProfile({String? name, String? bio, File? imageFile})`: PATCH /users/me multipart → 상태 업데이트

### 3.3 MyPage 레이아웃

```
┌─────────────────────────────┐
│  AppBar: "Profile"  [✏️][⚙️] │
├─────────────────────────────┤
│      ┌──────┐               │
│      │ 프로필 │               │
│      │ 사진  │               │
│      └──────┘               │
│    사용자 이름               │
│    자기소개 텍스트            │
├─────────────────────────────┤
│  Monthly Progress   Oct 2023│
│  S  M  T  W  T  F  S       │
│  (달력 그리드)               │
├─────────────────────────────┤
│  Recent workout             │
│  (루트 카드)                 │
└─────────────────────────────┘
```

**피그마 디자인 반영:**
- 배경색: `Color(0xFFF5F6F7)`
- 프로필 사진: 96px 원형, `Color(0xFFDADDDF)` 4px border, `Color(0x330066FF)` 배경
- 이름: Plus Jakarta Sans Bold 24px, `Color(0xFF2C2F30)`
- 자기소개: Inter Regular 14px, `Color(0xFF595C5D)`, 중앙 정렬, max 320px
- 달력 카드: 흰색 배경, 24px rounded, `BoxShadow(0, 4, 24, Color(0x0A2C2F30))`
- 운동한 날: `Color(0x1A0066FF)` 배경, 12px rounded, 하단 파란 도트
- 선택한 날: 추가로 `Color(0xFF0066FF)` 2px border, 텍스트 파란색
- 빈 날: `Color(0x80595C5D)` 텍스트
- Recent workout 카드: 12px rounded, `BoxShadow(0, 8, 32, Color(0x1F000000))`, 이미지 위 그라데이션 오버레이

### 3.4 편집 모드 UX

**hooks 상태:**
- `useState<bool>(false)` — 편집 모드 on/off
- `useState<File?>(null)` — 크롭된 이미지 (저장 전 미리보기용)
- `useTextEditingController()` x2 — 이름, bio
- `useState<DateTime>` — 달력 선택 날짜
- `useState<DateTime>` — 달력 현재 월

**일반 모드:**
- AppBar 우측: 수정 아이콘 버튼 + 설정 아이콘 버튼
- 프로필 사진, 이름, bio는 읽기 전용 텍스트

**편집 모드 진입 (수정 버튼 탭):**
1. 수정 버튼 → 저장 버튼으로 변경
2. 프로필 이미지 원 **우하단 가장자리**에 작은 수정 아이콘 배지 표시 (이미지 자체는 가리지 않음)
3. 이름, bio → TextField로 전환 (기존 값 prefill)

**프로필 이미지 편집:**
1. 수정 아이콘 배지 탭 → 시스템 이미지 피커 (갤러리/카메라 선택 — 기존 `image_picker` 패키지 활용)
2. 사진 선택 후 → `image_cropper` 패키지로 원형 크롭 미리보기 화면
3. 사용자가 핀치/드래그로 위치/확대 조절 후 확인
4. 크롭된 이미지를 프로필 원에 미리보기 반영 (아직 서버 업로드 안 함)

**저장 (저장 버튼 탭):**
1. PATCH /users/me multipart 호출 (변경된 필드만 전송)
2. 성공 시 편집 모드 해제, 상태 업데이트
3. 실패 시 SnackBar 에러 메시지

### 3.5 달력 위젯 (목업)

`my_page.dart` 내부 private 위젯 `_MonthlyCalendar`.

**목업 데이터:**
```dart
const _mockWorkoutDays = {1, 4, 5, 9, 11, 12, 13, 15, 17};
```

**구현:**
- 7열 그리드 (S M T W T F S)
- 운동한 날: 파란 배경 + 하단 도트
- 선택된 날: 파란 border + 파란 텍스트
- 월 선택기: "October 2023" 텍스트 + 화살표 아이콘 (목업이므로 탭해도 월 변경 없음)
- 날짜 탭 → 선택 상태 변경 + 하단 Recent workout 카드 내용 변경

### 3.6 Recent Workout 카드 (목업)

**목업 데이터:**
```dart
const _mockWorkouts = {
  15: { grade: 'V7', sector: 'The Overhang', name: 'Electric Drift', gym: 'Urban Apex Gym' },
  17: { grade: 'V5', sector: 'Slab Wall', name: 'Crimson Flow', gym: 'Urban Apex Gym' },
  // ... 기타 운동한 날짜별 데이터
};
```

**디자인:**
- 이미지 배경 (로컬 placeholder — 단색 그라데이션 Container로 대체, 별도 asset 불필요)
- 하단 그라데이션 오버레이 (black 0.8 → transparent)
- 난이도 배지 (컬러 pill)
- 루트 이름 (30px semibold white)
- 짐 이름 (18px white 80% opacity)

---

## 4. Dependencies

### pubspec.yaml 추가
```yaml
image_cropper: ^8.0.2
```

### 기존 활용
- `image_picker` — 이미 있음
- `hooks_riverpod`, `flutter_hooks` — 이미 있음
- `cached_network_image` — 프로필 이미지 표시에 활용

---

## 5. Scope 외 (추후)

- 달력 실제 데이터 연동 (GET /routes with date filter)
- 최근 운동 실제 데이터 연동
- 월 선택기 동작 (이전/다음 달 이동)
- 프로필 이미지 캐싱/오프라인 지원
