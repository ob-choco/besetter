from typing import Generator, AsyncGenerator
from app.core.http_session import HttpClient
from datetime import datetime
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from bson import ObjectId
from app.models.user import User
from jose import jwe
import pytz
from app.core.config import get

security = HTTPBearer()

async def get_http_client() -> AsyncGenerator:
    try:
        client = await HttpClient.get_session()
        yield client
    finally:
        await HttpClient.close()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> User:
    try:
        from app.routers.authentications import Claim
        claim = Claim.model_validate_json(jwe.decrypt(credentials.credentials, get("authentication.key")))
        
        if claim.exp < int(datetime.now(tz=pytz.UTC).timestamp()):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="만료된 토큰입니다",
            )
            
        user = await User.find_one(User.id == ObjectId(claim.sub))
        if not user or user.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="유효하지 않은 토큰입니다",
            )
        return user
        
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="유효하지 않은 토큰입니다",
        )
