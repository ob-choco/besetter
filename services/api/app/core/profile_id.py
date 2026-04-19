"""profile_id validation, generation, and availability helpers.

Used by:
- sign-up paths (authentications.py) — assign random id at user creation
- PATCH /users/me/profile-id — user-driven edits
- GET availability endpoint — real-time UX
- backfill script — one-shot migration
"""

from __future__ import annotations

import re
import secrets
from enum import Enum
from typing import Optional

from app.core.profile_id_reserved import PROFANITY_SUBSTRINGS, RESERVED_EXACT
from app.models.user import User


class ProfileIdError(str, Enum):
    TOO_SHORT = "PROFILE_ID_TOO_SHORT"
    TOO_LONG = "PROFILE_ID_TOO_LONG"
    INVALID_CHARS = "PROFILE_ID_INVALID_CHARS"
    INVALID_START_END = "PROFILE_ID_INVALID_START_END"
    CONSECUTIVE_SPECIAL = "PROFILE_ID_CONSECUTIVE_SPECIAL"
    RESERVED = "PROFILE_ID_RESERVED"
    TAKEN = "PROFILE_ID_TAKEN"


# 헷갈리는 문자 제외: 0, o, 1, l, i
_ALPHABET: str = "abcdefghjkmnpqrstuvwxyz23456789"
_AUTOGEN_LENGTH: int = 12
_MIN_LENGTH: int = 8
_MAX_LENGTH: int = 16

_ALLOWED_CHARS_RE = re.compile(r"^[a-z0-9._]+$")
_ALPHANUM_RE = re.compile(r"[a-z0-9]")
_CONSECUTIVE_SPECIAL_RE = re.compile(r"[._]{2}")


def generate_profile_id() -> str:
    """Return a random 12-char profile_id from the safe alphabet."""
    return "".join(secrets.choice(_ALPHABET) for _ in range(_AUTOGEN_LENGTH))


def _contains_profanity(value: str) -> bool:
    return any(bad in value for bad in PROFANITY_SUBSTRINGS)


def validate_profile_id(value: str) -> Optional[ProfileIdError]:
    """Return the first validation error, or None if the value is valid."""
    if len(value) < _MIN_LENGTH:
        return ProfileIdError.TOO_SHORT
    if len(value) > _MAX_LENGTH:
        return ProfileIdError.TOO_LONG
    if not _ALLOWED_CHARS_RE.match(value):
        return ProfileIdError.INVALID_CHARS
    if not _ALPHANUM_RE.match(value[0]) or not _ALPHANUM_RE.match(value[-1]):
        return ProfileIdError.INVALID_START_END
    if _CONSECUTIVE_SPECIAL_RE.search(value):
        return ProfileIdError.CONSECUTIVE_SPECIAL
    if value in RESERVED_EXACT or _contains_profanity(value):
        return ProfileIdError.RESERVED
    return None


async def generate_unique_profile_id(max_attempts: int = 5) -> str:
    """Return a random profile_id that isn't taken yet.

    Retries on collision (or on accidental profanity match). Raises if we
    can't find a free value within max_attempts.
    """
    for _ in range(max_attempts):
        candidate = generate_profile_id()
        if _contains_profanity(candidate):
            continue
        existing = await User.find_one({"profileId": candidate})
        if existing is None:
            return candidate
    raise RuntimeError("Failed to generate unique profile_id")
