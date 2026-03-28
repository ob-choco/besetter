import io
import math
import logging
from datetime import datetime

import requests
from PIL import Image as PILImage, ImageDraw, ImageFont
from bson import ObjectId

from app.models.route import Route, RouteType
from app.models.hold_polygon import HoldPolygon
from app.core.gcs import bucket, generate_signed_url, extract_blob_path_from_url, get_base_url

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


def _load_font(font_size):
    """플랫폼에 맞는 폰트를 로드한다."""
    for path in [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]:
        try:
            return ImageFont.truetype(path, font_size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()


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
    font = _load_font(font_size)

    for _ in range(10):
        text_bbox = draw.textbbox((0, 0), "TOP", font=font)
        text_w = text_bbox[2] - text_bbox[0]
        if text_w <= max_text_width or font_size <= 8:
            break
        font_size -= 1
        font = _load_font(font_size)

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
        try:
            await Route.find_one(Route.id == route_id).update(
                {"$set": {"overlayProcessing": False}}
            )
        except Exception:
            logger.error(f"Failed to reset overlay_processing for route {route_id}")
