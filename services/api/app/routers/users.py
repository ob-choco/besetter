import os
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi import status as http_status
from pydantic import BaseModel, Field

from app.core.gcs import bucket, generate_signed_url, extract_blob_path_from_url, get_base_url
from app.dependencies import get_current_user
from app.models import model_config
from app.models.user import User
from app.models.route import Route
from app.models.image import Image
from app.models.hold_polygon import HoldPolygon
from app.models.activity import Activity, UserRouteStats

router = APIRouter(prefix="/users", tags=["users"])


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------


class UserProfileResponse(BaseModel):
    model_config = model_config

    # Explicit alias overrides model_config's to_camel generator,
    # which would otherwise emit "_id" in the JSON response.
    id: str = Field(alias="id")
    name: Optional[str] = None
    email: Optional[str] = None
    bio: Optional[str] = None
    profile_image_url: Optional[str] = None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _build_profile_response(user: User) -> UserProfileResponse:
    """Build UserProfileResponse, converting profile_image_url to a signed URL if present."""
    signed_url = None
    if user.profile_image_url:
        blob_path = extract_blob_path_from_url(user.profile_image_url)
        if blob_path:
            signed_url = generate_signed_url(blob_path)
        else:
            signed_url = user.profile_image_url

    return UserProfileResponse(
        id=str(user.id),
        name=user.name,
        email=user.email,
        bio=user.bio,
        profile_image_url=signed_url,
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("/me", response_model=UserProfileResponse)
async def get_my_profile(current_user: User = Depends(get_current_user)):
    """인증된 유저의 프로필을 반환한다."""
    return _build_profile_response(current_user)


@router.patch("/me", response_model=UserProfileResponse)
async def update_my_profile(
    name: Optional[str] = Form(None),
    bio: Optional[str] = Form(None),
    profile_image: Optional[UploadFile] = File(None, alias="profileImage"),
    current_user: User = Depends(get_current_user),
):
    """인증된 유저의 프로필을 수정한다. multipart/form-data를 지원한다."""
    if name is not None:
        current_user.name = name

    if bio is not None:
        current_user.bio = bio

    if profile_image is not None and profile_image.filename:
        file_ext = os.path.splitext(profile_image.filename)[1].lower()
        if file_ext not in (".jpg", ".jpeg", ".png"):
            raise HTTPException(
                status_code=http_status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Only jpg/jpeg/png files are supported",
            )

        # 기존 프로필 이미지 삭제
        if current_user.profile_image_url:
            old_blob_path = extract_blob_path_from_url(current_user.profile_image_url)
            if old_blob_path:
                old_blob = bucket.blob(old_blob_path)
                old_blob.delete(if_generation_match=None)

        # 새 프로필 이미지 업로드
        user_id = str(current_user.id)
        unique_hex = uuid.uuid4().hex[:8]
        blob_path = f"profile_images/{user_id}_{unique_hex}{file_ext}"
        content = await profile_image.read()
        content_type = "image/png" if file_ext == ".png" else "image/jpeg"
        blob = bucket.blob(blob_path)
        blob.upload_from_string(data=content, content_type=content_type)
        current_user.profile_image_url = f"{get_base_url()}/{blob_path}"

    current_user.updated_at = datetime.now(tz=timezone.utc)
    await current_user.save()

    return _build_profile_response(current_user)


@router.delete("/me", status_code=204)
async def delete_account(current_user: User = Depends(get_current_user)):
    """인증된 유저의 계정과 모든 리소스를 soft delete 한다."""
    now = datetime.now(tz=timezone.utc)

    # 유저의 루트 soft delete
    await Route.find(
        Route.user_id == current_user.id,
        Route.is_deleted != True,
    ).update_many({"$set": {"isDeleted": True, "deletedAt": now}})

    # 유저의 이미지 soft delete
    await Image.find(
        Image.user_id == current_user.id,
        Image.is_deleted != True,
    ).update_many({"$set": {"isDeleted": True, "deletedAt": now}})

    # 유저의 홀드 폴리곤 soft delete
    await HoldPolygon.find(
        HoldPolygon.user_id == current_user.id,
        HoldPolygon.is_deleted != True,
    ).update_many({"$set": {"isDeleted": True, "deletedAt": now}})

    # Activity hard delete
    await Activity.find(Activity.user_id == current_user.id).delete()

    # UserRouteStats hard delete
    await UserRouteStats.find(UserRouteStats.user_id == current_user.id).delete()

    # 유저 soft delete
    current_user.is_deleted = True
    current_user.deleted_at = now
    current_user.refresh_token = None
    await current_user.save()
