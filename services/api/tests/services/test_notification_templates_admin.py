from datetime import datetime, timezone
from types import SimpleNamespace

from beanie.odm.fields import PydanticObjectId

from app.services.notification_templates import TEMPLATES
from app.services.notification_renderer import render


def _make_notif(type_: str, params: dict):
    return SimpleNamespace(
        id=PydanticObjectId("64b000000000000000000001"),
        user_id=PydanticObjectId("64b000000000000000000002"),
        type=type_,
        title="",
        body="",
        link=None,
        read_at=None,
        created_at=datetime(2026, 4, 20, tzinfo=timezone.utc),
        params=params,
    )


def test_place_review_passed_renders_ko():
    notif = _make_notif("place_review_passed", {"place_name": "강남 클라이밍 파크"})
    title, body = render(notif, "ko")
    assert "강남 클라이밍 파크" in body
    assert title == "암장이 등록되었어요"


def test_place_review_failed_with_reason_suffix():
    notif = _make_notif("place_review_failed", {
        "place_name": "강남 클라이밍 파크",
        "reason_suffix": " 사유: 중복 등록",
    })
    _, body = render(notif, "ko")
    assert "반려되었어요" in body
    assert "사유: 중복 등록" in body


def test_place_review_failed_without_reason_suffix():
    notif = _make_notif("place_review_failed", {
        "place_name": "강남 클라이밍 파크",
        "reason_suffix": "",
    })
    _, body = render(notif, "ko")
    assert "반려되었어요" in body
    assert "사유" not in body


def test_place_merged_contains_both_names():
    notif = _make_notif("place_merged", {
        "place_name": "강남클라이밍파크",
        "target_name": "강남 클라이밍 파크",
    })
    _, body = render(notif, "ko")
    assert "강남클라이밍파크" in body
    assert "강남 클라이밍 파크" in body


def test_all_new_types_have_four_locales():
    for t in (
        "place_review_passed",
        "place_review_failed",
        "place_merged",
        "place_suggestion_approved",
        "place_suggestion_rejected",
    ):
        for field in ("title", "body"):
            for loc in ("ko", "en", "ja", "es"):
                assert TEMPLATES[t][field].get(loc), f"missing {t}.{field}.{loc}"
