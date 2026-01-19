from aiohttp import ClientSession, ClientTimeout
from typing import Optional


class HttpClient:
    _instance: Optional[ClientSession] = None
    _timeout: ClientTimeout = ClientTimeout(total=30)  # 기본 30초 타임아웃

    @classmethod
    async def initialize(cls, timeout_seconds: float = 30):
        """HttpClient 초기화"""
        if cls._instance is None:
            cls._timeout = ClientTimeout(total=timeout_seconds)
            cls._instance = ClientSession(timeout=cls._timeout)
        return cls._instance

    @classmethod
    async def close(cls):
        """세션 종료"""
        if cls._instance is not None:
            await cls._instance.close()
            cls._instance = None

    @classmethod
    async def get_session(cls) -> ClientSession:
        """세션 가져오기"""
        if cls._instance is None:
            await cls.initialize()
        return cls._instance
