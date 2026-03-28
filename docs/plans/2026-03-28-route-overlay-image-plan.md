# Route Overlay Image 자동 생성 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route 생성/수정 시 hold_polygon 오버레이 이미지를 비동기로 자동 생성하여 GCS에 저장한다.

**Architecture:** Route 모델에 overlay 관련 필드 4개를 추가하고, `app/services/route_overlay.py`에 이미지 렌더링 로직을 분리한다. 라우터에서 Route 저장 시 overlay 플래그를 세팅하고, FastAPI BackgroundTasks로 이미지 생성을 비동기 실행한다.

**Tech Stack:** FastAPI BackgroundTasks, Pillow, GCS (google-cloud-storage), Beanie/Motor (MongoDB)

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `app/models/route.py` | Modify | overlay 필드 4개 추가 |
| `app/services/__init__.py` | Create | 빈 패키지 init |
| `app/services/route_overlay.py` | Create | 오버레이 이미지 렌더링 + GCS 업로드 + DB 업데이트 |
| `app/routers/routes.py` | Modify | create/update에서 overlay 플래그 세팅 + BackgroundTasks 연결, 응답 모델에 overlay 필드 추가 |

---

### Task 1: Route 모델에 overlay 필드 추가

**Files:**
- Modify: `services/api/app/models/route.py`

- [ ] **Step 1: Route 모델에 필드 4개 추가**

`services/api/app/models/route.py`의 `Route` 클래스에 `is_deleted` 필드 아래에 추가:

```python
overlay_image_url: Optional[HttpUrl] = Field(None, description="오버레이 이미지 URL")
overlay_processing: bool = Field(False, description="오버레이 이미지 생성 작업 중 여부")
overlay_started_at: Optional[datetime] = Field(None, description="오버레이 작업 시작 시간")
overlay_completed_at: Optional[datetime] = Field(None, description="오버레이 작업 완료 시간")
```

- [ ] **Step 2: 정적 분석으로 검증**

Run: `cd services/api && flutter analyze` → 해당 없음 (Python). 대신:
```bash
cd services/api && .venv/bin/python3 -c "from app.models.route import Route; print('OK')"
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add services/api/app/models/route.py
git commit -m "feat(api): add overlay image fields to Route model"
```

---

### Task 2: 오버레이 이미지 서비스 모듈 생성

**Files:**
- Create: `services/api/app/services/__init__.py`
- Create: `services/api/app/services/route_overlay.py`

- [ ] **Step 1: services 패키지 생성**

`services/api/app/services/__init__.py` — 빈 파일 생성.

- [ ] **Step 2: route_overlay.py 작성**

`services/api/app/services/route_overlay.py` — 테스트 스크립트(`scripts/test_route_image.py`)의 렌더링 로직을 서비스 함수로 이전:

