from io import BytesIO
from datetime import datetime
from typing import List, Optional, Literal
from bson import ObjectId
from fastapi import APIRouter, Depends, Query, HTTPException, status
from app.models.image import Image, ImageMetadata, LocationMetadata, CameraMetadata
from app.models.user import User
from app.dependencies import get_current_user
from pydantic import BaseModel, HttpUrl, Field
import pytz
from pathlib import Path
from PIL import Image as PILImage
from PIL.ExifTags import TAGS, GPSTAGS
import base64
from beanie.odm.operators.find.logical import Or, And
from beanie.odm.operators.find.comparison import LT, GT, Eq
from app.core.gcs import generate_signed_url, extract_blob_path_from_url

from app.models import model_config

router = APIRouter(prefix="/images", tags=["images"])

# 파일 저장 경로 설정
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)


class ImageServiceView(BaseModel):
    model_config = model_config

    id: ObjectId

    url: HttpUrl
    filename: str
    user_id: ObjectId
    uploaded_at: datetime
    hold_polygon_id: Optional[ObjectId]

    gym_name: Optional[str] = Field(None, description="암장 이름")
    wall_name: Optional[str] = Field(None, description="벽 이름")
    wall_expiration_date: Optional[datetime] = Field(None, description="벽 만료 일자")


class ImageListMeta(BaseModel):
    model_config = model_config

    next_token: Optional[str] = None

class ImageListResponse(BaseModel):
    model_config = model_config

    data: List[ImageServiceView]
    meta: ImageListMeta

class ImageCountResponse(BaseModel):
    model_config = model_config
    
    total_count: int = Field(..., description="전체 이미지 수")


class ImageCountQuery(BaseModel):
    model_config = model_config
    
    include_deleted: bool = Field(
        False, 
        description="삭제된 이미지 포함 여부"
    )

def encode_cursor(sort_field: str, sort_order: str, last_id: str) -> str:
    cursor_str = f"{sort_field}:{sort_order}:{last_id}"
    return base64.b64encode(cursor_str.encode()).decode()

def decode_cursor(cursor: str) -> tuple[str, str, str]:
    decoded = base64.b64decode(cursor.encode()).decode()
    sort_field, sort_order, last_id = decoded.split(":")
    return sort_field, sort_order, last_id

@router.get("", response_model=ImageListResponse)
async def get_images(
    current_user: User = Depends(get_current_user),
    sort: str = Query("uploadedAt:desc", description="정렬 기준 (예: uploadedAt:desc)"),
    limit: int = Query(10, ge=1, le=100),
    next: Optional[str] = None
):
    # 쿼리 빌더 초기화
    query = Image.find(Image.user_id == current_user.id)
    
    # 정렬 옵션 처리
    sort_field, sort_order = sort.split(':')
    db_field = "uploaded_at" if sort_field == "uploadedAt" else sort_field
    
    # 커서 처리
    if next:
        cursor_sort_field, cursor_sort_order, last_id = decode_cursor(next)
        last_doc = await Image.get(ObjectId(last_id))
        
        if last_doc:
            cursor_value = getattr(last_doc, db_field)
            cursor_id = last_doc.id
            
            if sort_order == "desc":
                # (field < cursor_value) OR (field == cursor_value AND _id < cursor_id)
                query = query.find(
                    Or(
                        LT(getattr(Image, db_field), cursor_value),
                        And(
                            Eq(getattr(Image, db_field), cursor_value),
                            LT(Image.id, cursor_id)
                        )
                    )
                )
            else:
                # (field > cursor_value) OR (field == cursor_value AND _id > cursor_id)
                query = query.find(
                    Or(
                        GT(getattr(Image, db_field), cursor_value),
                        And(
                            Eq(getattr(Image, db_field), cursor_value),
                            GT(Image.id, cursor_id)
                        )
                    )
                )
    
    # 정렬 적용 (복합 정렬: field와 _id로 정렬)
    if sort_order == "desc":
        query = query.sort([
            (db_field, -1),
            ("_id", -1)
        ])
    else:
        query = query.sort([
            (db_field, 1),
            ("_id", 1)
        ])
    
    # 프로젝션 및 제한 적용
    query = query.project(projection_model=ImageServiceView).limit(limit + 1)
    images = await query.to_list()
    
    # 다음 페이지 토큰 생성
    has_next = len(images) > limit
    next_token = None
    
    if has_next:
        images = images[:limit]  # 마지막 항목 제거
        last_image = images[-1]
        next_token = encode_cursor(
            sort_field,
            sort_order,
            str(last_image.id)
        )
    
    # 이미지 URL을 signed URL로 변환
    for image in images:
        blob_path = extract_blob_path_from_url(image.url)
        if blob_path:
            image.url = HttpUrl(generate_signed_url(blob_path))
    
    return ImageListResponse(
        data=images,
        meta=ImageListMeta(next_token=next_token)
    )


