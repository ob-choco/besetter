# besetter admin

Local-only Next.js app for operators to review pending gyms and place suggestions.

## Setup

1. `cp .env.local.example .env.local` and fill in credentials.
2. Authenticate to GCP for Secret Manager (`mongodb.url` / `mongodb.name` are
   pulled from `projects/371038003203/secrets/api-secret`):
   ```bash
   gcloud auth application-default login
   ```
3. Ensure MongoDB is running as a replica set (required for MERGE transactions):
   ```bash
   docker run --rm -p 27017:27017 mongo:7 --replSet rs0
   # in another shell:
   docker exec -it <container> mongosh --eval 'rs.initiate()'
   ```
4. `pnpm install`

## Dev loop

```bash
pnpm dev     # http://localhost:3000
pnpm test    # vitest
```

## Auth

Google OAuth restricted to `@olivebagel.com` domain + `ADMIN_EMAIL_ALLOWLIST` env.

## FCM push

Push dispatch is off by default (`ADMIN_FCM_ENABLED=false`). Set to `true` to
actually send to device tokens. Without it, notifications are still inserted
into MongoDB so mobile will see them on next fetch; only push fan-out is
skipped.

## Notification templates

When adding/editing a template, update BOTH:
- `services/api/app/services/notification_templates.py`
- `apps/admin/src/lib/notification-templates.ts`
