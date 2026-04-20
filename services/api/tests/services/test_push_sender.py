from app.services.push_sender import _is_invalid_token_error, _primary_locale


def test_primary_locale_none_returns_default():
    assert _primary_locale(None) == "ko"


def test_primary_locale_empty_string_returns_default():
    assert _primary_locale("") == "ko"


def test_primary_locale_ko_kr():
    assert _primary_locale("ko-KR") == "ko"


def test_primary_locale_en_us():
    assert _primary_locale("en-US") == "en"


def test_primary_locale_underscore_form():
    assert _primary_locale("ja_JP") == "ja"


def test_primary_locale_unsupported_falls_back():
    assert _primary_locale("de-DE") == "ko"


def test_primary_locale_raw_primary_tag():
    assert _primary_locale("es") == "es"


def test_is_invalid_token_404_is_invalid():
    assert _is_invalid_token_error(404, "") is True


def test_is_invalid_token_400_with_invalid_argument():
    body = '{"error": {"status": "INVALID_ARGUMENT"}}'
    assert _is_invalid_token_error(400, body) is True


def test_is_invalid_token_400_generic_is_not_invalid():
    assert _is_invalid_token_error(400, "something else") is False


def test_is_invalid_token_403_sender_mismatch():
    body = '{"error": {"status": "SENDER_ID_MISMATCH"}}'
    assert _is_invalid_token_error(403, body) is True


def test_is_invalid_token_403_generic_is_not_invalid():
    assert _is_invalid_token_error(403, "permission denied") is False


def test_is_invalid_token_429_quota_is_not_invalid():
    assert _is_invalid_token_error(429, "QUOTA_EXCEEDED") is False


def test_is_invalid_token_500_is_not_invalid():
    assert _is_invalid_token_error(500, "INTERNAL") is False


def test_is_invalid_token_200_is_not_invalid():
    assert _is_invalid_token_error(200, "") is False


# ---------------------------------------------------------------------------
# _is_consent_active
# ---------------------------------------------------------------------------

from datetime import datetime, timedelta, timezone

from app.services.push_sender import _is_consent_active


class _FakeUser:
    def __init__(self, consent: bool, consent_at):
        self.marketing_push_consent = consent
        self.marketing_push_consent_at = consent_at


def _now():
    return datetime(2026, 4, 21, 12, 0, 0, tzinfo=timezone.utc)


def test_is_consent_active_none_user_false():
    assert _is_consent_active(None, now=_now()) is False


def test_is_consent_active_not_consented_false():
    user = _FakeUser(consent=False, consent_at=None)
    assert _is_consent_active(user, now=_now()) is False


def test_is_consent_active_consent_at_missing_false():
    user = _FakeUser(consent=True, consent_at=None)
    assert _is_consent_active(user, now=_now()) is False


def test_is_consent_active_recent_true():
    user = _FakeUser(consent=True, consent_at=_now() - timedelta(days=30))
    assert _is_consent_active(user, now=_now()) is True


def test_is_consent_active_ttl_boundary_inside_true():
    user = _FakeUser(consent=True, consent_at=_now() - timedelta(days=729, hours=23))
    assert _is_consent_active(user, now=_now()) is True


def test_is_consent_active_ttl_expired_false():
    user = _FakeUser(consent=True, consent_at=_now() - timedelta(days=731))
    assert _is_consent_active(user, now=_now()) is False


# ---------------------------------------------------------------------------
# _is_night_hour_for_device
# ---------------------------------------------------------------------------

from app.services.push_sender import _is_night_hour_for_device


class _FakeDevice:
    def __init__(self, timezone_name):
        self.timezone = timezone_name


# 2026-04-21 13:00 UTC → Asia/Seoul 22:00 (night),
# Europe/Paris 15:00 (day), America/Los_Angeles 06:00 (night)
_FIXED_UTC = datetime(2026, 4, 21, 13, 0, 0, tzinfo=timezone.utc)


def test_is_night_hour_kst_22h_true():
    d = _FakeDevice("Asia/Seoul")
    assert _is_night_hour_for_device(d, now=_FIXED_UTC) is True


def test_is_night_hour_paris_15h_false():
    d = _FakeDevice("Europe/Paris")
    assert _is_night_hour_for_device(d, now=_FIXED_UTC) is False


def test_is_night_hour_la_6h_true():
    d = _FakeDevice("America/Los_Angeles")
    assert _is_night_hour_for_device(d, now=_FIXED_UTC) is True


def test_is_night_hour_fallback_when_missing():
    d = _FakeDevice(None)
    assert _is_night_hour_for_device(d, now=_FIXED_UTC) is True


def test_is_night_hour_invalid_timezone_falls_back():
    d = _FakeDevice("Not/AZone")
    assert _is_night_hour_for_device(d, now=_FIXED_UTC) is True


def test_is_night_hour_boundary_21h_true():
    now = datetime(2026, 4, 21, 12, 0, 0, tzinfo=timezone.utc)
    d = _FakeDevice("Asia/Seoul")
    assert _is_night_hour_for_device(d, now=now) is True


def test_is_night_hour_boundary_8h_false():
    now = datetime(2026, 4, 20, 23, 0, 0, tzinfo=timezone.utc)
    d = _FakeDevice("Asia/Seoul")
    assert _is_night_hour_for_device(d, now=now) is False
