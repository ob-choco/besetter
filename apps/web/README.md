# apps/web

Firebase Hosting configuration that fronts custom domains (`*.olivebagel.com`) over backend services such as Cloud Run.

## Why this exists

Cloud Run's default URL (`besetter-api-<hash>-an.a.run.app`) is owned by Google and changes when the service name, region, or project changes. To keep the mobile app's API base URL stable across infrastructure changes, traffic is routed through a domain we own (`api.besetter.olivebagel.com`).

Cloud Run's native domain mapping does not support `asia-northeast3` (Seoul), so Firebase Hosting acts as the fronting layer instead.

## Request flow

```
Mobile app
  └─ https://api.besetter.olivebagel.com/...
      └─ Cloudflare DNS  → A 199.36.158.100
          └─ Firebase Hosting (CDN edge, SSL)
              └─ rewrite to Cloud Run service `besetter-api` (asia-northeast3)
```

The Hosting → Cloud Run hop runs over Google's internal network, so egress is only billed once at the edge.

## File layout

```
apps/web/
├── firebase.json          # Hosting site definitions, rewrite rules
├── .firebaserc            # Firebase project + hosting target mapping
└── sites/
    └── api/
        └── public/
            └── index.html # Placeholder; rewrite-all means it is rarely served
```

`firebase.json` defines one site per Hosting target. Add a new entry under `hosting[]` to add a site (e.g. `web`, `admin`).

## Firebase project

- Project ID: `regal-operand-451709-f4`
- Hosting site ID: `besetter-api`
- Default URLs: `besetter-api.web.app`, `besetter-api.firebaseapp.com`
- Custom domain: `api.besetter.olivebagel.com`

## DNS configuration

The domain `olivebagel.com` is registered on Squarespace but its nameservers point to Cloudflare (`faye.ns.cloudflare.com`, `eric.ns.cloudflare.com`). All DNS records must be edited in Cloudflare; records added in the Squarespace UI are silently ignored.

Records added for `api.besetter.olivebagel.com`:

| Type | Name                          | Value                                | Proxy        | Purpose                                        |
| ---- | ----------------------------- | ------------------------------------ | ------------ | ---------------------------------------------- |
| TXT  | `api.besetter`                | `hosting-site=besetter-api`          | n/a          | Firebase domain ownership verification         |
| TXT  | `_acme-challenge.api.besetter`| `<random>` (issued by Firebase)      | n/a          | Let's Encrypt ACME DNS-01 challenge for SSL    |
| A    | `api.besetter`                | `199.36.158.100`                     | DNS only ⚠️ | Points the hostname at Firebase Hosting        |

The A record's proxy status must be **DNS only (gray cloud)**. Cloudflare proxy mode breaks the SSL handshake with Firebase Hosting.

The two TXT records can be removed after the certificate is issued, but keeping them is harmless and protects against re-verification flows.

## Deploy

Requires Firebase CLI (`npm i -g firebase-tools`) and a logged-in account with access to the project.

```bash
cd apps/web
firebase deploy --only hosting:api
```

Verify the deploy with the default URL first, then the custom domain:

```bash
curl -i https://besetter-api.web.app/<endpoint>
curl -i https://api.besetter.olivebagel.com/<endpoint>
```

## Deep link manifests (`/.well-known/...`)

Firebase Hosting intercepts `/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json` before applying the rewrite, so Cloud Run's responses for these paths are not reachable through the custom domain. Firebase auto-generates them from the iOS/Android apps registered in the Firebase project:

- iOS AASA includes the real bundle (`Y82F57J2YR.com.olivebagel.besetter`) with path `/*`, which is sufficient for the app's `/share/routes/*` Universal Links.
- Android `assetlinks.json` is currently `[]` because no Android signing key is registered with Firebase; App Links won't auto-verify until that's fixed (see `apps/mobile/README.md`).

To override Firebase's auto-generated file, place a static file at `sites/api/public/.well-known/<filename>` and redeploy.

## Adding another site (e.g. web, admin)

1. Create a new Hosting site in the Firebase console (e.g. `besetter-web`).
2. Append a target in `.firebaserc`:
   ```json
   "hosting": { "api": ["besetter-api"], "web": ["besetter-web"] }
   ```
3. Append a hosting entry in `firebase.json` with `target`, `public`, and `rewrites`.
4. Create the public directory (`sites/web/public/`) and put the build output there.
5. Add DNS records in Cloudflare for the new hostname (TXT verification, ACME challenge, then A record with **DNS only**).
6. Attach the custom domain in the Firebase console.
7. Deploy: `firebase deploy --only hosting:web`.
