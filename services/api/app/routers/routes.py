import logging

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from fastapi import status
from typing import List, Optional, Dict, Any

from pydantic import BaseModel, Field, HttpUrl
from datetime import datetime
from beanie.odm.fields import PydanticObjectId
from bson import ObjectId
from app.dependencies import get_current_user
from app.models.user import User
from app.models.hold_polygon import HoldPolygon, HoldPolygonData
from app.models.image import Image
from app.models.place import Place
from app.models import IdView
from app.models.route import Route, BoulderingHold, EnduranceHold, Visibility, RouteType
from app.models.activity import Activity, UserRouteStats
from app.core.gcs import generate_signed_url, extract_blob_path_from_url


from beanie.odm.operators.find.comparison import In
from beanie.odm.operators.find.logical import Or, And
from beanie.odm.operators.find.comparison import LT, GT, Eq, In
import base64


from app.models import model_config
from app.routers.places import PlaceView, place_to_view
from typing import Optional, List
from deepdiff import DeepDiff
from app.services.route_overlay import generate_route_overlay
from app.services.place_status import resolve_place_for_use
from app.services import user_stats as user_stats_service

router = APIRouter(prefix="/routes", tags=["routes"])

logger = logging.getLogger(__name__)


async def _inc_image_route_count(image_id: PydanticObjectId, delta: int) -> None:
    """Fire-and-forget ``$inc`` on ``Image.routeCount``. Swallows exceptions."""
    try:
        await Image.get_pymongo_collection().update_one(
            {"_id": image_id},
            {"$inc": {"routeCount": delta}},
        )
    except Exception:
        logger.exception("inc image.routeCount failed: image_id=%s delta=%s", image_id, delta)


def _can_access_route(route, user) -> bool:
    """Return True if `user` may access `route`.

    Owner: always allowed (any visibility).
    Non-owner: allowed unless visibility is explicitly PRIVATE.
    UNLISTED is treated like PUBLIC for direct access (matches share.py).
    """
    if route.user_id == user.id:
        return True
    return route.visibility != Visibility.PRIVATE


class CreateBoulderingHoldRequest(BaseModel):
    model_config = model_config

    polygon_id: int = Field(..., description="폴리곤 ID")
    type: str = Field(..., description="홀드 타입")
    marking_count: Optional[int] = Field(None, description="마킹 개수")
    checkpoint_score: Optional[int] = Field(None, description="체크포인트 점수")


class CreateEnduranceHoldRequest(BaseModel):
    model_config = model_config

    polygon_id: int = Field(..., description="폴리곤 ID")
    grip_hand: Optional[str] = Field(None, description="손")


class CreateRouteRequest(BaseModel):
    model_config = model_config

    type: RouteType = Field(..., description="루트 타입")
    title: Optional[str] = Field(None, description="루트 제목")
    description: Optional[str] = Field(None, description="루트 설명")
    image_id: PydanticObjectId = Field(..., description="이미지 ID")
    grade_type: str = Field(..., description="등급 타입")
    grade: str = Field(..., description="등급")
    grade_color: Optional[str] = Field(None, description="등급 색상")
    grade_score: Optional[int] = Field(None, description="등급 점수")
    visibility: Visibility = Field(Visibility.PUBLIC, description="루트 공개 여부")
    bouldering_holds: Optional[List[CreateBoulderingHoldRequest]] = Field(None, description="볼더링 홀드 목록")
    endurance_holds: Optional[List[CreateEnduranceHoldRequest]] = Field(None, description="지구력 홀드 목록")


