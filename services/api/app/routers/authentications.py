from datetime import datetime, timezone, timedelta
from typing import Annotated, Optional
from pathlib import Path
from bson import ObjectId
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status, Body
from beanie.odm.fields import PydanticObjectId


from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from aiohttp import ClientSession, FormData

from app.models.open_id_nonce import OpenIdNonce

from uuid import uuid4

from app.models.user import LineUser, User, AppleUser, GoogleUser, KakaoUser

from jose import jwe, jwt

from pydantic import BaseModel
from humps import camelize

import pytz

import json

from app.models.claim import Claim

from google.oauth2 import id_token
from google.auth.transport.requests import Request

from app.core.config import get
from app.core.profile_id import generate_unique_profile_id
from app.services import telegram_notifier


security = HTTPBearer()


from ..dependencies import get_http_client

router = APIRouter(prefix="/authentications", tags=["authentication"])


def create_access_token(user: User):
    now = int(datetime.now(timezone.utc).timestamp())
    claim = Claim(
        sub=str(user.id),
        exp=now + 60 * 60 * 24 * 365,  # 1 year
        iat=now,
        name=user.name,
        email=user.email,
    )
    return jwe.encrypt(
        json.dumps(claim.model_dump(by_alias=True)),
        get("authentication.key"),
        algorithm="dir",
        encryption="A256GCM",
    )


def create_refresh_token(user: User):
    now = int(datetime.now(timezone.utc).timestamp())
    claim = Claim(
        sub=str(user.id),
        exp=now + 60 * 60 * 24 * 365 * 10,  # 10 years
        iat=now,
        name=user.name,
        email=user.email,
    )
    return jwe.encrypt(
        json.dumps(claim.model_dump(by_alias=True)),
        get("authentication.key"),
        algorithm="dir",
        encryption="A256GCM",
    )


@router.post("/nonces", response_model=OpenIdNonce)
async def create_nonce(type: Annotated[str, Body(embed=True)]):
    now = datetime.now(tz=pytz.UTC)
    nonce = await OpenIdNonce(nonce=str(uuid4()), type=type, created_at=now).save()

    return nonce


class SignInResponse(BaseModel):
    access_token: str
    refresh_token: str

    class Config:
        populate_by_name = True
        alias_generator = camelize


@router.post("/sign-in/line", response_model=SignInResponse)
async def signin(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    http_client: ClientSession = Depends(get_http_client),
):

    access_token = credentials.credentials

    response = await http_client.post(
        "https://api.line.me/oauth2/v2.1/userinfo",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    if response.status != 200:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="라인 토큰이 유효하지 않습니다",
        )

    profile = await response.json()
    unique_id = profile["sub"]
    user = await User.find_one({"line.uniqueId": unique_id})

    if not user:
        # todo email matching 추가
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="회원가입이 필요합니다",
        )

    access_token = create_access_token(user)
    refresh_token = create_refresh_token(user)
    user.refresh_token = refresh_token.decode("utf-8")
    await user.save()
    return SignInResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/sign-up/line", status_code=status.HTTP_201_CREATED)
async def signup(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    background_tasks: BackgroundTasks,
    nonce_id: str = Body(embed=True, alias="nonceId"),
    marketing_push_consent: bool = Body(False, embed=True, alias="marketingPushConsent"),
    http_client: ClientSession = Depends(get_http_client),
):
    nonce = await OpenIdNonce.find_one(OpenIdNonce.id == PydanticObjectId(nonce_id))
    if not nonce:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="유효하지 않은 nonce입니다",
        )
    # id_token={token}&client_id=2006504173 형태로 인코딩됨
    # FormData를 사용하여 데이터 인코딩
    form = FormData()
    form.add_field("nonce", nonce.nonce)
    form.add_field("id_token", credentials.credentials)
    form.add_field("client_id", get("oauth2.line.client_id"))

    response = await http_client.post(
        "https://api.line.me/oauth2/v2.1/verify",
        data=form,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    if response.status != 200:
        print(response.status, await response.json())
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="라인 토큰이 유효하지 않습니다",
        )

    result = await response.json()

    user = await User.find_one({"line.uniqueId": result["sub"]})
    if user:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="이미 가입된 유저입니다",
        )

    now = datetime.now(tz=pytz.UTC)
    profile_id = await generate_unique_profile_id()

    user = User(
        id=ObjectId(),
        profile_id=profile_id,
        line=LineUser(
            unique_id=result["sub"],
            name=result["name"],
            profile_image_url=result.get("picture"),
            email=result.get("email"),
            last_login_at=now,
            signed_up_at=now,
        ),
        name=result["name"],
        email=result.get("email"),
        profile_image_url=result.get("picture"),
        marketing_push_consent=marketing_push_consent,
        marketing_push_consent_at=(now if marketing_push_consent else None),
        marketing_push_consent_source=("signup" if marketing_push_consent else None),
        created_at=now,
        updated_at=now,
    )
    access_token = create_access_token(user)
    refresh_token = create_refresh_token(user)

    user.refresh_token = refresh_token.decode("utf-8")
    await user.save()
    background_tasks.add_task(telegram_notifier.notify_new_user, user, "line")
    return SignInResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/sign-in/kakao", response_model=SignInResponse)
