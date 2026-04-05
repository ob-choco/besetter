"""
Route에 hold_polygon을 입힌 이미지를 생성하는 테스트 스크립트.

사용법:
  cd services/api && ../.venv/bin/python3 ../../scripts/test_route_image.py
  또는
  PYTHONPATH=services/api python3 scripts/test_route_image.py
"""

import asyncio
import sys
import os
import io
import math
import requests
from PIL import Image, ImageDraw, ImageFont

# services/api를 모듈 경로에 추가
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "services", "api"))

from motor.motor_asyncio import AsyncIOMotorClient
from app.core.config import get
from app.core.gcs import generate_signed_url, extract_blob_path_from_url

# 모바일 앱(BoulderingRoutePolygonPainter + route_viewer._getHoldColor)과 동일한 색상
# neonLimeColor = Color.fromRGBO(188, 244, 33, 1.0)
NEON_LIME = (188, 244, 33)
NEON_LIME_HIGHLIGHT = (*NEON_LIME, 77)  # 0.3 opacity (코드 동일)

# _getHoldColor: starting=green 0.3, finishing=red 0.3, 나머지=blue 0.3
HOLD_FILL_COLORS = {
    "starting": (76, 175, 80, 77),      # Colors.green.withOpacity(0.3)
    "finishing": (244, 67, 54, 77),      # Colors.red.withOpacity(0.3)
}
DEFAULT_FILL_COLOR = (33, 150, 243, 77)  # Colors.blue.withOpacity(0.3)

# 테두리: isHighlighted일 때 neonLimeColor solid
STROKE_COLOR = (*NEON_LIME, 255)


def select_edges(edges, start_index, target_length, k=1):
    """BoulderingRouteHoldPropertyPainter.selectEdges()와 동일한 로직."""
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


def draw_marking_tapes(draw, points, marking_count, scale):
    """BoulderingRouteHoldPropertyPainter — markingCount > 0일 때 검은색 테이프 그리기."""
    if marking_count is None or marking_count <= 0:
        return

    # 각 변의 중점, 법선, 길이 계산
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

    # 모바일: selectEdges(edges, (edges.length / 2).round(), 10, markingCount)
    selected = select_edges(edges, round(len(edges) / 2), 10 * scale, marking_count)

    # 모바일: tapeWidth=4.0, tapeLength=25.0 (화면 좌표)
    tape_width = 4.0 * scale
    tape_length = 25.0 * scale

    for edge in selected:
        mid = edge["midPoint"]
        n = edge["normal"]
        # 법선에 수직인 방향 (변 방향)
        perp = [-n[1], n[0]]

        # 테이프의 4꼭짓점 계산
        p1 = (mid[0] - (tape_width / 2) * perp[0], mid[1] - (tape_width / 2) * perp[1])
        p2 = (mid[0] + (tape_width / 2) * perp[0], mid[1] + (tape_width / 2) * perp[1])
        p3 = (p2[0] + tape_length * n[0], p2[1] + tape_length * n[1])
        p4 = (p1[0] + tape_length * n[0], p1[1] + tape_length * n[1])

        draw.polygon([p1, p2, p3, p4], fill=(0, 0, 0, 255))


def draw_top_mark(draw, points, scale):
    """BoulderingRouteHoldPropertyPainter — finishing 홀드에 TOP 아이콘 그리기."""
    if len(points) < 2:
        return

    # 모바일: middleIndex = points.length ~/ 2
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

    # 모바일: scale=6.0, svgSize=15.0 (화면 좌표)
    normal_scale = 6.0 * scale
    normal_x = -dy / length * normal_scale
    normal_y = dx / length * normal_scale

    svg_size = 15.0 * scale
    draw_x = center_x + normal_x
    draw_y = center_y + normal_y

    # TOP 마크: 흰색 원 + 검은색 테두리 + "TOP" 텍스트
    circle_r = svg_size / 2
    circle_stroke = max(1, round(1.0 * scale))

    # 원 그리기
    bbox = [
        draw_x - circle_r, draw_y - circle_r,
        draw_x + circle_r, draw_y + circle_r,
    ]
    draw.ellipse(bbox, fill=(255, 255, 255, 255), outline=(0, 0, 0, 255), width=circle_stroke)

    # "TOP" 텍스트 — 원 안에 맞도록 폰트 크기를 원 지름 기준으로 조정
    # 원 내접 사각형 너비 = 지름 * 0.707, 여유를 두고 0.6배
    max_text_width = circle_r * 2 * 0.6
    font_size = max(8, round(svg_size * 0.5))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
    except (OSError, IOError):
        font = ImageFont.load_default()

    # 폰트 크기를 줄여가며 원 안에 맞추기
    for _ in range(10):
        text_bbox = draw.textbbox((0, 0), "TOP", font=font)
        text_w = text_bbox[2] - text_bbox[0]
        if text_w <= max_text_width or font_size <= 8:
            break
        font_size -= 1
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


