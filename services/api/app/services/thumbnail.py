from io import BytesIO
from PIL import Image as PILImage

PRESETS = {
    "w400": {"mode": "width", "size": 400},
    "s100": {"mode": "square", "size": 100},
}


def generate_thumbnail(image_bytes: bytes, preset: str) -> bytes:
    """Resize image bytes according to preset, return JPEG bytes."""
    config = PRESETS[preset]

    try:
        img = PILImage.open(BytesIO(image_bytes))
    except Exception:
        raise ValueError("Not a valid image file")

    if img.mode != "RGB":
        img = img.convert("RGB")

    if config["mode"] == "width":
        target_w = config["size"]
        if img.width > target_w:
            ratio = target_w / img.width
            target_h = int(img.height * ratio)
            img = img.resize((target_w, target_h), PILImage.Resampling.LANCZOS)

    elif config["mode"] == "square":
        target_size = config["size"]
        w, h = img.size
        min_dim = min(w, h)
        left = (w - min_dim) // 2
        top = (h - min_dim) // 2
        img = img.crop((left, top, left + min_dim, top + min_dim))
        if min_dim > target_size:
            img = img.resize((target_size, target_size), PILImage.Resampling.LANCZOS)

    output = BytesIO()
    img.save(output, format="JPEG", quality=85)
    return output.getvalue()


def compute_thumbnail_path(blob_path: str, preset: str) -> str:
    """Compute the GCS blob path for a thumbnail.

    Example: wall_images/abc.jpg + w400 -> wall_images/abc_w400.jpg
    """
    dot_idx = blob_path.rfind(".")
    if dot_idx == -1:
        return f"{blob_path}_{preset}"
    return f"{blob_path[:dot_idx]}_{preset}{blob_path[dot_idx:]}"
