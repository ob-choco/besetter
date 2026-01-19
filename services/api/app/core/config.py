from functools import lru_cache
from yaml import load
from yaml import Loader
from pydash import get as pydash_get
from google.cloud import secretmanager


@lru_cache
def get_settings():
    client = secretmanager.SecretManagerServiceClient()
    response = client.access_secret_version(
        request={"name": "projects/371038003203/secrets/api-secret/versions/latest"}
    )
    return load(response.payload.data.decode("UTF-8"), Loader=Loader)


def get(key: str):
    value = pydash_get(get_settings(), key)
    if value is None:
        raise ValueError(f"Could not find key '{key}' in settings.")
    return value
