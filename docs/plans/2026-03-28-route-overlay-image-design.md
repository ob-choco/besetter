# Route Overlay Image 자동 생성

## 개요

Route 생성/수정 시 hold_polygon을 입힌 오버레이 이미지를 자동 생성하여 GCS에 저장한다. 이미지 생성은 비동기(BackgroundTasks)로 처리하며, 작업 상태를 Route 도큐먼트에서 관리한다.

## Route 모델 변경

Route 도큐먼트에 4개 필드 추가:

| 필드 | 타입 | 기본값 | 설명 |
|------|------|--------|------|
| `overlay_image_url` | `Optional[HttpUrl]` | `None` | 생성된 오버레이 이미지 GCS URL |
| `overlay_processing` | `bool` | `False` | 이미지 생성 작업 중 플래그 |
| `overlay_started_at` | `Optional[datetime]` | `None` | 작업 시작 시간 |
| `overlay_completed_at` | `Optional[datetime]` | `None` | 작업 완료 시간 |

## API 응답 변경

`RouteDetailView`, `RouteServiceView`에 2개 필드 추가:

- `overlay_image_url`: signed URL로 변환하여 제공 (기존 `image_url` 패턴과 동일)
- `overlay_processing`: 클라이언트 로딩 상태 표시용

`overlay_started_at`, `overlay_completed_at`은 내부 관리용으로 API 응답에 포함하지 않는다.

## 서비스 모듈: `app/services/route_overlay.py`

### 함수: `generate_route_overlay(route: Route)`

라우터에서 Route 도큐먼트를 직접 전달받아 처리한다. (별도 Route 조회 없음)

**플로우:**

1. HoldPolygon 조회 (`route.image_id` 기준)
2. 루트 홀드 목록에서 해당 polygon_id만 필터링
3. 원본 이미지 다운로드 (GCS signed URL)
4. Pillow로 오버레이 렌더링 (3개 레이어 합성)
   - Layer 1: neonLime highlight 채우기 (0.3 opacity)
   - Layer 2: 타입별 fill color 채우기 (starting=green, finishing=red, 나머지=blue, 각 0.3 opacity)
   - Layer 3: neonLime 테두리 + TOP 마크 (finishing) + 검은 띠 마킹 (markingCount > 0)
5. GCS 업로드 (`route_images/{route_id}.jpg`)
6. Route overlay 필드만 부분 업데이트: `overlay_image_url`, `overlay_processing=False`, `overlay_completed_at=now`

**에러 처리:**

- try/finally로 실패 시에도 `overlay_processing=False` 리셋
- `overlay_completed_at`은 성공 시에만 갱신

## 라우터 변경: `app/routers/routes.py`

### `create_route`

Route 도큐먼트 생성 시 `overlay_processing=True`, `overlay_started_at=now`를 함께 세팅하여 한 번의 `save()`로 처리. 응답 반환 후 `BackgroundTasks`로 `generate_route_overlay(route)` 실행.

### `update_route`

기존 DeepDiff 결과에서 홀드 관련 필드(`bouldering_holds`, `endurance_holds`) 변경이 감지되면 `overlay_processing=True`, `overlay_started_at=now`를 세팅하여 `save()`. 응답 반환 후 `BackgroundTasks`로 `generate_route_overlay(route)` 실행.

홀드 외 필드(title, description, grade 등)만 변경된 경우에는 오버레이를 재생성하지 않는다.

## GCS 저장 경로

- 경로: `route_images/{route_id}.jpg`
- 기존 GCS 버킷 사용 (원본 이미지와 동일 버킷)
- 수정 시 동일 경로에 덮어쓰기

## 기존 테스트 스크립트와의 관계

`scripts/test_route_image.py`의 렌더링 로직을 `app/services/route_overlay.py`로 이전한다. 테스트 스크립트는 참조용으로 유지.
