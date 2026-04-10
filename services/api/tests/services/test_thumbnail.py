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
