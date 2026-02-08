from fastapi import APIRouter
from fastapi.responses import JSONResponse

router = APIRouter(prefix="/.well-known", tags=["well-known"])

# iOS App 정보 - TODO: 실제 값으로 교체
IOS_TEAM_ID = "XXXXXXXXXX"  # Apple Developer Team ID
IOS_BUNDLE_ID = "com.olivebagel.besetter"

# Android App 정보 - TODO: 실제 값으로 교체
ANDROID_PACKAGE_NAME = "com.olivebagel.besetter"
ANDROID_SHA256_FINGERPRINTS = [
    "XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX"
]


@router.get("/apple-app-site-association")
async def apple_app_site_association():
    """iOS Universal Links를 위한 AASA 파일"""
    return JSONResponse(
        content={
            "applinks": {
                "apps": [],
                "details": [
                    {
                        "appID": f"{IOS_TEAM_ID}.{IOS_BUNDLE_ID}",
                        "paths": ["/share/routes/*"],
                    }
                ],
            }
        },
        media_type="application/json",
    )


@router.get("/assetlinks.json")
async def asset_links():
    """Android App Links를 위한 assetlinks.json 파일"""
    return JSONResponse(
        content=[
            {
                "relation": ["delegate_permission/common.handle_all_urls"],
                "target": {
                    "namespace": "android_app",
                    "package_name": ANDROID_PACKAGE_NAME,
                    "sha256_cert_fingerprints": ANDROID_SHA256_FINGERPRINTS,
                },
            }
        ],
        media_type="application/json",
    )
