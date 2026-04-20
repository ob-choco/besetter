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
