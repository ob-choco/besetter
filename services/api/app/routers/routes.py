from fastapi import APIRouter, Depends, HTTPException, Query
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
from app.models import IdView
from app.models.route import Route, BoulderingHold, EnduranceHold, Visibility, RouteType
from app.core.gcs import generate_signed_url, extract_blob_path_from_url


from beanie.odm.operators.find.comparison import In
from beanie.odm.operators.find.logical import Or, And
from beanie.odm.operators.find.comparison import LT, GT, Eq, In
import base64


from app.models import model_config
from typing import Optional, List
from deepdiff import DeepDiff

router = APIRouter(prefix="/routes", tags=["routes"])


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

    gym_name: Optional[str] = Field(None, description="암장 이름")
    wall_name: Optional[str] = Field(None, description="벽 이름")
    wall_expiration_date: Optional[datetime] = Field(None, description="벽 만료 일자")

    polygons: List[HoldPolygonData]


@router.post("", status_code=status.HTTP_201_CREATED, response_model=RouteDetailView)
async def create_route(request: CreateRouteRequest, current_user: User = Depends(get_current_user)):
    image = await Image.find_one(
        Image.id == ObjectId(request.image_id),
        Image.user_id == current_user.id,
        Image.is_deleted == False,
    )
    if not image:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")

    if not image.hold_polygon_id:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Hold polygon not found")

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
    )

    created_route = await route.save()

    blob_path = extract_blob_path_from_url(created_route.image_url)
    if blob_path:
        created_route.image_url = HttpUrl(generate_signed_url(blob_path))

    return await _enrich_route_with_hold_polygon_data(created_route)


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

    created_at: datetime
    updated_at: Optional[datetime]
    deleted_at: Optional[datetime]

    gym_name: Optional[str] = Field(None, description="암장 이름")
    wall_name: Optional[str] = Field(None, description="벽 이름")
    wall_expiration_date: Optional[datetime] = Field(None, description="벽 만료 일자")


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
):
    # 쿼리 빌더 초기화
    query = Route.find(Route.user_id == current_user.id, Route.is_deleted == False)

    # 정렬 옵션 처리
    sort_field, sort_order = sort.split(":")
    db_field = "created_at" if sort_field == "createdAt" else sort_field

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
            cursor_value = getattr(last_doc, db_field)
            cursor_id = last_doc.id

            if sort_order == "desc":
                query = query.find(
                    Or(
                        LT(getattr(Route, db_field), cursor_value),
                        And(Eq(getattr(Route, db_field), cursor_value), LT(Route.id, cursor_id)),
                    )
                )
            else:
                query = query.find(
                    Or(
                        GT(getattr(Route, db_field), cursor_value),
                        And(Eq(getattr(Route, db_field), cursor_value), GT(Route.id, cursor_id)),
                    )
                )

    # 정렬 적용
    if sort_order == "desc":
        query = query.sort([(db_field, -1), ("_id", -1)])
    else:
        query = query.sort([(db_field, 1), ("_id", 1)])

    # 프로젝션 및 제한 적용
    query = query.project(projection_model=RouteServiceView).limit(limit + 1)
    routes = await query.to_list()

    # 이미지 정보 추가
    image_ids = [route.image_id for route in routes]
    images = await Image.find(In(Image.id, image_ids)).to_list()
    image_dict = {str(image.id): image for image in images}

    for route in routes:
        image = image_dict.get(str(route.image_id))
        if image:
            route.gym_name = image.gym_name
            route.wall_name = image.wall_name
            route.wall_expiration_date = image.wall_expiration_date

    # 다음 페이지 토큰 생성
    has_next = len(routes) > limit
    next_token = None

    if has_next:
        routes = routes[:limit]  # 마지막 항목 제거
        last_route = routes[-1]
        next_token = encode_cursor(sort_field, sort_order, str(last_route.id))

    for route in routes:
        blob_path = extract_blob_path_from_url(route.image_url)
        if blob_path:
            route.image_url = HttpUrl(generate_signed_url(blob_path))

    return RouteListResponse(data=routes, meta=RouteListMeta(next_token=next_token))


class RouteCountResponse(BaseModel):
    model_config = model_config

    total_count: int = Field(..., description="전체 루트 수")


@router.get("/count", response_model=RouteCountResponse)
async def get_route_count(current_user: User = Depends(get_current_user)):
    count = await Route.find(And(Route.user_id == current_user.id, Route.is_deleted == False)).count()

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
                    "gymName": 1,
                    "wallName": 1,
                    "wallExpirationDate": 1,
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

    route_detail = RouteDetailView(**route.model_dump(), polygons=hold_polygon.get("polygons"))
    route_detail.gym_name = hold_polygon.get("gymName")
    route_detail.wall_name = hold_polygon.get("wallName")
    route_detail.wall_expiration_date = hold_polygon.get("wallExpirationDate")

    return route_detail


@router.get("/{route_id}", response_model=RouteDetailView)
async def get_route(route_id: str, current_user: User = Depends(get_current_user)):
    route = await Route.find_one(
        Route.id == ObjectId(route_id), Route.user_id == current_user.id, Route.is_deleted == False
    )
    if not route:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Route not found")

    blob_path = extract_blob_path_from_url(route.image_url)
    if blob_path:
        route.image_url = HttpUrl(generate_signed_url(blob_path))

    return await _enrich_route_with_hold_polygon_data(route)


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
async def update_route(route_id: str, request: UpdateRouteRequest, current_user: User = Depends(get_current_user)):
    # 기존 route 조회
    route = await Route.find_one(
        Route.id == ObjectId(route_id), Route.user_id == current_user.id, Route.is_deleted == False
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
        updated_route.updated_at = datetime.utcnow()
        await updated_route.save()
        return await _enrich_route_with_hold_polygon_data(updated_route)

    blob_path = extract_blob_path_from_url(route.image_url)
    if blob_path:
        route.image_url = HttpUrl(generate_signed_url(blob_path))

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