async def signin(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    http_client: ClientSession = Depends(get_http_client),
):

    id_token = credentials.credentials

    form = FormData()
    form.add_field("id_token", id_token)

    response = await http_client.post(
        "https://kauth.kakao.com/oauth/tokeninfo",
        data=form,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    if response.status != 200:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="카카오 토큰이 유효하지 않습니다",
        )

    profile = await response.json()
    unique_id = profile["sub"]
    user = await User.find_one({"kakao.uniqueId": unique_id})

    if not user:
        # todo email matching 추가
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="회원가입이 필요합니다",
        )

    access_token = create_access_token(user)
    refresh_token = create_refresh_token(user)
    user.refresh_token = refresh_token.decode("utf-8")
    await user.save()
    return SignInResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/sign-up/kakao", status_code=status.HTTP_201_CREATED)
async def signup(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    background_tasks: BackgroundTasks,
    marketing_push_consent: bool = Body(False, embed=True, alias="marketingPushConsent"),
    http_client: ClientSession = Depends(get_http_client),
):
    # access-token으로 사용자 정보 가져오기

    access_token = credentials.credentials
    response = await http_client.get(
        "https://kapi.kakao.com/v1/oidc/userinfo",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    if response.status != 200:
        print(response.status, await response.json())
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="카카오 토큰이 유효하지 않습니다",
        )

    result = await response.json()

    user = await User.find_one({"line.uniqueId": result["sub"]})
    if user:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="이미 가입된 유저입니다",
        )

    now = datetime.now(tz=pytz.UTC)
    profile_id = await generate_unique_profile_id()

    user = User(
        id=ObjectId(),
        profile_id=profile_id,
        kakao=KakaoUser(
            unique_id=result["sub"],
            name=result.get("nickname"),
            profile_image_url=result.get("picture"),
            email=result.get("email"),
            last_login_at=now,
            signed_up_at=now,
        ),
        name=result.get("nickname"),
        email=result.get("email"),
        profile_image_url=result.get("picture"),
        marketing_push_consent=marketing_push_consent,
        marketing_push_consent_at=(now if marketing_push_consent else None),
        marketing_push_consent_source=("signup" if marketing_push_consent else None),
        created_at=now,
        updated_at=now,
    )
    access_token = create_access_token(user)
    refresh_token = create_refresh_token(user)

    user.refresh_token = refresh_token.decode("utf-8")
    await user.save()
    background_tasks.add_task(telegram_notifier.notify_new_user, user, "kakao")
    return SignInResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/sign-in/apple")
async def signin_apple(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    http_client: ClientSession = Depends(get_http_client),
):
    # identityToken(jwt) 검증

    # todo use bundle id 확인
    client_id = get("oauth2.apple.bundle_id")

    id_token = credentials.credentials
    headers = {
        "kid": get("oauth2.apple.key_id"),
    }
    payload = jwt.decode(
        id_token,
        "",
        audience=client_id,
        algorithms="RS256",
        options={"verify_signature": False},
    )

    unique_id = payload["sub"]
    user = await User.find_one({"apple.uniqueId": unique_id})
    if not user:
        # todo email matching 추가
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="회원가입이 필요합니다",
        )

    access_token = create_access_token(user)
    refresh_token = create_refresh_token(user)
    user.refresh_token = refresh_token.decode("utf-8")
    await user.save()
    return SignInResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/sign-up/apple", status_code=status.HTTP_201_CREATED)