class RouteDetailView(Route):
    model_config = model_config

    place: Optional[PlaceView] = Field(None, description="장소 정보")
    wall_name: Optional[str] = Field(None, description="벽 이름")
    wall_expiration_date: Optional[datetime] = Field(None, description="벽 만료 일자")

    polygons: List[HoldPolygonData]

    has_other_user_activities: Optional[bool] = Field(
        None,
        description="다른 사용자가 이 루트로 활동 기록을 남겼는지 (소유자 + withActivityCheck=true 때만 채움)",
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=RouteDetailView)
async def create_route(request: CreateRouteRequest, background_tasks: BackgroundTasks, current_user: User = Depends(get_current_user)):
    image = await Image.find_one(
        Image.id == ObjectId(request.image_id),
        Image.user_id == current_user.id,
        Image.is_deleted != True,
    )
    if not image:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")

    if not image.hold_polygon_id:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Hold polygon not found")

    # Stale-place defense: rejected/foreign-pending/deleted → 409;
    # merged → transparent redirect (also opportunistically fix the image's place_id).
    if image.place_id:
        place = await Place.get(image.place_id)
        if place is None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "code": "PLACE_NOT_USABLE",
                    "place_id": str(image.place_id),
                    "place_name": "",
                    "place_status": "deleted",
                },
            )
        effective = await resolve_place_for_use(place, current_user)
        if effective.id != image.place_id:
            image.place_id = effective.id
            await image.save()

    hold_polygon = await HoldPolygon.find_one(HoldPolygon.id == image.hold_polygon_id, projection_model=IdView)
    if not hold_polygon:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Hold polygon not found")

    if request.type == RouteType.BOULDERING:
        bouldering_holds = [BoulderingHold(**hold.model_dump()) for hold in request.bouldering_holds]
    elif request.type == RouteType.ENDURANCE:
        endurance_holds = [EnduranceHold(**hold.model_dump()) for hold in request.endurance_holds]

    route = Route(
        type=request.type,
        title=request.title,
        description=request.description,
        grade_type=request.grade_type,
        grade=request.grade,
        grade_score=request.grade_score,
        grade_color=request.grade_color,
        visibility=request.visibility,
        hold_polygon_id=hold_polygon.id,
        image_id=image.id,
        user_id=current_user.id,
        image_url=image.url,
        bouldering_holds=bouldering_holds if request.type == RouteType.BOULDERING else None,
        endurance_holds=endurance_holds if request.type == RouteType.ENDURANCE else None,
        overlay_processing=True,
        overlay_started_at=datetime.utcnow(),
    )

    created_route = await route.save()

    blob_path = extract_blob_path_from_url(created_route.image_url)
    if blob_path:
        created_route.image_url = HttpUrl(generate_signed_url(blob_path))
    if created_route.overlay_image_url:
        overlay_blob_path = extract_blob_path_from_url(created_route.overlay_image_url)
        if overlay_blob_path:
            created_route.overlay_image_url = HttpUrl(generate_signed_url(overlay_blob_path))

    background_tasks.add_task(generate_route_overlay, created_route)
    enriched = await _enrich_route_with_hold_polygon_data(created_route)
    await user_stats_service.on_route_created(created_route)
    await _inc_image_route_count(created_route.image_id, 1)
    return enriched


class RouteServiceView(BaseModel):
    model_config = model_config

    id: ObjectId
    type: RouteType
    title: Optional[str] = Field(None, description="루트 제목")
    description: Optional[str] = Field(None, description="루트 설명")
    visibility: Visibility = Field(Visibility.PUBLIC, description="루트 공개 여부")
    grade_type: str
    grade: str
    grade_color: Optional[str]
    hold_polygon_id: ObjectId
    image_id: ObjectId
    user_id: ObjectId
    image_url: str

    overlay_image_url: Optional[str] = Field(None, description="오버레이 이미지 URL")
    overlay_processing: bool = Field(False, description="오버레이 이미지 생성 작업 중 여부")

    created_at: datetime
    updated_at: Optional[datetime]
    deleted_at: Optional[datetime]

    place: Optional[PlaceView] = Field(None, description="장소 정보")
    wall_name: Optional[str] = Field(None, description="벽 이름")
    wall_expiration_date: Optional[datetime] = Field(None, description="벽 만료 일자")

    total_count: Optional[int] = Field(None, description="내 총 활동 횟수 (시도+완등, projection=stats)")
    completed_count: Optional[int] = Field(None, description="내 총 완등 횟수 (projection=stats)")
    attempted_count: Optional[int] = Field(None, description="내 순수 시도 횟수 = total - completed (projection=stats)")
    last_activity_at: Optional[datetime] = Field(None, description="내 마지막 활동 시각 (projection=stats)")


class RouteListMeta(BaseModel):
    model_config = model_config

    next_token: Optional[str] = None


class RouteListResponse(BaseModel):
    model_config = model_config

    data: List[RouteServiceView]
    meta: RouteListMeta


def encode_cursor(sort_field: str, sort_order: str, last_id: str) -> str:
    cursor_str = f"{sort_field}:{sort_order}:{last_id}"
    return base64.b64encode(cursor_str.encode()).decode()


def decode_cursor(cursor: str) -> tuple[str, str, str]:
    decoded = base64.b64decode(cursor.encode()).decode()
    sort_field, sort_order, last_id = decoded.split(":")
    return sort_field, sort_order, last_id


class CursorValidationError(HTTPException):
    def __init__(self, current_sort: tuple[str, str], cursor_sort: tuple[str, str]):
        detail = {
            "errorCode": "INVALID_CURSOR",
            "message": "Cursor is invalid for the current sort parameters",
            "data": {
                "current": {"field": current_sort[0], "order": current_sort[1]},
                "cursor": {"field": cursor_sort[0], "order": cursor_sort[1]},
            },
        }
        super().__init__(status_code=422, detail=detail)