```python
import io
import math
import logging
from datetime import datetime

import requests
from PIL import Image as PILImage, ImageDraw, ImageFont
from bson import ObjectId

from app.models.route import Route, RouteType
from app.models.hold_polygon import HoldPolygon
from app.core.gcs import bucket, generate_signed_url, extract_blob_path_from_url

logger = logging.getLogger(__name__)

# 모바일 앱(BoulderingRoutePolygonPainter + route_viewer._getHoldColor)과 동일한 색상
NEON_LIME = (188, 244, 33)
NEON_LIME_HIGHLIGHT = (*NEON_LIME, 77)  # 0.3 opacity
HOLD_FILL_COLORS = {
    "starting": (76, 175, 80, 77),      # Colors.green.withOpacity(0.3)
    "finishing": (244, 67, 54, 77),      # Colors.red.withOpacity(0.3)
}
DEFAULT_FILL_COLOR = (33, 150, 243, 77)  # Colors.blue.withOpacity(0.3)
STROKE_COLOR = (*NEON_LIME, 255)


def _select_edges(edges, start_index, target_length, k=1):
    """BoulderingRouteHoldPropertyPainter.selectEdges() 재현."""
    selected = []
    total = len(edges)
    if total == 0:
        return selected
    current = start_index % total
    selected.append(edges[current])

    while len(selected) < k:
        cumulative = 0.0
        current = (current + 1) % total
        while cumulative < target_length:
            cumulative += edges[current]["length"]
            current = (current + 1) % total
        sel_idx = (current - 1 + total) % total
        selected.append(edges[sel_idx])
        if edges[sel_idx]["length"] >= target_length and len(selected) < k:
            current = (current + 1) % total
            selected.append(edges[current])
        if len(selected) >= k:
            break

    return selected[:k]


def _draw_marking_tapes(draw, points, marking_count, scale):
    """검은색 테이프 마킹 그리기 (markingCount > 0인 홀드)."""
    if marking_count is None or marking_count <= 0:
        return

    edges = []
    for i in range(len(points)):
        p1 = points[i]
        p2 = points[(i + 1) % len(points)]
        dx = p2[0] - p1[0]
        dy = p2[1] - p1[1]
        length = math.sqrt(dx * dx + dy * dy)
        if length > 0:
            mid = [(p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2]
            normal = [-dy / length, dx / length]
            edges.append({"midPoint": mid, "normal": normal, "length": length})

    if not edges:
        return

    selected = _select_edges(edges, round(len(edges) / 2), 10 * scale, marking_count)
    tape_width = 4.0 * scale
    tape_length = 25.0 * scale

    for edge in selected:
        mid = edge["midPoint"]
        n = edge["normal"]
        perp = [-n[1], n[0]]
        p1 = (mid[0] - (tape_width / 2) * perp[0], mid[1] - (tape_width / 2) * perp[1])
        p2 = (mid[0] + (tape_width / 2) * perp[0], mid[1] + (tape_width / 2) * perp[1])
        p3 = (p2[0] + tape_length * n[0], p2[1] + tape_length * n[1])
        p4 = (p1[0] + tape_length * n[0], p1[1] + tape_length * n[1])
        draw.polygon([p1, p2, p3, p4], fill=(0, 0, 0, 255))


def _draw_top_mark(draw, points, scale):
    """finishing 홀드에 TOP 아이콘 그리기."""
    if len(points) < 2:
        return

    middle_idx = len(points) // 2
    p1 = points[middle_idx]
    p2 = points[(middle_idx + 1) % len(points)]

    center_x = (p1[0] + p2[0]) / 2
    center_y = (p1[1] + p2[1]) / 2

    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    length = math.sqrt(dx * dx + dy * dy)
    if length == 0:
        return

    normal_scale = 6.0 * scale
    normal_x = -dy / length * normal_scale
    normal_y = dx / length * normal_scale

    svg_size = 15.0 * scale
    draw_x = center_x + normal_x
    draw_y = center_y + normal_y

    circle_r = svg_size / 2
    circle_stroke = max(1, round(1.0 * scale))

    bbox = [
        draw_x - circle_r, draw_y - circle_r,
        draw_x + circle_r, draw_y + circle_r,
    ]
    draw.ellipse(bbox, fill=(255, 255, 255, 255), outline=(0, 0, 0, 255), width=circle_stroke)

    max_text_width = circle_r * 2 * 0.6
    font_size = max(8, round(svg_size * 0.5))
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", font_size)
    except (OSError, IOError):
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
        except (OSError, IOError):
            font = ImageFont.load_default()

    for _ in range(10):
        text_bbox = draw.textbbox((0, 0), "TOP", font=font)
        text_w = text_bbox[2] - text_bbox[0]
        if text_w <= max_text_width or font_size <= 8:
            break
        font_size -= 1
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", font_size)
        except (OSError, IOError):
            try:
                font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
            except (OSError, IOError):
                font = ImageFont.load_default()
                break

    text_bbox = draw.textbbox((0, 0), "TOP", font=font)
    text_w = text_bbox[2] - text_bbox[0]
    text_h = text_bbox[3] - text_bbox[1]
    text_x = draw_x - text_w / 2
    text_y = draw_y - text_h / 2 - text_bbox[1]
    draw.text((text_x, text_y), "TOP", fill=(0, 0, 0, 255), font=font)


def _render_overlay(img, route_type, holds_by_polygon_id, route_polygons):
    """Pillow로 3개 레이어를 합성하여 오버레이 이미지를 생성한다."""
    scale = img.size[0] / 390.0
    stroke_width = max(2, round(2.0 * scale))

    # Layer 1: neonLime highlight
    highlight_layer = PILImage.new("RGBA", img.size, (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight_layer)
    for polygon in route_polygons:
        point_tuples = [(p[0], p[1]) for p in polygon["points"]]
        if len(point_tuples) >= 3:
            highlight_draw.polygon(point_tuples, fill=NEON_LIME_HIGHLIGHT)
    result = PILImage.alpha_composite(img, highlight_layer)

    # Layer 2: 타입별 fill color
    fill_layer = PILImage.new("RGBA", result.size, (0, 0, 0, 0))
    fill_draw = ImageDraw.Draw(fill_layer)
    for polygon in route_polygons:
        polygon_id = polygon["polygonId"]
        hold = holds_by_polygon_id[polygon_id]
        hold_type = hold.get("type", "normal") if route_type == "bouldering" else "normal"
        fill_color = HOLD_FILL_COLORS.get(hold_type, DEFAULT_FILL_COLOR)
        point_tuples = [(p[0], p[1]) for p in polygon["points"]]
        if len(point_tuples) >= 3:
            fill_draw.polygon(point_tuples, fill=fill_color)
    result = PILImage.alpha_composite(result, fill_layer)

    # Layer 3: 테두리 + 홀드 속성
    stroke_layer = PILImage.new("RGBA", result.size, (0, 0, 0, 0))
    stroke_draw = ImageDraw.Draw(stroke_layer)
    for polygon in route_polygons:
        point_tuples = [(p[0], p[1]) for p in polygon["points"]]
        if len(point_tuples) >= 3:
            for i in range(len(point_tuples)):
                p1_pt = point_tuples[i]
                p2_pt = point_tuples[(i + 1) % len(point_tuples)]
                stroke_draw.line([p1_pt, p2_pt], fill=STROKE_COLOR, width=stroke_width)

    for polygon in route_polygons:
        polygon_id = polygon["polygonId"]
        points = [(p[0], p[1]) for p in polygon["points"]]
        hold = holds_by_polygon_id[polygon_id]
        hold_type = hold.get("type", "normal") if route_type == "bouldering" else "normal"
        if hold_type == "finishing":
            _draw_top_mark(stroke_draw, points, scale)
        else:
            _draw_marking_tapes(stroke_draw, points, hold.get("markingCount"), scale)

    result = PILImage.alpha_composite(result, stroke_layer)
    return result.convert("RGB")


async def generate_route_overlay(route: Route):
    """Route의 오버레이 이미지를 생성하여 GCS에 업로드하고 Route를 업데이트한다."""
    route_id = route.id
    try:
        # 1. HoldPolygon 조회
        hold_polygon_doc = await HoldPolygon.find_one(HoldPolygon.image_id == route.image_id)
        if not hold_polygon_doc:
            logger.warning(f"No hold polygon found for route {route_id}")
            return

        # 2. 홀드 목록에서 polygon_id 매핑
        holds_by_polygon_id = {}
        holds = route.bouldering_holds if route.type == RouteType.BOULDERING else route.endurance_holds
        if holds:
            for hold in holds:
                holds_by_polygon_id[hold.polygon_id] = hold.model_dump()

        # 3. 루트에 포함된 폴리곤만 필터링
        route_polygons = []
        for polygon in hold_polygon_doc.polygons:
            if polygon.polygon_id in holds_by_polygon_id:
                polygon_dict = polygon.model_dump()
                # points를 list of list로 변환 (튜플 → 리스트)
                polygon_dict["points"] = [list(p) for p in polygon_dict["points"]]
                route_polygons.append(polygon_dict)

        if not route_polygons:
            logger.warning(f"No matching polygons for route {route_id}")
            return

        # 4. 원본 이미지 다운로드
        blob_path = extract_blob_path_from_url(route.image_url)
        if not blob_path:
            logger.error(f"Cannot extract blob path from {route.image_url}")
            return
        signed_url = generate_signed_url(blob_path)
        resp = requests.get(signed_url)
        resp.raise_for_status()
        img = PILImage.open(io.BytesIO(resp.content)).convert("RGBA")

        # 5. 렌더링
        result = _render_overlay(img, route.type.value, holds_by_polygon_id, route_polygons)

        # 6. GCS 업로드
        output_buffer = io.BytesIO()
        result.save(output_buffer, "JPEG", quality=90)
        output_buffer.seek(0)

        gcs_path = f"route_images/{route_id}.jpg"
        blob = bucket.blob(gcs_path)
        blob.upload_from_file(output_buffer, content_type="image/jpeg")

        from app.core.gcs import get_base_url
        overlay_url = f"{get_base_url()}/{gcs_path}"

        # 7. Route 부분 업데이트 (overlay 필드만)
        await Route.find_one(Route.id == route_id).update(
            {"$set": {
                "overlayImageUrl": overlay_url,
                "overlayProcessing": False,
                "overlayCompletedAt": datetime.utcnow(),
            }}
        )
        logger.info(f"Overlay image generated for route {route_id}")

    except Exception as e:
        logger.error(f"Failed to generate overlay for route {route_id}: {e}")
        # 실패 시에도 processing 플래그 리셋
        try:
            await Route.find_one(Route.id == route_id).update(
                {"$set": {"overlayProcessing": False}}
            )
        except Exception:
            logger.error(f"Failed to reset overlay_processing for route {route_id}")
```

