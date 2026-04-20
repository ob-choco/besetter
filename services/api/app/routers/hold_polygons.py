from datetime import datetime, timedelta
from bson import ObjectId
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, Body
from fastapi import status
from typing import Optional
import uuid
import os
from pathlib import Path
import pytz
from fastapi.encoders import jsonable_encoder
from typing import List
import jsonpatch
from pydantic import BaseModel, HttpUrl, Field
from beanie.odm.fields import PydanticObjectId


from app.dependencies import get_current_user
from app.models.user import User
from app.models.image import Image
from app.models.hold_polygon import HoldPolygon, HoldPolygonData
from app.models.place import Place
from app.services.place_status import resolve_place_for_use
from app.models import model_config

import aiohttp

from app.routers.images import extract_metadata
from app.routers.places import PlaceView, place_to_view

import google.auth.transport.requests
import google.oauth2.id_token
from google.oauth2.service_account import Credentials

from google.cloud import storage

from app.core.gcs import get_base_url, bucket, storage_client, generate_signed_url, extract_blob_path_from_url


router = APIRouter(prefix="/hold-polygons", tags=["hold-polygons"])


WALL_NAME_MAX_LENGTH = 32


def _validate_wall_name(value: Optional[str]) -> None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError("wall_name must be a string")
    if len(value) > WALL_NAME_MAX_LENGTH:
        raise ValueError(f"wall_name must be {WALL_NAME_MAX_LENGTH} characters or fewer")
    return None


class HoldPolygonResponse(BaseModel):
    """HoldPolygon + Image 메타데이터를 합친 응답 모델"""
    model_config = model_config

    id: PydanticObjectId
    image_id: PydanticObjectId
    user_id: PydanticObjectId
    image_url: HttpUrl
    polygons: List[HoldPolygonData]
    is_deleted: bool = False
    created_at: datetime
    updated_at: Optional[datetime] = None

    # Image에서 join한 메타데이터
    place: Optional[PlaceView] = None
    wall_name: Optional[str] = None
    wall_expiration_date: Optional[datetime] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None


def _build_response(hold_polygon: HoldPolygon, image: Optional[Image] = None, place: Optional[Place] = None) -> HoldPolygonResponse:
    """HoldPolygon + Image + Place로부터 응답 모델 생성"""
    return HoldPolygonResponse(
        id=hold_polygon.id,
        image_id=hold_polygon.image_id,
        user_id=hold_polygon.user_id,
        image_url=hold_polygon.image_url,
        polygons=hold_polygon.polygons,
        is_deleted=hold_polygon.is_deleted,
        created_at=hold_polygon.created_at,
        updated_at=hold_polygon.updated_at,
        place=place_to_view(place) if place else None,
        wall_name=image.wall_name if image else None,
        wall_expiration_date=image.wall_expiration_date if image else None,
        latitude=image.metadata.location.latitude if image and image.metadata and image.metadata.location else None,
        longitude=image.metadata.location.longitude if image and image.metadata and image.metadata.location else None,
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=HoldPolygonResponse)
async def create_hold_polygon(
    file: UploadFile = File(...),
    latitude: Optional[float] = Form(None),
    longitude: Optional[float] = Form(None),
    current_user: User = Depends(get_current_user),
):
    # 1. 파일 저장
    file_ext = os.path.splitext(file.filename)[1]

    if file_ext not in [".jpg", ".jpeg"]:
        raise HTTPException(status_code=400, detail="지원되지 않는 파일 형식입니다")

    unique_filename = f"{uuid.uuid4()}{file_ext}"
    content = await file.read()
    metadata = extract_metadata(content)

    # 클라이언트에서 전달받은 GPS 좌표로 location 설정
    if latitude is not None and longitude is not None:
        metadata.location.latitude = latitude
        metadata.location.longitude = longitude

    blob = bucket.blob(f"wall_images/{unique_filename}")
    blob.upload_from_string(data=content, content_type="image/jpeg")

    # 파일 URL 생성
    file_url = HttpUrl(f"{get_base_url()}/wall_images/{unique_filename}")

    # 2. Image 모델에 저장
    image_id = ObjectId()
    image = Image(
        id=image_id,
        url=file_url,
        filename=unique_filename,
        metadata=metadata,
        user_id=current_user.id,
        uploaded_at=datetime.now(tz=pytz.UTC),
    )

    # 3. 외부 API를 통해 홀드 폴리곤 데이터 가져오기
    try:
        target_audience = "https://besetter-detectron2-371038003203.asia-northeast3.run.app/"
        try:
            # Cloud Run 환경: 메타데이터 서버에서 ID token 발급
            auth_req = google.auth.transport.requests.Request()
            id_token = google.oauth2.id_token.fetch_id_token(auth_req, target_audience)
        except Exception:
            # 로컬 환경: 서비스 계정으로 ID token 발급
            from app.core.config import get as get_config
            from google.oauth2.service_account import IDTokenCredentials
            id_token_credentials = IDTokenCredentials.from_service_account_info(
                get_config("google_cloud.storage.account_info"),
                target_audience=target_audience,
            )
            id_token_credentials.refresh(google.auth.transport.requests.Request())
            id_token = id_token_credentials.token

        # API 호출 준비
        url = "https://besetter-detectron2-371038003203.asia-northeast3.run.app/hold-polygons"
        headers = {"Authorization": f"Bearer {id_token}"}

        # 이미지 데이터로 multipart 요청 보내기
        async with aiohttp.ClientSession() as session:
            form = aiohttp.FormData()
            form.add_field("image", content, filename="image.jpg", content_type="image/jpeg")

            async with session.post(url, data=form, headers=headers) as response:
                if response.status != 201:
                    error_text = await response.text()
                    raise Exception(f"API 호출 실패: {response.status}, {error_text}")

                result = await response.json()
                polygons = result.get("polygons", [])

                if not polygons:
                    raise Exception("폴리곤 데이터를 받지 못했습니다.")
    except Exception as e:
        print(e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"폴리곤 데이터 처리 중 오류 발생: {str(e)}"
        )

    # 5. HoldPolygon 모델에 저장
    hold_polygon_id = ObjectId()
    hold_polygon = HoldPolygon(
        id=hold_polygon_id,
        image_id=image_id,
        user_id=current_user.id,
        image_url=file_url,
        polygons=polygons,
    )

    await hold_polygon.save()

    # 6. Image 모델 업데이트
    image.hold_polygon_id = hold_polygon_id
    await image.save()

    signed_url = HttpUrl(
        blob.generate_signed_url(
            version="v4",
            expiration=timedelta(minutes=5),
            method="GET",
        )
    )
    image.url = signed_url
    hold_polygon.image_url = signed_url

    return _build_response(hold_polygon, image)


