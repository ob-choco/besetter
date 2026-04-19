"""Idempotent backfill for the ``userStats`` collection.

Recomputes stats from ``activities`` / ``userRouteStats`` / ``routes`` per user.
Safe to run repeatedly. Exposes a ``backfill_user`` coroutine for programmatic
use (and tests) plus a ``main`` entry that iterates all users.

Usage:
    python -m scripts.backfill_user_stats              # all users
    python -m scripts.backfill_user_stats --user-id X  # one user
"""

from __future__ import annotations

import argparse
import asyncio
import logging
from datetime import datetime, timezone
from typing import Optional

from beanie import init_beanie
from beanie.odm.fields import PydanticObjectId
from motor.motor_asyncio import AsyncIOMotorClient

from app.core.config import get
from app.models.activity import Activity, ActivityStatus, UserRouteStats
from app.models.notification import Notification
from app.models.hold_polygon import HoldPolygon
from app.models.image import Image
from app.models.open_id_nonce import OpenIdNonce
from app.models.place import Place, PlaceSuggestion
from app.models.route import Route
from app.models.user import User
from app.models.user_stats import (
    ActivityCounters,
    RoutesCreatedCounters,
    UserStats,
)


logger = logging.getLogger(__name__)


async def _activity_counters(user_id: PydanticObjectId) -> ActivityCounters:
    collection = Activity.get_pymongo_collection()
    pipeline = [
        {"$match": {"userId": user_id}},
        {
            "$group": {
                "_id": None,
                "total": {"$sum": 1},
                "completed": {
                    "$sum": {"$cond": [{"$eq": ["$status", ActivityStatus.COMPLETED.value]}, 1, 0]}
                },
                "verified_completed": {
                    "$sum": {
                        "$cond": [
                            {
                                "$and": [
                                    {"$eq": ["$status", ActivityStatus.COMPLETED.value]},
                                    {"$eq": ["$locationVerified", True]},
                                ]
                            },
                            1,
                            0,
                        ]
                    }
                },
            }
        },
    ]
    async for doc in collection.aggregate(pipeline):
        return ActivityCounters(
            total_count=doc["total"],
            completed_count=doc["completed"],
            verified_completed_count=doc["verified_completed"],
        )
    return ActivityCounters()


async def _distinct_routes_counters(user_id: PydanticObjectId) -> ActivityCounters:
    collection = UserRouteStats.get_pymongo_collection()
    pipeline = [
        {"$match": {"userId": user_id}},
        {
            "$group": {
                "_id": None,
                "total": {"$sum": {"$cond": [{"$gte": ["$totalCount", 1]}, 1, 0]}},
                "completed": {"$sum": {"$cond": [{"$gte": ["$completedCount", 1]}, 1, 0]}},
                "verified_completed": {
                    "$sum": {"$cond": [{"$gte": ["$verifiedCompletedCount", 1]}, 1, 0]}
                },
            }
        },
    ]
    async for doc in collection.aggregate(pipeline):
        return ActivityCounters(
            total_count=doc["total"],
            completed_count=doc["completed"],
            verified_completed_count=doc["verified_completed"],
        )
    return ActivityCounters()


async def _distinct_days(user_id: PydanticObjectId) -> int:
    collection = Activity.get_pymongo_collection()
    pipeline = [
        {"$match": {"userId": user_id}},
        {
            "$addFields": {
                "_localDate": {
                    "$dateToString": {
                        "format": "%Y-%m-%d",
                        "date": "$startedAt",
                        "timezone": {"$ifNull": ["$timezone", "UTC"]},
                    }
                }
            }
        },
        {"$group": {"_id": "$_localDate"}},
        {"$count": "days"},
    ]
    async for doc in collection.aggregate(pipeline):
        return int(doc["days"])
    return 0


