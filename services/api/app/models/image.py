from beanie import Document
from typing import Optional, List
from beanie.odm.fields import PydanticObjectId
from pydantic import BaseModel, HttpUrl, Field
from datetime import datetime
from pymongo import IndexModel, ASCENDING

from . import model_config


# 정의: 사진의 위치 정보를 담는 LocationMetadata
class LocationMetadata(BaseModel):
    model_config = model_config

    latitude: Optional[float] = Field(None, description="위도")
    longitude: Optional[float] = Field(None, description="경도")
    altitude: Optional[float] = Field(None, description="고도")


# 정의: 카메라 정보를 담는 CameraMetadata
class CameraMetadata(BaseModel):
    model_config = model_config

    make: Optional[str] = Field(None, description="카메라 제조사")
    model: Optional[str] = Field(None, description="카메라 모델")


# 정의: 사진의 메타데이터 전체를 포함하는 클래스
class ImageMetadata(BaseModel):
    model_config = model_config

    captured_at: Optional[datetime] = Field(None, description="사진이 촬영된 시간")
    location: Optional[LocationMetadata] = Field(None, description="위치 정보")
    camera: Optional[CameraMetadata] = Field(None, description="카메라 정보")
    width: Optional[int] = Field(None, description="이미지 가로 픽셀 수")
    height: Optional[int] = Field(None, description="이미지 세로 픽셀 수")
    tags: Optional[List[str]] = Field(default_factory=list, description="이미지 관련 태그")


# 정의: Image Document
class Image(Document):
    model_config = model_config

    url: HttpUrl = Field(..., description="업로드된 이미지의 URL")
    filename: str = Field(..., description="업로드된 이미지의 파일명")  # 추가된 필드
    metadata: ImageMetadata = Field(..., description="사진의 메타데이터")
    source: str = Field("userUpload", description="이미지의 출처 (예: userUpload, modelGenerated 등)")
    user_id: PydanticObjectId = Field(..., description="이미지를 업로드한 사용자의 ID")
    hold_polygon_id: Optional[PydanticObjectId] = Field(None, description="연결된 홀드 폴리곤의 ID")

    is_deleted: bool = Field(False, description="이미지가 삭제되었는지 여부")
    uploaded_at: datetime = Field(..., description="이미지가 업로드된 시간")
    deleted_at: Optional[datetime] = Field(None, description="이미지가 삭제된 시간")

    wall_name: Optional[str] = Field(None, description="벽 이름")
    wall_expiration_date: Optional[datetime] = Field(None, description="벽 만료 일자")
    place_id: Optional[PydanticObjectId] = Field(None, description="연결된 Place ID")

    class Settings:
        name = "images"
        indexes = [IndexModel([("filename", ASCENDING)])]
        keep_nulls = True