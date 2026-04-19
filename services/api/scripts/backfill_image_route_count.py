"""Idempotent backfill for ``Image.routeCount``.

Recomputes ``routeCount`` per image from ``Route.find({imageId, isDeleted!=True})``.
Safe to run repeatedly. Exposes ``backfill_image`` and ``backfill_all`` coroutines
for programmatic use (and tests) plus a ``main`` entry that iterates all images.

Usage:
    python -m scripts.backfill_image_route_count                 # all images
    python -m scripts.backfill_image_route_count --image-id X    # one image
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
from app.models.image import Image
from app.models.route import Route


logger = logging.getLogger(__name__)


async def backfill_image(image_id: PydanticObjectId) -> int:
    """Recompute and set ``routeCount`` for a single image. Returns the new count."""
    count = await Route.get_pymongo_collection().count_documents(
        {"imageId": image_id, "isDeleted": {"$ne": True}}
    )
    await Image.get_pymongo_collection().update_one(
        {"_id": image_id},
        {"$set": {"routeCount": int(count)}},
    )
    return int(count)


async def backfill_all() -> None:
    """Recompute ``routeCount`` for every image.

    Step 1: zero every image so images with no active routes converge to 0.
    Step 2: aggregate active-route counts per imageId and ``$set`` them.
    """
    images = Image.get_pymongo_collection()
    await images.update_many({}, {"$set": {"routeCount": 0}})

    pipeline = [
        {"$match": {"isDeleted": {"$ne": True}}},
        {"$group": {"_id": "$imageId", "count": {"$sum": 1}}},
    ]
    processed = 0
    async for doc in Route.get_pymongo_collection().aggregate(pipeline):
        await images.update_one(
            {"_id": doc["_id"]},
            {"$set": {"routeCount": int(doc["count"])}},
        )
        processed += 1
        if processed % 100 == 0:
            logger.info("backfilled %d images so far", processed)
    logger.info("backfill complete: %d images with active routes", processed)


async def main(image_id: Optional[str] = None) -> None:
    client = AsyncIOMotorClient(get("mongodb.url"), tz_aware=True)
    try:
        db = client.get_database(get("mongodb.name"))
        await init_beanie(database=db, document_models=[Image, Route])

        if image_id is not None:
            count = await backfill_image(PydanticObjectId(image_id))
            logger.info("image %s routeCount=%d", image_id, count)
        else:
            await backfill_all()
    finally:
        client.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser()
    parser.add_argument("--image-id", dest="image_id", default=None)
    args = parser.parse_args()
    asyncio.run(main(args.image_id))
