#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-.env}
COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.prod.yml}
BACKUP_DIR=${BACKUP_DIR:-./backups}
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "${BACKUP_DIR}"
set -a
source "${ENV_FILE}"
set +a

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" | gzip > "${BACKUP_DIR}/postgres-${TIMESTAMP}.sql.gz"

docker run --rm \
  --volumes-from "$(docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" ps -q minio)" \
  -v "$(pwd)/${BACKUP_DIR}:/backup" \
  alpine:3.20 sh -c "tar czf /backup/minio-${TIMESTAMP}.tar.gz /data"

find "${BACKUP_DIR}" -type f -mtime +"${BACKUP_RETENTION_DAYS:-14}" -delete
echo "Backup completed in ${BACKUP_DIR}."
