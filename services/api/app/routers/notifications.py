from datetime import datetime, timedelta, timezone
from typing import List, Optional

from beanie.odm.fields import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.dependencies import get_current_user
from app.models import model_config
from app.models.notification import Notification
from app.models.user import User

router = APIRouter(prefix="/notifications", tags=["notifications"])

_CLOCK_SKEW = timedelta(seconds=5)


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------


class NotificationView(BaseModel):
    model_config = model_config

    id: PydanticObjectId
    type: str
    title: str
    body: str
    link: Optional[str] = None
    read_at: Optional[datetime] = None
    created_at: datetime


class NotificationListResponse(BaseModel):
    model_config = model_config

    items: List[NotificationView]
    next_cursor: Optional[datetime] = None


class MarkReadRequest(BaseModel):
    model_config = model_config

    before: datetime


class MarkReadResponse(BaseModel):
    model_config = model_config

    marked_count: int
    unread_notification_count: int


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def notification_to_view(notif: Notification) -> NotificationView:
    return NotificationView(
        id=notif.id,
        type=notif.type,
        title=notif.title,
        body=notif.body,
        link=notif.link,
        read_at=notif.read_at,
        created_at=notif.created_at,
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("", response_model=NotificationListResponse)
async def list_notifications(
    before: Optional[datetime] = Query(None, description="이 시각 이전 알림만"),
    limit: int = Query(20, ge=1, le=50),
    current_user: User = Depends(get_current_user),
):
    query_filter: dict = {"userId": current_user.id}
    if before is not None:
        query_filter["createdAt"] = {"$lt": before}

    items = (
        await Notification.find(query_filter)
        .sort(-Notification.created_at)
        .limit(limit)
        .to_list()
    )

    next_cursor = items[-1].created_at if len(items) == limit else None
    return NotificationListResponse(
        items=[notification_to_view(n) for n in items],
        next_cursor=next_cursor,
    )


@router.post("/mark-read", response_model=MarkReadResponse)
async def mark_notifications_read(
    payload: MarkReadRequest,
    current_user: User = Depends(get_current_user),
):
    now = datetime.now(tz=timezone.utc)
    if payload.before > now + _CLOCK_SKEW:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="before must be <= now",
        )

    notif_coll = Notification.get_motor_collection()
    result = await notif_coll.update_many(
        {
            "userId": current_user.id,
            "readAt": None,
            "createdAt": {"$lte": payload.before},
        },
        {"$set": {"readAt": now}},
    )
    marked = result.modified_count

    if marked:
        await User.get_motor_collection().update_one(
            {"_id": current_user.id},
            {"$inc": {"unreadNotificationCount": -marked}},
        )

    fresh = await User.get(current_user.id)
    count = fresh.unread_notification_count if fresh else 0
    return MarkReadResponse(
        marked_count=marked,
        unread_notification_count=max(0, count),
    )