- [ ] **Step 3: import 검증**

```bash
cd services/api && .venv/bin/python3 -c "from app.services.route_overlay import generate_route_overlay; print('OK')"
```
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add services/api/app/services/
git commit -m "feat(api): add route overlay image generation service"
```

---

### Task 3: 라우터 응답 모델에 overlay 필드 추가

**Files:**
- Modify: `services/api/app/routers/routes.py`

- [ ] **Step 1: RouteServiceView에 overlay 필드 추가**

`services/api/app/routers/routes.py`의 `RouteServiceView` 클래스(121행 부근)에 추가:

```python
class RouteServiceView(BaseModel):
    model_config = model_config

    id: ObjectId
    type: RouteType
    title: Optional[str] = Field(None, description="루트 제목")
    description: Optional[str] = Field(None, description="루트 설명")
    visibility: Visibility = Field(Visibility.PUBLIC, description="루트 공개 여부")
    grade_type: str
    grade: str
    grade_color: Optional[str]
    hold_polygon_id: ObjectId
    image_id: ObjectId
    user_id: ObjectId
    image_url: str

    overlay_image_url: Optional[str] = Field(None, description="오버레이 이미지 URL")
    overlay_processing: bool = Field(False, description="오버레이 이미지 생성 작업 중 여부")

    created_at: datetime
    updated_at: Optional[datetime]
    deleted_at: Optional[datetime]

    gym_name: Optional[str] = Field(None, description="암장 이름")
    wall_name: Optional[str] = Field(None, description="벽 이름")
    wall_expiration_date: Optional[datetime] = Field(None, description="벽 만료 일자")
