from pydantic import ConfigDict, BaseModel
from pydantic.alias_generators import to_camel as camelize
from bson import ObjectId
from beanie.odm.fields import PydanticObjectId


def to_camel(string: str) -> str:
    if string == "id":
        return "_id"
    return camelize(string)


model_config = ConfigDict(
    alias_generator=to_camel,
    populate_by_name=True,
    arbitrary_types_allowed=True,
    json_encoders={ObjectId: str},
)


class IdView(BaseModel):
    model_config = model_config

    id: PydanticObjectId
