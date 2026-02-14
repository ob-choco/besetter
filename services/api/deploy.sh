#!/bin/bash
set -e

PROJECT_ID="regal-operand-451709-f4"
REGION="asia-northeast3"
SERVICE_NAME="besetter-api"
IMAGE_NAME="asia-docker.pkg.dev/${PROJECT_ID}/olivebagel/besetter-api"

echo "=== Besetter API - Cloud Run Deploy ==="

cd "$(dirname "$0")"

# 1. gcloud 프로젝트 설정
echo "[1/5] Setting GCP project..."
gcloud config set project ${PROJECT_ID}

# 2. Docker 인증 설정
echo "[2/5] Configuring Docker auth..."
gcloud auth configure-docker asia-docker.pkg.dev --quiet

# 3. 로컬 Docker 이미지 빌드
echo "[3/5] Building Docker image locally..."
docker build --platform linux/amd64 -t ${IMAGE_NAME} .

# 4. 이미지 push
echo "[4/5] Pushing image..."
docker push ${IMAGE_NAME}

# 5. Cloud Run 배포
echo "[5/5] Deploying to Cloud Run..."
gcloud run deploy ${SERVICE_NAME} \
  --image ${IMAGE_NAME} \
  --region ${REGION} \
  --platform managed \
  --port 8080 \
  --allow-unauthenticated \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 0 \
  --max-instances 3 \
  --timeout 300

echo ""
echo "=== Deploy complete! ==="
gcloud run services describe ${SERVICE_NAME} --region ${REGION} --format="value(status.url)"