@router.get("", response_model=RouteListResponse)
async def get_routes(
    current_user: User = Depends(get_current_user),
    sort: str = Query("createdAt:desc", description="정렬 기준 (예: createdAt:desc)"),
    limit: int = Query(10, ge=1, le=100),
    next: Optional[str] = None,
    type: Optional[RouteType] = Query(None, description="루트 타입 필터 (bouldering, endurance)"),
    projection: Optional[str] = Query(
        None,
        description="확장 프로젝션 (쉼표 구분). 지원: stats — 사용자 루트 스탯(시도/완등/최근 활동)을 각 루트에 포함",
    ),
):
    projection_set = {p.strip() for p in projection.split(",")} if projection else set()
    include_stats = "stats" in projection_set
    # 쿼리 빌더 초기화
    query = Route.find(Route.user_id == current_user.id, Route.is_deleted != True)

    # 타입 필터
    if type:
        query = query.find(Route.type == type)

    # 정렬 옵션 처리
    sort_field, sort_order = sort.split(":")
    attr_field = "created_at" if sort_field == "createdAt" else sort_field

    # 커서 처리
    if next:
        cursor_sort_field, cursor_sort_order, last_id = decode_cursor(next)

        # 커서 검증
        if cursor_sort_field != sort_field or cursor_sort_order != sort_order:
            raise CursorValidationError(
                current_sort=(sort_field, sort_order), cursor_sort=(cursor_sort_field, cursor_sort_order)
            )

        last_doc = await Route.get(ObjectId(last_id))

        if last_doc:
            cursor_value = getattr(last_doc, attr_field)
            cursor_id = last_doc.id

            if sort_order == "desc":
                query = query.find(
                    Or(
                        LT(getattr(Route, attr_field), cursor_value),
                        And(Eq(getattr(Route, attr_field), cursor_value), LT(Route.id, cursor_id)),
                    )
                )
            else:
                query = query.find(
                    Or(
                        GT(getattr(Route, attr_field), cursor_value),
                        And(Eq(getattr(Route, attr_field), cursor_value), GT(Route.id, cursor_id)),
                    )
                )

    # 정렬 적용 — sort_field는 API 파라미터의 camelCase 값
    if sort_order == "desc":
        query = query.sort([(sort_field, -1), ("_id", -1)])
    else:
        query = query.sort([(sort_field, 1), ("_id", 1)])

    # 제한 적용 (프로젝션 제거 — place 조인을 위해 full document 조회)
    query = query.limit(limit + 1)
    raw_routes = await query.to_list()

    # 다음 페이지 토큰 생성
    has_next = len(raw_routes) > limit
    next_token = None

    if has_next:
        raw_routes = raw_routes[:limit]  # 마지막 항목 제거
        last_route = raw_routes[-1]
        next_token = encode_cursor(sort_field, sort_order, str(last_route.id))

    # 이미지 정보 추가
    image_ids = [route.image_id for route in raw_routes]
    images = await Image.find(In(Image.id, image_ids)).to_list()
    image_dict = {str(image.id): image for image in images}

    # Place 일괄 조회
    place_ids = list({image.place_id for image in images if image.place_id})
    if place_ids:
        places = await Place.find(In(Place.id, place_ids)).to_list()
        place_dict: dict = {place.id: place for place in places}
    else:
        place_dict = {}

    # UserRouteStats 일괄 조회 (projection=stats)
    stats_dict: dict = {}
    if include_stats and raw_routes:
        route_ids = [route.id for route in raw_routes]
        stats_list = await UserRouteStats.find(
            UserRouteStats.user_id == current_user.id,
            In(UserRouteStats.route_id, route_ids),
        ).to_list()
        stats_dict = {stats.route_id: stats for stats in stats_list}

    # RouteServiceView 구성
    routes: list[RouteServiceView] = []
    for route in raw_routes:
        image = image_dict.get(str(route.image_id))

        image_url = str(route.image_url)
        blob_path = extract_blob_path_from_url(route.image_url)
        if blob_path:
            image_url = generate_signed_url(blob_path)

        overlay_image_url = None
        if route.overlay_image_url:
            overlay_blob_path = extract_blob_path_from_url(route.overlay_image_url)
            overlay_image_url = generate_signed_url(overlay_blob_path) if overlay_blob_path else str(route.overlay_image_url)

        place_view = None
        if image and image.place_id and image.place_id in place_dict:
            place_view = place_to_view(place_dict[image.place_id])

        stats = stats_dict.get(route.id) if include_stats else None

        routes.append(RouteServiceView(
            id=route.id,
            type=route.type,
            title=route.title,
            description=route.description,
            visibility=route.visibility,
            grade_type=route.grade_type,
            grade=route.grade,
            grade_color=route.grade_color,
            hold_polygon_id=route.hold_polygon_id,
            image_id=route.image_id,
            user_id=route.user_id,
            image_url=image_url,
            overlay_image_url=overlay_image_url,
            overlay_processing=route.overlay_processing or False,
            created_at=route.created_at,
            updated_at=route.updated_at,
            deleted_at=route.deleted_at,
            place=place_view,
            wall_name=image.wall_name if image else None,
            wall_expiration_date=image.wall_expiration_date if image else None,
            total_count=stats.total_count if stats else (0 if include_stats else None),
            completed_count=stats.completed_count if stats else (0 if include_stats else None),
            attempted_count=(stats.total_count - stats.completed_count) if stats else (0 if include_stats else None),
            last_activity_at=stats.last_activity_at if stats else None,
        ))

    return RouteListResponse(data=routes, meta=RouteListMeta(next_token=next_token))


