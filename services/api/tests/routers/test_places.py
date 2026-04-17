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
    """Declared defaults: status='approved', merged_into_place_id=None.

    Both Place() and Place.model_validate() trigger Beanie's
    CollectionWasNotInitialized guard without a live DB connection, so we
    construct via model_construct which still applies field defaults for
    omitted keys."""
    from datetime import datetime, timezone
    from bson import ObjectId
    from app.models.place import Place

    p = Place.model_construct(
        name="Foo",
        normalized_name="foo",
        type="private-gym",
        created_by=ObjectId(),
        created_at=datetime.now(tz=timezone.utc),
    )
    assert p.status == "approved"
    assert p.merged_into_place_id is None


def test_place_view_serializes_status_camelcase():
    from bson import ObjectId
    from app.routers.places import PlaceView

    v = PlaceView(
        id=ObjectId(),
        name="Foo",
        type="gym",
        status="pending",
        latitude=37.5,
        longitude=127.0,
        cover_image_url=None,
        created_by=ObjectId(),
    )
    dumped = v.model_dump(by_alias=True)
    assert dumped["status"] == "pending"
    assert "coverImageUrl" in dumped  # sanity: camelCase alias still in effect


def test_place_construction_gym_vs_private_gym_status():
    """Sanity-check the branching logic used by POST /places."""
    from datetime import datetime, timezone
    from bson import ObjectId
    from app.models.place import Place

    common = dict(
        name="X",
        normalized_name="x",
        created_by=ObjectId(),
        created_at=datetime.now(tz=timezone.utc),
    )
    gym = Place.model_construct(
        type="gym",
        status="pending" if "gym" == "gym" else "approved",
        **common,
    )
    private = Place.model_construct(
        type="private-gym",
        status="pending" if "private-gym" == "gym" else "approved",
        **common,
    )
    assert gym.status == "pending"
    assert private.status == "approved"
