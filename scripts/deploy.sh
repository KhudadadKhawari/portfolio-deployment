#!/usr/bin/env bash
set -euo pipefail

SERVICE=${1:-}
IMAGE_TAG=${2:-}
APP_DIR=${APP_DIR:-/opt/portfolio}
COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.prod.yml}
ENV_FILE=${ENV_FILE:-.env}

if [[ ${SERVICE} != "backend" && ${SERVICE} != "frontend" ]]; then
  echo "Usage: $0 backend|frontend docker.io/owner/image:tag"
  exit 1
fi

if [[ -z ${IMAGE_TAG} ]]; then
  echo "Missing image tag."
  exit 1
fi

cd "${APP_DIR}"

if [[ ! -f ${ENV_FILE} ]]; then
  echo "Missing ${APP_DIR}/${ENV_FILE}."
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

if [[ -n ${DOCKERHUB_USERNAME:-} && -n ${DOCKERHUB_TOKEN:-} ]]; then
  echo "${DOCKERHUB_TOKEN}" | docker login docker.io -u "${DOCKERHUB_USERNAME}" --password-stdin
fi

# if [[ ${SERVICE} == "backend" ]]; then
#   sed -i "s#^BACKEND_IMAGE=.*#BACKEND_IMAGE=${IMAGE_TAG}#" "${ENV_FILE}"
# else
#   sed -i "s#^FRONTEND_IMAGE=.*#FRONTEND_IMAGE=${IMAGE_TAG}#" "${ENV_FILE}"
# fi

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" pull "${SERVICE}"

if [[ ${SERVICE} == "backend" ]]; then
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" run --rm backend alembic upgrade head
fi

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d --no-deps "${SERVICE}"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d nginx
./scripts/healthcheck.sh

echo "${SERVICE} deployed with image ${IMAGE_TAG}."
