"""Tests for profile_id validation and generation."""

from unittest.mock import AsyncMock, patch

import pytest

from app.core.profile_id import (
    ProfileIdError,
    generate_profile_id,
    generate_unique_profile_id,
    validate_profile_id,
)


def test_profile_id_error_codes_are_stable_strings():
    """ProfileIdError enum values are used in HTTP responses; must be stable."""
    assert ProfileIdError.TOO_SHORT.value == "PROFILE_ID_TOO_SHORT"
    assert ProfileIdError.TOO_LONG.value == "PROFILE_ID_TOO_LONG"
    assert ProfileIdError.INVALID_CHARS.value == "PROFILE_ID_INVALID_CHARS"
    assert ProfileIdError.INVALID_START_END.value == "PROFILE_ID_INVALID_START_END"
    assert ProfileIdError.CONSECUTIVE_SPECIAL.value == "PROFILE_ID_CONSECUTIVE_SPECIAL"
    assert ProfileIdError.RESERVED.value == "PROFILE_ID_RESERVED"
    assert ProfileIdError.TAKEN.value == "PROFILE_ID_TAKEN"


@pytest.mark.parametrize(
    "value",
    [
        "climber99",
        "climber_99",
        "climb.er99",
        "abcdef",                             # 6 chars exact (min)
        "abcdefghij0123456789abcdefghij",     # 30 chars exact (max)
        "a1b2c3d4",
    ],
)
def test_validate_accepts_valid_values(value):
    assert validate_profile_id(value) is None


def test_validate_too_short():
    assert validate_profile_id("abc12") is ProfileIdError.TOO_SHORT


def test_validate_too_long():
    assert validate_profile_id("a" * 31) is ProfileIdError.TOO_LONG


@pytest.mark.parametrize("value", ["Climber99", "climber-99", "climber 99", "한글이름abcd", "user@namee"])
def test_validate_invalid_chars(value):
    assert validate_profile_id(value) is ProfileIdError.INVALID_CHARS


@pytest.mark.parametrize("value", ["_climber9", "9climber_", ".climber9", "climber9."])
def test_validate_invalid_start_end(value):
    assert validate_profile_id(value) is ProfileIdError.INVALID_START_END


@pytest.mark.parametrize("value", ["clim__ber", "clim..ber", "clim._ber", "clim_.ber"])
def test_validate_consecutive_special(value):
    assert validate_profile_id(value) is ProfileIdError.CONSECUTIVE_SPECIAL


@pytest.mark.parametrize("value", ["admin123", "climber99"])
def test_validate_accepts_substring_of_reserved(value):
    """`admin` is reserved (exact) but `admin123` is not."""
    assert validate_profile_id(value) is None


@pytest.mark.parametrize("value", ["besetter", "helpdesk", "climbing"])
def test_validate_reserved_exact_blocked(value):
    """Exact matches of reserved words (length >= 6) are blocked."""
    assert validate_profile_id(value) is ProfileIdError.RESERVED


def test_validate_profanity_substring():
    """Profanity is blocked by substring match (unlike exact-match reserved)."""
    assert validate_profile_id("fuck1234") is ProfileIdError.RESERVED
    assert validate_profile_id("abcshitab") is ProfileIdError.RESERVED


def test_generate_profile_id_length_and_charset():
    for _ in range(50):
        value = generate_profile_id()
        assert len(value) == 12
        assert validate_profile_id(value) is None  # autogen values always valid


def test_generate_profile_id_is_random():
    seen = {generate_profile_id() for _ in range(100)}
    # With 31^12 entropy, 100 samples should never collide.
    assert len(seen) == 100


async def test_generate_unique_profile_id_first_try():
    """Returns the first candidate when not taken."""
    with patch("app.core.profile_id.User") as MockUser:
        MockUser.find_one = AsyncMock(return_value=None)
        result = await generate_unique_profile_id()
        assert len(result) == 12
        MockUser.find_one.assert_awaited_once()


async def test_generate_unique_profile_id_retries_on_collision():
    """Retries when find_one returns an existing user."""
    existing = object()
    with patch("app.core.profile_id.User") as MockUser:
        MockUser.find_one = AsyncMock(side_effect=[existing, existing, None])
        result = await generate_unique_profile_id()
        assert len(result) == 12
        assert MockUser.find_one.await_count == 3


async def test_generate_unique_profile_id_exhaustion_raises():
    """Raises after max_attempts collisions."""
    existing = object()
    with patch("app.core.profile_id.User") as MockUser:
        MockUser.find_one = AsyncMock(return_value=existing)
        with pytest.raises(RuntimeError, match="Failed to generate unique"):
            await generate_unique_profile_id(max_attempts=3)
