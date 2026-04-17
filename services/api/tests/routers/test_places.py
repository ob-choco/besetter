from unittest.mock import MagicMock, patch

from tests.conftest import create_test_image


@patch("app.routers.places.bucket")
@patch("app.routers.places.get_base_url", return_value="https://example.com")
def test_upload_place_image_returns_single_url(mock_get_base_url, mock_bucket):
    """_upload_place_image uploads exactly one blob and returns its URL."""
    from app.routers.places import _upload_place_image

    mock_blob = MagicMock()
    mock_bucket.blob.return_value = mock_blob

    content = create_test_image(400, 400)
    url = _upload_place_image(content, ".jpg")

    # Exactly one blob creation (no thumbnail)
    assert mock_bucket.blob.call_count == 1
    call_path = mock_bucket.blob.call_args[0][0]
    assert call_path.startswith("place_images/")
    assert call_path.endswith(".jpg")

    # Exactly one upload_from_string call
    assert mock_blob.upload_from_string.call_count == 1

    # Returned URL is a string pointing at the same blob path
    assert isinstance(url, str)
    assert url == f"https://example.com/{call_path}"


@patch("app.routers.places.bucket")
@patch("app.routers.places.get_base_url", return_value="https://example.com")
def test_upload_place_image_uses_png_content_type(mock_get_base_url, mock_bucket):
    """PNG files should be uploaded with image/png content type."""
    from app.routers.places import _upload_place_image

    mock_blob = MagicMock()
    mock_bucket.blob.return_value = mock_blob

    _upload_place_image(b"fake png bytes", ".png")

    kwargs = mock_blob.upload_from_string.call_args.kwargs
    assert kwargs["content_type"] == "image/png"


def test_place_defaults_to_approved_status():
    """Place() without explicit status defaults to approved — preserves backward
    compatibility when Pydantic hydrates legacy documents that lack the field."""
    from datetime import datetime, timezone
    from bson import ObjectId
    from app.models.place import Place

    # model_construct bypasses Beanie's DB-initialisation guard while still
    # applying Pydantic field defaults for any key not supplied.
    p = Place.model_construct(
        name="Foo",
        normalized_name="foo",
        type="private-gym",
        created_by=ObjectId(),
        created_at=datetime.now(tz=timezone.utc),
    )
    assert p.status == "approved"
    assert p.merged_into_place_id is None
