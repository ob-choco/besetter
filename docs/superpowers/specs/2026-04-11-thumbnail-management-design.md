# Thumbnail Management Design

## Overview

GCS에 저장된 이미지에 대해 on-demand 썸네일 생성 및 redirect를 제공하는 API endpoint를 설계한다. 클라이언트는 별도 썸네일 URL 필드 없이, 하나의 endpoint에 원본 경로와 preset을 전달하여 썸네일에 접근한다.

## Endpoint

```
GET /images/{blob_path:path}?type={preset}
```

### Parameters

| 파라미터 | 타입 | 필수 | 설명 |
|---------|------|------|------|
| `blob_path` | path | Y | GCS blob 경로 (예: `wall_images/abc.jpg`) |
| `type` | query | N | 썸네일 preset. 없으면 원본 redirect |

### Presets

| Preset | 모드 | 크기 | 용도 |
|--------|------|------|------|
| `w400` | width | 폭 400px, 높이 비율 유지 | 홈/루트 페이지 — 벽 이미지, 루트 오버레이 |
| `s100` | square | 100x100 중앙 크롭 | 장소 이미지, 유저 프로필 |

### Responses

| 상황 | 응답 |
|------|------|
| 성공 | `302 Redirect` → `{base_url}/{thumbnail_blob_path}` |
| type 없음 | `302 Redirect` → `{base_url}/{blob_path}` (원본) |
| 유효하지 않은 preset | `400 Bad Request` |
| 원본 blob 없음 | `404 Not Found` |
| 원본이 이미지가 아닌 파일 | `400 Bad Request` |

### Authentication

없음 (public endpoint). GCS 버킷이 public이므로 redirect URL도 인증 불필요.

## Thumbnail Generation Flow

1. thumbnail blob 경로 계산: `wall_images/abc.jpg` + `w400` → `wall_images/abc_w400.jpg`
2. GCS에 해당 blob 존재 확인 (`blob.exists()`)
3. 존재하면 → 바로 302 redirect
4. 없으면:
   - 원본 blob을 메모리에 다운로드
   - Pillow로 리사이즈
     - `w{n}`: 폭 n px, 높이 비율 유지
     - `s{n}`: n x n 정사각형, 중앙 크롭 후 리사이즈
   - JPEG 품질 85로 인코딩
   - GCS에 업로드
   - 302 redirect

### Edge Cases

- **원본이 요청 preset보다 작은 경우**: 원본 크기 그대로 저장 (확대하지 않음)
- **동시 요청**: 같은 썸네일에 대한 동시 요청 시 중복 생성 가능하나, 결과물이 동일하므로 별도 lock 없이 허용 (idempotent)

## GCS Storage

### 썸네일 저장 경로

원본과 같은 디렉토리에 suffix 추가:

```
원본: wall_images/abc.jpg
썸네일: wall_images/abc_w400.jpg
썸네일: wall_images/abc_s100.jpg
```

### 이미지 포맷

- JPEG, 품질 85
- 포맷 변환 없음 (원본 JPEG → 썸네일 JPEG)

## Code Structure

| 파일 | 역할 |
|------|------|
| `routers/images.py` | `GET /images/{blob_path:path}` endpoint 추가 |
| `services/thumbnail.py` | 신규 — 썸네일 존재 확인, 생성, 업로드 로직 |
| `core/gcs.py` | 필요 시 `blob.exists()` 헬퍼 추가 |

### services/thumbnail.py

주요 함수:

- `get_or_create_thumbnail(blob_path, preset)` → thumbnail blob 경로 반환
- `generate_thumbnail(image_bytes, preset)` → 리사이즈된 JPEG bytes 반환

### Preset 정의

```python
PRESETS = {
    "w400": {"mode": "width", "size": 400},
    "s100": {"mode": "square", "size": 100},
}
```

## Scope

### In Scope

- 모든 이미지 타입에 대한 on-demand 썸네일 생성 (wall_images, route_images, place_images)
- `w400`, `s100` 두 가지 preset
- GCS 캐싱 (한 번 생성 후 재사용)

### Out of Scope

- 기존 signed URL 제거/마이그레이션 (레거시로 유지)
- 기존 place_images의 `_thumb.jpg` 마이그레이션
- CDN, Cloud Function 분리
- WebP 등 포맷 변환
