from app.routers.users import UserProfileResponse


def test_user_profile_response_has_consent_fields():
    fields = set(UserProfileResponse.model_fields.keys())
    assert "marketing_push_consent" in fields
    assert "marketing_push_consent_at" in fields
    assert "marketing_push_consent_source" in fields


def test_user_profile_response_camelcases_consent_fields():
    resp = UserProfileResponse(
        id="x",
        profile_id="p",
        marketing_push_consent=True,
        marketing_push_consent_at=None,
        marketing_push_consent_source="signup",
    )
    dumped = resp.model_dump(by_alias=True)
    assert dumped["marketingPushConsent"] is True
    assert dumped["marketingPushConsentSource"] == "signup"