def draw_order_marker(draw, points, orders, scale):
    """endurance 홀드에 순서 번호 마커 그리기."""
    if not points or not orders:
        return

    center_x = sum(p[0] for p in points) / len(points)
    center_y = sum(p[1] for p in points) / len(points)

    circle_size = 18.0 * scale
    circle_r = circle_size / 2
    border_width = max(1, round(2.0 * scale))

    font_size = max(8, round(10.0 * scale))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
    except (OSError, IOError):
        font = ImageFont.load_default()

    spacing = circle_size * 0.7
    total_width = circle_size + (len(orders) - 1) * spacing
    start_x = center_x - total_width / 2 + circle_r

    for i, order in enumerate(orders):
        cx = start_x + i * spacing
        cy = center_y

        bbox = [cx - circle_r, cy - circle_r, cx + circle_r, cy + circle_r]
        draw.ellipse(bbox, fill=(255, 255, 255, 204), outline=(244, 67, 54, 255), width=border_width)

        text = str(order)
        text_bbox = draw.textbbox((0, 0), text, font=font)
        text_w = text_bbox[2] - text_bbox[0]
        text_h = text_bbox[3] - text_bbox[1]
        text_x = cx - text_w / 2
        text_y = cy - text_h / 2 - text_bbox[1]
        draw.text((text_x, text_y), text, fill=(0, 0, 0, 255), font=font)


