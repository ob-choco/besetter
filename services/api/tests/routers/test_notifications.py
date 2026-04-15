from datetime import datetime, timezone
from types import SimpleNamespace

from beanie.odm.fields import PydanticObjectId

from app.routers.notifications import notification_to_view


def test_notification_to_view_maps_all_fields():
    now = datetime(2026, 4, 15, 12, 0, 0, tzinfo=timezone.utc)
    notif_id = PydanticObjectId("64b000000000000000000001")
    notif = SimpleNamespace(
        id=notif_id,
        user_id=PydanticObjectId("64b000000000000000000002"),
        type="place_suggestion_ack",
        title="정보 수정 제안이 접수되었습니다",
        body="클라이밍파크 강남점에 대한 소중한 제보 감사합니다 🙌 운영진이 확인하고 반영할게요.",
        link="/places/64b000000000000000000003",
        read_at=None,
        created_at=now,
    )
    view = notification_to_view(notif)
    assert view.id == notif_id
    assert view.type == "place_suggestion_ack"
    assert view.title == "정보 수정 제안이 접수되었습니다"
    assert view.body.startswith("클라이밍파크 강남점")
    assert view.link == "/places/64b000000000000000000003"
    assert view.read_at is None
    assert view.created_at == now
