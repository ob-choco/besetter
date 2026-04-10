# Thumbnail Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an on-demand thumbnail generation endpoint that serves resized images from GCS with caching.

**Architecture:** Single FastAPI endpoint receives blob path + preset query param, checks GCS for cached thumbnail, generates on first request using Pillow, and returns 302 redirect to the public GCS URL.

**Tech Stack:** FastAPI, Pillow, google-cloud-storage, pytest

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `services/api/pyproject.toml` | Modify | Add test dependencies |
| `services/api/app/services/thumbnail.py` | Create | Preset definitions, path computation, image resize, GCS orchestration |
| `services/api/app/routers/images.py` | Modify | Add `GET /{blob_path:path}` endpoint (must be last route) |
| `services/api/tests/conftest.py` | Create | GCS module mock, test image helper |
| `services/api/tests/services/test_thumbnail.py` | Create | Unit tests for thumbnail service |

---

### Task 1: Set up test infrastructure

**Files:**
- Modify: `services/api/pyproject.toml:36-37`
- Create: `services/api/tests/__init__.py`
- Create: `services/api/tests/services/__init__.py`
- Create: `services/api/tests/conftest.py`

- [ ] **Step 1: Add test dependencies to pyproject.toml**

Replace the empty dev group:

```toml
[dependency-groups]
dev = [
    "pytest>=7.0.0",
]
```

- [ ] **Step 2: Install dev dependencies**

Run: `cd services/api && uv sync --group dev`

- [ ] **Step 3: Create test directory structure**

```bash
mkdir -p services/api/tests/services
touch services/api/tests/__init__.py
touch services/api/tests/services/__init__.py
```

- [ ] **Step 4: Create conftest.py**

```python
# services/api/tests/conftest.py
import sys
from unittest.mock import MagicMock
from io import BytesIO
from PIL import Image as PILImage

# Mock infrastructure modules to avoid Secret Manager / GCS deps in tests
sys.modules.setdefault("app.core.config", MagicMock())
sys.modules.setdefault("app.core.gcs", MagicMock())


def create_test_image(width: int, height: int, color: str = "red") -> bytes:
    """Create a JPEG test image in memory."""
    img = PILImage.new("RGB", (width, height), color=color)
    buffer = BytesIO()
    img.save(buffer, format="JPEG", quality=85)
    return buffer.getvalue()
```

- [ ] **Step 5: Verify pytest runs**

Run: `cd services/api && uv run pytest tests/ -v --co`
Expected: "no tests ran" (collected 0 items)

- [ ] **Step 6: Commit**

```bash
git add services/api/pyproject.toml services/api/tests/
git commit -m "chore: add test infrastructure for thumbnail feature"
```

---

### Task 2: Implement thumbnail path computation and presets

**Files:**
- Create: `services/api/app/services/thumbnail.py`
- Create: `services/api/tests/services/test_thumbnail.py`

- [ ] **Step 1: Write failing tests for compute_thumbnail_path**

```python
# services/api/tests/services/test_thumbnail.py
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_thumbnail.py -v`
Expected: FAIL with ImportError

- [ ] **Step 3: Implement PRESETS and compute_thumbnail_path**

```python
# services/api/app/services/thumbnail.py

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_thumbnail.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add services/api/app/services/thumbnail.py services/api/tests/services/test_thumbnail.py
git commit -m "feat: add thumbnail presets and path computation"
```

---

### Task 3: Implement thumbnail generation (Pillow resize)

**Files:**
- Modify: `services/api/app/services/thumbnail.py`
- Modify: `services/api/tests/services/test_thumbnail.py`

- [ ] **Step 1: Write failing tests for generate_thumbnail**

Append to `tests/services/test_thumbnail.py`:

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_thumbnail.py::test_generate_thumbnail_width_resizes -v`
Expected: FAIL with ImportError

- [ ] **Step 3: Implement generate_thumbnail**

Add to `services/api/app/services/thumbnail.py`:

```python
from io import BytesIO
from PIL import Image as PILImage


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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_thumbnail.py -v`
Expected: 10 passed

- [ ] **Step 5: Commit**

```bash
git add services/api/app/services/thumbnail.py services/api/tests/services/test_thumbnail.py
git commit -m "feat: implement thumbnail generation with Pillow"
```

---

### Task 4: Implement get_or_create_thumbnail (GCS orchestration)

**Files:**
- Modify: `services/api/app/services/thumbnail.py`
- Modify: `services/api/tests/services/test_thumbnail.py`

- [ ] **Step 1: Write failing tests for get_or_create_thumbnail**

Append to `tests/services/test_thumbnail.py`:

```python
from unittest.mock import MagicMock, patch


@patch("app.core.gcs.get_base_url", return_value="https://storage.example.com/bucket")
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


@patch("app.core.gcs.get_base_url", return_value="https://storage.example.com/bucket")
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