class RouteCountResponse(BaseModel):
    model_config = model_config

    total_count: int = Field(..., description="전체 루트 수")


@router.get("/count", response_model=RouteCountResponse)
async def get_route_count(current_user: User = Depends(get_current_user)):
    count = await Route.find(And(Route.user_id == current_user.id, Route.is_deleted != True)).count()

    return RouteCountResponse(total_count=count)


async def _enrich_route_with_hold_polygon_data(route: Route) -> RouteDetailView:
    """Route 객체에 hold_polygon 데이터를 입혀서 RouteDetailView로 반환합니다."""
    holds = route.bouldering_holds if route.type == RouteType.BOULDERING else route.endurance_holds
    polygon_ids = [hold.polygon_id for hold in holds] if holds else []

    hold_polygon = await HoldPolygon.get_pymongo_collection().aggregate(
        [
            {"$match": {"imageId": route.image_id}},
            {
                "$project": {
                    "_id": 1,
                    "polygons": {
                        "$filter": {
                            "input": "$polygons",
                            "as": "polygon",
                            "cond": {"$in": ["$$polygon.polygonId", polygon_ids]},
                        }
                    },
                }
            },
        ]
    ).to_list(length=None)

    hold_polygon = hold_polygon[0] if hold_polygon else None

    # Image에서 wall 메타데이터 + Place 해석
    image = await Image.get(route.image_id)
    place = await Place.get(image.place_id) if image and image.place_id else None

    route_detail = RouteDetailView(**route.model_dump(), polygons=hold_polygon.get("polygons"))
    route_detail.place = place_to_view(place) if place else None
    route_detail.wall_name = image.wall_name if image else None
    route_detail.wall_expiration_date = image.wall_expiration_date if image else None

    return route_detail


@router.get("/{route_id}", response_model=RouteDetailView)
async def get_route(
    route_id: str,
    with_activity_check: bool = Query(False, alias="withActivityCheck"),
    current_user: User = Depends(get_current_user),
):
    route = await Route.find_one(
        Route.id == ObjectId(route_id),
        Route.is_deleted != True,
    )
    if not route:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Route not found")

    if not _can_access_route(route, current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"reason": "private"},
        )

    blob_path = extract_blob_path_from_url(route.image_url)
    if blob_path:
        route.image_url = HttpUrl(generate_signed_url(blob_path))
    if route.overlay_image_url:
        overlay_blob_path = extract_blob_path_from_url(route.overlay_image_url)
        if overlay_blob_path:
            route.overlay_image_url = HttpUrl(generate_signed_url(overlay_blob_path))

    detail = await _enrich_route_with_hold_polygon_data(route)

    is_owner = route.user_id == current_user.id
    if is_owner and with_activity_check:
        other_activity = await Activity.find_one(
            Activity.route_id == route.id,
            Activity.user_id != current_user.id,
        )
        detail.has_other_user_activities = other_activity is not None

    return detail


class UpdateRouteRequest(BaseModel):
    model_config = model_config

    grade_type: Optional[str] = Field(None, description="등급 타입")
    grade: Optional[str] = Field(None, description="등급")
    grade_score: Optional[int] = Field(None, description="등급 점수")
    grade_color: Optional[str] = Field(None, description="등급 색상")
    title: Optional[str] = Field(None, description="루트 제목")
    description: Optional[str] = Field(None, description="루트 설명")
    visibility: Optional[Visibility] = Field(None, description="루트 공개 여부")
    bouldering_holds: Optional[List[CreateBoulderingHoldRequest]] = Field(None, description="볼더링 홀드 목록")
    endurance_holds: Optional[List[CreateEnduranceHoldRequest]] = Field(None, description="지구력 홀드 목록")


