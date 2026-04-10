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