async def signup_apple(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    background_tasks: BackgroundTasks,
    marketing_push_consent: bool = Body(False, embed=True, alias="marketingPushConsent"),
    http_client: ClientSession = Depends(get_http_client),
):
    # authorization code 검증

    # todo use bundle id 확인
    client_id = get("oauth2.apple.bundle_id")

    headers = {
        "kid": get("oauth2.apple.key_id"),
    }

    payload = {
        "iss": get("oauth2.apple.team_id"),
        "iat": int(datetime.now(tz=pytz.UTC).timestamp()),
        "exp": int(datetime.now(tz=pytz.UTC).timestamp() + 60 * 5),
        "aud": "https://appleid.apple.com",
        "sub": client_id,
    }

    client_secret = jwt.encode(payload, get("oauth2.apple.private_key"), algorithm="ES256", headers=headers)

    form = FormData()
    form.add_field("client_id", client_id)
    form.add_field("client_secret", client_secret)
    form.add_field("code", credentials.credentials)
    form.add_field("grant_type", "authorization_code")
    response = await http_client.post(
        "https://appleid.apple.com/auth/token",
        data=form,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    if response.status != 200:
        print(response.status, await response.json())
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Apple token is invalid",
        )
    result = await response.json()

    id_token = result["id_token"]

    payload = jwt.decode(
        id_token,
        "",
        audience=client_id,
        algorithms="RS256",
        options={"verify_signature": False},
        access_token=result["access_token"],
    )
    unique_id = payload["sub"]

    user = await User.find_one({"apple.uniqueId": unique_id})
    if user:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="이미 가입된 유저입니다",
        )

    now = datetime.now(tz=pytz.UTC)
    profile_id = await generate_unique_profile_id()

    user = User(
        id=ObjectId(),
        profile_id=profile_id,
        apple=AppleUser(
            unique_id=unique_id,
            email=payload.get("email"),
            last_login_at=now,
            signed_up_at=now,
        ),
        email=payload.get("email"),
        marketing_push_consent=marketing_push_consent,
        marketing_push_consent_at=(now if marketing_push_consent else None),
        marketing_push_consent_source=("signup" if marketing_push_consent else None),
        created_at=now,
        updated_at=now,
    )
    access_token = create_access_token(user)
    refresh_token = create_refresh_token(user)

    user.refresh_token = refresh_token.decode("utf-8")
    await user.save()
    background_tasks.add_task(telegram_notifier.notify_new_user, user, "apple")
    return SignInResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/sign-in/google")
async def signin_google(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    http_client: ClientSession = Depends(get_http_client),
):
    # identityToken(jwt) 검증

    token = credentials.credentials

    id_info = id_token.verify_oauth2_token(token, Request(), get("oauth2.google.audience"))

    unique_id = id_info["sub"]
    user = await User.find_one({"google.uniqueId": unique_id})
    if not user:
        # todo email matching 추가
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="회원가입이 필요합니다",
        )

    access_token = create_access_token(user)
    refresh_token = create_refresh_token(user)
    user.refresh_token = refresh_token.decode("utf-8")
    await user.save()
    return SignInResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/sign-up/google", status_code=status.HTTP_201_CREATED)
async def signup_google(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    background_tasks: BackgroundTasks,
    marketing_push_consent: bool = Body(False, embed=True, alias="marketingPushConsent"),
    http_client: ClientSession = Depends(get_http_client),
):
    # identityToken(jwt) 검증

    token = credentials.credentials

    id_info = id_token.verify_oauth2_token(token, Request(), get("oauth2.google.audience"))

    unique_id = id_info["sub"]
    user = await User.find_one({"google.uniqueId": unique_id})
    if user:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="이미 가입된 유저입니다",
        )

    now = datetime.now(tz=pytz.UTC)
    profile_id = await generate_unique_profile_id()

    user = User(
        id=ObjectId(),
        profile_id=profile_id,
        google=GoogleUser(
            unique_id=unique_id,
            email=id_info.get("email"),
            name=id_info.get("name"),
            profile_image_url=id_info.get("picture"),
            last_login_at=now,
            signed_up_at=now,
        ),
        email=id_info.get("email"),
        name=id_info.get("name"),
        profile_image_url=id_info.get("picture"),
        marketing_push_consent=marketing_push_consent,
        marketing_push_consent_at=(now if marketing_push_consent else None),
        marketing_push_consent_source=("signup" if marketing_push_consent else None),
        created_at=now,
        updated_at=now,
    )
    access_token = create_access_token(user)
    refresh_token = create_refresh_token(user)

    user.refresh_token = refresh_token.decode("utf-8")
    await user.save()
    background_tasks.add_task(telegram_notifier.notify_new_user, user, "google")
    return SignInResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/refresh")
async def refresh(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
):
    refresh_token = Claim.model_validate_json(jwe.decrypt(credentials.credentials, get("authentication.key")))

    if refresh_token.exp < int(datetime.now(tz=pytz.UTC).timestamp()):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="만료된 토큰입니다",
        )
    user = await User.find_one(User.id == ObjectId(refresh_token.sub))
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="유효하지 않은 토큰입니다",
        )

    return SignInResponse(access_token=create_access_token(user), refresh_token=credentials.credentials)
