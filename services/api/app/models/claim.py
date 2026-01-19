from pydantic import BaseModel
from typing import Optional
from humps import camelize

from . import model_config


class Claim(BaseModel):
    model_config = model_config

    sub: str
    exp: int
    iat: int

    name: Optional[str] = None
    email: Optional[str] = None
