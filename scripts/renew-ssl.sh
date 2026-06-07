#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.prod.yml}
ENV_FILE=${ENV_FILE:-.env}

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" run --rm certbot renew --webroot --webroot-path /var/www/certbot
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec nginx nginx -s reload
