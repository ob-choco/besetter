"""Idempotent backfill for ``routes.completerStats``.

Recomputes per-route distinct-user counters from ``userRouteStats``. Safe to run
repeatedly. Exposes ``backfill_route`` for programmatic use (and tests) plus a
``main`` entry that iterates all routes.

Usage:
    python -m scripts.backfill_route_completer_stats                 # all routes
    python -m scripts.backfill_route_completer_stats --route-id X    # one route
"""

from __future__ import annotations

import argparse
import asyncio
import logging
from typing import Optional

from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from motor.motor_asyncio import AsyncIOMotorClient

from app.core.config import get
from app.models.activity import Activity, UserRouteStats
from app.models.hold_polygon import HoldPolygon
from app.models.image import Image
from app.models.notification import Notification
from app.models.open_id_nonce import OpenIdNonce
from app.models.place import Place, PlaceSuggestion
from app.models.route import Route
from app.models.user import User
from app.models.user_stats import UserStats


logger = logging.getLogger(__name__)


async def _compute_counts(route_id: PydanticObjectId) -> tuple[int, int, int]:
    collection = UserRouteStats.get_pymongo_collection()
    pipeline = [
        {"$match": {"routeId": route_id}},
        {
            "$group": {
                "_id": None,
                "participant": {"$sum": {"$cond": [{"$gte": ["$totalCount", 1]}, 1, 0]}},
                "completer": {"$sum": {"$cond": [{"$gte": ["$completedCount", 1]}, 1, 0]}},
                "verified": {"$sum": {"$cond": [{"$gte": ["$verifiedCompletedCount", 1]}, 1, 0]}},
            }
        },
    ]
    async for doc in collection.aggregate(pipeline):
        return int(doc["participant"]), int(doc["completer"]), int(doc["verified"])
    return 0, 0, 0


async def backfill_route(route_id: PydanticObjectId) -> None:
    """Recompute and $set ``completerStats`` for one route."""
    participant, completer, verified = await _compute_counts(route_id)
    await Route.get_pymongo_collection().update_one(
        {"_id": route_id},
        {"$set": {
            "completerStats.participantCount": participant,
            "completerStats.completerCount": completer,
            "completerStats.verifiedCompleterCount": verified,
        }},
    )


async def backfill_all() -> None:
    processed = 0
    async for route in Route.find_all():
        await backfill_route(route.id)
        processed += 1
        if processed % 100 == 0:
            logger.info("backfilled %d routes so far", processed)
    logger.info("backfill complete: %d routes", processed)


async def main(route_id: Optional[str] = None) -> None:
    client = AsyncIOMotorClient(get("mongodb.url"), tz_aware=True)
    try:
        db = client.get_database(get("mongodb.name"))
        await init_beanie(
            database=db,
            document_models=[
                OpenIdNonce, User, HoldPolygon, Image, Route, Place, PlaceSuggestion,
                Activity, UserRouteStats, Notification, UserStats,
            ],
        )
        if route_id is not None:
            await backfill_route(PydanticObjectId(route_id))
        else:
            await backfill_all()
    finally:
        client.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser()
    parser.add_argument("--route-id", dest="route_id", default=None)
    args = parser.parse_args()
    asyncio.run(main(args.route_id))
