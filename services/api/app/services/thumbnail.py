PRESETS = {
    "w400": {"mode": "width", "size": 400},
    "s100": {"mode": "square", "size": 100},
}


def compute_thumbnail_path(blob_path: str, preset: str) -> str:
    """Compute the GCS blob path for a thumbnail.

    Example: wall_images/abc.jpg + w400 -> wall_images/abc_w400.jpg
    """
    dot_idx = blob_path.rfind(".")
    if dot_idx == -1:
        return f"{blob_path}_{preset}"
    return f"{blob_path[:dot_idx]}_{preset}{blob_path[dot_idx:]}"
