from datetime import datetime, timezone
from types import SimpleNamespace

from beanie.odm.fields import PydanticObjectId

from app.routers.notifications import notification_to_view


def _notif(**overrides):
    base = dict(
        id=PydanticObjectId("64b000000000000000000001"),
        user_id=PydanticObjectId("64b000000000000000000002"),
        type="place_suggestion_ack",
        title="saved title",
        body="saved body",
        link="/places/64b000000000000000000003",
        read_at=None,
        created_at=datetime(2026, 4, 15, 12, 0, 0, tzinfo=timezone.utc),
        params={},
    )
    base.update(overrides)
    return SimpleNamespace(**base)


def test_notification_to_view_maps_all_fields_old_record():
    """Records without params return stored title/body regardless of locale."""
    notif = _notif(
        title="정보 수정 제안이 접수되었습니다",
        body="클라이밍파크 강남점에 대한 소중한 제보 감사합니다 🙌 운영진이 확인하고 반영할게요.",
    )
    view = notification_to_view(notif, locale="en")
    assert view.id == notif.id
    assert view.type == "place_suggestion_ack"
    assert view.title == "정보 수정 제안이 접수되었습니다"
    assert view.body.startswith("클라이밍파크 강남점")
    assert view.link == "/places/64b000000000000000000003"
    assert view.read_at is None
    assert view.created_at == notif.created_at


def test_notification_to_view_renders_from_params_ko():
    notif = _notif(
        type="place_suggestion_ack",
        params={"place_name": "클라이밍파크"},
    )
    view = notification_to_view(notif, locale="ko")
    assert view.title == "장소 정보 수정 제안이 접수되었습니다"
    assert "클라이밍파크" in view.body


def test_notification_to_view_renders_from_params_en():
    notif = _notif(
        type="place_registration_ack",
        params={"place_name": "ClimbPark"},
    )
    view = notification_to_view(notif, locale="en")
    assert view.title == "Your gym registration request has been received"
    assert "ClimbPark" in view.body
