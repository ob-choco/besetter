import os
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi import status as http_status
from pydantic import BaseModel

from app.core.gcs import bucket, generate_signed_url, extract_blob_path_from_url, get_base_url
from app.dependencies import get_current_user
from app.models import model_config
from app.models.user import User
from app.models.route import Route
from app.models.image import Image
from app.models.hold_polygon import HoldPolygon

router = APIRouter(prefix="/users", tags=["users"])


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------


class UserProfileResponse(BaseModel):
    model_config = model_config

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

    # 유저 soft delete
    current_user.is_deleted = True
    current_user.deleted_at = now
    current_user.refresh_token = None
    await current_user.save()
