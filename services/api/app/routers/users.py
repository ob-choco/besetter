from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from app.dependencies import get_current_user
from app.models.user import User
from app.models.route import Route
from app.models.image import Image
from app.models.hold_polygon import HoldPolygon

router = APIRouter(prefix="/users", tags=["users"])


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
