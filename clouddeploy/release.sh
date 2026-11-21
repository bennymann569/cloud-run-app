#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
REGION="${GCP_REGION:?GCP_REGION is required}"
PIPELINE="${CLOUD_DEPLOY_PIPELINE:-cloud-run-app}"
TARGET="${1:?Usage: release.sh <dev|staging|prod> <image-uri>}"
IMAGE="${2:?Usage: release.sh <dev|staging|prod> <image-uri>}"
COMMIT_SHA="${SOURCE_COMMIT:-${GITHUB_SHA:-$(git rev-parse HEAD)}}"
RELEASE_NAME="rel-${COMMIT_SHA:0:12}-$(date +%Y%m%d%H%M%S)"

gcloud deploy releases create "${RELEASE_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --delivery-pipeline="${PIPELINE}" \
  --images="app=${IMAGE}" \
  --skaffold-profile="${TARGET}" \
  --skaffold-file=skaffold.yaml \
  --source=.

echo "Created Cloud Deploy release: ${RELEASE_NAME}"
