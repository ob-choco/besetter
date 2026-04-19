"""Fixtures for backfill-script tests.

Mirrors ``tests/services/conftest.py``: spins up an in-memory Mongo
(``mongomock-motor``) and initialises Beanie with the document models the
backfill script touches. Needed because pytest conftest discovery is
directory-scoped and ``tests/services/conftest.py`` is not visible here.
"""

from __future__ import annotations

import pytest_asyncio
from beanie import init_beanie
from mongomock_motor import AsyncMongoMockClient

from app.models.activity import Activity, UserRouteStats
from app.models.image import Image
from app.models.route import Route
from app.models.user import User
from app.models.user_stats import UserStats


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient()
    db = client.get_database("besetter-test")
    await init_beanie(
        database=db,
        document_models=[User, Route, Activity, UserRouteStats, UserStats, Image],
    )
    yield db