def extract_metadata(image_bytes: bytes) -> ImageMetadata:
    try:
        with PILImage.open(BytesIO(image_bytes)) as img:
            # 기본 메타데이터 초기화
            metadata = ImageMetadata(
                width=img.width,
                height=img.height,
                tags=[],
                captured_at=None,
                location=LocationMetadata(),
                camera=CameraMetadata(),
            )

            # EXIF 데이터가 없는 경우
            if not hasattr(img, "_getexif") or img._getexif() is None:
                return metadata

            exif = {TAGS.get(key, key): value for key, value in img._getexif().items() if key in TAGS}

            # 카메라 정보 추출
            if "Make" in exif:
                metadata.camera.make = exif["Make"].strip()
            if "Model" in exif:
                metadata.camera.model = exif["Model"].strip()

            # 촬영 시간 추출
            if "DateTimeOriginal" in exif:
                try:
                    captured_at = datetime.strptime(exif["DateTimeOriginal"], "%Y:%m:%d %H:%M:%S")
                    metadata.captured_at = captured_at.replace(tzinfo=pytz.UTC)
                except ValueError:
                    pass

            # GPS 정보 추출
            if "GPSInfo" in exif:
                gps_info = {GPSTAGS.get(key, key): value for key, value in exif["GPSInfo"].items()}

                if "GPSLatitude" in gps_info and "GPSLatitudeRef" in gps_info:
                    lat = _convert_to_degrees(gps_info["GPSLatitude"])
                    if gps_info["GPSLatitudeRef"] != "N":
                        lat = -lat
                    metadata.location.latitude = lat

                if "GPSLongitude" in gps_info and "GPSLongitudeRef" in gps_info:
                    lon = _convert_to_degrees(gps_info["GPSLongitude"])
                    if gps_info["GPSLongitudeRef"] != "E":
                        lon = -lon
                    metadata.location.longitude = lon

                if "GPSAltitude" in gps_info:
                    alt = float(gps_info["GPSAltitude"])
                    metadata.location.altitude = alt

            return metadata
    except Exception as e:
        print(f"메타데이터 추출 중 오류 발생: {e}")
        return ImageMetadata(
            width=None,
            height=None,
            tags=[],
            location=LocationMetadata(),
            camera=CameraMetadata(),
        )


def _convert_to_degrees(value):
    """GPS 좌표를 도(degree) 단위로 변환"""
    d = float(value[0])
    m = float(value[1])
    s = float(value[2])
    return d + (m / 60.0) + (s / 3600.0)


@router.get("/{image_id}", response_model=ImageServiceView)
async def get_image(
    image_id: str,
    current_user: User = Depends(get_current_user)
):
    try:
        # ObjectId로 변환
        object_id = ObjectId(image_id)
    except:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="유효하지 않은 이미지 ID입니다."
        )

    # 이미지 조회
    image = await Image.find_one(
        And(
            Image.id == object_id,
            Image.user_id == current_user.id,
            Image.is_deleted == False
        )
    ).project(ImageServiceView)

    if not image:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="이미지를 찾을 수 없습니다."
        )

    # 이미지 URL을 signed URL로 변환
    blob_path = extract_blob_path_from_url(image.url)
    if blob_path:
        image.url = generate_signed_url(blob_path)
    
    return image


@router.get("/count", response_model=ImageCountResponse)
async def get_image_count(
    current_user: User = Depends(get_current_user),
    query: ImageCountQuery = Depends()
):
    # 기본 쿼리 조건
    query_conditions = [Image.user_id == current_user.id]
    
    # include_deleted가 False인 경우에만 is_deleted 조건 추가
    if not query.include_deleted:
        query_conditions.append(Image.is_deleted == False)
    
    count = await Image.find(
        And(*query_conditions)
    ).count()
    
    return ImageCountResponse(total_count=count)
