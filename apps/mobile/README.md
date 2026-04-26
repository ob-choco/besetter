# besetter mobile

Flutter app for besetter. This README captures non-obvious architectural choices and outstanding follow-ups; for verification commands see `CLAUDE.md`.

## API base URL

The app talks to the API at `https://api.besetter.olivebagel.com`. This domain is fronted by Firebase Hosting and rewrites to the Cloud Run service `besetter-api` in `asia-northeast3`. See `apps/web/README.md` for the hosting setup.

The base URL is configurable per build:

```bash
flutter run --dart-define=API_URL=https://other-host.example.com
```

The default (`AuthorizedHttpClient._baseUrl`) uses the production custom domain. A handful of share-link generation sites (`route_card.dart`, `route_list_item.dart`, `recent_climbed_route_card.dart`, `route_viewer.dart`) and the legal/login hosts (`terms_page.dart`, `login.dart`) hardcode the same URL — keep them in sync if you change the production hostname.

## Deep links

Route share URLs use the API base URL: `https://api.besetter.olivebagel.com/share/routes/<id>`. iOS Universal Links and Android App Links should open these in the app.

### iOS — done

`ios/Runner/Runner.entitlements` lists three associated domains:

- `applinks:api.besetter.olivebagel.com` — current production share host
- `applinks:olivebagel.com` — apex domain (reserved for future use)
- `applinks:besetter-api-371038003203.asia-northeast3.run.app` — legacy Cloud Run host (kept so links shared before the domain migration still open the app)

Apple fetches `/.well-known/apple-app-site-association` from each host. For the new domain Firebase Hosting auto-generates an AASA from the iOS app registered in the Firebase project (`Y82F57J2YR.com.olivebagel.besetter`, paths `/*`), so no static file is required. The legacy host serves the AASA from `services/api/app/routers/well_known.py` — note that the team ID there is still a placeholder, so the legacy host has likely never auto-verified; the new domain replaces it.

### Android — TODO (revisit before Play Store release)

Android App Links are **not functional**. The Play Store release is not yet shipped, so this is intentional debt:

- `android/app/build.gradle` release block uses the debug signing config (`signingConfig = signingConfigs.debug`).
- `services/api/app/routers/well_known.py` returns a placeholder SHA-256 fingerprint in `assetlinks.json`.
- Firebase Hosting intercepts `/.well-known/assetlinks.json` and currently returns `[]`, because no Android signing key is registered with the Firebase project.
- `android/app/src/main/AndroidManifest.xml` only lists the legacy `besetter-api-...run.app` host in its app-link intent filter; `api.besetter.olivebagel.com` is not yet declared.

Steps when picking this up:

1. Generate a release keystore and configure `key.properties` + a `release` signingConfig in `android/app/build.gradle`.
2. Run `keytool -list -v -keystore <path>` to extract the SHA-256 cert fingerprint.
3. Register the SHA-256 with the Firebase project (Project Settings → your Android app). Firebase will then emit a real `/.well-known/assetlinks.json` for `api.besetter.olivebagel.com`. Alternatively, place a static `assetlinks.json` under `apps/web/sites/api/public/.well-known/` to override Firebase's auto-generated file.
4. Add an `<intent-filter android:autoVerify="true">` for `api.besetter.olivebagel.com` (path prefix `/share/routes`) to `AndroidManifest.xml`. Keep the legacy run.app entry for backward compatibility with already-shared links.
5. Verify with `adb shell pm get-app-links com.olivebagel.besetter` after installing a signed build.
6. Optional cleanup: update `IOS_TEAM_ID` and `ANDROID_SHA256_FINGERPRINTS` in `services/api/app/routers/well_known.py` with real values, or delete the file entirely and rely on Firebase Hosting's auto-generation.
