import os
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi import status as http_status
from pydantic import BaseModel, Field
from pymongo.errors import DuplicateKeyError

from app.core.gcs import bucket, generate_signed_url, extract_blob_path_from_url, get_base_url
from app.core.profile_id import ProfileIdError, validate_profile_id
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
    profile_id: str
    name: Optional[str] = None
    email: Optional[str] = None
    bio: Optional[str] = None
    profile_image_url: Optional[str] = None
    unread_notification_count: int = 0
    marketing_push_consent: bool = False
    marketing_push_consent_at: Optional[datetime] = None
    marketing_push_consent_source: Optional[str] = None


class UpdateProfileIdRequest(BaseModel):
    model_config = model_config

    profile_id: str


USER_NAME_MAX_LENGTH = 32
USER_BIO_MAX_LENGTH = 300


class UpdateMyProfileRequest(BaseModel):
    """Validation schema for PATCH /users/me form fields (name, bio)."""

    model_config = model_config

    name: Optional[str] = Field(None, max_length=USER_NAME_MAX_LENGTH)
    bio: Optional[str] = Field(None, max_length=USER_BIO_MAX_LENGTH)


def _validate_user_name_or_raise(name: str) -> None:
    if len(name) > USER_NAME_MAX_LENGTH:
        raise HTTPException(
            status_code=http_status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"name must be {USER_NAME_MAX_LENGTH} characters or fewer",
        )


def _validate_user_bio_or_raise(bio: str) -> None:
    if len(bio) > USER_BIO_MAX_LENGTH:
        raise HTTPException(
            status_code=http_status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"bio must be {USER_BIO_MAX_LENGTH} characters or fewer",
        )


_PROFILE_ID_ERROR_MESSAGES: dict[ProfileIdError, str] = {
    ProfileIdError.TOO_SHORT: "6자 이상 입력해 주세요",
    ProfileIdError.TOO_LONG: "30자 이하로 입력해 주세요",
    ProfileIdError.INVALID_CHARS: "소문자, 숫자, 점(.), 밑줄(_)만 사용할 수 있습니다",
    ProfileIdError.INVALID_START_END: "첫 글자와 끝 글자는 영문 소문자 또는 숫자여야 합니다",
    ProfileIdError.CONSECUTIVE_SPECIAL: "점(.)과 밑줄(_)을 연속해서 쓸 수 없습니다",
    ProfileIdError.RESERVED: "사용할 수 없는 프로필 ID입니다",
    ProfileIdError.TAKEN: "이미 사용 중인 프로필 ID입니다",
}


def _validate_profile_id_or_raise(value: str) -> None:
    err = validate_profile_id(value)
    if err is None:
        return
    raise HTTPException(
        status_code=http_status.HTTP_422_UNPROCESSABLE_ENTITY,
        detail={"code": err.value, "message": _PROFILE_ID_ERROR_MESSAGES[err]},
    )


class ProfileIdAvailabilityResponse(BaseModel):
    model_config = model_config

    value: str
    available: bool
    reason: Optional[str] = None


def _compute_profile_id_availability(
    *,
    value: str,
    current_user: User,
    exists: Optional[bool],
) -> ProfileIdAvailabilityResponse:
    """Decide availability given validation + optional DB-existence probe.

    `exists` is what a `find_one({"profileId": value})` returned (True if
    another user owns it, False if free, None if DB probe was skipped).
    """
    if value == current_user.profile_id:
        return ProfileIdAvailabilityResponse(value=value, available=True, reason=None)

    err = validate_profile_id(value)
    if err is not None:
        return ProfileIdAvailabilityResponse(
            value=value, available=False, reason=err.value,
        )

    if exists:
        return ProfileIdAvailabilityResponse(
            value=value,
            available=False,
            reason=ProfileIdError.TAKEN.value,
        )
    return ProfileIdAvailabilityResponse(value=value, available=True, reason=None)


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
        profile_id=user.profile_id,
        name=user.name,
        email=user.email,
        bio=user.bio,
        profile_image_url=signed_url,
        unread_notification_count=max(0, user.unread_notification_count),
        marketing_push_consent=user.marketing_push_consent,
        marketing_push_consent_at=user.marketing_push_consent_at,
        marketing_push_consent_source=user.marketing_push_consent_source,
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
        _validate_user_name_or_raise(name)
        current_user.name = name

    if bio is not None:
        _validate_user_bio_or_raise(bio)
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


@router.get("/me/profile-id/availability", response_model=ProfileIdAvailabilityResponse)
async def check_profile_id_availability(
    value: str,
    current_user: User = Depends(get_current_user),
):
    """Return whether `value` can be used as the caller's new profile_id.

    Always 200. No 409/422 — instead reports reason in the body.
    """
    if value == current_user.profile_id:
        return _compute_profile_id_availability(
            value=value, current_user=current_user, exists=None,
        )
    if validate_profile_id(value) is not None:
        return _compute_profile_id_availability(
            value=value, current_user=current_user, exists=None,
        )

    other = await User.find_one({"profileId": value})
    exists = other is not None and other.id != current_user.id
    return _compute_profile_id_availability(
        value=value, current_user=current_user, exists=exists,
    )


@router.patch("/me/profile-id", response_model=UserProfileResponse)
async def update_my_profile_id(
    body: UpdateProfileIdRequest,
    current_user: User = Depends(get_current_user),
):
    """Change the caller's profile_id. Returns the full profile on success.

    422 on validation failure, 409 on uniqueness collision.
    """
    new_value = body.profile_id
    _validate_profile_id_or_raise(new_value)

    if new_value == current_user.profile_id:
        return _build_profile_response(current_user)

    current_user.profile_id = new_value
    current_user.updated_at = datetime.now(tz=timezone.utc)
    try:
        await current_user.save()
    except DuplicateKeyError:
        raise HTTPException(
            status_code=http_status.HTTP_409_CONFLICT,
            detail={
                "code": ProfileIdError.TAKEN.value,
                "message": _PROFILE_ID_ERROR_MESSAGES[ProfileIdError.TAKEN],
            },
        )

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
