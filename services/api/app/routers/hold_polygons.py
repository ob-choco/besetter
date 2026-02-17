from datetime import datetime, timedelta
from bson import ObjectId
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, Body
from fastapi import status
import uuid
import os
from pathlib import Path
import pytz
from fastapi.encoders import jsonable_encoder
from typing import List
import jsonpatch
from pydantic import HttpUrl


from app.dependencies import get_current_user
from app.models.user import User
from app.models.image import Image
from app.models.hold_polygon import HoldPolygon

import aiohttp

from app.routers.images import extract_metadata

import google.auth.transport.requests
import google.oauth2.id_token
from google.oauth2.service_account import Credentials

from google.cloud import storage

from app.core.gcs import get_base_url, bucket, storage_client, generate_signed_url, extract_blob_path_from_url


router = APIRouter(prefix="/hold-polygons", tags=["hold-polygons"])


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_hold_polygon(file: UploadFile = File(...), current_user: User = Depends(get_current_user)):
    # 1. 파일 저장
    file_ext = os.path.splitext(file.filename)[1]

    if file_ext not in [".jpg", ".jpeg"]:
        raise HTTPException(status_code=400, detail="지원되지 않는 파일 형식입니다")

    unique_filename = f"{uuid.uuid4()}{file_ext}"
    content = await file.read()
    metadata = extract_metadata(content)

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
        auth_req = google.auth.transport.requests.Request()
        id_token = google.oauth2.id_token.fetch_id_token(
            auth_req,
            "https://besetter-detectron2-371038003203.asia-northeast3.run.app/",
        )

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

    return hold_polygon


@router.get("/{hold_polygon_id}")
async def get_hold_polygon(hold_polygon_id: str, current_user: User = Depends(get_current_user)):
    """홀드 폴리곤 정보를 조회하는 엔드포인트

    Args:
        hold_polygon_id (str): 조회할 홀드 폴리곤의 ID
        current_user (User): 현재 인증된 사용자

    Returns:
        HoldPolygon: 조회된 홀드 폴리곤 정보

    Raises:
        HTTPException: 폴리곤을 찾을 수 없거나 접근 권한이 없는 경우
    """
    hold_polygon = await HoldPolygon.find_one(
        HoldPolygon.id == ObjectId(hold_polygon_id),
        HoldPolygon.user_id == current_user.id,
        HoldPolygon.is_deleted != True,
    )

    if not hold_polygon:
        raise HTTPException(status_code=404, detail="홀드 폴리곤을 찾을 수 없거나 접근 권한이 없습니다")

    blob_path = extract_blob_path_from_url(hold_polygon.image_url)
    if blob_path:
        signed_url = generate_signed_url(blob_path)
        hold_polygon.image_url = HttpUrl(signed_url)

    return hold_polygon


@router.patch("/{hold_polygon_id}", status_code=status.HTTP_204_NO_CONTENT)
async def update_hold_polygon(
    hold_polygon_id: str,
    patch: List[dict] = Body(...),
    current_user: User = Depends(get_current_user),
):
    """홀드 폴리곤을 JSON Patch로 업데이트하는 엔드포인트

    Args:
        hold_polygon_id (str): 업데이트할 홀드 폴리곤의 ID
        patch (List[dict]): JSON Patch 작업 목록
        current_user (User): 현재 인증된 사용자

    Raises:
        HTTPException: 폴리곤을 찾을 수 없거나, 패치 적용에 실패한 경우
    """
    hold_polygon = await HoldPolygon.find_one(
        HoldPolygon.id == ObjectId(hold_polygon_id),
        HoldPolygon.user_id == current_user.id,
        HoldPolygon.is_deleted != True,
    )

    if not hold_polygon:
        raise HTTPException(status_code=404, detail="홀드 폴리곤을 찾을 수 없거나 접근 권한이 없습니다")

    image = await Image.find_one(Image.id == hold_polygon.image_id)

    if not image:
        raise HTTPException(status_code=404, detail="홀드 폴리곤을 찾을 수 없거나 접근 권한이 없습니다")

    try:
        # 문서를 dict로 변환
        hold_polygon_dict = jsonable_encoder(hold_polygon)

        # JSON Patch 적용
        patch = jsonpatch.JsonPatch(patch)
        patched_data = patch.apply(hold_polygon_dict)
        updated_hold_polygon = HoldPolygon.model_validate(patched_data)

        hold_polygon.polygons = updated_hold_polygon.polygons
        hold_polygon.gym_name = updated_hold_polygon.gym_name
        hold_polygon.wall_name = updated_hold_polygon.wall_name
        hold_polygon.wall_expiration_date = updated_hold_polygon.wall_expiration_date
        hold_polygon.updated_at = datetime.now(tz=pytz.UTC)
        await hold_polygon.save()

        image.gym_name = updated_hold_polygon.gym_name
        image.wall_name = updated_hold_polygon.wall_name
        image.wall_expiration_date = updated_hold_polygon.wall_expiration_date
        await image.save()

    except (jsonpatch.JsonPatchException, ValueError) as e:
        raise HTTPException(status_code=400, detail=f"패치 적용에 실패했습니다: {str(e)}")