```

- [ ] **Step 2: RouteDetailView는 Route를 상속하므로 자동으로 포함됨 확인**

`RouteDetailView`는 `Route`를 상속하므로 Route 모델에 추가한 overlay 필드가 자동으로 응답에 포함된다. 별도 수정 불필요.

- [ ] **Step 3: get_routes의 signed URL 변환 로직에 overlay_image_url 추가**

`services/api/app/routers/routes.py`의 `get_routes` 함수(259행 부근)에서 기존 `image_url` signed URL 변환 루프에 overlay도 추가:

기존:
```python
    for route in routes:
        blob_path = extract_blob_path_from_url(route.image_url)
        if blob_path:
            route.image_url = HttpUrl(generate_signed_url(blob_path))
```

변경:
```python
    for route in routes:
        blob_path = extract_blob_path_from_url(route.image_url)
        if blob_path:
            route.image_url = generate_signed_url(blob_path)
        if route.overlay_image_url:
            overlay_blob_path = extract_blob_path_from_url(route.overlay_image_url)
            if overlay_blob_path:
                route.overlay_image_url = generate_signed_url(overlay_blob_path)
```

- [ ] **Step 4: get_route (단건 조회)에도 overlay signed URL 변환 추가**

`services/api/app/routers/routes.py`의 `get_route` 함수(316행 부근)에서 기존 signed URL 변환 후에 추가:

기존:
```python
    blob_path = extract_blob_path_from_url(route.image_url)
    if blob_path:
        route.image_url = HttpUrl(generate_signed_url(blob_path))

    return await _enrich_route_with_hold_polygon_data(route)
```

변경:
```python
    blob_path = extract_blob_path_from_url(route.image_url)
    if blob_path:
        route.image_url = HttpUrl(generate_signed_url(blob_path))
    if route.overlay_image_url:
        overlay_blob_path = extract_blob_path_from_url(route.overlay_image_url)
        if overlay_blob_path:
            route.overlay_image_url = HttpUrl(generate_signed_url(overlay_blob_path))

    return await _enrich_route_with_hold_polygon_data(route)
```

- [ ] **Step 5: import 검증**

```bash
cd services/api && .venv/bin/python3 -c "from app.routers.routes import router; print('OK')"
```
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add services/api/app/routers/routes.py
git commit -m "feat(api): add overlay fields to route response models"
```

---

### Task 4: create_route에 BackgroundTasks 연결

**Files:**
- Modify: `services/api/app/routers/routes.py`

- [ ] **Step 1: import 추가**

`services/api/app/routers/routes.py` 상단에 import 추가:

