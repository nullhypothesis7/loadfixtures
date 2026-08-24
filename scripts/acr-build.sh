#!/usr/bin/env bash
# Build the testfixtures Docker image and push it to ACR.
# Run this before azure-deploy.sh whenever source code changes.
#
# Usage:
#   ./scripts/acr-build.sh [IMAGE_TAG]
#
# IMAGE_TAG defaults to the short git SHA of HEAD.
# Passing "latest" is fine for ad-hoc dev deployments.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform"
IMAGE_TAG="${1:-$(git -C "${REPO_ROOT}" rev-parse --short HEAD)}"

echo "Reading ACR login server from terraform output..."
cd "${TF_DIR}"
ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)

echo "Logging in to ACR: ${ACR_LOGIN_SERVER}"
az acr login --name "${ACR_LOGIN_SERVER%%.*}"

IMAGE="${ACR_LOGIN_SERVER}/testfixtures:${IMAGE_TAG}"
LATEST="${ACR_LOGIN_SERVER}/testfixtures:latest"

echo ""
echo "Building image: ${IMAGE}"
cd "${REPO_ROOT}"
docker build \
  --platform linux/amd64 \
  --tag "${IMAGE}" \
  --tag "${LATEST}" \
  .

echo ""
echo "Pushing ${IMAGE}..."
docker push "${IMAGE}"
docker push "${LATEST}"

echo ""
echo "Done. Image available at:"
echo "  ${IMAGE}"
echo "  ${LATEST}"
echo ""
echo "Next step:"
echo "  ./scripts/azure-deploy.sh ${IMAGE_TAG}"
