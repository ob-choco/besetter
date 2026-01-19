from pydantic import ConfigDict, BaseModel
from pydantic.alias_generators import to_camel as camelize


def to_camel(string: str) -> str:
    if string == "id":
        return "_id"
    return camelize(string)


model_config = ConfigDict(
    alias_generator=to_camel,
    populate_by_name=True,
    arbitrary_types_allowed=True,
)