```python
from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks
```

그리고 서비스 import 추가:

```python
from app.services.route_overlay import generate_route_overlay
```

- [ ] **Step 2: create_route 함수 시그니처에 BackgroundTasks 추가, Route 생성 시 overlay 플래그 세팅**

`services/api/app/routers/routes.py`의 `create_route` 함수를 수정:

기존:
```python
@router.post("", status_code=status.HTTP_201_CREATED, response_model=RouteDetailView)
async def create_route(request: CreateRouteRequest, current_user: User = Depends(get_current_user)):
```

변경:
```python
@router.post("", status_code=status.HTTP_201_CREATED, response_model=RouteDetailView)
async def create_route(request: CreateRouteRequest, background_tasks: BackgroundTasks, current_user: User = Depends(get_current_user)):
```

Route 도큐먼트 생성 부분(95행 부근)에 overlay 필드 추가:

기존:
```python
    route = Route(
        type=request.type,
        title=request.title,
        description=request.description,
        grade_type=request.grade_type,
        grade=request.grade,
        grade_score=request.grade_score,
        grade_color=request.grade_color,
        visibility=request.visibility,
        hold_polygon_id=hold_polygon.id,
        image_id=image.id,
        user_id=current_user.id,
        image_url=image.url,
        bouldering_holds=bouldering_holds if request.type == RouteType.BOULDERING else None,
        endurance_holds=endurance_holds if request.type == RouteType.ENDURANCE else None,
    )
```

변경:
```python
    route = Route(
        type=request.type,
        title=request.title,
        description=request.description,
        grade_type=request.grade_type,
        grade=request.grade,
        grade_score=request.grade_score,
        grade_color=request.grade_color,
        visibility=request.visibility,
        hold_polygon_id=hold_polygon.id,
        image_id=image.id,
        user_id=current_user.id,
        image_url=image.url,
        bouldering_holds=bouldering_holds if request.type == RouteType.BOULDERING else None,
        endurance_holds=endurance_holds if request.type == RouteType.ENDURANCE else None,
        overlay_processing=True,
        overlay_started_at=datetime.utcnow(),
    )
```

`return` 직전에 BackgroundTasks 등록 추가:

기존:
```python
    return await _enrich_route_with_hold_polygon_data(created_route)
```

변경:
```python
    background_tasks.add_task(generate_route_overlay, created_route)
    return await _enrich_route_with_hold_polygon_data(created_route)
```

- [ ] **Step 3: import 검증**

```bash
cd services/api && .venv/bin/python3 -c "from app.routers.routes import router; print('OK')"
```
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add services/api/app/routers/routes.py
git commit -m "feat(api): trigger overlay generation on route creation"
```

---

### Task 5: update_route에 홀드 변경 감지 + BackgroundTasks 연결

**Files:**
- Modify: `services/api/app/routers/routes.py`

- [ ] **Step 1: update_route에서 홀드 변경 감지 및 overlay 플래그 세팅**

`services/api/app/routers/routes.py`의 `update_route` 함수에서, 기존 `if diff:` 블록 내부를 수정:

기존:
```python
    if diff:  # 변경사항이 있는 경우
        updated_route.updated_at = datetime.utcnow()
        await updated_route.save()
        return await _enrich_route_with_hold_polygon_data(updated_route)
```

변경:
```python
    if diff:  # 변경사항이 있는 경우
        # 홀드 관련 필드 변경 여부 확인
        holds_changed = any(
            "bouldering_holds" in path or "endurance_holds" in path
            for path in str(diff).split("root")
        )
        if holds_changed:
            updated_route.overlay_processing = True
            updated_route.overlay_started_at = datetime.utcnow()

        updated_route.updated_at = datetime.utcnow()
        await updated_route.save()

        if holds_changed:
            background_tasks.add_task(generate_route_overlay, updated_route)

        return await _enrich_route_with_hold_polygon_data(updated_route)
```

- [ ] **Step 2: update_route 함수 시그니처에 BackgroundTasks 추가**

기존:
```python
@router.patch("/{route_id}", response_model=RouteDetailView)
async def update_route(route_id: str, request: UpdateRouteRequest, current_user: User = Depends(get_current_user)):
```

변경:
```python
@router.patch("/{route_id}", response_model=RouteDetailView)
async def update_route(route_id: str, request: UpdateRouteRequest, background_tasks: BackgroundTasks, current_user: User = Depends(get_current_user)):
```

- [ ] **Step 3: 홀드 변경 감지를 DeepDiff의 affected_paths로 정확하게 처리**

Step 1의 `holds_changed` 감지를 더 정확하게 수정. DeepDiff 결과에서 변경된 경로를 직접 확인:

```python
        holds_changed = False
        for change_type in diff:
            for path in diff[change_type]:
                if "bouldering_holds" in path or "endurance_holds" in path:
                    holds_changed = True
                    break
            if holds_changed:
                break
