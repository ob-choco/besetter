# services/api/tests/conftest.py
import sys
from unittest.mock import MagicMock
from io import BytesIO
from PIL import Image as PILImage

# Mock infrastructure modules to avoid Secret Manager / GCS deps in tests
sys.modules.setdefault("app.core.config", MagicMock())
_gcs_mock = MagicMock()
sys.modules.setdefault("app.core.gcs", _gcs_mock)

# Ensure app.core has a .gcs attribute so @patch("app.core.gcs.*") resolves correctly
import app.core as _app_core
if not hasattr(_app_core, "gcs"):
    _app_core.gcs = sys.modules["app.core.gcs"]


def create_test_image(width: int, height: int, color: str = "red") -> bytes:
    """Create a JPEG test image in memory."""
    img = PILImage.new("RGB", (width, height), color=color)
    buffer = BytesIO()
    img.save(buffer, format="JPEG", quality=85)
    return buffer.getvalue()