@router.get("/{hold_polygon_id}", response_model=HoldPolygonResponse)
async def get_hold_polygon(hold_polygon_id: str, current_user: User = Depends(get_current_user)):
    hold_polygon = await HoldPolygon.find_one(
        HoldPolygon.id == ObjectId(hold_polygon_id),
        HoldPolygon.user_id == current_user.id,
        HoldPolygon.is_deleted != True,
    )

    if not hold_polygon:
        raise HTTPException(status_code=404, detail="홀드 폴리곤을 찾을 수 없거나 접근 권한이 없습니다")

    # Image join
    image = await Image.find_one(Image.id == hold_polygon.image_id)

    # Place resolution
    place = await Place.get(image.place_id) if image and image.place_id else None

    blob_path = extract_blob_path_from_url(hold_polygon.image_url)
    if blob_path:
        signed_url = generate_signed_url(blob_path)
        hold_polygon.image_url = HttpUrl(signed_url)

    return _build_response(hold_polygon, image, place)


@router.patch("/{hold_polygon_id}", status_code=status.HTTP_204_NO_CONTENT)
async def update_hold_polygon(
    hold_polygon_id: str,
    patch: List[dict] = Body(...),
    current_user: User = Depends(get_current_user),
):
    hold_polygon = await HoldPolygon.find_one(
        HoldPolygon.id == ObjectId(hold_polygon_id),
        HoldPolygon.user_id == current_user.id,
        HoldPolygon.is_deleted != True,
    )

    if not hold_polygon:
        raise HTTPException(status_code=404, detail="홀드 폴리곤을 찾을 수 없거나 접근 권한이 없습니다")

    image = await Image.find_one(Image.id == hold_polygon.image_id)

    if not image:
        raise HTTPException(status_code=404, detail="이미지를 찾을 수 없습니다")

    try:
        # HoldPolygon + Image 메타데이터를 합친 dict로 patch 적용
        hp_dict = jsonable_encoder(hold_polygon)
        # Image 메타데이터를 HoldPolygon dict에 포함 (patch에서 참조할 수 있도록)
        hp_dict["wallName"] = jsonable_encoder(image.wall_name)
        hp_dict["wallExpirationDate"] = jsonable_encoder(image.wall_expiration_date)
        hp_dict["placeId"] = jsonable_encoder(image.place_id)

        # JSON Patch 적용
        patch = jsonpatch.JsonPatch(patch)
        patched_data = patch.apply(hp_dict)

        # place_id 먼저 검증 (실패 시 부분-쓰기 방지 — 저장 전에 409/404 raise)
        incoming_place_id = patched_data.get("placeId")
        if incoming_place_id:
            place = await Place.get(ObjectId(incoming_place_id))
            if place is None:
                raise HTTPException(status_code=404, detail="Place not found")
            effective = await resolve_place_for_use(place, current_user)
            resolved_place_id = effective.id
        else:
            resolved_place_id = None

        # HoldPolygon 필드 업데이트 (polygons만)
        hold_polygon.polygons = HoldPolygon.model_validate(patched_data).polygons
        hold_polygon.updated_at = datetime.now(tz=pytz.UTC)
        await hold_polygon.save()

        # Image 메타데이터 업데이트 (정본)
        new_wall_name = patched_data.get("wallName")
        try:
            _validate_wall_name(new_wall_name)
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=str(exc),
            )
        image.wall_name = new_wall_name
        wall_exp = patched_data.get("wallExpirationDate")
        image.wall_expiration_date = datetime.fromisoformat(wall_exp) if wall_exp else None
        image.place_id = resolved_place_id
        await image.save()

    except (jsonpatch.JsonPatchException, ValueError) as e:
        raise HTTPException(status_code=400, detail=f"패치 적용에 실패했습니다: {str(e)}")
