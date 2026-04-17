# Place Registration Request — Deploy Notes

## Pre-deploy (run BEFORE API deploy)

MongoDB Atlas shell:

```
db.places.updateMany(
  { status: { $exists: false } },
  { $set: { status: "approved" } }
)
```

Reason: the new API filters by `status: "approved"` with exact-match; without this
backfill, existing approved gyms disappear from nearby/instant-search until the
field is present.

## Pre-deploy (optional)

```
db.places.createIndex({ type: 1, status: 1 })
```

Supports the new compound filter.

## Deploy order

1. Run backfill (above).
2. (Optional) Create compound index.
3. Deploy API (`services/api/deploy.sh`).
4. Deploy mobile binaries.

## Smoke checklist (post-deploy)

- [ ] Register a new gym → status=pending, ack notification received.
- [ ] Own pending place visible on nearby / instant-search with "검수중" badge.
- [ ] Pending place "정보 수정" works; guide banner visible.
- [ ] Pending place delete removes place + linked images + routes.
- [ ] DB-flip a place to rejected → upload image with its id → 409 popup, local work preserved.
- [ ] DB-flip a place to merged with a valid target → upload image with its id → success, saved image shows target place.
- [ ] Share URL for a pending place's route → "검수중" badge visible.
