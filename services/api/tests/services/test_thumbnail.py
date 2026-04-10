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