```

- [ ] **Step 4: import 검증**

```bash
cd services/api && .venv/bin/python3 -c "from app.routers.routes import router; print('OK')"
```
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/routes.py
git commit -m "feat(api): trigger overlay regeneration on hold changes"
```

---

### Task 6: create_route의 signed URL 변환에 overlay 추가

**Files:**
- Modify: `services/api/app/routers/routes.py`

- [ ] **Step 1: create_route에서 응답 반환 전 overlay signed URL 변환 추가**

`create_route` 함수에서 기존 image_url signed URL 변환 후에 추가:

기존:
```python
    blob_path = extract_blob_path_from_url(created_route.image_url)
    if blob_path:
        created_route.image_url = HttpUrl(generate_signed_url(blob_path))
```

변경:
```python
    blob_path = extract_blob_path_from_url(created_route.image_url)
    if blob_path:
        created_route.image_url = HttpUrl(generate_signed_url(blob_path))
    if created_route.overlay_image_url:
        overlay_blob_path = extract_blob_path_from_url(created_route.overlay_image_url)
        if overlay_blob_path:
            created_route.overlay_image_url = HttpUrl(generate_signed_url(overlay_blob_path))
```

참고: 생성 직후에는 `overlay_image_url`이 None이므로 실질적으로 실행되지 않지만, 코드 일관성을 위해 추가.

- [ ] **Step 2: update_route의 변경 없는 경우 응답에도 overlay signed URL 변환 추가**

`update_route` 함수의 변경 없는 경우 응답 부분:

기존:
```python
    blob_path = extract_blob_path_from_url(route.image_url)
    if blob_path:
        route.image_url = HttpUrl(generate_signed_url(blob_path))

    # 변경사항이 없는 경우 기존 데이터 반환
    return await _enrich_route_with_hold_polygon_data(route)
```

변경:
```python
    blob_path = extract_blob_path_from_url(route.image_url)
    if blob_path:
        route.image_url = HttpUrl(generate_signed_url(blob_path))
    if route.overlay_image_url:
        overlay_blob_path = extract_blob_path_from_url(route.overlay_image_url)
        if overlay_blob_path:
            route.overlay_image_url = HttpUrl(generate_signed_url(overlay_blob_path))

    # 변경사항이 없는 경우 기존 데이터 반환
    return await _enrich_route_with_hold_polygon_data(route)
```

- [ ] **Step 3: update_route의 변경 있는 경우 응답에도 overlay signed URL 변환 추가**

`update_route` 함수의 `if diff:` 블록 내 `return` 직전에 추가:

```python
        if updated_route.overlay_image_url:
            overlay_blob_path = extract_blob_path_from_url(updated_route.overlay_image_url)
            if overlay_blob_path:
                updated_route.overlay_image_url = HttpUrl(generate_signed_url(overlay_blob_path))

        return await _enrich_route_with_hold_polygon_data(updated_route)
```

- [ ] **Step 4: Commit**

```bash
git add services/api/app/routers/routes.py
git commit -m "feat(api): add overlay signed URL conversion in route responses"
```

---

### Task 7: 통합 검증

- [ ] **Step 1: 전체 import 체인 검증**

```bash
cd services/api && .venv/bin/python3 -c "
from app.models.route import Route
from app.services.route_overlay import generate_route_overlay
from app.routers.routes import router
print('All imports OK')
print('Route overlay fields:', hasattr(Route, 'overlay_image_url'), hasattr(Route, 'overlay_processing'))
"
```
Expected: `All imports OK` + `True True`

- [ ] **Step 2: FastAPI app 시작 검증**

```bash
cd services/api && timeout 5 .venv/bin/python3 -c "
from app.main import app
print('App created OK')
print('Routes:', [r.path for r in app.routes if hasattr(r, 'path')])
" 2>&1 || true
```

앱 초기화가 에러 없이 진행되는지 확인. (DB 연결은 lifespan에서 이뤄지므로 타임아웃 OK)

- [ ] **Step 3: Commit (최종)**

```bash
git add -A
git commit -m "feat(api): route overlay image auto-generation on create/update"
```
