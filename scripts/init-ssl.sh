#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.prod.yml}
ENV_FILE=${ENV_FILE:-.env}

if [[ ! -f ${ENV_FILE} ]]; then
  echo "Missing ${ENV_FILE}. Copy .env.example to .env and update values first."
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d nginx
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" run --rm certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  --email "${LETSENCRYPT_EMAIL}" \
  --agree-tos \
  --no-eff-email \
  -d "${DOMAIN}"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" restart nginx

echo "SSL certificate issued for ${DOMAIN}."
