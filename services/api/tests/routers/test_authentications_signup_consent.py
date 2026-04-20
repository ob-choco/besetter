"""Signature-level check: /sign-up/* routes declare marketingPushConsent.

Touches only the router declarations, not the full OAuth flows.
"""
from fastapi.routing import APIRoute

from app.routers.authentications import router


_PATHS = {
    "/authentications/sign-up/line",
    "/authentications/sign-up/kakao",
    "/authentications/sign-up/apple",
    "/authentications/sign-up/google",
}


def test_all_signup_routes_declare_marketing_consent_body():
    routes = {r.path: r for r in router.routes if isinstance(r, APIRoute)}
    for path in _PATHS:
        assert path in routes, f"missing route {path}"
        r = routes[path]
        param_names = {p.name for p in r.dependant.body_params}
        assert "marketing_push_consent" in param_names, (
            f"{path} is missing marketingPushConsent body param; got {param_names}"
        )
