from app.core.geo import haversine_distance


def test_haversine_same_point():
    assert haversine_distance(37.5665, 126.9780, 37.5665, 126.9780) == 0.0


def test_haversine_known_distance():
    d = haversine_distance(37.5665, 126.9780, 37.4979, 127.0276)
    assert 8700 < d < 9100


def test_haversine_short_distance():
    d = haversine_distance(37.5665, 126.9780, 37.5674, 126.9780)
    assert 90 < d < 110


def test_haversine_returns_metres():
    d = haversine_distance(35.6762, 139.6503, 34.6937, 135.5023)
    assert 390_000 < d < 405_000
