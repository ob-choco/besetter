"""Render notifications for a given locale.

- `pick_locale` picks the first supported primary subtag in an Accept-Language
  header, else the default locale.
- `render` returns `(title, body)`. For records with non-empty `params`, it
  formats the type/locale template; otherwise it returns the stored
  `title`/`body` (backwards compatibility for records created before this
  feature).
"""
from typing import Any

from app.services.notification_templates import (
    DEFAULT_LOCALE,
    SUPPORTED_LOCALES,
    TEMPLATES,
)


def pick_locale(accept_language: str | None) -> str:
    """Return the first supported primary subtag in the header, else default.

    Very small parser: splits on commas and semicolons, lowercases, takes the
    primary subtag before any hyphen, ignores quality values. Good enough for
    our four-locale set.
    """
    if not accept_language:
        return DEFAULT_LOCALE
    for raw in accept_language.split(","):
        tag = raw.split(";", 1)[0].strip().lower()
        if not tag:
            continue
        primary = tag.split("-", 1)[0]
        if primary in SUPPORTED_LOCALES:
            return primary
    return DEFAULT_LOCALE


def _render_field(
    type_: str,
    field: str,
    locale: str,
    params: dict[str, Any],
    stored: str,
) -> str:
    by_field = TEMPLATES.get(type_)
    if not by_field:
        return stored
    by_locale = by_field.get(field, {})
    template = by_locale.get(locale) or by_locale.get(DEFAULT_LOCALE)
    if not template:
        return stored
    try:
        return template.format(**params)
    except (KeyError, IndexError):
        return stored


def render(notif, locale: str) -> tuple[str, str]:
    """Render (title, body) for a notification in the given locale.

    Returns stored title/body unchanged if the record has no params (old
    records created before this feature were pre-rendered in Korean).
    """
    params = getattr(notif, "params", None) or {}
    if not params:
        return notif.title, notif.body
    title = _render_field(notif.type, "title", locale, params, notif.title)
    body = _render_field(notif.type, "body", locale, params, notif.body)
    return title, body
