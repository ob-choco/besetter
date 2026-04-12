from beanie import Document
from pydantic import ConfigDict
from pymongo import IndexModel
import datetime

from . import model_config


class OpenIdNonce(Document):
    model_config = model_config

    type: str
    nonce: str
    created_at: datetime.datetime

    class Settings:
        name = "openIdNonces"
        keep_nulls = True
        indexes = [
            IndexModel("createdAt", expireAfterSeconds=86400),
        ]