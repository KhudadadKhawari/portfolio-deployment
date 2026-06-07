#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-.env}
COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.prod.yml}

if [[ -f ${ENV_FILE} ]]; then
  set -a
  source "${ENV_FILE}"
  set +a
fi

DOMAIN=${DOMAIN:-localhost}
SCHEME=${SCHEME:-https}

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" ps
curl --fail --silent --show-error "${SCHEME}://${DOMAIN}/.well-known/health" >/dev/null
curl --fail --silent --show-error "${SCHEME}://${DOMAIN}/api/health" >/dev/null

echo "Health checks passed for ${DOMAIN}."
