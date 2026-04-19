from app.services.thumbnail import compute_thumbnail_path, PRESETS


def test_presets_defined():
    assert "w400" in PRESETS
    assert "s100" in PRESETS
    assert PRESETS["w400"] == {"mode": "width", "size": 400}
    assert PRESETS["s100"] == {"mode": "square", "size": 100}


def test_compute_thumbnail_path_wall_image():
    assert compute_thumbnail_path("wall_images/abc.jpg", "w400") == "wall_images/abc_w400.jpg"


def test_compute_thumbnail_path_place_image():
    assert compute_thumbnail_path("place_images/xyz.jpg", "s100") == "place_images/xyz_s100.jpg"


def test_compute_thumbnail_path_route_image():
    assert compute_thumbnail_path("route_images/123.jpg", "w400") == "route_images/123_w400.jpg"


from io import BytesIO
import pytest
from PIL import Image as PILImage
from tests.conftest import create_test_image
from app.services.thumbnail import generate_thumbnail


def test_generate_thumbnail_width_resizes():
    image_bytes = create_test_image(800, 600)
    result = generate_thumbnail(image_bytes, "w400")
    img = PILImage.open(BytesIO(result))
    assert img.width == 400
    assert img.height == 300


def test_generate_thumbnail_width_no_upscale():
    image_bytes = create_test_image(200, 150)
    result = generate_thumbnail(image_bytes, "w400")
    img = PILImage.open(BytesIO(result))
    assert img.width == 200
    assert img.height == 150


def test_generate_thumbnail_square_crops_and_resizes():
    image_bytes = create_test_image(800, 600)
    result = generate_thumbnail(image_bytes, "s100")
    img = PILImage.open(BytesIO(result))
    assert img.width == 100
    assert img.height == 100


def test_generate_thumbnail_square_no_upscale():
    image_bytes = create_test_image(80, 60)
    result = generate_thumbnail(image_bytes, "s100")
    img = PILImage.open(BytesIO(result))
    assert img.width == 60
    assert img.height == 60


def test_generate_thumbnail_invalid_image():
    with pytest.raises(ValueError, match="Not a valid image"):
        generate_thumbnail(b"not an image", "w400")


def test_generate_thumbnail_output_is_jpeg():
    image_bytes = create_test_image(800, 600)
    result = generate_thumbnail(image_bytes, "w400")
    img = PILImage.open(BytesIO(result))
    assert img.format == "JPEG"


from unittest.mock import MagicMock, patch


@patch(
    "app.core.gcs.get_public_url",
    side_effect=lambda path: f"https://storage.example.com/bucket/{path}",
)
@patch("app.core.gcs.bucket")
def test_get_or_create_thumbnail_cached(mock_bucket, mock_base_url):
    """When thumbnail already exists in GCS, return URL without generating."""
    from app.services.thumbnail import get_or_create_thumbnail

    mock_blob = MagicMock()
    mock_blob.exists.return_value = True
    mock_bucket.blob.return_value = mock_blob

    result = get_or_create_thumbnail("wall_images/abc.jpg", "w400")

    assert result == "https://storage.example.com/bucket/wall_images/abc_w400.jpg"
    mock_bucket.blob.assert_called_once_with("wall_images/abc_w400.jpg")
    mock_blob.download_as_bytes.assert_not_called()


@patch(
    "app.core.gcs.get_public_url",
    side_effect=lambda path: f"https://storage.example.com/bucket/{path}",
)
@patch("app.core.gcs.bucket")
def test_get_or_create_thumbnail_generates(mock_bucket, mock_base_url):
    """When thumbnail doesn't exist, generate and upload it."""
    from app.services.thumbnail import get_or_create_thumbnail

    thumb_blob = MagicMock()
    thumb_blob.exists.return_value = False
    original_blob = MagicMock()
    original_blob.exists.return_value = True
    original_blob.download_as_bytes.return_value = create_test_image(800, 600)

    def blob_side_effect(path):
        return thumb_blob if "_w400" in path else original_blob
    mock_bucket.blob.side_effect = blob_side_effect

    result = get_or_create_thumbnail("wall_images/abc.jpg", "w400")

    assert result == "https://storage.example.com/bucket/wall_images/abc_w400.jpg"
    thumb_blob.upload_from_string.assert_called_once()
    assert thumb_blob.upload_from_string.call_args.kwargs["content_type"] == "image/jpeg"


@patch(
    "app.core.gcs.get_public_url",
    side_effect=lambda path: f"https://storage.example.com/bucket/{path}",
)
@patch("app.core.gcs.bucket")
def test_get_or_create_thumbnail_original_not_found(mock_bucket, mock_base_url):
    """When original blob doesn't exist, return None."""
    from app.services.thumbnail import get_or_create_thumbnail

    thumb_blob = MagicMock()
    thumb_blob.exists.return_value = False
    original_blob = MagicMock()
    original_blob.exists.return_value = False

    def blob_side_effect(path):
        return thumb_blob if "_w400" in path else original_blob
    mock_bucket.blob.side_effect = blob_side_effect

    result = get_or_create_thumbnail("wall_images/abc.jpg", "w400")
    assert result is None
