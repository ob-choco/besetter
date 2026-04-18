from datetime import datetime, timezone
from types import SimpleNamespace

from beanie.odm.fields import PydanticObjectId

from app.services.notification_renderer import pick_locale, render


def _make_notif(
    *,
    type: str = "place_suggestion_ack",
    params: dict | None = None,
    title: str = "",
    body: str = "",
):
    return SimpleNamespace(
        id=PydanticObjectId("64b000000000000000000001"),
        user_id=PydanticObjectId("64b000000000000000000002"),
        type=type,
        title=title,
        body=body,
        link=None,
        read_at=None,
        created_at=datetime(2026, 4, 18, tzinfo=timezone.utc),
        params=params if params is not None else {},
    )


# --- pick_locale ---

def test_pick_locale_returns_primary_subtag():
    assert pick_locale("ko-KR,ko;q=0.9,en;q=0.8") == "ko"
    assert pick_locale("en-US") == "en"
    assert pick_locale("ja") == "ja"
    assert pick_locale("es-ES") == "es"


def test_pick_locale_none_returns_default():
    assert pick_locale(None) == "ko"
    assert pick_locale("") == "ko"


def test_pick_locale_unsupported_falls_back_to_default():
    assert pick_locale("fr-FR") == "ko"
    assert pick_locale("zh,fr") == "ko"


def test_pick_locale_is_case_insensitive():
    assert pick_locale("EN-US") == "en"
    assert pick_locale("Ja-JP") == "ja"


# --- render ---

def test_render_new_record_uses_template_for_locale():
    notif = _make_notif(
        type="place_suggestion_ack",
        params={"place_name": "클라이밍파크"},
    )
    title, body = render(notif, "ko")
    assert title == "장소 정보 수정 제안이 접수되었습니다"
    assert "클라이밍파크" in body
    assert "소중한 제보 감사합니다" in body


def test_render_new_record_english():
    notif = _make_notif(
        type="place_registration_ack",
        params={"place_name": "ClimbPark"},
    )
    title, body = render(notif, "en")
    assert title == "Your gym registration request has been received"
    assert "ClimbPark" in body


def test_render_new_record_japanese():
    notif = _make_notif(
        type="place_suggestion_ack",
        params={"place_name": "クライミングパーク"},
    )
    title, body = render(notif, "ja")
    assert "スポット情報" in title
    assert "クライミングパーク" in body


def test_render_new_record_spanish():
    notif = _make_notif(
        type="place_registration_ack",
        params={"place_name": "ClimbPark"},
    )
    title, body = render(notif, "es")
    assert "solicitud de registro" in title
    assert "ClimbPark" in body


def test_render_unsupported_locale_uses_default_template():
    notif = _make_notif(
        type="place_suggestion_ack",
        params={"place_name": "클라이밍파크"},
    )
    title, body = render(notif, "fr")
    assert title == "장소 정보 수정 제안이 접수되었습니다"
    assert "클라이밍파크" in body


def test_render_old_record_without_params_returns_stored_values():
    """Records created before this feature have empty params; we must return
    whatever was pre-rendered into title/body at creation time."""
    notif = _make_notif(
        type="place_suggestion_ack",
        params={},
        title="정보 수정 제안이 접수되었습니다",
        body="클라이밍파크에 대한 소중한 제보 감사합니다 🙌 운영진이 확인하고 반영할게요.",
    )
    title, body = render(notif, "en")
    assert title == "정보 수정 제안이 접수되었습니다"
    assert body.startswith("클라이밍파크")


def test_render_unknown_type_falls_back_to_stored():
    notif = _make_notif(
        type="totally_unknown_type",
        params={"place_name": "X"},
        title="saved title",
        body="saved body",
    )
    title, body = render(notif, "ko")
    assert title == "saved title"
    assert body == "saved body"


def test_render_missing_placeholder_falls_back_to_stored():
    """If the template references {place_name} but params don't include it,
    fall back to the stored value rather than crashing."""
    notif = _make_notif(
        type="place_suggestion_ack",
        params={"other_var": "X"},
        title="saved title",
        body="saved body",
    )
    title, body = render(notif, "ko")
    # Title template has no placeholder so it still renders.
    assert title == "장소 정보 수정 제안이 접수되었습니다"
    # Body needs place_name — should fall back to stored body.
    assert body == "saved body"