@router.patch("/{route_id}", response_model=RouteDetailView)
async def update_route(route_id: str, request: UpdateRouteRequest, background_tasks: BackgroundTasks, current_user: User = Depends(get_current_user)):
    # 기존 route 조회
    route = await Route.find_one(
        Route.id == ObjectId(route_id), Route.user_id == current_user.id, Route.is_deleted != True
    )
    if not route:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Route not found")

    # 홀드 타입 검증
    if request.bouldering_holds is not None and route.type != RouteType.BOULDERING:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot update bouldering holds for non-bouldering route"
        )
    if request.endurance_holds is not None and route.type != RouteType.ENDURANCE:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot update endurance holds for non-endurance route"
        )

    # Stale-place defense: rejected/foreign-pending/deleted → 409;
    # merged → transparent redirect (also opportunistically fix the image's place_id).
    image = await Image.get(route.image_id)
    if image and image.place_id:
        place = await Place.get(image.place_id)
        if place is None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "code": "PLACE_NOT_USABLE",
                    "place_id": str(image.place_id),
                    "place_name": "",
                    "place_status": "deleted",
                },
            )
        effective = await resolve_place_for_use(place, current_user)
        if effective.id != image.place_id:
            image.place_id = effective.id
            await image.save()

    # 업데이트할 데이터 준비
    update_data = request.model_dump(exclude_unset=True)

    # 홀드 객체 변환
    if request.bouldering_holds is not None:
        update_data["bouldering_holds"] = [BoulderingHold(**hold.model_dump()) for hold in request.bouldering_holds]
    if request.endurance_holds is not None:
        update_data["endurance_holds"] = [EnduranceHold(**hold.model_dump()) for hold in request.endurance_holds]

    # 변경사항 확인
    original_data = route.model_dump()
    updated_route = route.model_copy(update=update_data)
    updated_data = updated_route.model_dump()

    # DeepDiff를 사용하여 실제 변경사항 확인
    diff = DeepDiff(original_data, updated_data, exclude_paths=["root['updated_at']"])

    if diff:  # 변경사항이 있는 경우
        # 홀드 관련 필드 변경 여부 확인
        holds_changed = False
        for change_type in diff:
            for path in diff[change_type]:
                if "bouldering_holds" in path or "endurance_holds" in path:
                    holds_changed = True
                    break
            if holds_changed:
                break

        if holds_changed:
            updated_route.overlay_processing = True
            updated_route.overlay_started_at = datetime.utcnow()

        updated_route.updated_at = datetime.utcnow()
        await updated_route.save()

        if holds_changed:
            background_tasks.add_task(generate_route_overlay, updated_route)

        if updated_route.overlay_image_url:
            overlay_blob_path = extract_blob_path_from_url(updated_route.overlay_image_url)
            if overlay_blob_path:
                updated_route.overlay_image_url = HttpUrl(generate_signed_url(overlay_blob_path))

        return await _enrich_route_with_hold_polygon_data(updated_route)

    blob_path = extract_blob_path_from_url(route.image_url)
    if blob_path:
        route.image_url = HttpUrl(generate_signed_url(blob_path))
    if route.overlay_image_url:
        overlay_blob_path = extract_blob_path_from_url(route.overlay_image_url)
        if overlay_blob_path:
            route.overlay_image_url = HttpUrl(generate_signed_url(overlay_blob_path))

    # 변경사항이 없는 경우 기존 데이터 반환
    return await _enrich_route_with_hold_polygon_data(route)


@router.delete("/{route_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_route(route_id: str, current_user: User = Depends(get_current_user)):
    """루트를 삭제합니다 (소프트 삭제)"""

    # ObjectId 유효성 검증
    try:
        route_object_id = ObjectId(route_id)
    except:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="유효하지 않은 route_id 형식입니다")

    # 루트 조회
    route = await Route.find_one(Route.id == route_object_id, Route.user_id == current_user.id)

    if not route:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="루트를 찾을 수 없습니다")

    if route.is_deleted:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="이미 삭제된 루트입니다")

    # 소프트 삭제 처리
    route.is_deleted = True
    route.deleted_at = datetime.utcnow()
    await route.save()
    await user_stats_service.on_route_soft_deleted(route)
    await _inc_image_route_count(route.image_id, -1)