async def _own_routes_activity_counters(user_id: PydanticObjectId) -> ActivityCounters:
    collection = UserRouteStats.get_pymongo_collection()
    pipeline = [
        {"$match": {"userId": user_id}},
        {
            "$lookup": {
                "from": "routes",
                "localField": "routeId",
                "foreignField": "_id",
                "as": "route",
            }
        },
        {"$unwind": "$route"},
        {"$match": {"route.userId": user_id, "route.isDeleted": {"$ne": True}}},
        {
            "$group": {
                "_id": None,
                "total": {"$sum": {"$cond": [{"$gte": ["$totalCount", 1]}, 1, 0]}},
                "completed": {"$sum": {"$cond": [{"$gte": ["$completedCount", 1]}, 1, 0]}},
                "verified_completed": {
                    "$sum": {"$cond": [{"$gte": ["$verifiedCompletedCount", 1]}, 1, 0]}
                },
            }
        },
    ]
    async for doc in collection.aggregate(pipeline):
        return ActivityCounters(
            total_count=doc["total"],
            completed_count=doc["completed"],
            verified_completed_count=doc["verified_completed"],
        )
    return ActivityCounters()


async def _routes_created_counters(user_id: PydanticObjectId) -> RoutesCreatedCounters:
    collection = Route.get_pymongo_collection()
    pipeline = [
        {"$match": {"userId": user_id, "isDeleted": {"$ne": True}}},
        {
            "$group": {
                "_id": None,
                "total": {"$sum": 1},
                "bouldering": {"$sum": {"$cond": [{"$eq": ["$type", "bouldering"]}, 1, 0]}},
                "endurance": {"$sum": {"$cond": [{"$eq": ["$type", "endurance"]}, 1, 0]}},
            }
        },
    ]
    async for doc in collection.aggregate(pipeline):
        return RoutesCreatedCounters(
            total_count=doc["total"],
            bouldering_count=doc["bouldering"],
            endurance_count=doc["endurance"],
        )
    return RoutesCreatedCounters()


async def backfill_user(user_id: PydanticObjectId) -> None:
    """Recompute and replace the ``userStats`` document for ``user_id``."""
    activity = await _activity_counters(user_id)
    distinct_routes = await _distinct_routes_counters(user_id)
    distinct_days = await _distinct_days(user_id)
    own_routes_activity = await _own_routes_activity_counters(user_id)
    routes_created = await _routes_created_counters(user_id)

    collection = UserStats.get_pymongo_collection()
    await collection.replace_one(
        {"userId": user_id},
        {
            "userId": user_id,
            "activity": activity.model_dump(by_alias=True),
            "distinctRoutes": distinct_routes.model_dump(by_alias=True),
            "distinctDays": distinct_days,
            "ownRoutesActivity": own_routes_activity.model_dump(by_alias=True),
            "routesCreated": routes_created.model_dump(by_alias=True),
            "updatedAt": datetime.now(tz=timezone.utc),
        },
        upsert=True,
    )


async def backfill_all() -> None:
    processed = 0
    async for user in User.find_all():
        await backfill_user(user.id)
        processed += 1
        if processed % 50 == 0:
            logger.info("backfilled %d users so far", processed)
    logger.info("backfill complete: %d users", processed)


async def main(user_id: Optional[str] = None) -> None:
    client = AsyncIOMotorClient(get("mongodb.url"), tz_aware=True)
    db = client.get_database(get("mongodb.name"))
    await init_beanie(
        database=db,
        document_models=[
            OpenIdNonce,
            User,
            HoldPolygon,
            Image,
            Route,
            Place,
            PlaceSuggestion,
            Activity,
            UserRouteStats,
            Notification,
            UserStats,
        ],
    )

    if user_id is not None:
        await backfill_user(PydanticObjectId(user_id))
    else:
        await backfill_all()

    client.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser()
    parser.add_argument("--user-id", dest="user_id", default=None)
    args = parser.parse_args()
    asyncio.run(main(args.user_id))
