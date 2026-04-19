"""Fixtures that spin up an in-memory Mongo (mongomock-motor) and init Beanie.

Overrides the root conftest's ``sys.modules.setdefault("app.core.config", MagicMock())``
for this package: the service tests need the real config module available, but we
still avoid hitting real Mongo by pointing Beanie at a mongomock client.
"""

from __future__ import annotations

import pytest_asyncio
from beanie import init_beanie
from mongomock_motor import AsyncMongoMockClient

from app.models.activity import Activity, UserRouteStats
from app.models.route import Route
from app.models.user import User
from app.models.user_stats import UserStats


@pytest_asyncio.fixture
async def mongo_db():
    client = AsyncMongoMockClient()
    db = client.get_database("besetter-test")
    await init_beanie(
        database=db,
        document_models=[User, Route, Activity, UserRouteStats, UserStats],
    )
    yield db
