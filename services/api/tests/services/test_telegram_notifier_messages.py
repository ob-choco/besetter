"""Pure-function tests for telegram_notifier message builders."""
from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace

from app.services.telegram_notifier import _build_signup_text


def _make_user(**overrides):
    defaults = dict(
        name="Alice",
        email="alice@example.com",
        profile_id="alice123",
        created_at=datetime(2026, 4, 23, 5, 30, tzinfo=timezone.utc),  # 14:30 KST
    )
    defaults.update(overrides)
    return SimpleNamespace(**defaults)


def test_build_signup_text_line_provider():
    user = _make_user()
    text = _build_signup_text(user, provider="line")
    assert "🆕 <b>새 유저 가입</b>" in text
    assert "이름: Alice" in text
    assert "이메일: alice@example.com" in text
    assert "Provider: line" in text
    assert "Profile ID: alice123" in text
    assert "2026-04-23 14:30" in text


def test_build_signup_text_missing_name_renders_dash():
    user = _make_user(name=None)
    text = _build_signup_text(user, provider="apple")
    assert "이름: —" in text


def test_build_signup_text_missing_email_renders_dash():
    user = _make_user(email=None)
    text = _build_signup_text(user, provider="apple")
    assert "이메일: —" in text


def test_build_signup_text_html_escapes_user_fields():
    user = _make_user(name="<Alice & Co>")
    text = _build_signup_text(user, provider="line")
    assert "&lt;Alice &amp; Co&gt;" in text
    assert "<Alice & Co>" not in text


def test_build_signup_text_includes_each_of_four_providers():
    for provider in ("line", "kakao", "apple", "google"):
        text = _build_signup_text(_make_user(), provider=provider)
        assert f"Provider: {provider}" in text
