from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from beanie.odm.fields import PydanticObjectId
from bson.errors import InvalidId

from app.models.route import Route, Visibility

router = APIRouter(prefix="/share", tags=["share"])

templates = Jinja2Templates(directory="app/templates")

APP_STORE_URL = "https://apps.apple.com/app/besetter/id123456789"  # TODO: 실제 App Store URL로 교체
PLAY_STORE_URL = "https://play.google.com/store/apps/details?id=com.olivebagel.besetter"


@router.get("/routes/{route_id}", response_class=HTMLResponse)
async def share_route(request: Request, route_id: str):
    """공유 링크로 접근 시 OG 태그가 포함된 HTML 페이지 반환"""

    # ObjectId 유효성 검사
    try:
        object_id = PydanticObjectId(route_id)
    except (InvalidId, ValueError):
        return templates.TemplateResponse(
            "share_error.html",
            {
                "request": request,
                "icon": "🔍",
                "title": "루트를 찾을 수 없습니다",
                "message": "요청하신 루트가 존재하지 않습니다.",
            },
            status_code=404,
        )

    # 루트 조회
    route = await Route.get(object_id)

    # 루트가 없거나 삭제된 경우
    if route is None or route.is_deleted:
        return templates.TemplateResponse(
            "share_error.html",
            {
                "request": request,
                "icon": "🔍",
                "title": "루트를 찾을 수 없습니다",
                "message": "요청하신 루트가 존재하지 않거나 삭제되었습니다.",
            },
            status_code=404,
        )

    # 비공개 루트인 경우
    if route.visibility == Visibility.PRIVATE:
        return templates.TemplateResponse(
            "share_error.html",
            {
                "request": request,
                "icon": "🔒",
                "title": "비공개 루트입니다",
                "message": "이 루트는 비공개로 설정되어 있습니다.",
            },
            status_code=403,
        )

    # 제목 생성 (grade + type)
    route_type_kr = "볼더링" if route.type.value == "bouldering" else "지구력"
    title = f"{route.grade} {route_type_kr}"
    if route.title:
        title = route.title

    # 설명 생성
    description_parts = [route.grade]
    if route.gym_name:
        description_parts.append(route.gym_name)
    description = " · ".join(description_parts)

    share_url = str(request.url)

    return templates.TemplateResponse(
        "share_route.html",
        {
            "request": request,
            "title": title,
            "description": description,
            "image_url": str(route.image_url),
            "share_url": share_url,
            "app_store_url": APP_STORE_URL,
            "play_store_url": PLAY_STORE_URL,
        },
    )
