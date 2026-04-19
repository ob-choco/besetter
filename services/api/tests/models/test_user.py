"""Tests for User model additions."""

from beanie.odm.fields import PydanticObjectId

from app.models.user import OwnerView


def test_owner_view_serializes_with_camel_case():
    view = OwnerView(
        user_id=PydanticObjectId("507f1f77bcf86cd799439011"),
        profile_id="climber42",
        profile_image_url="https://cdn.example/x.jpg",
        is_deleted=False,
    )
    dumped = view.model_dump(by_alias=True, mode="json")
    assert dumped["userId"] == "507f1f77bcf86cd799439011"
    assert dumped["profileId"] == "climber42"
    assert dumped["profileImageUrl"] == "https://cdn.example/x.jpg"
    assert dumped["isDeleted"] is False


def test_owner_view_deleted_user_defaults():
    view = OwnerView(user_id=PydanticObjectId(), is_deleted=True)
    assert view.profile_id is None
    assert view.profile_image_url is None
    assert view.is_deleted is True
