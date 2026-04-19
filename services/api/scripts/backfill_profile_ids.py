"""One-shot backfill: assign a profile_id to every user that lacks one.

Run BEFORE deploying the new User model (which requires profile_id). After this
completes, deploy — Beanie will then create the unique index for profileId.

Bypasses Beanie: the new User model would fail Pydantic validation on legacy
documents that lack profileId. Raw motor updates only the profileId field.

Idempotent: restricts to `{profileId: {$exists: False}}` so re-runs skip done users.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

from motor.motor_asyncio import AsyncIOMotorClient

from app.core.config import get
from app.core.profile_id import _contains_profanity, generate_profile_id

log = logging.getLogger(__name__)


async def main() -> None:
    client = AsyncIOMotorClient(get("mongodb.url"))
    db = client[get("mongodb.name")]
    users = db["users"]

    cursor = users.find({"profileId": {"$exists": False}}, {"_id": 1})
    processed = 0
    failed = 0

    async for doc in cursor:
        for _ in range(10):
            candidate = generate_profile_id()
            if _contains_profanity(candidate):
                continue
            if await users.find_one({"profileId": candidate}, {"_id": 1}):
                continue
            await users.update_one(
                {"_id": doc["_id"]},
                {
                    "$set": {
                        "profileId": candidate,
                        "updatedAt": datetime.now(tz=timezone.utc),
                    }
                },
            )
            processed += 1
            break
        else:
            log.error("Failed to assign profileId for user %s", doc["_id"])
            failed += 1

    log.info("Backfilled %d users (%d failed)", processed, failed)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
