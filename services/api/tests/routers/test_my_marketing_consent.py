from app.routers.my import MarketingConsentRequest


def test_marketing_consent_request_true():
    body = MarketingConsentRequest.model_validate({"consent": True})
    assert body.consent is True


def test_marketing_consent_request_false():
    body = MarketingConsentRequest.model_validate({"consent": False})
    assert body.consent is False


def test_marketing_consent_request_missing_rejected():
    import pytest as _pytest
    from pydantic import ValidationError
    with _pytest.raises(ValidationError):
        MarketingConsentRequest.model_validate({})