async def main():
    # MongoDB 연결
    mongo_url = get("mongodb.url")
    mongo_db_name = get("mongodb.name")
    client = AsyncIOMotorClient(mongo_url, tz_aware=True)
    db = client.get_database(mongo_db_name)

    # 1. Route 하나 조회 (삭제되지 않은 endurance 타입)
    route = await db.routes.find_one({"isDeleted": {"$ne": True}, "type": "endurance"})
    if not route:
        print("No route found")
        return

    print(f"Route ID: {route['_id']}")
    print(f"Type: {route['type']}")
    print(f"Title: {route.get('title', '(no title)')}")
    print(f"Grade: {route.get('grade', '?')}")
    print(f"Image ID: {route['imageId']}")

    # 2. 루트에 연결된 홀드 정보 수집
    holds_by_polygon_id = {}
    if route["type"] == "bouldering" and route.get("boulderingHolds"):
        for hold in route["boulderingHolds"]:
            holds_by_polygon_id[hold["polygonId"]] = hold
    elif route["type"] == "endurance" and route.get("enduranceHolds"):
        for hold in route["enduranceHolds"]:
            holds_by_polygon_id[hold["polygonId"]] = hold

    print(f"Holds count: {len(holds_by_polygon_id)}")

    # 3. HoldPolygon 조회
    hold_polygon = await db.holdPolygons.find_one({"imageId": route["imageId"]})
    if not hold_polygon:
        print("No hold polygon found for this route's image")
        return

    # 루트에 포함된 폴리곤만 필터링
    route_polygons = []
    for polygon in hold_polygon.get("polygons", []):
        if polygon["polygonId"] in holds_by_polygon_id:
            route_polygons.append(polygon)

    print(f"Matched polygons: {len(route_polygons)}")

    # 4. 이미지 다운로드
    image_url_str = str(route["imageUrl"])
    blob_path = extract_blob_path_from_url(image_url_str)
    if blob_path:
        signed_url = generate_signed_url(blob_path)
    else:
        signed_url = image_url_str

    print(f"Downloading image...")
    resp = requests.get(signed_url)
    resp.raise_for_status()
    img = Image.open(io.BytesIO(resp.content)).convert("RGBA")
    print(f"Image size: {img.size}")

    # 화면 좌표 → 이미지 좌표 변환 비율
    # 모바일: containerSize.width = screenWidth ≈ 390
    scale = img.size[0] / 390.0

    # 5. endurance 순서 맵 생성
    hold_order_map = None
    route_type = route["type"]
    if route_type == "endurance" and route.get("enduranceHolds"):
        hold_order_map = {}
        for i, hold in enumerate(route["enduranceHolds"]):
            order = i + 1
            pid = hold["polygonId"]
            if pid in hold_order_map:
                hold_order_map[pid].append(order)
            else:
                hold_order_map[pid] = [order]

    # 6. 폴리곤 오버레이 그리기 (서비스 코드의 _render_overlay와 동일 로직)
    stroke_width = max(2, round(2.0 * scale))

    # Layer 1: neonLime highlight 채우기
    highlight_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight_layer)
    for polygon in route_polygons:
        point_tuples = [(p[0], p[1]) for p in polygon["points"]]
        if len(point_tuples) >= 3:
            highlight_draw.polygon(point_tuples, fill=NEON_LIME_HIGHLIGHT)
    result = Image.alpha_composite(img, highlight_layer)

    # Layer 2: 타입별 fillColor 채우기 (bouldering만)
    if route_type == "bouldering":
        fill_layer = Image.new("RGBA", result.size, (0, 0, 0, 0))
        fill_draw = ImageDraw.Draw(fill_layer)
        for polygon in route_polygons:
            polygon_id = polygon["polygonId"]
            hold = holds_by_polygon_id[polygon_id]
            hold_type = hold.get("type", "normal")
            fill_color = HOLD_FILL_COLORS.get(hold_type, DEFAULT_FILL_COLOR)
            point_tuples = [(p[0], p[1]) for p in polygon["points"]]
            if len(point_tuples) >= 3:
                fill_draw.polygon(point_tuples, fill=fill_color)
        result = Image.alpha_composite(result, fill_layer)

    # Layer 3: 테두리 + 홀드 속성
    stroke_layer = Image.new("RGBA", result.size, (0, 0, 0, 0))
    stroke_draw = ImageDraw.Draw(stroke_layer)
    for polygon in route_polygons:
        point_tuples = [(p[0], p[1]) for p in polygon["points"]]
        if len(point_tuples) >= 3:
            for i in range(len(point_tuples)):
                p1 = point_tuples[i]
                p2 = point_tuples[(i + 1) % len(point_tuples)]
                stroke_draw.line([p1, p2], fill=STROKE_COLOR, width=stroke_width)

    if route_type == "bouldering":
        for polygon in route_polygons:
            polygon_id = polygon["polygonId"]
            points = [(p[0], p[1]) for p in polygon["points"]]
            hold = holds_by_polygon_id[polygon_id]
            hold_type = hold.get("type", "normal")
            if hold_type == "finishing":
                draw_top_mark(stroke_draw, points, scale)
            else:
                draw_marking_tapes(stroke_draw, points, hold.get("markingCount"), scale)
    elif route_type == "endurance" and hold_order_map:
        for polygon in route_polygons:
            polygon_id = polygon["polygonId"]
            points = [(p[0], p[1]) for p in polygon["points"]]
            orders = hold_order_map.get(polygon_id)
            if orders:
                draw_order_marker(stroke_draw, points, orders, scale)

    result = Image.alpha_composite(result, stroke_layer)
    result = result.convert("RGB")

    # 7. 저장
    output_path = os.path.join(os.path.dirname(__file__), "test_route_output.jpg")
    result.save(output_path, "JPEG", quality=90)
    print(f"\nSaved to: {output_path}")

    client.close()


if __name__ == "__main__":
    asyncio.run(main())