@patch("app.core.gcs.get_base_url", return_value="https://storage.example.com/bucket")
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd services/api && uv run pytest tests/services/test_thumbnail.py::test_get_or_create_thumbnail_cached -v`
Expected: FAIL with ImportError

- [ ] **Step 3: Implement get_or_create_thumbnail**

Add to `services/api/app/services/thumbnail.py` (use lazy imports to avoid GCS initialization at import time):

```python
def get_or_create_thumbnail(blob_path: str, preset: str) -> str | None:
    """Check GCS for cached thumbnail, generate if missing.

    Returns the public URL of the thumbnail, or None if the original doesn't exist.
    Raises ValueError if the original is not a valid image.
    """
    from app.core.gcs import bucket, get_base_url

    thumb_path = compute_thumbnail_path(blob_path, preset)
    thumb_blob = bucket.blob(thumb_path)

    if thumb_blob.exists():
        return f"{get_base_url()}/{thumb_path}"

    original_blob = bucket.blob(blob_path)
    if not original_blob.exists():
        return None

    original_bytes = original_blob.download_as_bytes()
    thumb_bytes = generate_thumbnail(original_bytes, preset)
    thumb_blob.upload_from_string(thumb_bytes, content_type="image/jpeg")

    return f"{get_base_url()}/{thumb_path}"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd services/api && uv run pytest tests/services/test_thumbnail.py -v`
Expected: 13 passed

- [ ] **Step 5: Commit**

```bash
git add services/api/app/services/thumbnail.py services/api/tests/services/test_thumbnail.py
git commit -m "feat: implement thumbnail GCS orchestration with caching"
```

---

### Task 5: Implement the endpoint

**Files:**
- Modify: `services/api/app/routers/images.py:1-19` (imports), end of file (new route)

**Important:** This route MUST be defined as the last route in the file. The `{blob_path:path}` converter is greedy and would match routes like `/count` or `/{image_id}` if defined before them.

- [ ] **Step 1: Add imports at the top of images.py**

Add these imports to the existing import block at the top of `services/api/app/routers/images.py`:

```python
from fastapi.responses import RedirectResponse
from app.services.thumbnail import PRESETS, get_or_create_thumbnail
from app.core.gcs import get_base_url as gcs_get_base_url
```

- [ ] **Step 2: Add the endpoint at the end of images.py**

Append after the last existing route (`get_image_count`):

```python
@router.get("/{blob_path:path}")
async def get_image_by_blob_path(
    blob_path: str,
    type: Optional[str] = Query(None, description="Thumbnail preset (w400, s100)"),
):
    """Serve image or thumbnail via redirect to public GCS URL.

    Without ?type: redirects to original image.
    With ?type=<preset>: generates thumbnail on first request, then redirects to cached version.
    """
    if type is None:
        base_url = gcs_get_base_url()
        return RedirectResponse(url=f"{base_url}/{blob_path}", status_code=302)

    if type not in PRESETS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid thumbnail preset: {type}. Valid: {', '.join(PRESETS.keys())}",
        )

    try:
        url = get_or_create_thumbnail(blob_path, type)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    if url is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")

    return RedirectResponse(url=url, status_code=302)
```

- [ ] **Step 3: Verify syntax**

Run: `cd services/api && uv run python -c "import ast; ast.parse(open('app/routers/images.py').read()); print('Syntax OK')"`
Expected: "Syntax OK"

- [ ] **Step 4: Commit**

```bash
git add services/api/app/routers/images.py
git commit -m "feat: add thumbnail redirect endpoint"
```

---

### Task 6: Manual verification

- [ ] **Step 1: Start the API server**

Run: `cd services/api && uv run uvicorn app.main:app --port 8080`

- [ ] **Step 2: Test original redirect (no type param)**

Run: `curl -I "http://localhost:8080/images/wall_images/<EXISTING_BLOB>.jpg"`
Expected: `HTTP 302` with `Location` header pointing to the public GCS URL.

- [ ] **Step 3: Test thumbnail generation (first request)**

Run: `curl -I "http://localhost:8080/images/wall_images/<EXISTING_BLOB>.jpg?type=w400"`
Expected: `HTTP 302` with `Location` pointing to `.../<EXISTING_BLOB>_w400.jpg`. First request takes a moment for generation.

- [ ] **Step 4: Test thumbnail cache hit (second request)**

Run the same curl again. Expected: `HTTP 302` immediately (thumbnail already exists in GCS).

- [ ] **Step 5: Test square crop**

Run: `curl -I "http://localhost:8080/images/place_images/<EXISTING_BLOB>.jpg?type=s100"`
Expected: `HTTP 302` with `Location` pointing to `..._s100.jpg`.

- [ ] **Step 6: Test invalid preset**

Run: `curl -I "http://localhost:8080/images/wall_images/abc.jpg?type=w999"`
Expected: `HTTP 400`

- [ ] **Step 7: Test non-existent blob**

Run: `curl -I "http://localhost:8080/images/wall_images/nonexistent.jpg?type=w400"`
Expected: `HTTP 404`
