"""
Patch Beanie Document.__init__ so that Document subclasses can be
instantiated in unit tests without a live MongoDB connection.
"""
from unittest.mock import MagicMock, patch
import pytest


@pytest.fixture(autouse=True)
def mock_beanie_collection():
    """Allow Beanie Documents to be constructed without DB initialisation."""
    with patch(
        "beanie.odm.documents.Document.get_pymongo_collection",
        return_value=MagicMock(),
    ):
        yield
