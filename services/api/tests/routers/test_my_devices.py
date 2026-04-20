from app.routers.my import RegisterDeviceRequest


def test_register_device_request_accepts_timezone():
    body = RegisterDeviceRequest.model_validate({
        "token": "abc",
        "platform": "ios",
        "timezone": "Asia/Seoul",
    })
    assert body.timezone == "Asia/Seoul"


def test_register_device_request_timezone_optional():
    body = RegisterDeviceRequest.model_validate({
        "token": "abc",
        "platform": "ios",
    })
    assert body.timezone is None
