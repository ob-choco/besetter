import os
from fastapi import APIRouter, File, UploadFile
from fastapi import status
import io
import numpy as np
import cv2
from PIL import Image as PILImage

from app.models.hold_polygon import HoldPolygon, HoldPolygonData

from detectron2.engine import DefaultPredictor
from detectron2.config import get_cfg


current_dir = os.path.dirname(os.path.abspath(__file__))

cfg = get_cfg()
cfg.merge_from_file(os.path.join(current_dir, "../../config.yml"))
cfg.MODEL.ROI_HEADS.SCORE_THRESH_TEST = 0.6
cfg.MODEL.WEIGHTS = os.path.join(current_dir, "../../model_final.pth")

predictor = DefaultPredictor(cfg)


router = APIRouter(prefix="/hold-polygons", tags=["hold-polygons"])


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_hold_polygon(image: UploadFile = File(...)):
    image_bytes = await image.read()  # 이미 읽은 파일 내용 재사용
    pil_image = PILImage.open(io.BytesIO(image_bytes))
    np_image = np.array(pil_image)

    outputs = predictor(np_image)
    instances = outputs["instances"].to("cpu")

    bit_masks = instances.pred_masks
    classes = instances.pred_classes
    scores = instances.scores

    # 4. HoldPolygon 데이터 생성
    polygons = []
    for i, bit_mask in enumerate(bit_masks):
        mask = bit_mask.numpy().astype(np.uint8)
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        for contour in contours:
            # if len(contour) >= 3:
            #     points = [
            #         (int(p[0]), int(p[1])) for p in np.squeeze(contour, axis=1).tolist()
            #     ]
            epsilon = 0.002 * cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, epsilon, True)
            if len(approx) >= 3:
                approximated_points = [(int(p[0][0]), int(p[0][1])) for p in approx]

        polygon_data = HoldPolygonData(
            polygon_id=i,
            points=approximated_points or [],
            type="hold" if classes[i] == 0 else "volume",
            score=float(scores[i].item()),
        )
        polygons.append(polygon_data)

    # 5. HoldPolygon 모델에 저장
    hold_polygon = HoldPolygon(polygons=polygons)

    return hold_polygon
