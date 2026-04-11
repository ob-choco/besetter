from google.cloud import storage
from google.oauth2.service_account import Credentials
from datetime import timedelta
from app.core.config import get


# GCS 클라이언트 초기화 함수
def get_gcs_client():
    account_info = get("google_cloud.storage.account_info")
    credentials = Credentials.from_service_account_info(account_info)
    storage_client = storage.Client(
        project=account_info["project_id"],
        credentials=credentials,
    )
    return storage_client


# 버킷 가져오기 함수
def get_bucket():
    client = get_gcs_client()
    bucket_name = get("google_cloud.storage.bucket_name")
    return client.bucket(bucket_name)


def get_base_url():
    return get("google_cloud.storage.base_url")


def get_public_url(blob_path: str) -> str:
    """Return a publicly accessible URL for a GCS blob (for redirects)."""
    bucket_name = get("google_cloud.storage.bucket_name")
    return f"https://storage.googleapis.com/{bucket_name}/{blob_path}"


# 자주 사용하는 인스턴스 미리 생성
storage_client = get_gcs_client()
bucket = get_bucket()


# Signed URL 생성 함수 추가
def generate_signed_url(blob_path, expiration_minutes=5):
    """GCS 객체에 대한 signed URL을 생성합니다.

    Args:
        blob_path (str): 버킷 내 객체 경로 (예: "wall_images/example.jpg")
        expiration_minutes (int): URL 만료 시간(분)

    Returns:
        str: 생성된 signed URL
    """
    blob = bucket.blob(blob_path)
    signed_url = blob.generate_signed_url(
        version="v4",
        expiration=timedelta(minutes=expiration_minutes),
        method="GET",
    )
    return signed_url


# GCS URL에서 blob 경로 추출 함수
def extract_blob_path_from_url(url):
    """GCS URL에서 blob 경로를 추출합니다.

    Args:
        url (str 또는 pydantic.HttpUrl): GCS URL (예: "https://storage.cloud.google.com/besetter/wall_images/example.jpg")

    Returns:
        str: blob 경로 (예: "wall_images/example.jpg")
    """
    # Pydantic URL 객체를 문자열로 변환
    url_str = str(url) if url else ""
    bucket_name = get("google_cloud.storage.bucket_name")
    if not url_str or bucket_name not in url_str:
        return None

    # URL에서 버킷 이름 이후의 경로 추출
    parts = url_str.split(bucket_name + "/")
    if len(parts) < 2:
        return None

    return parts[1]
